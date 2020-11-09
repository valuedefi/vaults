// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";

import "../IMultiVaultConverter.sol";
import "../IValueVaultMaster.sol";
import "../IValueVaultMaster.sol";

import "../pool-interfaces/IStableSwap3Pool.sol";
import "../pool-interfaces/IDepositBUSD.sol";
import "../pool-interfaces/IStableSwapBUSD.sol";
import "../pool-interfaces/IStableSwapHUSD.sol";
import "../pool-interfaces/IStableSwapSUSD.sol";

// Supported Pool Tokens:
// 0. 3pool [DAI, USDC, USDT]
// 1. BUSD [(y)DAI, (y)USDC, (y)USDT, (y)BUSD]
// 2. sUSD [DAI, USDC, USDT, sUSD]
// 3. husd [HUSD, 3pool]
// 4. Compound [(c)DAI, (c)USDC]
// 5. Y [(y)DAI, (y)USDC, (y)USDT, (y)TUSD]
// 6. Swerve [(y)DAI...(y)TUSD]
contract StableSwapBusdConverter is IMultiVaultConverter {
    using SafeMath for uint;
    using SafeERC20 for IERC20;

    IERC20[4] public bpoolTokens; // DAI, USDC, USDT, BUSD
    IERC20 public tokenBCrv; // BCrv (yDAI+yUSDC+yUSDT+yBUSD)

    IERC20 public token3Crv; // 3Crv

    IERC20 public tokenSUSD; // sUSD
    IERC20 public tokenSCrv; // sCrv (DAI/USDC/USDT/sUSD)

    IERC20 public tokenHUSD; // hUSD
    IERC20 public tokenHCrv; // hCrv (HUSD/3Crv)

    address public governance;

    IStableSwap3Pool public stableSwap3Pool;
    IDepositBUSD public depositBUSD;
    IStableSwapBUSD public stableSwapBUSD;

    IStableSwapSUSD public stableSwapSUSD;

    IStableSwapHUSD public stableSwapHUSD;

    IValueVaultMaster public vaultMaster;

    uint public defaultSlippage = 1; // very small 0.01%

    constructor (IERC20 _tokenDAI, IERC20 _tokenUSDC, IERC20 _tokenUSDT, IERC20 _token3Crv,
        IERC20 _tokenBUSD, IERC20 _tokenBCrv,
        IERC20 _tokenSUSD, IERC20 _tokenSCrv,
        IERC20 _tokenHUSD, IERC20 _tokenHCrv,
        IStableSwap3Pool _stableSwap3Pool,
        IStableSwapBUSD _stableSwapBUSD,
        IStableSwapSUSD _stableSwapSUSD,
        IStableSwapHUSD _stableSwapHUSD,
        IDepositBUSD _depositBUSD,
        IValueVaultMaster _vaultMaster) public {
        bpoolTokens[0] = _tokenDAI;
        bpoolTokens[1] = _tokenUSDC;
        bpoolTokens[2] = _tokenUSDT;
        bpoolTokens[3] = _tokenBUSD;
        token3Crv = _token3Crv;
        tokenBCrv = _tokenBCrv;
        tokenSUSD = _tokenSUSD;
        tokenSCrv = _tokenSCrv;
        tokenHUSD = _tokenHUSD;
        tokenHCrv = _tokenHCrv;
        stableSwap3Pool = _stableSwap3Pool;
        stableSwapBUSD = _stableSwapBUSD;
        stableSwapSUSD = _stableSwapSUSD;
        stableSwapHUSD = _stableSwapHUSD;
        depositBUSD = _depositBUSD;

        bpoolTokens[0].safeApprove(address(stableSwap3Pool), type(uint256).max);
        bpoolTokens[1].safeApprove(address(stableSwap3Pool), type(uint256).max);
        bpoolTokens[2].safeApprove(address(stableSwap3Pool), type(uint256).max);
        token3Crv.safeApprove(address(stableSwap3Pool), type(uint256).max);

        bpoolTokens[0].safeApprove(address(stableSwapBUSD), type(uint256).max);
        bpoolTokens[1].safeApprove(address(stableSwapBUSD), type(uint256).max);
        bpoolTokens[2].safeApprove(address(stableSwapBUSD), type(uint256).max);
        bpoolTokens[3].safeApprove(address(stableSwapBUSD), type(uint256).max);
        tokenBCrv.safeApprove(address(stableSwapBUSD), type(uint256).max);

        bpoolTokens[0].safeApprove(address(depositBUSD), type(uint256).max);
        bpoolTokens[1].safeApprove(address(depositBUSD), type(uint256).max);
        bpoolTokens[2].safeApprove(address(depositBUSD), type(uint256).max);
        bpoolTokens[3].safeApprove(address(depositBUSD), type(uint256).max);
        tokenBCrv.safeApprove(address(depositBUSD), type(uint256).max);

        bpoolTokens[0].safeApprove(address(stableSwapSUSD), type(uint256).max);
        bpoolTokens[1].safeApprove(address(stableSwapSUSD), type(uint256).max);
        bpoolTokens[2].safeApprove(address(stableSwapSUSD), type(uint256).max);
        tokenSUSD.safeApprove(address(stableSwapSUSD), type(uint256).max);
        tokenSCrv.safeApprove(address(stableSwapSUSD), type(uint256).max);

        token3Crv.safeApprove(address(stableSwapHUSD), type(uint256).max);
        tokenHUSD.safeApprove(address(stableSwapHUSD), type(uint256).max);
        tokenHCrv.safeApprove(address(stableSwapHUSD), type(uint256).max);

        vaultMaster = _vaultMaster;
        governance = msg.sender;
    }

    function setGovernance(address _governance) public {
        require(msg.sender == governance, "!governance");
        governance = _governance;
    }

    function setVaultMaster(IValueVaultMaster _vaultMaster) external {
        require(msg.sender == governance, "!governance");
        vaultMaster = _vaultMaster;
    }

    function approveForSpender(IERC20 _token, address _spender, uint _amount) external {
        require(msg.sender == governance, "!governance");
        _token.safeApprove(_spender, _amount);
    }

    function setDefaultSlippage(uint _defaultSlippage) external {
        require(msg.sender == governance, "!governance");
        require(_defaultSlippage <= 100, "_defaultSlippage>1%");
        defaultSlippage = _defaultSlippage;
    }

    function token() external override returns (address) {
        return address(tokenBCrv);
    }

    // Average dollar value of pool token
    function get_virtual_price() external override view returns (uint) {
        return stableSwapBUSD.get_virtual_price();
    }

    function convert_rate(address _input, address _output, uint _inputAmount) public override view returns (uint _outputAmount) {
        if (_inputAmount == 0) return 0;
        if (_output == address(tokenBCrv)) { // convert to BCrv
            uint[4] memory _amounts;
            for (uint8 i = 0; i < 4; i++) {
                if (_input == address(bpoolTokens[i])) {
                    _amounts[i] = _inputAmount;
                    _outputAmount = stableSwapBUSD.calc_token_amount(_amounts, true);
                    return _outputAmount.mul(10000 - defaultSlippage).div(10000);
                }
            }
            if (_input == address(tokenSUSD)) {
                _amounts[0] = stableSwapSUSD.get_dy_underlying(int128(3), int128(0), _inputAmount); // convert to DAI
                _outputAmount = stableSwapBUSD.calc_token_amount(_amounts, true); // DAI -> BCrv
            }
            if (_input == address(tokenHUSD)) {
                uint _3crvAmount = stableSwapHUSD.get_dy(int128(0), int128(1), _inputAmount); // HUSD -> 3Crv
                _amounts[0] = stableSwap3Pool.calc_withdraw_one_coin(_3crvAmount, 0); // 3Crv -> DAI
                _outputAmount = stableSwapBUSD.calc_token_amount(_amounts, true); // DAI -> BCrv
            }
            if (_input == address(token3Crv)) {
                _amounts[0] = stableSwap3Pool.calc_withdraw_one_coin(_inputAmount, 0); // 3Crv -> DAI
                _outputAmount = stableSwapBUSD.calc_token_amount(_amounts, true); // DAI -> BCrv
            }
        } else if (_input == address(tokenBCrv)) { // convert from BCrv
            for (uint8 i = 0; i < 4; i++) {
                if (_output == address(bpoolTokens[i])) {
                    _outputAmount = depositBUSD.calc_withdraw_one_coin(_inputAmount, i);
                    return _outputAmount.mul(10000 - defaultSlippage).div(10000);
                }
            }
            if (_output == address(tokenSUSD)) {
                uint _daiAmount = depositBUSD.calc_withdraw_one_coin(_inputAmount, 0); // BCrv -> DAI
                _outputAmount = stableSwapSUSD.get_dy_underlying(int128(0), int128(3), _daiAmount); // DAI -> SUSD
            }
            if (_output == address(tokenHUSD)) {
                uint _3crvAmount = _convert_bcrv_to_3crv_rate(_inputAmount); // BCrv -> DAI -> 3Crv
                _outputAmount = stableSwapHUSD.get_dy(int128(1), int128(0), _3crvAmount); // 3Crv -> HUSD
            }
        }
        if (_outputAmount > 0) {
            uint _slippage = _outputAmount.mul(vaultMaster.convertSlippage(_input, _output)).div(10000);
            _outputAmount = _outputAmount.sub(_slippage);
        }
    }

    function _convert_bcrv_to_3crv_rate(uint _bcrvAmount) internal view returns (uint _3crv) {
        uint[3] memory _amounts;
        _amounts[0] = depositBUSD.calc_withdraw_one_coin(_bcrvAmount, 0); // BCrv -> DAI
        _3crv = stableSwap3Pool.calc_token_amount(_amounts, true); // DAI -> 3Crv
    }

    // 0: DAI, 1: USDC, 2: USDT, 3: 3Crv, 4: BUSD, 5: sUSD, 6: husd
    function calc_token_amount_deposit(uint[] calldata _amounts) external override view returns (uint _shareAmount) {
        uint[4] memory _bpoolAmounts;
        _bpoolAmounts[0] = _amounts[0];
        _bpoolAmounts[1] = _amounts[1];
        _bpoolAmounts[2] = _amounts[2];
        _bpoolAmounts[3] = _amounts[4];
        uint _bpoolToBcrv = stableSwapBUSD.calc_token_amount(_bpoolAmounts, true);
        uint _3crvToBCrv = convert_rate(address(token3Crv), address(tokenBCrv), _amounts[3]);
        uint _susdToBCrv = convert_rate(address(tokenSUSD), address(tokenBCrv), _amounts[5]);
        uint _husdToBCrv = convert_rate(address(tokenHUSD), address(tokenBCrv), _amounts[6]);
        return _shareAmount.add(_bpoolToBcrv).add(_3crvToBCrv).add(_susdToBCrv).add(_husdToBCrv);
    }

    function calc_token_amount_withdraw(uint _shares, address _output) external override view returns (uint _outputAmount) {
        for (uint8 i = 0; i < 4; i++) {
            if (_output == address(bpoolTokens[i])) {
                _outputAmount = depositBUSD.calc_withdraw_one_coin(_shares, i);
                return _outputAmount.mul(10000 - defaultSlippage).div(10000);
            }
        }
        if (_output == address(token3Crv)) {
            _outputAmount = _convert_bcrv_to_3crv_rate(_shares); // BCrv -> DAI -> 3Crv
        } else if (_output == address(tokenSUSD)) {
            uint _daiAmount = depositBUSD.calc_withdraw_one_coin(_shares, 0); // BCrv -> DAI
            _outputAmount = stableSwapSUSD.get_dy_underlying(int128(0), int128(3), _daiAmount); // DAI -> SUSD
        } else if (_output == address(tokenHUSD)) {
            uint _3crvAmount = _convert_bcrv_to_3crv_rate(_shares); // BCrv -> DAI -> 3Crv
            _outputAmount = stableSwapHUSD.get_dy(int128(1), int128(0), _3crvAmount); // 3Crv -> HUSD
        }
        if (_outputAmount > 0) {
            uint _slippage = _outputAmount.mul(vaultMaster.slippage(_output)).div(10000);
            _outputAmount = _outputAmount.sub(_slippage);
        }
    }

    function convert(address _input, address _output, uint _inputAmount) external override returns (uint _outputAmount) {
        require(vaultMaster.isVault(msg.sender) || vaultMaster.isController(msg.sender) || msg.sender == governance, "!(governance||vault||controller)");
        if (_output == address(tokenBCrv)) { // convert to BCrv
            uint[4] memory amounts;
            for (uint8 i = 0; i < 4; i++) {
                if (_input == address(bpoolTokens[i])) {
                    amounts[i] = _inputAmount;
                    uint _before = tokenBCrv.balanceOf(address(this));
                    depositBUSD.add_liquidity(amounts, 1);
                    uint _after = tokenBCrv.balanceOf(address(this));
                    _outputAmount = _after.sub(_before);
                    tokenBCrv.safeTransfer(msg.sender, _outputAmount);
                    return _outputAmount;
                }
            }
            if (_input == address(token3Crv)) {
                _outputAmount = _convert_3crv_to_shares(_inputAmount);
                tokenBCrv.safeTransfer(msg.sender, _outputAmount);
                return _outputAmount;
            }
            if (_input == address(tokenSUSD)) {
                _outputAmount = _convert_susd_to_shares(_inputAmount);
                tokenBCrv.safeTransfer(msg.sender, _outputAmount);
                return _outputAmount;
            }
            if (_input == address(tokenHUSD)) {
                _outputAmount = _convert_husd_to_shares(_inputAmount);
                tokenBCrv.safeTransfer(msg.sender, _outputAmount);
                return _outputAmount;
            }
        } else if (_input == address(tokenBCrv)) { // convert from BCrv
            for (uint8 i = 0; i < 4; i++) {
                if (_output == address(bpoolTokens[i])) {
                    uint _before = bpoolTokens[i].balanceOf(address(this));
                    depositBUSD.remove_liquidity_one_coin(_inputAmount, i, 1);
                    uint _after = bpoolTokens[i].balanceOf(address(this));
                    _outputAmount = _after.sub(_before);
                    bpoolTokens[i].safeTransfer(msg.sender, _outputAmount);
                    return _outputAmount;
                }
            }
            if (_output == address(token3Crv)) {
                // remove BCrv to DAI
                uint[3] memory amounts;
                uint _before = bpoolTokens[0].balanceOf(address(this));
                depositBUSD.remove_liquidity_one_coin(_inputAmount, 0, 1);
                uint _after = bpoolTokens[0].balanceOf(address(this));
                amounts[0] = _after.sub(_before);

                // add DAI to 3pool to get back 3Crv
                _before = token3Crv.balanceOf(address(this));
                stableSwap3Pool.add_liquidity(amounts, 1);
                _after = token3Crv.balanceOf(address(this));
                _outputAmount = _after.sub(_before);

                token3Crv.safeTransfer(msg.sender, _outputAmount);
                return _outputAmount;
            }
            if (_output == address(tokenSUSD)) {
                // remove BCrv to DAI
                uint _before = bpoolTokens[0].balanceOf(address(this));
                depositBUSD.remove_liquidity_one_coin(_inputAmount, 0, 1);
                uint _after = bpoolTokens[0].balanceOf(address(this));
                _outputAmount = _after.sub(_before);

                // convert DAI to SUSD
                _before = tokenSUSD.balanceOf(address(this));
                stableSwapSUSD.exchange_underlying(int128(0), int128(3), _outputAmount, 1);
                _after = tokenSUSD.balanceOf(address(this));
                _outputAmount = _after.sub(_before);

                tokenSUSD.safeTransfer(msg.sender, _outputAmount);
                return _outputAmount;
            }
            if (_output == address(tokenHUSD)) {
                _outputAmount = _convert_shares_to_husd(_inputAmount);
                tokenHUSD.safeTransfer(msg.sender, _outputAmount);
                return _outputAmount;
            }
        }
        return 0;
    }

    // @dev convert from 3Crv to BCrv (via DAI)
    function _convert_3crv_to_shares(uint _3crv) internal returns (uint _shares) {
        // convert to DAI
        uint[4] memory amounts;
        uint _before = bpoolTokens[0].balanceOf(address(this));
        stableSwap3Pool.remove_liquidity_one_coin(_3crv, 0, 1);
        uint _after = bpoolTokens[0].balanceOf(address(this));
        amounts[0] = _after.sub(_before);

        // add DAI to bpool to get back BCrv
        _before = tokenBCrv.balanceOf(address(this));
        depositBUSD.add_liquidity(amounts, 1);
        _after = tokenBCrv.balanceOf(address(this));

        _shares = _after.sub(_before);
    }

    // @dev convert from SUSD to BCrv (via DAI)
    function _convert_susd_to_shares(uint _amount) internal returns (uint _shares) {
        // convert to DAI
        uint[4] memory amounts;
        uint _before = bpoolTokens[0].balanceOf(address(this));
        stableSwapSUSD.exchange_underlying(int128(3), int128(0), _amount, 1);
        uint _after = bpoolTokens[0].balanceOf(address(this));
        amounts[0] = _after.sub(_before);

        // add DAI to bpool to get back BCrv
        _before = tokenBCrv.balanceOf(address(this));
        depositBUSD.add_liquidity(amounts, 1);
        _after = tokenBCrv.balanceOf(address(this));

        _shares = _after.sub(_before);
    }

    // @dev convert from HUSD to BCrv (HUSD -> 3Crv -> DAI -> BCrv)
    function _convert_husd_to_shares(uint _amount) internal returns (uint _shares) {
        // convert to 3Crv
        uint _before = token3Crv.balanceOf(address(this));
        stableSwapHUSD.exchange(int128(0), int128(1), _amount, 1);
        uint _after = token3Crv.balanceOf(address(this));
        _amount = _after.sub(_before);

        // convert 3Crv to DAI
        uint[4] memory amounts;
        _before = bpoolTokens[0].balanceOf(address(this));
        stableSwap3Pool.remove_liquidity_one_coin(_amount, 0, 1);
        _after = bpoolTokens[0].balanceOf(address(this));
        amounts[0] = _after.sub(_before);

        // add DAI to bpool to get back BCrv
        _before = tokenBCrv.balanceOf(address(this));
        depositBUSD.add_liquidity(amounts, 1);
        _after = tokenBCrv.balanceOf(address(this));

        _shares = _after.sub(_before);
    }

    // @dev convert from BCrv to HUSD (BCrv -> DAI -> 3Crv -> HUSD)
    function _convert_shares_to_husd(uint _amount) internal returns (uint _husd) {
        // convert to DAI
        uint[3] memory amounts;
        uint _before = bpoolTokens[0].balanceOf(address(this));
        depositBUSD.remove_liquidity_one_coin(_amount, 0, 1);
        uint _after = bpoolTokens[0].balanceOf(address(this));
        amounts[0] = _after.sub(_before);

        // add DAI to 3pool to get back 3Crv
        _before = token3Crv.balanceOf(address(this));
        stableSwap3Pool.add_liquidity(amounts, 1);
        _after = token3Crv.balanceOf(address(this));
        _amount = _after.sub(_before);

        // convert 3Crv to HUSD
        _before = tokenHUSD.balanceOf(address(this));
        stableSwapHUSD.exchange(int128(1), int128(0), _amount, 1);
        _after = tokenHUSD.balanceOf(address(this));
        _husd = _after.sub(_before);
    }

    function convertAll(uint[] calldata _amounts) external override returns (uint _outputAmount) {
        require(vaultMaster.isVault(msg.sender) || vaultMaster.isController(msg.sender) || msg.sender == governance, "!(governance||vault||controller)");
        uint _before = tokenBCrv.balanceOf(address(this));
        if (_amounts[0] > 0 || _amounts[1] > 0 || _amounts[2] > 0 || _amounts[4] == 0) {
            uint[4] memory _bpoolAmounts;
            _bpoolAmounts[0] = _amounts[0];
            _bpoolAmounts[1] = _amounts[1];
            _bpoolAmounts[2] = _amounts[2];
            _bpoolAmounts[3] = _amounts[4];
            depositBUSD.add_liquidity(_bpoolAmounts, 1);
        }
        if (_amounts[3] > 0) { // 3Crv
            _convert_3crv_to_shares(_amounts[3]);
        }
        if (_amounts[5] > 0) { // sUSD
            _convert_susd_to_shares(_amounts[5]);
        }
        if (_amounts[6] > 0) { // hUSD
            _convert_husd_to_shares(_amounts[6]);
        }
        uint _after = tokenBCrv.balanceOf(address(this));
        _outputAmount = _after.sub(_before);
        tokenBCrv.safeTransfer(msg.sender, _outputAmount);
        return _outputAmount;
    }

    function governanceRecoverUnsupported(IERC20 _token, uint _amount, address _to) external {
        require(msg.sender == governance, "!governance");
        _token.transfer(_to, _amount);
    }
}
