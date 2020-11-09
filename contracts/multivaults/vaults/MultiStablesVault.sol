// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "@openzeppelin/contracts-ethereum-package/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts-ethereum-package/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts-ethereum-package/contracts/utils/Address.sol";
import "@openzeppelin/contracts-ethereum-package/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts-ethereum-package/contracts/token/ERC20/SafeERC20.sol";

import "../../interfaces/Converter.sol";

import "../IValueMultiVault.sol";
import "../IValueVaultMaster.sol";
import "../IMultiVaultController.sol";
import "../IMultiVaultConverter.sol";
import "../IShareConverter.sol";

contract MultiStablesVault is ERC20UpgradeSafe, IValueMultiVault {
    using Address for address;
    using SafeMath for uint;
    using SafeERC20 for IERC20;

    // Curve Pools
    // 0. 3pool [DAI, USDC, USDT]
    // 1. BUSD [(y)DAI, (y)USDC, (y)USDT, (y)BUSD]
    // 2. sUSD [DAI, USDC, USDT, sUSD]
    // 3. husd [HUSD, 3pool]
    // 4. Compound [(c)DAI, (c)USDC]
    // 5. Y [(y)DAI, (y)USDC, (y)USDT, (y)TUSD]
    IERC20 public basedToken; // [3CRV] (used for center-metric price: share value will based on this)

    IERC20[] public inputTokens; // DAI, USDC, USDT, 3CRV, BUSD, sUSD, husd
    IERC20[] public wantTokens; // [3CRV], [yDAI+yUSDC+yUSDT+yBUSD], [crvPlain3andSUSD], [husd3CRV], [cDAI+cUSDC], [yDAI+yUSDC+yUSDT+yTUSD]

    mapping(address => uint) public inputTokenIndex; // input_token_address => (index + 1)
    mapping(address => uint) public wantTokenIndex; // want_token_address => (index + 1)
    mapping(address => address) public input2Want; // eg. BUSD => [yDAI+yUSDC+yUSDT+yBUSD], sUSD => [husd3CRV]
    mapping(address => bool) public allowWithdrawFromOtherWant; // we allow to withdraw from others if based want strategies have not enough balance

    uint public min = 9500;
    uint public constant max = 10000;

    uint public earnLowerlimit = 10 ether; // minimum to invest is 10 3CRV
    uint totalDepositCap = 10000000 ether; // initial cap set at 10 million dollar

    address public governance;
    address public controller;
    uint public insurance;
    IValueVaultMaster vaultMaster;
    IMultiVaultConverter public basedConverter; // converter for 3CRV
    IShareConverter public shareConverter; // converter for shares (3CRV <-> BCrv, etc ...)

    mapping(address => IMultiVaultConverter) public converters; // want_token_address => converter
    mapping(address => address) public converterMap; // non-core token => converter

    bool public acceptContractDepositor = false;
    mapping(address => bool) public whitelistedContract;

    event Deposit(address indexed user, uint amount);
    event Withdraw(address indexed user, uint amount);
    event RewardPaid(address indexed user, uint reward);

    function initialize(IERC20 _basedToken, IValueVaultMaster _vaultMaster) public initializer {
        __ERC20_init("ValueDefi:MultiVault:Stables", "mvUSD");
        basedToken = _basedToken;
        vaultMaster = _vaultMaster;
        governance = msg.sender;
    }

    /**
     * @dev Throws if called by a not-whitelisted contract while we do not accept contract depositor.
     */
    modifier checkContract() {
        if (!acceptContractDepositor && !whitelistedContract[msg.sender]) {
            require(!address(msg.sender).isContract() && msg.sender == tx.origin, "contract not support");
        }
        _;
    }

    function setAcceptContractDepositor(bool _acceptContractDepositor) external {
        require(msg.sender == governance, "!governance");
        acceptContractDepositor = _acceptContractDepositor;
    }

    function whitelistContract(address _contract) external {
        require(msg.sender == governance, "!governance");
        whitelistedContract[_contract] = true;
    }

    function unwhitelistContract(address _contract) external {
        require(msg.sender == governance, "!governance");
        whitelistedContract[_contract] = false;
    }

    function cap() external override view returns (uint) {
        return totalDepositCap;
    }

    function getConverter(address _want) external override view returns (address) {
        return address(converters[_want]);
    }

    function getVaultMaster() external override view returns (address) {
        return address(vaultMaster);
    }

    function accept(address _input) external override view returns (bool) {
        return inputTokenIndex[_input] > 0;
    }

    // Ignore insurance fund for balance calculations
    function balance() public override view returns (uint) {
        uint bal = basedToken.balanceOf(address(this));
        if (controller != address(0)) bal = bal.add(IMultiVaultController(controller).balanceOf(address(basedToken), false));
        return bal.sub(insurance);
    }

    // sub a small percent (~0.02%) for not-based strategy balance when selling shares
    function balance_to_sell() public view returns (uint) {
        uint bal = basedToken.balanceOf(address(this));
        if (controller != address(0)) bal = bal.add(IMultiVaultController(controller).balanceOf(address(basedToken), true));
        return bal.sub(insurance);
    }

    function setMin(uint _min) external {
        require(msg.sender == governance, "!governance");
        min = _min;
    }

    function setGovernance(address _governance) external {
        require(msg.sender == governance, "!governance");
        governance = _governance;
    }

    function setController(address _controller) external {
        require(msg.sender == governance, "!governance");
        controller = _controller;
    }

    function setConverter(address _want, IMultiVaultConverter _converter) external {
        require(msg.sender == governance, "!governance");
        require(_converter.token() == _want, "!_want");
        converters[_want] = _converter;
        if (_want == address(basedToken)) basedConverter = _converter;
    }

    function setShareConverter(IShareConverter _shareConverter) external {
        require(msg.sender == governance, "!governance");
        shareConverter = _shareConverter;
    }

    function setConverterMap(address _token, address _converter) external {
        require(msg.sender == governance, "!governance");
        converterMap[_token] = _converter;
    }

    function setVaultMaster(IValueVaultMaster _vaultMaster) external {
        require(msg.sender == governance, "!governance");
        vaultMaster = _vaultMaster;
    }

    function setEarnLowerlimit(uint _earnLowerlimit) external {
        require(msg.sender == governance, "!governance");
        earnLowerlimit = _earnLowerlimit;
    }

    function setCap(uint _cap) external {
        require(msg.sender == governance, "!governance");
        totalDepositCap = _cap;
    }

    // claim by controller: auto-compounding
    // claim by governance: send the fund to insuranceFund
    function claimInsurance() external override {
        if (msg.sender != controller) {
            require(msg.sender == governance, "!governance");
            basedToken.safeTransfer(vaultMaster.insuranceFund(), insurance);
        }
        insurance = 0;
    }

    function setInputTokens(IERC20[] memory _inputTokens) external {
        require(msg.sender == governance, "!governance");
        for (uint256 i = 0; i < inputTokens.length; ++i) {
            inputTokenIndex[address(inputTokens[i])] = 0;
        }
        delete inputTokens;
        for (uint256 i = 0; i < _inputTokens.length; ++i) {
            inputTokens.push(_inputTokens[i]);
            inputTokenIndex[address(_inputTokens[i])] = i + 1;
        }
    }

    function setInputToken(uint _index, IERC20 _inputToken) external {
        require(msg.sender == governance, "!governance");
        inputTokenIndex[address(inputTokens[_index])] = 0;
        inputTokens[_index] = _inputToken;
        inputTokenIndex[address(_inputToken)] = _index + 1;
    }

    function setWantTokens(IERC20[] memory _wantTokens) external {
        require(msg.sender == governance, "!governance");
        for (uint256 i = 0; i < wantTokens.length; ++i) {
            wantTokenIndex[address(wantTokens[i])] = 0;
        }
        delete wantTokens;
        for (uint256 i = 0; i < _wantTokens.length; ++i) {
            wantTokens.push(_wantTokens[i]);
            wantTokenIndex[address(_wantTokens[i])] = i + 1;
        }
    }

    function setInput2Want(address _inputToken, address _wantToken) external {
        require(msg.sender == governance, "!governance");
        input2Want[_inputToken] = _wantToken;
    }

    function setAllowWithdrawFromOtherWant(address _token, bool _allow) external {
        require(msg.sender == governance, "!governance");
        allowWithdrawFromOtherWant[_token] = _allow;
    }

    function token() public override view returns (address) {
        return address(basedToken);
    }

    // Custom logic in here for how much the vault allows to be borrowed
    // Sets minimum required on-hand to keep small withdrawals cheap
    function available(address _want) public override view returns (uint) {
        uint _bal = IERC20(_want).balanceOf(address(this));
        return (_want == address(basedToken)) ? _bal.mul(min).div(max) : _bal;
    }

    function earn(address _want) public override {
        if (controller != address(0)) {
            IMultiVaultController _contrl = IMultiVaultController(controller);
            if (!_contrl.investDisabled(_want)) {
                uint _bal = available(_want);
                if ((_bal > 0) && (_want != address(basedToken) || _bal >= earnLowerlimit)) {
                    IERC20(_want).safeTransfer(controller, _bal);
                    _contrl.earn(_want, _bal);
                }
            }
        }
    }

    // if some want (nonbased) stay idle and we want to convert to based-token to re-invest
    function convert_nonbased_want(address _want, uint _amount) external {
        require(msg.sender == governance, "!governance");
        require(_want != address(basedToken), "basedToken");
        require(address(shareConverter) != address(0), "!shareConverter");
        require(shareConverter.convert_shares_rate(_want, address(basedToken), _amount) > 0, "rate=0");
        IERC20(_want).safeTransfer(address(shareConverter), _amount);
        shareConverter.convert_shares(_want, address(basedToken), _amount);
    }

    // Only allows to earn some extra yield from non-core tokens
    function earnExtra(address _token) external {
        require(msg.sender == governance, "!governance");
        require(converterMap[_token] != address(0), "!converter");
        require(address(_token) != address(basedToken), "3crv");
        require(address(_token) != address(this), "mvUSD");
        require(wantTokenIndex[_token] == 0, "wantToken");
        uint _amount = IERC20(_token).balanceOf(address(this));
        address _converter = converterMap[_token];
        IERC20(_token).safeTransfer(_converter, _amount);
        Converter(_converter).convert(_token);
    }

    function withdraw_fee(uint _shares) public override view returns (uint) {
        return (controller == address(0)) ? 0 : IMultiVaultController(controller).withdraw_fee(address(basedToken), _shares);
    }

    function calc_token_amount_deposit(uint[] calldata _amounts) external override view returns (uint) {
        return basedConverter.calc_token_amount_deposit(_amounts).mul(1e18).div(getPricePerFullShare());
    }

    function calc_token_amount_withdraw(uint _shares, address _output) external override view returns (uint) {
        uint _withdrawFee = withdraw_fee(_shares);
        if (_withdrawFee > 0) {
            _shares = _shares.sub(_withdrawFee);
        }
        uint _totalSupply = totalSupply();
        uint r = (_totalSupply == 0) ? _shares : (balance().mul(_shares)).div(_totalSupply);
        if (_output == address(basedToken)) {
            return r;
        }
        return basedConverter.calc_token_amount_withdraw(r, _output).mul(1e18).div(getPricePerFullShare());
    }

    function convert_rate(address _input, uint _amount) external override view returns (uint) {
        return basedConverter.convert_rate(_input, address(basedToken), _amount).mul(1e18).div(getPricePerFullShare());
    }

    function deposit(address _input, uint _amount, uint _min_mint_amount) external override checkContract returns (uint) {
        return depositFor(msg.sender, msg.sender, _input, _amount, _min_mint_amount);
    }

    function depositFor(address _account, address _to, address _input, uint _amount, uint _min_mint_amount) public override checkContract returns (uint _mint_amount) {
        require(msg.sender == _account || msg.sender == vaultMaster.bank(address(this)), "!bank && !yourself");
        uint _pool = balance();
        require(totalDepositCap == 0 || _pool <= totalDepositCap, ">totalDepositCap");
        uint _before = 0;
        uint _after = 0;
        address _want = address(0);
        address _ctrlWant = IMultiVaultController(controller).want();
        if (_input == address(basedToken) || _input == _ctrlWant) {
            _want = _want;
            _before = IERC20(_input).balanceOf(address(this));
            basedToken.safeTransferFrom(_account, address(this), _amount);
            _after = IERC20(_input).balanceOf(address(this));
            _amount = _after.sub(_before); // additional check for deflationary tokens
        } else {
            _want = input2Want[_input];
            if (_want == address(0)) {
                _want = _ctrlWant;
            }
            IMultiVaultConverter _converter = converters[_want];
            require(_converter.convert_rate(_input, _want, _amount) > 0, "rate=0");
            _before = IERC20(_want).balanceOf(address(this));
            IERC20(_input).safeTransferFrom(_account, address(_converter), _amount);
            _converter.convert(_input, _want, _amount);
            _after = IERC20(_want).balanceOf(address(this));
            _amount = _after.sub(_before); // additional check for deflationary tokens
        }
        require(_amount > 0, "no _want");
        _mint_amount = _deposit(_to, _pool, _amount, _want);
        require(_mint_amount >= _min_mint_amount, "slippage");
    }

    function depositAll(uint[] calldata _amounts, uint _min_mint_amount) external override checkContract returns (uint) {
        return depositAllFor(msg.sender, msg.sender, _amounts, _min_mint_amount);
    }

    // Transfers tokens of all kinds
    // 0: DAI, 1: USDC, 2: USDT, 3: 3CRV, 4: BUSD, 5: sUSD, 6: husd
    function depositAllFor(address _account, address _to, uint[] calldata _amounts, uint _min_mint_amount) public override checkContract returns (uint _mint_amount) {
        require(msg.sender == _account || msg.sender == vaultMaster.bank(address(this)), "!bank && !yourself");
        uint _pool = balance();
        require(totalDepositCap == 0 || _pool <= totalDepositCap, ">totalDepositCap");
        address _want = IMultiVaultController(controller).want();
        IMultiVaultConverter _converter = converters[_want];
        require(address(_converter) != address(0), "!converter");
        uint _length = _amounts.length;
        for (uint8 i = 0; i < _length; i++) {
            uint _inputAmount = _amounts[i];
            if (_inputAmount > 0) {
                inputTokens[i].safeTransferFrom(_account, address(_converter), _inputAmount);
            }
        }
        uint _before = IERC20(_want).balanceOf(address(this));
        _converter.convertAll(_amounts);
        uint _after = IERC20(_want).balanceOf(address(this));
        uint _totalDepositAmount = _after.sub(_before); // additional check for deflationary tokens
        _mint_amount = (_totalDepositAmount > 0) ? _deposit(_to, _pool, _totalDepositAmount, _want) : 0;
        require(_mint_amount >= _min_mint_amount, "slippage");
    }

    function _deposit(address _mintTo, uint _pool, uint _amount, address _want) internal returns (uint _shares) {
        uint _insuranceFee = vaultMaster.insuranceFee();
        if (_insuranceFee > 0) {
            uint _insurance = _amount.mul(_insuranceFee).div(10000);
            _amount = _amount.sub(_insurance);
            insurance = insurance.add(_insurance);
        }

        if (_want != address(basedToken)) {
            _amount = shareConverter.convert_shares_rate(_want, address(basedToken), _amount);
            if (_amount == 0) {
                _amount = basedConverter.convert_rate(_want, address(basedToken), _amount); // try [stables_2_basedWant] if [share_2_share] failed
            }
        }

        if (totalSupply() == 0) {
            _shares = _amount;
        } else {
            _shares = (_amount.mul(totalSupply())).div(_pool);
        }

        if (_shares > 0) {
            earn(_want);
            _mint(_mintTo, _shares);
        }
    }

    // Used to swap any borrowed reserve over the debt limit to liquidate to 'token'
    function harvest(address reserve, uint amount) external override {
        require(msg.sender == controller, "!controller");
        require(reserve != address(basedToken), "basedToken");
        IERC20(reserve).safeTransfer(controller, amount);
    }

    function harvestStrategy(address _strategy) external override {
        require(msg.sender == governance || msg.sender == vaultMaster.bank(address(this)), "!governance && !bank");
        IMultiVaultController(controller).harvestStrategy(_strategy);
    }

    function harvestWant(address _want) external override {
        require(msg.sender == governance || msg.sender == vaultMaster.bank(address(this)), "!governance && !bank");
        IMultiVaultController(controller).harvestWant(_want);
    }

    function harvestAllStrategies() external override {
        require(msg.sender == governance || msg.sender == vaultMaster.bank(address(this)), "!governance && !bank");
        IMultiVaultController(controller).harvestAllStrategies();
    }

    function withdraw(uint _shares, address _output, uint _min_output_amount) external override returns (uint) {
        return withdrawFor(msg.sender, _shares, _output, _min_output_amount);
    }

    // No rebalance implementation for lower fees and faster swaps
    function withdrawFor(address _account, uint _shares, address _output, uint _min_output_amount) public override returns (uint _output_amount) {
        _output_amount = (balance_to_sell().mul(_shares)).div(totalSupply());
        _burn(msg.sender, _shares);

        uint _withdrawalProtectionFee = vaultMaster.withdrawalProtectionFee();
        if (_withdrawalProtectionFee > 0) {
            uint _withdrawalProtection = _output_amount.mul(_withdrawalProtectionFee).div(10000);
            _output_amount = _output_amount.sub(_withdrawalProtection);
        }

        // Check balance
        uint b = basedToken.balanceOf(address(this));
        if (b < _output_amount) {
            uint _toWithdraw = _output_amount.sub(b);
            uint _wantBal = IMultiVaultController(controller).wantStrategyBalance(address(basedToken));
            if (_wantBal < _toWithdraw && allowWithdrawFromOtherWant[_output]) {
                // if balance is not enough and we allow withdrawing from other wants
                address _otherWant = input2Want[_output];
                if (_otherWant != address(0) && _otherWant != address(basedToken)) {
                    IMultiVaultConverter otherConverter = converters[_otherWant];
                    if (address(otherConverter) != address(0)) {
                        uint _toWithdrawOtherWant = shareConverter.convert_shares_rate(address(basedToken), _otherWant, _output_amount);
                        _wantBal = IMultiVaultController(controller).wantStrategyBalance(_otherWant);
                        if (_wantBal >= _toWithdrawOtherWant) {
                            {
                                uint _before = IERC20(_otherWant).balanceOf(address(this));
                                uint _withdrawFee = IMultiVaultController(controller).withdraw(_otherWant, _toWithdrawOtherWant);
                                uint _after = IERC20(_otherWant).balanceOf(address(this));
                                _output_amount = _after.sub(_before);
                                if (_withdrawFee > 0) {
                                    _output_amount = _output_amount.sub(_withdrawFee, "_output_amount < _withdrawFee");
                                }
                            }
                            if (_output != _otherWant) {
                                require(otherConverter.convert_rate(_otherWant, _output, _output_amount) > 0, "rate=0");
                                IERC20(_otherWant).safeTransfer(address(otherConverter), _output_amount);
                                _output_amount = otherConverter.convert(_otherWant, _output, _output_amount);
                            }
                            require(_output_amount >= _min_output_amount, "slippage");
                            IERC20(_output).safeTransfer(_account, _output_amount);
                            return _output_amount;
                        }
                    }
                }
            }
            uint _withdrawFee = IMultiVaultController(controller).withdraw(address(basedToken), _toWithdraw);
            uint _after = basedToken.balanceOf(address(this));
            uint _diff = _after.sub(b);
            if (_diff < _toWithdraw) {
                _output_amount = b.add(_diff);
            }
            if (_withdrawFee > 0) {
                _output_amount = _output_amount.sub(_withdrawFee, "_output_amount < _withdrawFee");
            }
        }

        if (_output == address(basedToken)) {
            require(_output_amount >= _min_output_amount, "slippage");
            basedToken.safeTransfer(_account, _output_amount);
        } else {
            require(basedConverter.convert_rate(address(basedToken), _output, _output_amount) > 0, "rate=0");
            basedToken.safeTransfer(address(basedConverter), _output_amount);
            uint _outputAmount = basedConverter.convert(address(basedToken), _output, _output_amount);
            require(_outputAmount >= _min_output_amount, "slippage");
            IERC20(_output).safeTransfer(_account, _outputAmount);
        }
    }

    function getPricePerFullShare() public override view returns (uint) {
        return (totalSupply() == 0) ? 1e18 : balance().mul(1e18).div(totalSupply());
    }

    // @dev average dollar value of vault share token
    function get_virtual_price() external override view returns (uint) {
        return basedConverter.get_virtual_price().mul(getPricePerFullShare()).div(1e18);
    }

    /**
     * This function allows governance to take unsupported tokens out of the contract. This is in an effort to make someone whole, should they seriously mess up.
     * There is no guarantee governance will vote to return these. It also allows for removal of airdropped tokens.
     */
    function governanceRecoverUnsupported(IERC20 _token, uint amount, address to) external {
        require(msg.sender == governance, "!governance");
        require(address(_token) != address(basedToken), "3crv");
        require(address(_token) != address(this), "mvUSD");
        require(wantTokenIndex[address(_token)] == 0, "wantToken");
        _token.safeTransfer(to, amount);
    }
}
