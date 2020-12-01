// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

interface ILpPairConverter {
    function lpPair() external view returns (address);
    function token0() external view returns (address);
    function token1() external view returns (address);

    function accept(address _input) external view returns (bool);
    function get_virtual_price() external view returns (uint);

    function convert_rate(address _input, address _output, uint _inputAmount) external view returns (uint _outputAmount);
    function calc_add_liquidity(uint _amount0, uint _amount1) external view returns (uint);
    function calc_remove_liquidity(uint _shares) external view returns (uint _amount0, uint _amount1);

    function convert(address _input, address _output, address _to) external returns (uint _outputAmount);
    function add_liquidity(address _to) external returns (uint _outputAmount);
    function remove_liquidity(address _to) external returns (uint _amount0, uint _amount1);
}
