// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

interface IERC20 {
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address recipient, uint256 amount) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
}

interface ISodaPool {
    // Deposit LP tokens to SodaPool for SODA allocation
    function deposit(uint256 _poolId, uint256 _amount) external;

    // Claim SODA (and potentially other tokens depends on strategy).
    function claim(uint256 _poolId) external;

    // Withdraw LP tokens from SodaPool
    function withdraw(uint256 _poolId, uint256 _amount) external;
}

contract MockSodaPool is ISodaPool {
    IERC20 public sodaToken;
    IERC20 public lpToken;

    constructor(IERC20 _sodaToken, IERC20 _lpToken) public {
        sodaToken = _sodaToken;
        lpToken = _lpToken;
    }

    function deposit(uint256, uint256 _amount) public override {
        lpToken.transferFrom(msg.sender, address(this), _amount);
    }

    // mock: send rewards is anything this contract has
    function claim(uint256) public override {
        sodaToken.transfer(msg.sender, sodaToken.balanceOf(address(this)));
    }

    function withdraw(uint256, uint256 _amount) public override {
        lpToken.transfer(msg.sender, _amount);
    }
}
