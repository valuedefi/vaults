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
import "../pool-interfaces/IStableSwapCompound.sol";

import "../pool-interfaces/IDepositCompound.sol";

// Supported Pool Tokens:
// 0. 3pool [DAI, USDC, USDT]
// 1. BUSD [(y)DAI, (y)USDC, (y)USDT, (y)BUSD]
// 2. sUSD [DAI, USDC, USDT, sUSD]
// 3. husd [HUSD, 3pool]
// 4. Compound [(c)DAI, (c)USDC]
// 5. Y [(y)DAI, (y)USDC, (y)USDT, (y)TUSD]
// 6. Swerve [(y)DAI...(y)TUSD]
contract StableSwapCompoundConverter is IMultiVaultConverter {
    using SafeMath for uint;
    using SafeERC20 for IERC20;

    IERC20[2] public cpoolTokens; // DAI, USDC

    IERC20 public tokenUSDT;

    IERC20 public tokenBUSD; // BUSD

    IERC20 public token3Crv; // 3Crv

    IERC20 public tokenSUSD; // sUSD

    IERC20 public tokenHUSD; // hUSD

    IERC20 public tokenCCrv; // cDAI+cUSDC ((c)DAI+(c)USDC)

    address public governance;

    IStableSwap3Pool public stableSwap3Pool;
    IStableSwapBUSD public stableSwapBUSD;
    IStableSwapSUSD public stableSwapSUSD;
    IStableSwapHUSD public stableSwapHUSD;
    IStableSwapCompound public stableSwapCompound;

    IDepositCompound public depositCompound;

    IValueVaultMaster public vaultMaster;

    uint public defaultSlippage = 1; // very small 0.01%

    // stableSwapUSD: 0. stableSwap3Pool, 1. stableSwapBUSD, 2. stableSwapSUSD, 3. stableSwapHUSD, 4. stableSwapCompound
    constructor (IERC20 _tokenDAI, IERC20 _tokenUSDC, IERC20 _tokenUSDT, IERC20 _token3Crv,
        IERC20 _tokenBUSD, IERC20 _tokenSUSD, IERC20 _tokenHUSD,
        IERC20 _tokenCCrv,
        address[] memory _stableSwapUSD,
        IDepositCompound _depositCompound,
        IValueVaultMaster _vaultMaster) public {
        cpoolTokens[0] = _tokenDAI;
        cpoolTokens[1] = _tokenUSDC;
        tokenUSDT = _tokenUSDT;
        tokenBUSD = _tokenBUSD;
        token3Crv = _token3Crv;
        tokenSUSD = _tokenSUSD;
        tokenHUSD = _tokenHUSD;
        tokenCCrv = _tokenCCrv;

        stableSwap3Pool = IStableSwap3Pool(_stableSwapUSD[0]);
        stableSwapBUSD = IStableSwapBUSD(_stableSwapUSD[1]);
        stableSwapSUSD = IStableSwapSUSD(_stableSwapUSD[2]);
        stableSwapHUSD = IStableSwapHUSD(_stableSwapUSD[3]);
        stableSwapCompound = IStableSwapCompound(_stableSwapUSD[4]);

        depositCompound = _depositCompound;

        cpoolTokens[0].safeApprove(address(stableSwap3Pool), type(uint256).max);
        cpoolTokens[1].safeApprove(address(stableSwap3Pool), type(uint256).max);
        tokenUSDT.safeApprove(address(stableSwap3Pool), type(uint256).max);
        token3Crv.safeApprove(address(stableSwap3Pool), type(uint256).max);

        cpoolTokens[0].safeApprove(address(stableSwapBUSD), type(uint256).max);
        cpoolTokens[1].safeApprove(address(stableSwapBUSD), type(uint256).max);
        tokenUSDT.safeApprove(address(stableSwapBUSD), type(uint256).max);
        tokenBUSD.safeApprove(address(stableSwapBUSD), type(uint256).max);

        cpoolTokens[0].safeApprove(address(stableSwapSUSD), type(uint256).max);
        cpoolTokens[1].safeApprove(address(stableSwapSUSD), type(uint256).max);
        tokenUSDT.safeApprove(address(stableSwapSUSD), type(uint256).max);
        tokenSUSD.safeApprove(address(stableSwapSUSD), type(uint256).max);

        token3Crv.safeApprove(address(stableSwapHUSD), type(uint256).max);
        tokenHUSD.safeApprove(address(stableSwapHUSD), type(uint256).max);

        cpoolTokens[0].safeApprove(address(stableSwapCompound), type(uint256).max);
        cpoolTokens[1].safeApprove(address(stableSwapCompound), type(uint256).max);
        tokenCCrv.safeApprove(address(stableSwapCompound), type(uint256).max);

        cpoolTokens[0].safeApprove(address(depositCompound), type(uint256).max);
        cpoolTokens[1].safeApprove(address(depositCompound), type(uint256).max);
        tokenCCrv.safeApprove(address(depositCompound), type(uint256).max);

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
        return address(tokenCCrv);
    }

    // Average dollar value of pool token
    function get_virtual_price() external override view returns (uint) {
        return stableSwapCompound.get_virtual_price();
    }

    function convert_rate(address _input, address _output, uint _inputAmount) public override view returns (uint _outputAmount) {
        if (_inputAmount == 0) return 0;
        if (_output == address(tokenCCrv)) { // convert to CCrv
            uint[2] memory _amounts;
            for (uint8 i = 0; i < 2; i++) {
                if (_input == address(cpoolTokens[i])) {
                    _amounts[i] = _inputAmount;
                    _outputAmount = stableSwapCompound.calc_token_amount(_amounts, true);
                    return _outputAmount.mul(10000 - defaultSlippage).div(10000);
                }
            }
            if (_input == address(tokenUSDT)) {
                _amounts[0] = stableSwap3Pool.get_dy(int128(2), int128(0), _inputAmount); // convert to DAI
                _outputAmount = stableSwapCompound.calc_token_amount(_amounts, true); // DAI -> CCrv
            }
            if (_input == address(tokenBUSD)) {
                _amounts[0] = stableSwapBUSD.get_dy_underlying(int128(3), int128(0), _inputAmount); // convert to DAI
                _outputAmount = stableSwapCompound.calc_token_amount(_amounts, true); // DAI -> CCrv
            }
            if (_input == address(tokenSUSD)) {
                _amounts[0] = stableSwapSUSD.get_dy_underlying(int128(3), int128(0), _inputAmount); // convert to DAI
                _outputAmount = stableSwapCompound.calc_token_amount(_amounts, true); // DAI -> CCrv
            }
            if (_input == address(tokenHUSD)) {
                uint _3crvAmount = stableSwapHUSD.get_dy(int128(0), int128(1), _inputAmount); // HUSD -> 3Crv
                _amounts[0] = stableSwap3Pool.calc_withdraw_one_coin(_3crvAmount, 0); // 3Crv -> DAI
                _outputAmount = stableSwapCompound.calc_token_amount(_amounts, true); // DAI -> CCrv
            }
            if (_input == address(token3Crv)) {
                _amounts[0] = stableSwap3Pool.calc_withdraw_one_coin(_inputAmount, 0); // 3Crv -> DAI
                _outputAmount = stableSwapCompound.calc_token_amount(_amounts, true); // DAI -> CCrv
            }
        } else if (_input == address(tokenCCrv)) { // convert from CCrv
            for (uint8 i = 0; i < 2; i++) {
                if (_output == address(cpoolTokens[i])) {
                    _outputAmount = depositCompound.calc_withdraw_one_coin(_inputAmount, i);
                    return _outputAmount.mul(10000 - defaultSlippage).div(10000);
                }
            }
            if (_output == address(tokenUSDT)) {
                uint _daiAmount = depositCompound.calc_withdraw_one_coin(_inputAmount, 0); // convert to DAI
                _outputAmount = stableSwap3Pool.get_dy(int128(0), int128(2), _daiAmount); // DAI -> USDT
            }
            if (_output == address(tokenBUSD)) {
                uint _daiAmount = depositCompound.calc_withdraw_one_coin(_inputAmount, 0); // convert to DAI
                _outputAmount = stableSwapBUSD.get_dy_underlying(int128(0), int128(3), _daiAmount); // DAI -> BUSD
            }
            if (_output == address(tokenSUSD)) {
                uint _daiAmount = depositCompound.calc_withdraw_one_coin(_inputAmount, 0); // CCrv -> DAI
                _outputAmount = stableSwapSUSD.get_dy_underlying(int128(0), int128(3), _daiAmount); // DAI -> SUSD
            }
            if (_output == address(tokenHUSD)) {
                uint _3crvAmount = _convert_ccrv_to_3crv_rate(_inputAmount); // CCrv -> DAI -> 3Crv
                _outputAmount = stableSwapHUSD.get_dy(int128(1), int128(0), _3crvAmount); // 3Crv -> HUSD
            }
        }
        if (_outputAmount > 0) {
            uint _slippage = _outputAmount.mul(vaultMaster.convertSlippage(_input, _output)).div(10000);
            _outputAmount = _outputAmount.sub(_slippage);
        }
    }

    function _convert_ccrv_to_3crv_rate(uint _ccrvAmount) internal view returns (uint _3crv) {
        uint[3] memory _amounts;
        _amounts[0] = depositCompound.calc_withdraw_one_coin(_ccrvAmount, 0); // CCrv -> DAI
        _3crv = stableSwap3Pool.calc_token_amount(_amounts, true); // DAI -> 3Crv
    }

    // 0: DAI, 1: USDC, 2: USDT, 3: 3Crv, 4: BUSD, 5: sUSD, 6: husd
    function calc_token_amount_deposit(uint[] calldata _amounts) external override view returns (uint _shareAmount) {
        if (_amounts[0] > 0 || _amounts[1] > 0) {
            uint[2] memory _cpoolAmounts;
            _cpoolAmounts[0] = _amounts[0];
            _cpoolAmounts[1] = _amounts[1];
            _shareAmount = stableSwapCompound.calc_token_amount(_cpoolAmounts, true);
        }
        if (_amounts[2] > 0) { // usdt
            _shareAmount = _shareAmount.add(convert_rate(address(tokenUSDT), address(tokenCCrv), _amounts[2]));
        }
        if (_amounts[3] > 0) { // 3crv
            _shareAmount = _shareAmount.add(convert_rate(address(token3Crv), address(tokenCCrv), _amounts[3]));
        }
        if (_amounts[4] > 0) { // busd
            _shareAmount = _shareAmount.add(convert_rate(address(token3Crv), address(tokenBUSD), _amounts[4]));
        }
        if (_amounts[5] > 0) { // susd
            _shareAmount = _shareAmount.add(convert_rate(address(token3Crv), address(tokenSUSD), _amounts[5]));
        }
        if (_amounts[6] > 0) { // husd
            _shareAmount = _shareAmount.add(convert_rate(address(token3Crv), address(tokenHUSD), _amounts[6]));
        }
        return _shareAmount;
    }

    function calc_token_amount_withdraw(uint _shares, address _output) external override view returns (uint _outputAmount) {
        for (uint8 i = 0; i < 2; i++) {
            if (_output == address(cpoolTokens[i])) {
                _outputAmount = depositCompound.calc_withdraw_one_coin(_shares, i);
                return _outputAmount.mul(10000 - defaultSlippage).div(10000);
            }
        }
        if (_output == address(token3Crv)) {
            _outputAmount = _convert_ccrv_to_3crv_rate(_shares); // CCrv -> DAI -> 3Crv
        } else if (_output == address(tokenUSDT)) {
            uint _daiAmount = depositCompound.calc_withdraw_one_coin(_shares, 0); // CCrv -> DAI
            _outputAmount = stableSwap3Pool.get_dy(int128(0), int128(2), _daiAmount); // DAI -> USDT
        } else if (_output == address(tokenBUSD)) {
            uint _daiAmount = depositCompound.calc_withdraw_one_coin(_shares, 0); // CCrv -> DAI
            _outputAmount = stableSwapBUSD.get_dy_underlying(int128(0), int128(3), _daiAmount); // DAI -> BUSD
        } else if (_output == address(tokenSUSD)) {
            uint _daiAmount = depositCompound.calc_withdraw_one_coin(_shares, 0); // CCrv -> DAI
            _outputAmount = stableSwapSUSD.get_dy_underlying(int128(0), int128(3), _daiAmount); // DAI -> SUSD
        } else if (_output == address(tokenHUSD)) {
            uint _3crvAmount = _convert_ccrv_to_3crv_rate(_shares); // CCrv -> DAI -> 3Crv
            _outputAmount = stableSwapHUSD.get_dy(int128(1), int128(0), _3crvAmount); // 3Crv -> HUSD
        }
        if (_outputAmount > 0) {
            uint _slippage = _outputAmount.mul(vaultMaster.slippage(_output)).div(10000);
            _outputAmount = _outputAmount.sub(_slippage);
        }
    }

    function convert(address _input, address _output, uint _inputAmount) external override returns (uint _outputAmount) {
        require(vaultMaster.isVault(msg.sender) || vaultMaster.isController(msg.sender) || msg.sender == governance, "!(governance||vault||controller)");
        if (_output == address(tokenCCrv)) { // convert to CCrv
            uint[2] memory amounts;
            for (uint8 i = 0; i < 2; i++) {
                if (_input == address(cpoolTokens[i])) {
                    amounts[i] = _inputAmount;
                    uint _before = tokenCCrv.balanceOf(address(this));
                    depositCompound.add_liquidity(amounts, 1);
                    uint _after = tokenCCrv.balanceOf(address(this));
                    _outputAmount = _after.sub(_before);
                    tokenCCrv.safeTransfer(msg.sender, _outputAmount);
                    return _outputAmount;
                }
            }
            if (_input == address(token3Crv)) {
                _outputAmount = _convert_3crv_to_shares(_inputAmount);
                tokenCCrv.safeTransfer(msg.sender, _outputAmount);
                return _outputAmount;
            }
            if (_input == address(tokenUSDT)) {
                _outputAmount = _convert_usdt_to_shares(_inputAmount);
                tokenCCrv.safeTransfer(msg.sender, _outputAmount);
                return _outputAmount;
            }
            if (_input == address(tokenBUSD)) {
                _outputAmount = _convert_busd_to_shares(_inputAmount);
                tokenCCrv.safeTransfer(msg.sender, _outputAmount);
                return _outputAmount;
            }
            if (_input == address(tokenSUSD)) {
                _outputAmount = _convert_susd_to_shares(_inputAmount);
                tokenCCrv.safeTransfer(msg.sender, _outputAmount);
                return _outputAmount;
            }
            if (_input == address(tokenHUSD)) {
                _outputAmount = _convert_husd_to_shares(_inputAmount);
                tokenCCrv.safeTransfer(msg.sender, _outputAmount);
                return _outputAmount;
            }
        } else if (_input == address(tokenCCrv)) { // convert from CCrv
            for (uint8 i = 0; i < 2; i++) {
                if (_output == address(cpoolTokens[i])) {
                    uint _before = cpoolTokens[i].balanceOf(address(this));
                    depositCompound.remove_liquidity_one_coin(_inputAmount, i, 1);
                    uint _after = cpoolTokens[i].balanceOf(address(this));
                    _outputAmount = _after.sub(_before);
                    cpoolTokens[i].safeTransfer(msg.sender, _outputAmount);
                    return _outputAmount;
                }
            }
            if (_output == address(token3Crv)) {
                // remove CCrv to DAI
                uint[3] memory amounts;
                uint _before = cpoolTokens[0].balanceOf(address(this));
                depositCompound.remove_liquidity_one_coin(_inputAmount, 0, 1);
                uint _after = cpoolTokens[0].balanceOf(address(this));
                amounts[0] = _after.sub(_before);

                // add DAI to 3pool to get back 3Crv
                _before = token3Crv.balanceOf(address(this));
                stableSwap3Pool.add_liquidity(amounts, 1);
                _after = token3Crv.balanceOf(address(this));
                _outputAmount = _after.sub(_before);

                token3Crv.safeTransfer(msg.sender, _outputAmount);
                return _outputAmount;
            }
            if (_output == address(tokenUSDT)) {
                // remove CCrv to DAI
                uint _before = cpoolTokens[0].balanceOf(address(this));
                depositCompound.remove_liquidity_one_coin(_inputAmount, 0, 1);
                uint _after = cpoolTokens[0].balanceOf(address(this));
                _outputAmount = _after.sub(_before);

                // convert DAI to USDT
                _before = tokenUSDT.balanceOf(address(this));
                stableSwap3Pool.exchange(int128(0), int128(2), _outputAmount, 1);
                _after = tokenUSDT.balanceOf(address(this));
                _outputAmount = _after.sub(_before);

                tokenUSDT.safeTransfer(msg.sender, _outputAmount);
                return _outputAmount;
            }
            if (_output == address(tokenBUSD)) {
                // remove CCrv to DAI
                uint _before = cpoolTokens[0].balanceOf(address(this));
                depositCompound.remove_liquidity_one_coin(_inputAmount, 0, 1);
                uint _after = cpoolTokens[0].balanceOf(address(this));
                _outputAmount = _after.sub(_before);

                // convert DAI to BUSD
                _before = tokenBUSD.balanceOf(address(this));
                stableSwapBUSD.exchange_underlying(int128(0), int128(3), _outputAmount, 1);
                _after = tokenBUSD.balanceOf(address(this));
                _outputAmount = _after.sub(_before);

                tokenBUSD.safeTransfer(msg.sender, _outputAmount);
                return _outputAmount;
            }
            if (_output == address(tokenSUSD)) {
                // remove CCrv to DAI
                uint _before = cpoolTokens[0].balanceOf(address(this));
                depositCompound.remove_liquidity_one_coin(_inputAmount, 0, 1);
                uint _after = cpoolTokens[0].balanceOf(address(this));
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

    // @dev convert from 3Crv to CCrv (via DAI)
    function _convert_3crv_to_shares(uint _3crv) internal returns (uint _shares) {
        // convert to DAI
        uint[2] memory amounts;
        uint _before = cpoolTokens[0].balanceOf(address(this));
        stableSwap3Pool.remove_liquidity_one_coin(_3crv, 0, 1);
        uint _after = cpoolTokens[0].balanceOf(address(this));
        amounts[0] = _after.sub(_before);

        // add DAI to cpool to get back CCrv
        _before = tokenCCrv.balanceOf(address(this));
        depositCompound.add_liquidity(amounts, 1);
        _after = tokenCCrv.balanceOf(address(this));

        _shares = _after.sub(_before);
    }

    // @dev convert from USDT to CCrv (via DAI)
    function _convert_usdt_to_shares(uint _usdt) internal returns (uint _shares) {
        // convert to DAI
        uint[2] memory amounts;
        uint _before = cpoolTokens[0].balanceOf(address(this));
        stableSwap3Pool.exchange(2, 0, _usdt, 1);
        uint _after = cpoolTokens[0].balanceOf(address(this));
        amounts[0] = _after.sub(_before);

        // add DAI to cpool to get back CCrv
        _before = tokenCCrv.balanceOf(address(this));
        depositCompound.add_liquidity(amounts, 1);
        _after = tokenCCrv.balanceOf(address(this));

        _shares = _after.sub(_before);
    }

    // @dev convert from BUSD to CCrv (via DAI)
    function _convert_busd_to_shares(uint _busd) internal returns (uint _shares) {
        // convert to DAI
        uint[2] memory amounts;
        uint _before = cpoolTokens[0].balanceOf(address(this));
        stableSwapBUSD.exchange_underlying(3, 0, _busd, 1);
        uint _after = cpoolTokens[0].balanceOf(address(this));
        amounts[0] = _after.sub(_before);

        // add DAI to cpool to get back CCrv
        _before = tokenCCrv.balanceOf(address(this));
        depositCompound.add_liquidity(amounts, 1);
        _after = tokenCCrv.balanceOf(address(this));

        _shares = _after.sub(_before);
    }

    // @dev convert from SUSD to CCrv (via DAI)
    function _convert_susd_to_shares(uint _amount) internal returns (uint _shares) {
        // convert to DAI
        uint[2] memory amounts;
        uint _before = cpoolTokens[0].balanceOf(address(this));
        stableSwapSUSD.exchange_underlying(int128(3), int128(0), _amount, 1);
        uint _after = cpoolTokens[0].balanceOf(address(this));
        amounts[0] = _after.sub(_before);

        // add DAI to cpool to get back CCrv
        _before = tokenCCrv.balanceOf(address(this));
        depositCompound.add_liquidity(amounts, 1);
        _after = tokenCCrv.balanceOf(address(this));

        _shares = _after.sub(_before);
    }

    // @dev convert from HUSD to CCrv (HUSD -> 3Crv -> DAI -> CCrv)
    function _convert_husd_to_shares(uint _amount) internal returns (uint _shares) {
        // convert to 3Crv
        uint _before = token3Crv.balanceOf(address(this));
        stableSwapHUSD.exchange(int128(0), int128(1), _amount, 1);
        uint _after = token3Crv.balanceOf(address(this));
        _amount = _after.sub(_before);

        // convert 3Crv to DAI
        uint[2] memory amounts;
        _before = cpoolTokens[0].balanceOf(address(this));
        stableSwap3Pool.remove_liquidity_one_coin(_amount, 0, 1);
        _after = cpoolTokens[0].balanceOf(address(this));
        amounts[0] = _after.sub(_before);

        // add DAI to cpool to get back CCrv
        _before = tokenCCrv.balanceOf(address(this));
        depositCompound.add_liquidity(amounts, 1);
        _after = tokenCCrv.balanceOf(address(this));

        _shares = _after.sub(_before);
    }

    // @dev convert from CCrv to HUSD (CCrv -> DAI -> 3Crv -> HUSD)
    function _convert_shares_to_husd(uint _amount) internal returns (uint _husd) {
        // convert to DAI
        uint[3] memory amounts;
        uint _before = cpoolTokens[0].balanceOf(address(this));
        depositCompound.remove_liquidity_one_coin(_amount, 0, 1);
        uint _after = cpoolTokens[0].balanceOf(address(this));
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
        uint _before = tokenCCrv.balanceOf(address(this));
        if (_amounts[0] > 0 || _amounts[1] > 0) {
            uint[2] memory _cpoolAmounts;
            _cpoolAmounts[0] = _amounts[0];
            _cpoolAmounts[1] = _amounts[1];
            depositCompound.add_liquidity(_cpoolAmounts, 1);
        }
        if (_amounts[2] > 0) { // USDT
            _convert_usdt_to_shares(_amounts[2]);
        }
        if (_amounts[3] > 0) { // 3Crv
            _convert_3crv_to_shares(_amounts[3]);
        }
        if (_amounts[4] > 0) { // BUSD
            _convert_busd_to_shares(_amounts[4]);
        }
        if (_amounts[5] > 0) { // sUSD
            _convert_susd_to_shares(_amounts[5]);
        }
        if (_amounts[6] > 0) { // hUSD
            _convert_husd_to_shares(_amounts[6]);
        }
        uint _after = tokenCCrv.balanceOf(address(this));
        _outputAmount = _after.sub(_before);
        tokenCCrv.safeTransfer(msg.sender, _outputAmount);
        return _outputAmount;
    }

    function governanceRecoverUnsupported(IERC20 _token, uint _amount, address _to) external {
        require(msg.sender == governance, "!governance");
        _token.transfer(_to, _amount);
    }
}
