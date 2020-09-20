// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IStrategy {
    function approve(IERC20 _token) external;

    function getValuePerShare(address _vault) external view returns(uint256);
    function pendingValuePerShare(address _vault) external view returns (uint256);

    // Deposit tokens to a farm to yield more tokens.
    function deposit(address _vault, uint256 _amount) external;

    // Claim the profit from a farm.
    function claim(address _vault) external;

    // Withdraw the principal from a farm.
    function withdraw(address _vault, uint256 _amount) external;

    // Target farming token of this strategy.
    function getTargetToken() external view returns(address);
}
