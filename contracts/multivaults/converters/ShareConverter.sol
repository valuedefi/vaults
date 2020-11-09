// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";

import "../IShareConverter.sol";
import "../IValueVaultMaster.sol";

import "../pool-interfaces/IStableSwap3Pool.sol";
import "../pool-interfaces/IDepositBUSD.sol";
import "../pool-interfaces/IStableSwapBUSD.sol";
import "../pool-interfaces/IDepositSUSD.sol";
import "../pool-interfaces/IStableSwapSUSD.sol";
import "../pool-interfaces/IDepositHUSD.sol";
import "../pool-interfaces/IStableSwapHUSD.sol";
import "../pool-interfaces/IDepositCompound.sol";
import "../pool-interfaces/IStableSwapCompound.sol";

// 0. 3pool [DAI, USDC, USDT]                  ## APY: 0.88% +8.53% (CRV)                  ## Vol: $16,800,095  ## Liquidity: $163,846,738  (https://etherscan.io/address/0xbEbc44782C7dB0a1A60Cb6fe97d0b483032FF1C7)
// 1. BUSD [(y)DAI, (y)USDC, (y)USDT, (y)BUSD] ## APY: 2.54% +11.16%                       ## Vol: $6,580,652   ## Liquidity: $148,930,780  (https://etherscan.io/address/0x79a8C46DeA5aDa233ABaFFD40F3A0A2B1e5A4F27)
// 2. sUSD [DAI, USDC, USDT, sUSD]             ## APY: 2.59% +2.19% (SNX) +13.35% (CRV)    ## Vol: $11,854,566  ## Liquidity: $53,575,781   (https://etherscan.io/address/0xA5407eAE9Ba41422680e2e00537571bcC53efBfD)
// 3. husd [HUSD, 3pool]                       ## APY: 0.53% +8.45% (CRV)                  ## Vol: $0           ## Liquidity: $1,546,077    (https://etherscan.io/address/0x3eF6A01A0f81D6046290f3e2A8c5b843e738E604)
// 4. Compound [(c)DAI, (c)USDC]               ## APY: 3.97% +9.68% (CRV)                  ## Vol: $2,987,370   ## Liquidity: $121,783,878  (https://etherscan.io/address/0xA2B47E3D5c44877cca798226B7B8118F9BFb7A56)
// 5. Y [(y)DAI, (y)USDC, (y)USDT, (y)TUSD]    ## APY: 3.37% +8.39% (CRV)                  ## Vol: $8,374,971   ## Liquidity: $176,470,728  (https://etherscan.io/address/0x45F783CCE6B7FF23B2ab2D70e416cdb7D6055f51)
// 6. Swerve [(y)DAI...(y)TUSD]                ## APY: 0.43% +6.05% (CRV)                  ## Vol: $1,567,681   ## Liquidity: $28,631,966   (https://etherscan.io/address/0x329239599afB305DA0A2eC69c58F8a6697F9F88d)
contract ShareConverter is IShareConverter {
    using SafeMath for uint;
    using SafeERC20 for IERC20;

    IERC20[3] public pool3CrvTokens; // DAI, USDC, USDT
    IERC20 public token3CRV; // 3Crv

    IERC20 public tokenBUSD; // BUSD
    IERC20 public tokenBCrv; // BCrv (yDAI+yUSDC+yUSDT+yBUSD)

    IERC20 public tokenSUSD; // sUSD
    IERC20 public tokenSCrv; // SCrv (DAI/USDC/USDT/sUSD)

    IERC20 public tokenHUSD; // hUSD
    IERC20 public tokenHCrv; // HCrv (hUSD/3CRV)

    IERC20 public tokenCCrv; // cDAI+cUSDC ((c)DAI+(c)USDC)

    address public governance;

    IStableSwap3Pool public stableSwap3Pool;

    IDepositBUSD public depositBUSD;
    IStableSwapBUSD public stableSwapBUSD;

    IDepositSUSD public depositSUSD;
    IStableSwapSUSD public stableSwapSUSD;

    IDepositHUSD public depositHUSD;
    IStableSwapHUSD public stableSwapHUSD;

    IDepositCompound public depositCompound;
    IStableSwapCompound public stableSwapCompound;

    IValueVaultMaster public vaultMaster;

    // tokens: 0. BUSD, 1. sUSD, 2. hUSD
    // tokenCrvs: 0. BCrv, 1. SCrv, 2. HCrv
    // depositUSD: 0. depositBUSD, 1. depositSUSD, 2. depositHUSD, 3. depositCompound
    // stableSwapUSD: 0. stableSwapBUSD, 1. stableSwapSUSD, 2. stableSwapHUSD, 3. stableSwapCompound
    constructor (
        IERC20 _tokenDAI, IERC20 _tokenUSDC, IERC20 _tokenUSDT, IERC20 _token3CRV,
        IERC20[] memory _tokens, IERC20[] memory _tokenCrvs,
        address[] memory _depositUSD, address[] memory _stableSwapUSD,
        IStableSwap3Pool _stableSwap3Pool,
        IValueVaultMaster _vaultMaster) public {
        pool3CrvTokens[0] = _tokenDAI;
        pool3CrvTokens[1] = _tokenUSDC;
        pool3CrvTokens[2] = _tokenUSDT;

        token3CRV = _token3CRV;
        tokenBUSD = _tokens[0];
        tokenBCrv = _tokenCrvs[0];
        tokenSUSD = _tokens[1];
        tokenSCrv = _tokenCrvs[1];
        tokenHUSD = _tokens[2];
        tokenHCrv = _tokenCrvs[2];
        tokenCCrv = _tokenCrvs[3];

        stableSwap3Pool = _stableSwap3Pool;

        depositBUSD = IDepositBUSD(_depositUSD[0]);
        stableSwapBUSD = IStableSwapBUSD(_stableSwapUSD[0]);

        depositSUSD = IDepositSUSD(_depositUSD[1]);
        stableSwapSUSD = IStableSwapSUSD(_stableSwapUSD[1]);

        depositHUSD = IDepositHUSD(_depositUSD[2]);
        stableSwapHUSD = IStableSwapHUSD(_stableSwapUSD[2]);

        depositCompound = IDepositCompound(_depositUSD[3]);
        stableSwapCompound = IStableSwapCompound(_stableSwapUSD[3]);

        for (uint i = 0; i < 3; i++) {
            pool3CrvTokens[i].safeApprove(address(stableSwap3Pool), type(uint256).max);
            pool3CrvTokens[i].safeApprove(address(stableSwapBUSD), type(uint256).max);
            pool3CrvTokens[i].safeApprove(address(depositBUSD), type(uint256).max);
            pool3CrvTokens[i].safeApprove(address(stableSwapSUSD), type(uint256).max);
            pool3CrvTokens[i].safeApprove(address(depositSUSD), type(uint256).max);
            pool3CrvTokens[i].safeApprove(address(stableSwapHUSD), type(uint256).max);
            pool3CrvTokens[i].safeApprove(address(depositHUSD), type(uint256).max);
            if (i < 2) { // DAI && USDC
                pool3CrvTokens[i].safeApprove(address(depositCompound), type(uint256).max);
                pool3CrvTokens[i].safeApprove(address(stableSwapCompound), type(uint256).max);
            }
        }

        token3CRV.safeApprove(address(stableSwap3Pool), type(uint256).max);

        tokenBUSD.safeApprove(address(stableSwapBUSD), type(uint256).max);
        tokenBCrv.safeApprove(address(stableSwapBUSD), type(uint256).max);
        tokenBCrv.safeApprove(address(depositBUSD), type(uint256).max);

        tokenSUSD.safeApprove(address(stableSwapSUSD), type(uint256).max);
        tokenSCrv.safeApprove(address(stableSwapSUSD), type(uint256).max);
        tokenSCrv.safeApprove(address(depositSUSD), type(uint256).max);

        tokenHCrv.safeApprove(address(stableSwapHUSD), type(uint256).max);
        tokenHCrv.safeApprove(address(depositHUSD), type(uint256).max);

        tokenCCrv.safeApprove(address(depositCompound), type(uint256).max);
        tokenCCrv.safeApprove(address(stableSwapCompound), type(uint256).max);

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

    function convert_shares_rate(address _input, address _output, uint _inputAmount) external override view returns (uint _outputAmount) {
        if (_output == address(token3CRV)) {
            if (_input == address(tokenBCrv)) { // convert from BCrv -> 3CRV
                uint[3] memory _amounts;
                _amounts[1] = depositBUSD.calc_withdraw_one_coin(_inputAmount, 1); // BCrv -> USDC
                _outputAmount = stableSwap3Pool.calc_token_amount(_amounts, true); // USDC -> 3CRV
            } else if (_input == address(tokenSCrv)) { // convert from SCrv -> 3CRV
                uint[3] memory _amounts;
                _amounts[1] = depositSUSD.calc_withdraw_one_coin(_inputAmount, 1); // SCrv -> USDC
                _outputAmount = stableSwap3Pool.calc_token_amount(_amounts, true); // USDC -> 3CRV
            } else if (_input == address(tokenHCrv)) { // convert from HCrv -> 3CRV
                _outputAmount = stableSwapHUSD.calc_withdraw_one_coin(_inputAmount, 1); // HCrv -> 3CRV
            } else if (_input == address(tokenCCrv)) { // convert from CCrv -> 3CRV
                uint[3] memory _amounts;
                _amounts[1] = depositCompound.calc_withdraw_one_coin(_inputAmount, 1); // CCrv -> USDC
                _outputAmount = stableSwap3Pool.calc_token_amount(_amounts, true); // USDC -> 3CRV
            }
        } else if (_output == address(tokenBCrv)) {
            if (_input == address(token3CRV)) { // convert from 3CRV -> BCrv
                uint[4] memory _amounts;
                _amounts[1] = stableSwap3Pool.calc_withdraw_one_coin(_inputAmount, 1); // 3CRV -> USDC
                _outputAmount = stableSwapBUSD.calc_token_amount(_amounts, true); // USDC -> BCrv
            } else if (_input == address(tokenSCrv)) { // convert from SCrv -> BCrv
                uint[4] memory _amounts;
                _amounts[1] = depositSUSD.calc_withdraw_one_coin(_inputAmount, 1); // SCrv -> USDC
                _outputAmount = stableSwapBUSD.calc_token_amount(_amounts, true); // USDC -> BCrv
            } else if (_input == address(tokenHCrv)) { // convert from HCrv -> BCrv
                uint[4] memory _amounts;
                _amounts[1] = depositHUSD.calc_withdraw_one_coin(_inputAmount, 2); // HCrv -> USDC
                _outputAmount = stableSwapBUSD.calc_token_amount(_amounts, true); // USDC -> BCrv
            } else if (_input == address(tokenCCrv)) { // convert from CCrv -> BCrv
                uint[4] memory _amounts;
                _amounts[1] = depositCompound.calc_withdraw_one_coin(_inputAmount, 1); // CCrv -> USDC
                _outputAmount = stableSwapBUSD.calc_token_amount(_amounts, true); // USDC -> BCrv
            }
        } else if (_output == address(tokenSCrv)) {
            if (_input == address(token3CRV)) { // convert from 3CRV -> SCrv
                uint[4] memory _amounts;
                _amounts[1] = stableSwap3Pool.calc_withdraw_one_coin(_inputAmount, 1); // 3CRV -> USDC
                _outputAmount = stableSwapSUSD.calc_token_amount(_amounts, true); // USDC -> BCrv
            } else if (_input == address(tokenBCrv)) { // convert from BCrv -> SCrv
                uint[4] memory _amounts;
                _amounts[1] = depositBUSD.calc_withdraw_one_coin(_inputAmount, 1); // BCrv -> USDC
                _outputAmount = stableSwapSUSD.calc_token_amount(_amounts, true); // USDC -> SCrv
            } else if (_input == address(tokenHCrv)) { // convert from HCrv -> SCrv
                uint[4] memory _amounts;
                _amounts[1] = depositHUSD.calc_withdraw_one_coin(_inputAmount, 2); // HCrv -> USDC
                _outputAmount = stableSwapSUSD.calc_token_amount(_amounts, true); // USDC -> SCrv
            } else if (_input == address(tokenCCrv)) { // convert from CCrv -> SCrv
                uint[4] memory _amounts;
                _amounts[1] = depositCompound.calc_withdraw_one_coin(_inputAmount, 1); // CCrv -> USDC
                _outputAmount = stableSwapSUSD.calc_token_amount(_amounts, true); // USDC -> SCrv
            }
        } else if (_output == address(tokenHCrv)) {
            if (_input == address(token3CRV)) { // convert from 3CRV -> HCrv
                uint[2] memory _amounts;
                _amounts[1] = _inputAmount;
                _outputAmount = stableSwapHUSD.calc_token_amount(_amounts, true); // 3CRV -> HCrv
            } else if (_input == address(tokenBCrv)) { // convert from BCrv -> HCrv
                uint[4] memory _amounts;
                _amounts[2] = depositBUSD.calc_withdraw_one_coin(_inputAmount, 1); // BCrv -> USDC
                _outputAmount = depositHUSD.calc_token_amount(_amounts, true); // USDC -> HCrv
            } else if (_input == address(tokenSCrv)) { // convert from SCrv -> HCrv
                uint[4] memory _amounts;
                _amounts[2] = depositSUSD.calc_withdraw_one_coin(_inputAmount, 1); // SCrv -> USDC
                _outputAmount = depositHUSD.calc_token_amount(_amounts, true); // USDC -> HCrv
            } else if (_input == address(tokenCCrv)) { // convert from CCrv -> HCrv
                uint[4] memory _amounts;
                _amounts[2] = depositCompound.calc_withdraw_one_coin(_inputAmount, 1); // CCrv -> USDC
                _outputAmount = depositHUSD.calc_token_amount(_amounts, true); // USDC -> HCrv
            }
        } else if (_output == address(tokenCCrv)) {
            if (_input == address(token3CRV)) { // convert from 3CRV -> CCrv
                uint[2] memory _amounts;
                _amounts[1] = stableSwap3Pool.calc_withdraw_one_coin(_inputAmount, 1); // 3CRV -> USDC
                _outputAmount = stableSwapCompound.calc_token_amount(_amounts, true); // USDC -> CCrv
            } else if (_input == address(tokenBCrv)) { // convert from BCrv -> CCrv
                uint[2] memory _amounts;
                _amounts[1] = depositBUSD.calc_withdraw_one_coin(_inputAmount, 1); // BCrv -> USDC
                _outputAmount = stableSwapCompound.calc_token_amount(_amounts, true); // USDC -> CCrv
            } else if (_input == address(tokenSCrv)) { // convert from SCrv -> CCrv
                uint[2] memory _amounts;
                _amounts[1] = depositSUSD.calc_withdraw_one_coin(_inputAmount, 1); // SCrv -> USDC
                _outputAmount = stableSwapCompound.calc_token_amount(_amounts, true); // USDC -> CCrv
            } else if (_input == address(tokenHCrv)) { // convert from HCrv -> CCrv
                uint[2] memory _amounts;
                _amounts[1] = depositHUSD.calc_withdraw_one_coin(_inputAmount, 2); // HCrv -> USDC
                _outputAmount = stableSwapCompound.calc_token_amount(_amounts, true); // USDC -> CCrv
            }
        }
        if (_outputAmount > 0) {
            uint _slippage = _outputAmount.mul(vaultMaster.convertSlippage(_input, _output)).div(10000);
            _outputAmount = _outputAmount.sub(_slippage);
        }
    }

    function convert_shares(address _input, address _output, uint _inputAmount) external override returns (uint _outputAmount) {
        require(vaultMaster.isVault(msg.sender) || vaultMaster.isController(msg.sender) || msg.sender == governance, "!(governance||vault||controller)");
        if (_output == address(token3CRV)) {
            if (_input == address(tokenBCrv)) { // convert from BCrv -> 3CRV
                uint[3] memory _amounts;
                _amounts[1] = _convert_bcrv_to_usdc(_inputAmount);

                uint _before = token3CRV.balanceOf(address(this));
                stableSwap3Pool.add_liquidity(_amounts, 1);
                uint _after = token3CRV.balanceOf(address(this));

                _outputAmount = _after.sub(_before);
            } else if (_input == address(tokenSCrv)) { // convert from SCrv -> 3CRV
                uint[3] memory _amounts;
                _amounts[1] = _convert_scrv_to_usdc(_inputAmount);

                uint _before = token3CRV.balanceOf(address(this));
                stableSwap3Pool.add_liquidity(_amounts, 1);
                uint _after = token3CRV.balanceOf(address(this));

                _outputAmount = _after.sub(_before);
            } else if (_input == address(tokenHCrv)) { // convert from HCrv -> 3CRV
                _outputAmount = _convert_hcrv_to_3crv(_inputAmount);
            } else if (_input == address(tokenCCrv)) { // convert from CCrv -> 3CRV
                uint[3] memory _amounts;
                _amounts[1] = _convert_ccrv_to_usdc(_inputAmount);

                uint _before = token3CRV.balanceOf(address(this));
                stableSwap3Pool.add_liquidity(_amounts, 1);
                uint _after = token3CRV.balanceOf(address(this));

                _outputAmount = _after.sub(_before);
            }
        } else if (_output == address(tokenBCrv)) {
            if (_input == address(token3CRV)) { // convert from 3CRV -> BCrv
                uint[4] memory _amounts;
                _amounts[1] = _convert_3crv_to_usdc(_inputAmount);

                uint _before = tokenBCrv.balanceOf(address(this));
                depositBUSD.add_liquidity(_amounts, 1);
                uint _after = tokenBCrv.balanceOf(address(this));

                _outputAmount = _after.sub(_before);
            } else if (_input == address(tokenSCrv)) { // convert from SCrv -> BCrv
                uint[4] memory _amounts;
                _amounts[1] = _convert_scrv_to_usdc(_inputAmount);

                uint _before = tokenBCrv.balanceOf(address(this));
                depositBUSD.add_liquidity(_amounts, 1);
                uint _after = tokenBCrv.balanceOf(address(this));

                _outputAmount = _after.sub(_before);
            } else if (_input == address(tokenHCrv)) { // convert from HCrv -> BCrv
                uint[4] memory _amounts;
                _amounts[1] = _convert_hcrv_to_usdc(_inputAmount);

                uint _before = tokenBCrv.balanceOf(address(this));
                depositBUSD.add_liquidity(_amounts, 1);
                uint _after = tokenBCrv.balanceOf(address(this));

                _outputAmount = _after.sub(_before);
            } else if (_input == address(tokenCCrv)) { // convert from CCrv -> BCrv
                uint[4] memory _amounts;
                _amounts[1] = _convert_ccrv_to_usdc(_inputAmount);

                uint _before = tokenBCrv.balanceOf(address(this));
                depositBUSD.add_liquidity(_amounts, 1);
                uint _after = tokenBCrv.balanceOf(address(this));

                _outputAmount = _after.sub(_before);
            }
        } else if (_output == address(tokenSCrv)) {
            if (_input == address(token3CRV)) { // convert from 3CRV -> SCrv
                uint[4] memory _amounts;
                _amounts[1] = _convert_3crv_to_usdc(_inputAmount);

                uint _before = tokenSCrv.balanceOf(address(this));
                depositSUSD.add_liquidity(_amounts, 1);
                uint _after = tokenSCrv.balanceOf(address(this));

                _outputAmount = _after.sub(_before);
            } else if (_input == address(tokenBCrv)) { // convert from BCrv -> SCrv
                uint[4] memory _amounts;
                _amounts[1] = _convert_bcrv_to_usdc(_inputAmount);

                uint _before = tokenSCrv.balanceOf(address(this));
                depositSUSD.add_liquidity(_amounts, 1);
                uint _after = tokenSCrv.balanceOf(address(this));

                _outputAmount = _after.sub(_before);
            } else if (_input == address(tokenHCrv)) { // convert from HCrv -> SCrv
                uint[4] memory _amounts;
                _amounts[1] = _convert_hcrv_to_usdc(_inputAmount);

                uint _before = tokenSCrv.balanceOf(address(this));
                depositSUSD.add_liquidity(_amounts, 1);
                uint _after = tokenSCrv.balanceOf(address(this));

                _outputAmount = _after.sub(_before);
            } else if (_input == address(tokenCCrv)) { // convert from CCrv -> SCrv
                uint[4] memory _amounts;
                _amounts[1] = _convert_ccrv_to_usdc(_inputAmount);

                uint _before = tokenSCrv.balanceOf(address(this));
                depositSUSD.add_liquidity(_amounts, 1);
                uint _after = tokenSCrv.balanceOf(address(this));

                _outputAmount = _after.sub(_before);
            }
        } else if (_output == address(tokenHCrv)) {
            // todo: re-check
            if (_input == address(token3CRV)) { // convert from 3CRV -> HCrv
                uint[2] memory _amounts;
                _amounts[1] = _inputAmount;

                uint _before = tokenHCrv.balanceOf(address(this));
                stableSwapHUSD.add_liquidity(_amounts, 1);
                uint _after = tokenHCrv.balanceOf(address(this));

                _outputAmount = _after.sub(_before);
            } else if (_input == address(tokenBCrv)) { // convert from BCrv -> HCrv
                uint[4] memory _amounts;
                _amounts[2] = _convert_bcrv_to_usdc(_inputAmount);

                uint _before = tokenHCrv.balanceOf(address(this));
                depositHUSD.add_liquidity(_amounts, 1);
                uint _after = tokenHCrv.balanceOf(address(this));

                _outputAmount = _after.sub(_before);
            } else if (_input == address(tokenSCrv)) { // convert from SCrv -> HCrv
                uint[4] memory _amounts;
                _amounts[2] = _convert_scrv_to_usdc(_inputAmount);

                uint _before = tokenHCrv.balanceOf(address(this));
                depositHUSD.add_liquidity(_amounts, 1);
                uint _after = tokenHCrv.balanceOf(address(this));

                _outputAmount = _after.sub(_before);
            } else if (_input == address(tokenCCrv)) { // convert from CCrv -> HCrv
                uint[4] memory _amounts;
                _amounts[2] = _convert_ccrv_to_usdc(_inputAmount);

                uint _before = tokenHCrv.balanceOf(address(this));
                depositHUSD.add_liquidity(_amounts, 1);
                uint _after = tokenHCrv.balanceOf(address(this));

                _outputAmount = _after.sub(_before);
            }
        } else if (_output == address(tokenCCrv)) {
            if (_input == address(token3CRV)) { // convert from 3CRV -> CCrv
                uint[2] memory _amounts;
                _amounts[1] = _convert_3crv_to_usdc(_inputAmount);

                uint _before = tokenCCrv.balanceOf(address(this));
                depositCompound.add_liquidity(_amounts, 1);
                uint _after = tokenCCrv.balanceOf(address(this));

                _outputAmount = _after.sub(_before);
            } else if (_input == address(tokenBCrv)) { // convert from BCrv -> CCrv
                uint[2] memory _amounts;
                _amounts[1] = _convert_bcrv_to_usdc(_inputAmount);

                uint _before = tokenCCrv.balanceOf(address(this));
                depositCompound.add_liquidity(_amounts, 1);
                uint _after = tokenCCrv.balanceOf(address(this));

                _outputAmount = _after.sub(_before);
            } else if (_input == address(tokenSCrv)) { // convert from SCrv -> BCrv
                uint[2] memory _amounts;
                _amounts[1] = _convert_scrv_to_usdc(_inputAmount);

                uint _before = tokenCCrv.balanceOf(address(this));
                depositCompound.add_liquidity(_amounts, 1);
                uint _after = tokenCCrv.balanceOf(address(this));

                _outputAmount = _after.sub(_before);
            } else if (_input == address(tokenHCrv)) { // convert from HCrv -> BCrv
                uint[2] memory _amounts;
                _amounts[1] = _convert_hcrv_to_usdc(_inputAmount);

                uint _before = tokenCCrv.balanceOf(address(this));
                depositCompound.add_liquidity(_amounts, 1);
                uint _after = tokenCCrv.balanceOf(address(this));

                _outputAmount = _after.sub(_before);
            }
        }
        if (_outputAmount > 0) {
            IERC20(_output).safeTransfer(msg.sender, _outputAmount);
        }
        return _outputAmount;
    }

    function _convert_3crv_to_usdc(uint _inputAmount) internal returns (uint _outputAmount) {
        // 3CRV -> USDC
        uint _before = pool3CrvTokens[1].balanceOf(address(this));
        stableSwap3Pool.remove_liquidity_one_coin(_inputAmount, 1, 1);
        _outputAmount = pool3CrvTokens[1].balanceOf(address(this)).sub(_before);
    }

    function _convert_bcrv_to_usdc(uint _inputAmount) internal returns (uint _outputAmount) {
        // BCrv -> USDC
        uint _before = pool3CrvTokens[1].balanceOf(address(this));
        depositBUSD.remove_liquidity_one_coin(_inputAmount, 1, 1);
        _outputAmount = pool3CrvTokens[1].balanceOf(address(this)).sub(_before);
    }

    function _convert_scrv_to_usdc(uint _inputAmount) internal returns (uint _outputAmount) {
        // SCrv -> USDC
        uint _before = pool3CrvTokens[1].balanceOf(address(this));
        depositSUSD.remove_liquidity_one_coin(_inputAmount, 1, 1);
        _outputAmount = pool3CrvTokens[1].balanceOf(address(this)).sub(_before);
    }

    function _convert_hcrv_to_usdc(uint _inputAmount) internal returns (uint _outputAmount) {
        // HCrv -> USDC
        uint _before = pool3CrvTokens[1].balanceOf(address(this));
        depositHUSD.remove_liquidity_one_coin(_inputAmount, 2, 1);
        _outputAmount = pool3CrvTokens[1].balanceOf(address(this)).sub(_before);
    }

    function _convert_ccrv_to_usdc(uint _inputAmount) internal returns (uint _outputAmount) {
        // CCrv -> USDC
        uint _before = pool3CrvTokens[1].balanceOf(address(this));
        depositCompound.remove_liquidity_one_coin(_inputAmount, 1, 1);
        _outputAmount = pool3CrvTokens[1].balanceOf(address(this)).sub(_before);
    }

    function _convert_hcrv_to_3crv(uint _inputAmount) internal returns (uint _outputAmount) {
        // HCrv -> 3CRV
        uint _before = token3CRV.balanceOf(address(this));
        stableSwapHUSD.remove_liquidity_one_coin(_inputAmount, 1, 1);
        _outputAmount = token3CRV.balanceOf(address(this)).sub(_before);
    }

    function governanceRecoverUnsupported(IERC20 _token, uint _amount, address _to) external {
        require(msg.sender == governance, "!governance");
        _token.transfer(_to, _amount);
    }
}
