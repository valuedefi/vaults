// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "./TToken.sol";
import "hardhat/console.sol";

interface IDecimals {
    function decimals() external view returns (uint8);
}

contract MockWrapYERC20 is TToken {
    address public underlyingToken;
    uint8   private _decimals;

    constructor(
        string memory name,
        string memory symbol,
        address _underlyingToken
    ) public TToken(name, symbol, IDecimals(_underlyingToken).decimals()) {
        underlyingToken = _underlyingToken;
    }
    function getPricePerFullShare() external pure returns (uint) {
        return 10 ** 18;
    }

    function deposit(uint256 _amount) public {
        IERC20(underlyingToken).transferFrom(msg.sender, address(this), _amount);
        _mint(msg.sender, _amount);
    }

    function withdraw(uint256 _amount) public {
        IERC20(underlyingToken).transfer(msg.sender, _amount);
        _burn(msg.sender, _amount);
    }
}
