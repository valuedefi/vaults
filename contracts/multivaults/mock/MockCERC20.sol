// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "./TToken.sol";
interface IDecimals {
    function decimals() external view returns (uint8);
}

contract MockWrapCERC20 is TToken {
    using SafeMath for uint256;
    address public underlyingToken;
    uint256 public underlyingDecimals;
    constructor(
        string memory name,
        string memory symbol,
        address _underlyingToken
    ) public TToken(name, symbol, 8) {
        underlyingToken = _underlyingToken;
        underlyingDecimals = IDecimals(_underlyingToken).decimals();
    }

    function exchangeRateCurrent() external pure returns (uint) {
        return 10 ** 18;
    }

    function exchangeRateStored() external pure returns (uint) {
        return 10 ** 18;
    }

    function supplyRatePerBlock() external pure returns (uint) {
        return 1;
    }
    function accrualBlockNumber() external pure returns (uint) {
        return 1;
    }
    function mint(uint256 _amount) public returns (uint) {
        IERC20(underlyingToken).transferFrom(msg.sender, address(this), _amount);
        _mint(msg.sender, _amount);//.mul(10 ** 8).div( 10 ** underlyingDecimals));
        return 0;
    }

    function redeem(uint256 _amount) public returns (uint) {
        IERC20(underlyingToken).transfer(msg.sender, _amount);
        _burn(msg.sender, _amount);
        return 0;
    }
}
