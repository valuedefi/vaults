// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

// 0: hUSD, 1: 3Crv
interface IStableSwapHUSD {
    function get_virtual_price() external view returns (uint);
    function calc_token_amount(uint[2] calldata amounts, bool deposit) external view returns (uint);
    function get_dy(int128 i, int128 j, uint dx) external view returns (uint dy);
    function get_dy_underlying(int128 i, int128 j, uint dx) external view returns (uint dy);
    function get_dx_underlying(int128 i, int128 j, uint dy) external view returns (uint dx);
    function exchange_underlying(int128 i, int128 j, uint dx, uint min_dy) external;
    function exchange(int128 i, int128 j, uint dx, uint min_dy) external;
    function calc_withdraw_one_coin(uint amount, int128 i) external view returns (uint);
    function remove_liquidity_one_coin(uint amount, int128 i, uint minAmount) external returns (uint);
    function add_liquidity(uint[2] calldata amounts, uint min_mint_amount) external returns (uint);
}
