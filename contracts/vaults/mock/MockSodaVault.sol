// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockSodaVault is ERC20("Mock SodaVaultWETH", "msvWETH") {
    IERC20 public sodaToken;
    address public pool;

    constructor(IERC20 _sodaToken, address _pool) public {
        sodaToken = _sodaToken;
        pool = _pool;
    }

    function getPendingReward(address, uint256) public view returns (uint256) {
        return sodaToken.balanceOf(pool);
    }
}
