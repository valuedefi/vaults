// SPDX-License-Identifier: MIT

pragma solidity ^0.6.2;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";

import "../../interfaces/Converter.sol";

contract MockConverter is Converter {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    IERC20 want;

    constructor(IERC20 _want) public {
        want = _want;
    }

    function convert(address _token) external override returns (uint _wantAmount) {
        uint _tokenAmount = IERC20(_token).balanceOf(address(this));
        _wantAmount = _tokenAmount.div(2); // always convert to 50% amount of input
        want.safeTransfer(msg.sender, _wantAmount);
        IERC20(_token).safeTransfer(address(0x000000000000000000000000000000000000dEaD), _tokenAmount); // clear the _token balance (send to BurnAddress)
    }
}
