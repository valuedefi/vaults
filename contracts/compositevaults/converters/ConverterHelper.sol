// SPDX-License-Identifier: MIT

pragma solidity =0.6.12;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";

import "../../interfaces/IUniswapV2Router.sol";
import "../../interfaces/IUniswapV2Pair.sol";
import "../../libraries/Math.sol";
import "../../interfaces/Balancer.sol";

library ConverterHelper {
    using SafeMath for uint;
    using SafeERC20 for IERC20;
    function bmul(uint a, uint b)
    internal pure
    returns (uint)
    {
        uint c0 = a * b;
        require(a == 0 || c0 / a == b, "ERR_MUL_OVERFLOW");
        uint c1 = c0 + (1e18 / 2);
        require(c1 >= c0, "ERR_MUL_OVERFLOW");
        uint c2 = c1 / 1e18;
        return c2;
    }

    function bdiv(uint a, uint b)
    internal pure
    returns (uint)
    {
        require(b != 0, "ERR_DIV_ZERO");
        uint c0 = a * 1e18;
        require(a == 0 || c0 / a == 1e18, "ERR_DIV_INTERNAL");
        // bmul overflow
        uint c1 = c0 + (b / 2);
        require(c1 >= c0, "ERR_DIV_INTERNAL");
        //  badd require
        uint c2 = c1 / b;
        return c2;
    }

    function calculateAddBptLiquidity(Balancer _balPool,
        address _token0, address _token1,
        uint _amount0, uint _amount1) internal view returns (uint _poolAmountOut) {
        require(_amount0 > 0 && _amount1 > 0, "Insufficient liquidity amount");
        uint _balTotalSupply = _balPool.totalSupply();
        uint _balToken0Amount = _balPool.getBalance(_token0);
        uint _balToken1Amount = _balPool.getBalance(_token1);
        uint _poolOutByAmount0 = bdiv(bmul(_amount0, _balTotalSupply), _balToken0Amount);
        uint _poolOutByAmount1 = bdiv(bmul(_amount1, _balTotalSupply), _balToken1Amount);
        //        uint _poolOutByAmount0 = bmul(bdiv(_amount0, _balToken0Amount), _balTotalSupply);
        //        uint _poolOutByAmount1 = bmul(bdiv(_amount1, _balToken1Amount), _balTotalSupply);
        return bmul(Math.min(_poolOutByAmount0, _poolOutByAmount1), 1e18 - 1e10);
    }

    function calculateRemoveBptLiquidity(Balancer _balPool, uint _poolAmountIn,
        address _token0, address _token1
    ) internal view returns (uint _amount0, uint _amount1) {
        uint _balTotalSupply = _balPool.totalSupply();
        uint _balToken0Amount = _balPool.getBalance(_token0);
        uint _balToken1Amount = _balPool.getBalance(_token1);
        _amount0 = bdiv(bmul(_balToken0Amount, _poolAmountIn), _balTotalSupply);
        _amount1 = bdiv(bmul(_balToken1Amount, _poolAmountIn), _balTotalSupply);
    }

    function calculateAddUniLpLiquidity(IUniswapV2Pair _pair, uint _amount0, uint _amount1) internal view returns (uint) {
        uint _pairTotalSupply = _pair.totalSupply();
        uint _reserve0 = 0;
        uint _reserve1 = 0;
        (_reserve0, _reserve1,) = _pair.getReserves();
        return Math.min(_amount0.mul(_pairTotalSupply) / _reserve0, _amount1.mul(_pairTotalSupply) / _reserve1);
    }

    function calculateRemoveUniLpLiquidity(IUniswapV2Pair _pair, uint _shares) internal view returns (uint _amount0, uint _amount1) {
        uint _pairSupply = _pair.totalSupply();
        uint _reserve0 = 0;
        uint _reserve1 = 0;
        (_reserve0, _reserve1,) = _pair.getReserves();
        _amount0 = _shares.mul(_reserve0).div(_pairSupply);
        _amount1 = _shares.mul(_reserve1).div(_pairSupply);
        return (_amount0, _amount1);
    }

    function skim(address _token, address _to) internal returns (uint) {
        uint _amount = IERC20(_token).balanceOf(address(this));
        if (_amount > 0) {
            IERC20(_token).safeTransfer(_to, _amount);
        }
        return _amount;
    }

    function addUniLpLiquidity(IUniswapV2Router _router, IUniswapV2Pair _pair, address _to) internal returns (uint _outputAmount) {
        address _token0 = _pair.token0();
        address _token1 = _pair.token1();
        uint _amount0 = IERC20(_token0).balanceOf(address(this));
        uint _amount1 = IERC20(_token1).balanceOf(address(this));
        require(_amount0 > 0 && _amount1 > 0, "Insufficient liquidity amount");
        (,, _outputAmount) = _router.addLiquidity(_token0, _token1, _amount0, _amount1, 0, 0, _to, block.timestamp + 1);
        skim(_token0, _to);
        skim(_token1, _to);
    }

    function removeBptLiquidity(Balancer _pool) internal returns (uint _poolAmountIn) {
        uint[] memory _minAmountsOut = new uint[](2);
        _poolAmountIn = _pool.balanceOf(address(this));
        require(_poolAmountIn > 0, "Insufficient liquidity amount");
        _pool.exitPool(_poolAmountIn, _minAmountsOut);
    }

    function removeUniLpLiquidity(IUniswapV2Router _router, IUniswapV2Pair _pair, address _to) internal returns (uint _amount0, uint _amount1) {
        uint _liquidityAmount = _pair.balanceOf(address(this));
        require(_liquidityAmount > 0, "Insufficient liquidity amount");
        return _router.removeLiquidity(_pair.token0(), _pair.token1(), _liquidityAmount, 0, 0, _to, block.timestamp + 1);
    }

    function convertRateUniToUniInternal(address _input, address _output, uint _inputAmount) internal view returns (uint) {
        IUniswapV2Pair _inputPair = IUniswapV2Pair(_input);
        IUniswapV2Pair _outputPair = IUniswapV2Pair(_output);
        uint _amount0;
        uint _amount1;
        (_amount0, _amount1) = calculateRemoveUniLpLiquidity(_inputPair, _inputAmount);
        return calculateAddUniLpLiquidity(_outputPair, _amount0, _amount1);
    }

    function convertUniToUniLp(address _input, address _output, IUniswapV2Router _inputRouter, IUniswapV2Router _outputRouter, address _to) internal returns (uint) {
        IUniswapV2Pair _inputPair = IUniswapV2Pair(_input);
        IUniswapV2Pair _outputPair = IUniswapV2Pair(_output);
        removeUniLpLiquidity(_inputRouter, _inputPair, address(this));
        return addUniLpLiquidity(_outputRouter, _outputPair, _to);
    }

    function convertUniLpToBpt(address _input, address _output, IUniswapV2Router _inputRouter, address _to) internal returns (uint) {
        IUniswapV2Pair _inputPair = IUniswapV2Pair(_input);
        Balancer _balPool = Balancer(_output);
        address _token0 = _inputPair.token0();
        address _token1 = _inputPair.token1();
        uint _amount0;
        uint _amount1;
        (_amount0, _amount1) = removeUniLpLiquidity(_inputRouter, _inputPair, address(this));
        uint _balPoolAmountOut = calculateAddBptLiquidity(_balPool, _token0, _token1, _amount0, _amount1);
        uint _outputAmount = addBalancerLiquidity(_balPool, _balPoolAmountOut, _to);
        skim(_token0, _to);
        skim(_token1, _to);
        return _outputAmount;
    }

    function convertBPTToUniLp(address _input, address _output, IUniswapV2Router _outputRouter, address _to) internal returns (uint) {
        removeBptLiquidity(Balancer(_input));
        IUniswapV2Pair _outputPair = IUniswapV2Pair(_output);
        return addUniLpLiquidity(_outputRouter, _outputPair, _to);
    }

    function convertRateUniLpToBpt(address _input, address _lpBpt, uint _inputAmount) internal view returns (uint) {
        IUniswapV2Pair _inputPair = IUniswapV2Pair(_input);
        uint _amount0;
        uint _amount1;
        (_amount0, _amount1) = calculateRemoveUniLpLiquidity(_inputPair, _inputAmount);
        return calculateAddBptLiquidity(Balancer(_lpBpt), _inputPair.token0(), _inputPair.token1(), _amount0, _amount1);
    }

    function convertRateBptToUniLp(address _lpBpt, address _output, uint _inputAmount) internal view returns (uint) {
        IUniswapV2Pair _outputPair = IUniswapV2Pair(_output);
        uint _amount0;
        uint _amount1;
        (_amount0, _amount1) = calculateRemoveBptLiquidity(Balancer(_lpBpt), _inputAmount, _outputPair.token0(), _outputPair.token1());
        return calculateAddUniLpLiquidity(_outputPair, _amount0, _amount1);
    }

    function addBalancerLiquidity(Balancer _pool, uint _poolAmountOut, address _to) internal returns (uint _outputAmount) {
        uint[] memory _maxAmountsIn = new uint[](2);
        _maxAmountsIn[0] = type(uint256).max;
        _maxAmountsIn[1] = type(uint256).max;
        _pool.joinPool(_poolAmountOut, _maxAmountsIn);
        return skim(address(_pool), _to);
    }
}
