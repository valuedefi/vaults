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
contract StableSwap3PoolConverter is IMultiVaultConverter {
    using SafeMath for uint;
    using SafeERC20 for IERC20;

    IERC20[3] public pool3CrvTokens; // DAI, USDC, USDT
    IERC20 public token3Crv; // 3Crv

    IERC20 public tokenBUSD; // BUSD
    IERC20 public tokenBCrv; // BCrv (yDAI+yUSDC+yUSDT+yBUSD)

    IERC20 public tokenSUSD; // sUSD
    IERC20 public tokenSCrv; // sCrv (DAI/USDC/USDT/sUSD)

    IERC20 public tokenHUSD; // hUSD
    IERC20 public tokenHCrv; // hCrv (HUSD/3Crv)

    address public governance;

    IStableSwap3Pool public stableSwap3Pool;
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
        IValueVaultMaster _vaultMaster) public {
        pool3CrvTokens[0] = _tokenDAI;
        pool3CrvTokens[1] = _tokenUSDC;
        pool3CrvTokens[2] = _tokenUSDT;
        token3Crv = _token3Crv;
        tokenBUSD = _tokenBUSD;
        tokenBCrv = _tokenBCrv;
        tokenSUSD = _tokenSUSD;
        tokenSCrv = _tokenSCrv;
        tokenHUSD = _tokenHUSD;
        tokenHCrv = _tokenHCrv;
        stableSwap3Pool = _stableSwap3Pool;
        stableSwapBUSD = _stableSwapBUSD;
        stableSwapSUSD = _stableSwapSUSD;
        stableSwapHUSD = _stableSwapHUSD;

        pool3CrvTokens[0].safeApprove(address(stableSwap3Pool), type(uint256).max);
        pool3CrvTokens[1].safeApprove(address(stableSwap3Pool), type(uint256).max);
        pool3CrvTokens[2].safeApprove(address(stableSwap3Pool), type(uint256).max);
        token3Crv.safeApprove(address(stableSwap3Pool), type(uint256).max);

        pool3CrvTokens[0].safeApprove(address(stableSwapBUSD), type(uint256).max);
        pool3CrvTokens[1].safeApprove(address(stableSwapBUSD), type(uint256).max);
        pool3CrvTokens[2].safeApprove(address(stableSwapBUSD), type(uint256).max);
        tokenBUSD.safeApprove(address(stableSwapBUSD), type(uint256).max);
        tokenBCrv.safeApprove(address(stableSwapBUSD), type(uint256).max);

        pool3CrvTokens[0].safeApprove(address(stableSwapSUSD), type(uint256).max);
        pool3CrvTokens[1].safeApprove(address(stableSwapSUSD), type(uint256).max);
        pool3CrvTokens[2].safeApprove(address(stableSwapSUSD), type(uint256).max);
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
        return address(token3Crv);
    }

    // Average dollar value of pool token
    function get_virtual_price() external override view returns (uint) {
        return stableSwap3Pool.get_virtual_price();
    }

    function convert_rate(address _input, address _output, uint _inputAmount) public override view returns (uint _outputAmount) {
        if (_inputAmount == 0) return 0;
        if (_output == address(token3Crv)) { // convert to 3Crv
            uint[3] memory _amounts;
            for (uint8 i = 0; i < 3; i++) {
                if (_input == address(pool3CrvTokens[i])) {
                    _amounts[i] = _inputAmount;
                    _outputAmount = stableSwap3Pool.calc_token_amount(_amounts, true);
                    return _outputAmount.mul(10000 - defaultSlippage).div(10000);
                }
            }
            if (_input == address(tokenBUSD)) {
                _amounts[1] = stableSwapBUSD.get_dy_underlying(int128(3), int128(1), _inputAmount); // convert to USDC
                _outputAmount = stableSwap3Pool.calc_token_amount(_amounts, true); // USDC -> 3Crv
            }
            if (_input == address(tokenSUSD)) {
                _amounts[1] = stableSwapSUSD.get_dy_underlying(int128(3), int128(1), _inputAmount); // convert to USDC
                _outputAmount = stableSwap3Pool.calc_token_amount(_amounts, true); // USDC -> 3Crv
            }
            if (_input == address(tokenHUSD)) {
                _outputAmount = stableSwapHUSD.get_dy(int128(0), int128(1), _inputAmount); // HUSD -> 3Crv
            }
        } else if (_input == address(token3Crv)) { // convert from 3Crv
            for (uint8 i = 0; i < 3; i++) {
                if (_output == address(pool3CrvTokens[i])) {
                    // @dev this is for UI reference only, the actual share price (stable/CRV) will be re-calculated on-chain when we do convert()
                    _outputAmount = stableSwap3Pool.calc_withdraw_one_coin(_inputAmount, i);
                    return _outputAmount.mul(10000 - defaultSlippage).div(10000);
                }
            }
            if (_output == address(tokenBUSD)) {
                uint _usdcAmount = stableSwap3Pool.calc_withdraw_one_coin(_inputAmount, 1); // 3Crv -> USDC
                _outputAmount = stableSwapBUSD.get_dy_underlying(int128(1), int128(3), _usdcAmount); // USDC -> BUSD
            }
            if (_output == address(tokenSUSD)) {
                uint _usdcAmount = stableSwap3Pool.calc_withdraw_one_coin(_inputAmount, 1); // 3Crv -> USDC
                _outputAmount = stableSwapSUSD.get_dy_underlying(int128(1), int128(3), _usdcAmount); // USDC -> BUSD
            }
            if (_output == address(tokenHUSD)) {
                _outputAmount = stableSwapHUSD.get_dy(int128(1), int128(0), _inputAmount); // 3Crv -> HUSD
            }
        }
        if (_outputAmount > 0) {
            uint _slippage = _outputAmount.mul(vaultMaster.convertSlippage(_input, _output)).div(10000);
            _outputAmount = _outputAmount.sub(_slippage);
        }
    }

    // 0: DAI, 1: USDC, 2: USDT, 3: 3Crv, 4: BUSD, 5: sUSD, 6: husd
    function calc_token_amount_deposit(uint[] calldata _amounts) external override view returns (uint _shareAmount) {
        _shareAmount = _amounts[3]; // 3Crv amount
        uint[3] memory _3poolAmounts;
        _3poolAmounts[0] = _amounts[0];
        _3poolAmounts[1] = _amounts[1];
        _3poolAmounts[2] = _amounts[2];
        uint _3poolTo3crv = stableSwap3Pool.calc_token_amount(_3poolAmounts, true);
        uint _busdTo3Crv = convert_rate(address(tokenBUSD), address(token3Crv), _amounts[4]);
        uint _susdTo3Crv = convert_rate(address(tokenSUSD), address(token3Crv), _amounts[5]);
        uint _husdTo3Crv = convert_rate(address(tokenHUSD), address(token3Crv), _amounts[6]);
        return _shareAmount.add(_3poolTo3crv).add(_busdTo3Crv).add(_susdTo3Crv).add(_husdTo3Crv);
    }

    // @dev we use curve function calc_withdraw_one_coin() for UI reference only
    // the actual share price (stable/CRV) will be re-calculated on-chain when we do convert()
    function calc_token_amount_withdraw(uint _shares, address _output) external override view returns (uint _outputAmount) {
        for (uint8 i = 0; i < 3; i++) {
            if (_output == address(pool3CrvTokens[i])) {
                return stableSwap3Pool.calc_withdraw_one_coin(_shares, i);
            }
        }
        if (_output == address(tokenBUSD)) {
            uint _usdcAmount = stableSwap3Pool.calc_withdraw_one_coin(_shares, 1); // 3Crv -> USDC
            _outputAmount = stableSwapBUSD.get_dy_underlying(int128(1), int128(3), _usdcAmount); // USDC -> BUSD
        } else if (_output == address(tokenSUSD)) {
            uint _usdcAmount = stableSwap3Pool.calc_withdraw_one_coin(_shares, 1); // 3Crv -> USDC
            _outputAmount = stableSwapSUSD.get_dy_underlying(int128(1), int128(3), _usdcAmount); // USDC -> SUSD
        } else if (_output == address(tokenHUSD)) {
            _outputAmount = stableSwapHUSD.get_dy(int128(1), int128(0), _shares); // 3Crv -> HUSD
        }
        if (_outputAmount > 0) {
            uint _slippage = _outputAmount.mul(vaultMaster.slippage(_output)).div(10000);
            _outputAmount = _outputAmount.sub(_slippage);
        }
    }

    function convert(address _input, address _output, uint _inputAmount) external override returns (uint _outputAmount) {
        require(vaultMaster.isVault(msg.sender) || vaultMaster.isController(msg.sender) || msg.sender == governance, "!(governance||vault||controller)");
        if (_output == address(token3Crv)) { // convert to 3Crv
            uint[3] memory amounts;
            for (uint8 i = 0; i < 3; i++) {
                if (_input == address(pool3CrvTokens[i])) {
                    amounts[i] = _inputAmount;
                    uint _before = token3Crv.balanceOf(address(this));
                    stableSwap3Pool.add_liquidity(amounts, 1);
                    uint _after = token3Crv.balanceOf(address(this));
                    _outputAmount = _after.sub(_before);
                    token3Crv.safeTransfer(msg.sender, _outputAmount);
                    return _outputAmount;
                }
            }
            if (_input == address(tokenBUSD)) {
                _outputAmount = _convert_busd_to_shares(_inputAmount);
                token3Crv.safeTransfer(msg.sender, _outputAmount);
                return _outputAmount;
            }
            if (_input == address(tokenSUSD)) {
                _outputAmount = _convert_susd_to_shares(_inputAmount);
                token3Crv.safeTransfer(msg.sender, _outputAmount);
                return _outputAmount;
            }
            if (_input == address(tokenHUSD)) {
                _outputAmount = _convert_husd_to_shares(_inputAmount);
                token3Crv.safeTransfer(msg.sender, _outputAmount);
                return _outputAmount;
            }
        } else if (_input == address(token3Crv)) { // convert from 3Crv
            for (uint8 i = 0; i < 3; i++) {
                if (_output == address(pool3CrvTokens[i])) {
                    uint _before = pool3CrvTokens[i].balanceOf(address(this));
                    stableSwap3Pool.remove_liquidity_one_coin(_inputAmount, i, 1);
                    uint _after = pool3CrvTokens[i].balanceOf(address(this));
                    _outputAmount = _after.sub(_before);
                    pool3CrvTokens[i].safeTransfer(msg.sender, _outputAmount);
                    return _outputAmount;
                }
            }
            if (_output == address(tokenBUSD)) {
                // remove 3Crv to USDC
                uint _before = pool3CrvTokens[1].balanceOf(address(this));
                stableSwap3Pool.remove_liquidity_one_coin(_inputAmount, 1, 1);
                uint _after = pool3CrvTokens[1].balanceOf(address(this));
                _outputAmount = _after.sub(_before);

                // convert USDC to BUSD
                _before = tokenBUSD.balanceOf(address(this));
                stableSwapBUSD.exchange_underlying(int128(1), int128(3), _outputAmount, 1);
                _after = tokenBUSD.balanceOf(address(this));
                _outputAmount = _after.sub(_before);

                tokenBUSD.safeTransfer(msg.sender, _outputAmount);
                return _outputAmount;
            }
            if (_output == address(tokenSUSD)) {
                // remove 3Crv to USDC
                uint _before = pool3CrvTokens[1].balanceOf(address(this));
                stableSwap3Pool.remove_liquidity_one_coin(_inputAmount, 1, 1);
                uint _after = pool3CrvTokens[1].balanceOf(address(this));
                _outputAmount = _after.sub(_before);

                // convert USDC to SUSD
                _before = tokenSUSD.balanceOf(address(this));
                stableSwapSUSD.exchange_underlying(int128(1), int128(3), _outputAmount, 1);
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

    // @dev convert from BUSD to 3Crv (via USDC)
    function _convert_busd_to_shares(uint _amount) internal returns (uint _shares) {
        // convert to USDC
        uint[3] memory amounts;
        uint _before = pool3CrvTokens[1].balanceOf(address(this));
        stableSwapBUSD.exchange_underlying(int128(3), int128(1), _amount, 1);
        uint _after = pool3CrvTokens[1].balanceOf(address(this));
        amounts[1] = _after.sub(_before);

        // add USDC to 3pool to get back 3Crv
        _before = token3Crv.balanceOf(address(this));
        stableSwap3Pool.add_liquidity(amounts, 1);
        _after = token3Crv.balanceOf(address(this));

        _shares = _after.sub(_before);
    }

    // @dev convert from SUSD to 3Crv (via USDC)
    function _convert_susd_to_shares(uint _amount) internal returns (uint _shares) {
        // convert to USDC
        uint[3] memory amounts;
        uint _before = pool3CrvTokens[1].balanceOf(address(this));
        stableSwapSUSD.exchange_underlying(int128(3), int128(1), _amount, 1);
        uint _after = pool3CrvTokens[1].balanceOf(address(this));
        amounts[1] = _after.sub(_before);

        // add USDC to 3pool to get back 3Crv
        _before = token3Crv.balanceOf(address(this));
        stableSwap3Pool.add_liquidity(amounts, 1);
        _after = token3Crv.balanceOf(address(this));

        _shares = _after.sub(_before);
    }

    // @dev convert from HUSD to 3Crv
    function _convert_husd_to_shares(uint _amount) internal returns (uint _shares) {
        uint _before = token3Crv.balanceOf(address(this));
        stableSwapHUSD.exchange(int128(0), int128(1), _amount, 1);
        uint _after = token3Crv.balanceOf(address(this));

        _shares = _after.sub(_before);
    }

    // @dev convert from 3Crv to HUSD
    function _convert_shares_to_husd(uint _amount) internal returns (uint _husd) {
        uint _before = tokenHUSD.balanceOf(address(this));
        stableSwapHUSD.exchange(int128(1), int128(0), _amount, 1);
        uint _after = tokenHUSD.balanceOf(address(this));

        _husd = _after.sub(_before);
    }

    function convertAll(uint[] calldata _amounts) external override returns (uint _outputAmount) {
        require(vaultMaster.isVault(msg.sender) || vaultMaster.isController(msg.sender) || msg.sender == governance, "!(governance||vault||controller)");
        uint _before = token3Crv.balanceOf(address(this));
        if (_amounts[0] > 0 || _amounts[1] > 0 || _amounts[2] > 0) {
            uint[3] memory _3poolAmounts;
            _3poolAmounts[0] = _amounts[0];
            _3poolAmounts[1] = _amounts[1];
            _3poolAmounts[2] = _amounts[2];
            stableSwap3Pool.add_liquidity(_3poolAmounts, 1);
        }
        // if (_amounts[3] > 0) { // 3Crv
        // }
        if (_amounts[4] > 0) { // BUSD
            _convert_busd_to_shares(_amounts[4]);
        }
        if (_amounts[5] > 0) { // sUSD
            _convert_susd_to_shares(_amounts[5]);
        }
        if (_amounts[6] > 0) { // hUSD
            _convert_husd_to_shares(_amounts[6]);
        }
        uint _after = token3Crv.balanceOf(address(this));
        _outputAmount = _after.sub(_before);
        token3Crv.safeTransfer(msg.sender, _outputAmount);
        return _outputAmount;
    }

    function governanceRecoverUnsupported(IERC20 _token, uint _amount, address _to) external {
        require(msg.sender == governance, "!governance");
        _token.transfer(_to, _amount);
    }
}
