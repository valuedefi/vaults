// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IStrategyV2 {
    function approve(IERC20 _token) external;

    function approveForSpender(IERC20 _token, address spender) external;

    // Deposit tokens to a farm to yield more tokens.
    function deposit(uint256 _poolId, uint256 _amount) external;

    // Claim farming tokens
    function claim(uint256 _poolId) external;

    // The vault request to harvest the profit
    function harvest(uint256 _bankPoolId, uint256 _poolId) external;

    // Withdraw the principal from a farm.
    function withdraw(uint256 _poolId, uint256 _amount) external;

    // Set 0 to disable quota (no limit)
    function poolQuota(uint256 _poolId) external view returns (uint256);

    // Use when we want to switch between strategies
    function forwardToAnotherStrategy(address _dest, uint256 _amount) external returns (uint256);

    // Source LP token of this strategy
    function getLpToken() external view returns(address);

    // Target farming token of this strategy by vault
    function getTargetToken(uint256 _poolId) external view returns(address);

    function balanceOf(uint256 _poolId) external view returns (uint256);

    function pendingReward(uint256 _poolId) external view returns (uint256);

    // Helper function, Should never use it on-chain.
    // Return 1e18x of APY. _lpPairUsdcPrice = current lpPair price (1-wei in USDC-wei) multiple by 1e18
    function expectedAPY(uint256 _poolId, uint256 _lpPairUsdcPrice) external view returns (uint256);

    function governanceRescueToken(IERC20 _token) external returns (uint256);
}
