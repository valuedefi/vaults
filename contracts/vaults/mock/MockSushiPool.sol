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

interface ISushiPool {
    function deposit(uint256 _poolId, uint256 _amount) external;
    function withdraw(uint256 _poolId, uint256 _amount) external;
}

contract MockSushiPool is ISushiPool {
    IERC20 public sushiToken;
    IERC20 public lpToken;

    constructor(IERC20 _sushiToken, IERC20 _lpToken) public {
        sushiToken = _sushiToken;
        lpToken = _lpToken;
    }

    function deposit(uint256, uint256 _amount) public override {
        lpToken.transferFrom(msg.sender, address(this), _amount);
        if (_amount == 0) {
            // claim
            sushiToken.transfer(msg.sender, sushiToken.balanceOf(address(this)) / 10);
        }
    }

    function withdraw(uint256, uint256 _amount) public override {
        lpToken.transfer(msg.sender, _amount);
    }
}
