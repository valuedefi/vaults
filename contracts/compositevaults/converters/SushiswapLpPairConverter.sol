// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";

import "../../interfaces/IUniswapV2Router.sol";
import "../../interfaces/IUniswapV2Pair.sol";
import "../../libraries/Math.sol";
import "../../interfaces/Balancer.sol";
import "../../interfaces/OneSplitAudit.sol";

import "../ILpPairConverter.sol";
import "../IVaultMaster.sol";
import "./ConverterHelper.sol";
import "./IDecimals.sol";
import "./BaseConverter.sol";

contract SushiswapLpPairConverter is BaseConverter {
    constructor (
        IUniswapV2Router _uniswapRouter,
        IUniswapV2Router _sushiswapRouter,
        address _lpUni, address _lpSlp, address _lpBpt,
        OneSplitAudit _oneSplitAudit,
        IERC20 _usdc
    ) public BaseConverter(_uniswapRouter, _sushiswapRouter, _lpUni, _lpSlp, _lpBpt, _oneSplitAudit, _usdc) {
    }

    function getName() public override pure returns (string memory) {
        return "SushiswapLpPairConverter:[To_be_replaced_by_pair_name]";
    }

    function lpPair() external override view returns (address) {
        return lpSlp;
    }

    function token0() public override view returns (address) {
        return IUniswapV2Pair(lpSlp).token0();
    }

    function token1() public override view returns (address) {
        return IUniswapV2Pair(lpSlp).token1();
    }

    function accept(address _input) external override view returns (bool) {
        return (_input == lpUni) || (_input == lpSlp) || (_input == lpBpt);
    }

    function get_virtual_price() external override view returns (uint) {
        if (preset_virtual_price > 0) return preset_virtual_price;
        IUniswapV2Pair _pair = IUniswapV2Pair(lpSlp);
        uint _totalSupply = _pair.totalSupply();
        IDecimals _token0 = IDecimals(_pair.token0());
        uint _reserve0 = 0;
        (_reserve0,,) = _pair.getReserves();
        uint _amount = uint(10) ** _token0.decimals();
        // 0.1% pool
        if (_amount > _reserve0.div(1000)) {
            _amount = _reserve0.div(1000);
        }
        uint _returnAmount;
        (_returnAmount,) = oneSplitAudit.getExpectedReturn(address(_token0), address(tokenUSDC), _amount, 1, 0);
        // precision 1e18
        return _returnAmount.mul(2).mul(_reserve0).div(_amount).mul(10 ** 30).div(_totalSupply);
    }

    function convert_rate(address _input, address _output, uint _inputAmount) external override view returns (uint _outputAmount) {
        if (_input == _output) return 1;
        if (_inputAmount == 0) return 0;
        if ((_input == lpSlp && _output == lpUni) || (_input == lpUni && _output == lpSlp)) {// convert UNI <-> SLP
            return ConverterHelper.convertRateUniToUniInternal(_input, _output, _inputAmount);
        }
        if (_input == lpSlp && _output == lpBpt) {// convert SLP -> BPT
            return ConverterHelper.convertRateUniLpToBpt(_input, _output, _inputAmount);
        }
        if (_input == lpBpt && _output == lpSlp) {// convert BPT -> SLP
            return ConverterHelper.convertRateBptToUniLp(_input, _output, _inputAmount);
        }
        revert("Not supported");
    }

    function calc_add_liquidity(uint _amount0, uint _amount1) external override view returns (uint) {
        return ConverterHelper.calculateAddUniLpLiquidity(IUniswapV2Pair(lpSlp), _amount0, _amount1);
    }

    function calc_remove_liquidity(uint _shares) external override view returns (uint _amount0, uint _amount1) {
        return ConverterHelper.calculateRemoveUniLpLiquidity(IUniswapV2Pair(lpSlp), _shares);
    }

    function convert(address _input, address _output, address _to) external lock override returns (uint _outputAmount) {
        require(_input != _output, "same asset");
        if (_input == lpUni && _output == lpSlp) {// convert UNI -> SLP
            return ConverterHelper.convertUniToUniLp(_input, _output, uniswapRouter, sushiswapRouter, _to);
        }
        if (_input == lpSlp && _output == lpUni) {// convert SLP -> SLP
            return ConverterHelper.convertUniToUniLp(_input, _output, sushiswapRouter, uniswapRouter, _to);
        }
        if (_input == lpSlp && _output == lpBpt) {// convert SLP -> BPT
            return ConverterHelper.convertUniLpToBpt(_input, _output, sushiswapRouter, _to);
        }
        if (_input == lpBpt && _output == lpSlp) {// convert BPT -> SLP
            return ConverterHelper.convertBPTToUniLp(_input, _output, sushiswapRouter, _to);
        }
        revert("Not supported");
    }

    function add_liquidity(address _to) external lock override returns (uint _outputAmount) {
        return ConverterHelper.addUniLpLiquidity(sushiswapRouter, IUniswapV2Pair(lpSlp), _to);
    }

    function remove_liquidity(address _to) external lock override returns (uint _amount0, uint _amount1) {
        return ConverterHelper.removeUniLpLiquidity(sushiswapRouter, IUniswapV2Pair(lpSlp), _to);
    }
}
