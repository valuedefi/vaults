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

contract MockGovVault {
    IERC20 public valueToken;

    constructor(IERC20 _valueToken) public {
        valueToken = _valueToken;
    }

    function addValueReward(uint256 _amount) external {
        valueToken.transferFrom(msg.sender, address(this), _amount);
    }

    function make_profit(uint256 _amount) external {
        valueToken.transferFrom(msg.sender, address(this), _amount);
    }
}
