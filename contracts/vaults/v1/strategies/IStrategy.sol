// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IStrategy {
    function approve(IERC20 _token) external;

    function approveForSpender(IERC20 _token, address spender) external;

    // Deposit tokens to a farm to yield more tokens.
    function deposit(address _vault, uint256 _amount) external;

    // Claim farming tokens
    function claim(address _vault) external;

    // The vault request to harvest the profit
    function harvest(uint256 _bankPoolId) external;

    // Withdraw the principal from a farm.
    function withdraw(address _vault, uint256 _amount) external;

    // Target farming token of this strategy.
    function getTargetToken(address _vault) external view returns(address);

    function balanceOf(address _vault) external view returns (uint256);

    function pendingReward(address _vault) external view returns (uint256);

    function expectedAPY(address _vault) external view returns (uint256);

    function governanceRescueToken(IERC20 _token) external returns (uint256);
}
