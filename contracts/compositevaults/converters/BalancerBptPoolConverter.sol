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

contract BalancerBptPoolConverter is BaseConverter {
    constructor (
        IUniswapV2Router _uniswapRouter,
        IUniswapV2Router _sushiswapRouter,
        address _lpUni, address _lpSlp, address _lpBpt,
        OneSplitAudit _oneSplitAudit,
        IERC20 _usdc
    ) public BaseConverter(_uniswapRouter, _sushiswapRouter, _lpUni, _lpSlp, _lpBpt, _oneSplitAudit, _usdc) {
    }

    function getName() public override pure returns (string memory) {
        return "BalancerBptPoolConverter:[To_be_replaced_by_pair_name]";
    }

    function lpPair() external override view returns (address) {
        return lpBpt;
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
        Balancer _bPool = Balancer(lpBpt);
        uint _totalSupply = _bPool.totalSupply();
        IDecimals _token0 = IDecimals(token0());
        uint _reserve0 = _bPool.getBalance(address(_token0));
        uint _amount = uint(10) ** _token0.decimals();
        // 0.1% pool
        if (_amount > _reserve0.div(1000)) {
            _amount = _reserve0.div(1000);
        }
        uint _returnAmount;
        (_returnAmount,) = oneSplitAudit.getExpectedReturn(address(_token0), address(tokenUSDC), _amount, 1, 0);
        // precision 1e18
        uint _tmp = _returnAmount.mul(_reserve0).div(_amount).mul(10 ** 30).div(_totalSupply);
        return _tmp.mul(_bPool.getTotalDenormalizedWeight()).div(_bPool.getDenormalizedWeight(address(_token0)));
    }

    function convert_rate(address _input, address _output, uint _inputAmount) external override view returns (uint _outputAmount) {
        if (_input == _output) return 1;
        if (_inputAmount == 0) return 0;
        if ((_input == lpUni || _input == lpSlp) && _output == lpBpt) {// convert SLP,UNI -> BPT
            return ConverterHelper.convertRateUniLpToBpt(_input, _output, _inputAmount);
        }
        if (_input == lpBpt && (_output == lpSlp || _output == lpUni)) {// convert BPT -> SLP,UNI
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
        if (_input == lpUni && _output == lpBpt) {// convert UniLp -> BPT
            return ConverterHelper.convertUniLpToBpt(_input, _output, uniswapRouter, _to);
        }
        if (_input == lpSlp && _output == lpBpt) {// convert SLP -> BPT
            return ConverterHelper.convertUniLpToBpt(_input, _output, sushiswapRouter, _to);
        }
        if (_input == lpBpt && _output == lpSlp) {// convert BPT -> SLP
            return ConverterHelper.convertBPTToUniLp(_input, _output, sushiswapRouter, _to);
        }
        if (_input == lpBpt && _output == lpUni) {// convert BPT -> UniLp
            return ConverterHelper.convertBPTToUniLp(_input, _output, uniswapRouter, _to);
        }
        revert("Not supported");
    }

    function add_liquidity(address _to) external lock virtual override returns (uint _outputAmount) {
        Balancer _balPool = Balancer(lpBpt);
        address _token0 = token0();
        address _token1 = token1();
        uint _amount0 = IERC20(_token0).balanceOf(address(this));
        uint _amount1 = IERC20(_token1).balanceOf(address(this));
        uint _poolAmountOut = ConverterHelper.calculateAddBptLiquidity(_balPool, _token0, _token1, _amount0, _amount1);
        return ConverterHelper.addBalancerLiquidity(_balPool, _poolAmountOut, _to);
    }

    function remove_liquidity(address _to) external lock override returns (uint _amount0, uint _amount1) {
        ConverterHelper.removeBptLiquidity(Balancer(lpBpt));
        _amount0 = ConverterHelper.skim(token0(), _to);
        _amount1 = ConverterHelper.skim(token1(), _to);
    }
}
