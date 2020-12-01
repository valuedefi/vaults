// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "@openzeppelin/contracts-ethereum-package/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts-ethereum-package/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts-ethereum-package/contracts/utils/Address.sol";
import "@openzeppelin/contracts-ethereum-package/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts-ethereum-package/contracts/token/ERC20/SafeERC20.sol";

import "../../interfaces/Converter.sol";

import "../ICompositeVault.sol";
import "../IVaultMaster.sol";
import "../IController.sol";
import "../ILpPairConverter.sol";

abstract contract CompositeVaultBase is ERC20UpgradeSafe, ICompositeVault {
    using Address for address;
    using SafeMath for uint;
    using SafeERC20 for IERC20;

    IERC20 public basedToken;

    IERC20 public token0;
    IERC20 public token1;

    uint public min = 9500;
    uint public constant max = 10000;

    uint public earnLowerlimit = 1; // minimum to invest
    uint public depositLimit = 0; // limit for each deposit (set 0 to disable)
    uint private totalDepositCap = 0; // initial cap (set 0 to disable)

    address public governance;
    address public controller;

    IVaultMaster vaultMaster;
    ILpPairConverter public basedConverter; // converter for basedToken (SLP or BPT or UNI)

    mapping(address => address) public converterMap; // non-core token => converter

    bool public acceptContractDepositor = false;
    mapping(address => bool) public whitelistedContract;
    bool private _mutex;

    // variable used for avoid the call of mint and redeem in the same tx
    bytes32 private _minterBlock;

    uint public totalPendingCompound;
    uint public startReleasingCompoundBlk;
    uint public endReleasingCompoundBlk;

    function initialize(IERC20 _basedToken, IERC20 _token0, IERC20 _token1, IVaultMaster _vaultMaster) public initializer {
        __ERC20_init(_getName(), _getSymbol());
        basedToken = _basedToken;
        token0 = _token0;
        token1 = _token1;
        vaultMaster = _vaultMaster;
        governance = msg.sender;
    }

    function _getName() internal virtual view returns (string memory);

    function _getSymbol() internal virtual view returns (string memory);

    /**
     * @dev Throws if called by a not-whitelisted contract while we do not accept contract depositor.
     */
    modifier checkContract(address _account) {
        if (!acceptContractDepositor && !whitelistedContract[_account] && (_account != vaultMaster.bank(address(this)))) {
            require(!address(_account).isContract() && _account == tx.origin, "contract not support");
        }
        _;
    }

    modifier _non_reentrant_() {
        require(!_mutex, "reentry");
        _mutex = true;
        _;
        _mutex = false;
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

    function getConverter() external override view returns (address) {
        return address(basedConverter);
    }

    function getVaultMaster() external override view returns (address) {
        return address(vaultMaster);
    }

    function accept(address _input) external override view returns (bool) {
        return basedConverter.accept(_input);
    }

    function addNewCompound(uint _newCompound, uint _blocksToReleaseCompound) external override {
        require(msg.sender == governance || vaultMaster.isStrategy(msg.sender), "!authorized");
        if (_blocksToReleaseCompound == 0) {
            totalPendingCompound = 0;
            startReleasingCompoundBlk = 0;
            endReleasingCompoundBlk = 0;
        } else {
            totalPendingCompound = pendingCompound().add(_newCompound);
            startReleasingCompoundBlk = block.number;
            endReleasingCompoundBlk = block.number.add(_blocksToReleaseCompound);
        }
    }

    function pendingCompound() public view returns (uint) {
        if (totalPendingCompound == 0 || endReleasingCompoundBlk <= block.number) return 0;
        return totalPendingCompound.mul(endReleasingCompoundBlk.sub(block.number)).div(endReleasingCompoundBlk.sub(startReleasingCompoundBlk).add(1));
    }

    function balance() public override view returns (uint _balance) {
        _balance = basedToken.balanceOf(address(this)).add(IController(controller).balanceOf()).sub(pendingCompound());
    }

    function tvl() public override view returns (uint) {
        return balance().mul(basedConverter.get_virtual_price()).div(1e18);
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
        require(IController(_controller).want() == address(basedToken), "!token");
        controller = _controller;
    }

    function setConverter(ILpPairConverter _converter) external {
        require(msg.sender == governance, "!governance");
        require(_converter.lpPair() == address(basedToken), "!token");
        basedConverter = _converter;
    }

    function setConverterMap(address _token, address _converter) external {
        require(msg.sender == governance, "!governance");
        converterMap[_token] = _converter;
    }

    function setVaultMaster(IVaultMaster _vaultMaster) external {
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

    function setDepositLimit(uint _limit) external {
        require(msg.sender == governance, "!governance");
        depositLimit = _limit;
    }

    function token() public override view returns (address) {
        return address(basedToken);
    }

    // Custom logic in here for how much the vault allows to be borrowed
    // Sets minimum required on-hand to keep small withdrawals cheap
    function available() public override view returns (uint) {
        return basedToken.balanceOf(address(this)).mul(min).div(max);
    }

    function earn() public override {
        if (controller != address(0)) {
            IController _contrl = IController(controller);
            if (!_contrl.investDisabled()) {
                uint _bal = available();
                if (_bal >= earnLowerlimit) {
                    basedToken.safeTransfer(controller, _bal);
                    _contrl.earn(address(basedToken), _bal);
                }
            }
        }
    }

    // Only allows to earn some extra yield from non-core tokens
    function earnExtra(address _token) external {
        require(msg.sender == governance, "!governance");
        require(converterMap[_token] != address(0), "!converter");
        require(address(_token) != address(basedToken), "token");
        require(address(_token) != address(this), "share");
        uint _amount = IERC20(_token).balanceOf(address(this));
        address _converter = converterMap[_token];
        IERC20(_token).safeTransfer(_converter, _amount);
        Converter(_converter).convert(_token);
    }

    function withdraw_fee(uint _shares) public override view returns (uint) {
        return (controller == address(0)) ? 0 : IController(controller).withdraw_fee(_shares);
    }

    function calc_token_amount_deposit(address _input, uint _amount) external override view returns (uint) {
        return basedConverter.convert_rate(_input, address(basedToken), _amount).mul(1e18).div(getPricePerFullShare());
    }

    function calc_add_liquidity(uint _amount0, uint _amount1) external override view returns (uint) {
        return basedConverter.calc_add_liquidity(_amount0, _amount1).mul(1e18).div(getPricePerFullShare());
    }

    function _calc_shares_to_amount_withdraw(uint _shares) internal view returns (uint) {
        uint _withdrawFee = withdraw_fee(_shares);
        if (_withdrawFee > 0) {
            _shares = _shares.sub(_withdrawFee);
        }
        uint _totalSupply = totalSupply();
        return (_totalSupply == 0) ? _shares : (balance().mul(_shares)).div(_totalSupply);
    }

    function calc_token_amount_withdraw(uint _shares, address _output) external override view returns (uint) {
        uint r = _calc_shares_to_amount_withdraw(_shares);
        if (_output != address(basedToken)) {
            r = basedConverter.convert_rate(address(basedToken), _output, r);
        }
        return r.mul(getPricePerFullShare()).div((1e18));
    }

    function calc_remove_liquidity(uint _shares) external override view returns (uint _amount0, uint _amount1) {
        uint r = _calc_shares_to_amount_withdraw(_shares);
        (_amount0, _amount1) = basedConverter.calc_remove_liquidity(r);
        uint _getPricePerFullShare = getPricePerFullShare();
        _amount0 = _amount0.mul(_getPricePerFullShare).div((1e18));
        _amount1 = _amount1.mul(_getPricePerFullShare).div((1e18));
    }

    function deposit(address _input, uint _amount, uint _min_mint_amount) external override returns (uint) {
        return depositFor(msg.sender, msg.sender, _input, _amount, _min_mint_amount);
    }

    function depositFor(address _account, address _to, address _input, uint _amount, uint _min_mint_amount) public override checkContract(_account) _non_reentrant_ returns (uint _mint_amount) {
        uint _pool = balance();
        require(totalDepositCap == 0 || _pool <= totalDepositCap, ">totalDepositCap");
        uint _before = basedToken.balanceOf(address(this));
        if (_input == address(basedToken)) {
            basedToken.safeTransferFrom(_account, address(this), _amount);
        } else {
            // require(basedConverter.convert_rate(_input, address(basedToken), _amount) > 0, "rate=0");
            uint _before0 = token0.balanceOf(address(this));
            uint _before1 = token1.balanceOf(address(this));
            IERC20(_input).safeTransferFrom(_account, address(basedConverter), _amount);
            basedConverter.convert(_input, address(basedToken), address(this));
            uint _after0 = token0.balanceOf(address(this));
            uint _after1 = token1.balanceOf(address(this));
            if (_after0 > _before0) {
                token0.safeTransfer(_account, _after0.sub(_before0));
            }
            if (_after1 > _before1) {
                token1.safeTransfer(_account, _after1.sub(_before1));
            }
        }
        uint _after = basedToken.balanceOf(address(this));
        _amount = _after.sub(_before); // additional check for deflationary tokens
        require(depositLimit == 0 || _amount <= depositLimit, ">depositLimit");
        require(_amount > 0, "no token");
        _mint_amount = _deposit(_to, _pool, _amount);
        require(_mint_amount >= _min_mint_amount, "slippage");
    }

    function addLiquidity(uint _amount0, uint _amount1, uint _min_mint_amount) external override returns (uint) {
        return addLiquidityFor(msg.sender, msg.sender, _amount0, _amount1, _min_mint_amount);
    }

    function addLiquidityFor(address _account, address _to, uint _amount0, uint _amount1, uint _min_mint_amount) public override checkContract(_account) _non_reentrant_ returns (uint _mint_amount) {
        require(msg.sender == _account || msg.sender == vaultMaster.bank(address(this)), "!bank && !yourself");
        uint _pool = balance();
        require(totalDepositCap == 0 || _pool <= totalDepositCap, ">totalDepositCap");
        uint _beforeToken = basedToken.balanceOf(address(this));
        uint _before0 = token0.balanceOf(address(this));
        uint _before1 = token1.balanceOf(address(this));
        token0.safeTransferFrom(_account, address(basedConverter), _amount0);
        token1.safeTransferFrom(_account, address(basedConverter), _amount1);
        basedConverter.add_liquidity(address(this));
        uint _afterToken = basedToken.balanceOf(address(this));
        uint _after0 = token0.balanceOf(address(this));
        uint _after1 = token1.balanceOf(address(this));
        uint _totalDepositAmount = _afterToken.sub(_beforeToken); // additional check for deflationary tokens
        require(depositLimit == 0 || _totalDepositAmount <= depositLimit, ">depositLimit");
        require(_totalDepositAmount > 0, "no token");
        if (_after0 > _before0) {
            token0.safeTransfer(_account, _after0.sub(_before0));
        }
        if (_after1 > _before1) {
            token1.safeTransfer(_account, _after1.sub(_before1));
        }
        _mint_amount = _deposit(_to, _pool, _totalDepositAmount);
        require(_mint_amount >= _min_mint_amount, "slippage");
    }

    function _deposit(address _mintTo, uint _pool, uint _amount) internal returns (uint _shares) {
        if (totalSupply() == 0) {
            _shares = _amount;
        } else {
            _shares = (_amount.mul(totalSupply())).div(_pool);
        }

        if (_shares > 0) {
            earn();

            _minterBlock = keccak256(abi.encodePacked(tx.origin, block.number));
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
        IController(controller).harvestStrategy(_strategy);
    }

    function harvestAllStrategies() external override {
        require(msg.sender == governance || msg.sender == vaultMaster.bank(address(this)), "!governance && !bank");
        IController(controller).harvestAllStrategies();
    }

    function withdraw(uint _shares, address _output, uint _min_output_amount) external override returns (uint) {
        return withdrawFor(msg.sender, _shares, _output, _min_output_amount);
    }

    // No rebalance implementation for lower fees and faster swaps
    function withdrawFor(address _account, uint _shares, address _output, uint _min_output_amount) public override _non_reentrant_ returns (uint _output_amount) {
        // Check that no mint has been made in the same block from the same EOA
        require(keccak256(abi.encodePacked(tx.origin, block.number)) != _minterBlock, "REENTR MINT-BURN");

        _output_amount = (balance().mul(_shares)).div(totalSupply());
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
            uint _withdrawFee = IController(controller).withdraw(_toWithdraw);
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
            basedToken.safeTransfer(address(basedConverter), _output_amount);
            uint _received = basedConverter.convert(address(basedToken), _output, address(this));
            require(_received >= _min_output_amount, "slippage");
            IERC20(_output).safeTransfer(_account, _received);
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
        require(address(_token) != address(basedToken), "token");
        require(address(_token) != address(this), "share");
        _token.safeTransfer(to, amount);
    }
}
