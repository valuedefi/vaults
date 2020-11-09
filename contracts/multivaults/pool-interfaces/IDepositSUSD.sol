// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

interface IDepositSUSD {
    function calc_withdraw_one_coin(uint _token_amount, int128 i) external view returns (uint);
    function add_liquidity(uint[4] calldata amounts, uint min_mint_amount) external;
    function remove_liquidity_one_coin(uint _token_amount, int128 i, uint min_amount) external;
}
