// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

// 0: DAI, 1: USDC
interface IStableSwapCompound {
    function get_virtual_price() external view returns (uint);
    function calc_token_amount(uint[2] calldata amounts, bool deposit) external view returns (uint);
    function get_dy_underlying(int128 i, int128 j, uint dx) external view returns (uint dy);
    function get_dx_underlying(int128 i, int128 j, uint dy) external view returns (uint dx);
    function exchange_underlying(int128 i, int128 j, uint dx, uint min_dy) external;
}
