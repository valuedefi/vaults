// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";

contract MockLpPairConverter {
    using SafeMath for uint;
    using SafeERC20 for IERC20;

    address public lpPair;
    address public token0;
    address public token1;

    constructor (address _lpPair, address _token0, address _token1) public {
        lpPair = _lpPair;
        token0 = _token0;
        token1 = _token1;
    }

    function getName() public pure returns (string memory) {
        return "MockLpPairConverter";
    }

    function accept(address) external pure returns (bool) {
        return true;
    }

    function convert_rate(address _input, address, uint) external view returns (uint _outputAmount) {
        uint _tokenAmount = IERC20(_input).balanceOf(address(this));
        _outputAmount = _tokenAmount.div(5);
    }

    function convert(address _input, address _output, address _to) external returns (uint _outputAmount) {
        uint _tokenAmount = IERC20(_input).balanceOf(address(this));
        _outputAmount = _tokenAmount.div(5); // always convert to 20% amount of input
        IERC20(_output).safeTransfer(_to, _outputAmount);
    }

    function add_liquidity(address _to) external returns (uint _outputAmount) {
        _outputAmount = IERC20(token0).balanceOf(address(this)).div(5); // aways convert to 20% amount of input
        IERC20(lpPair).safeTransfer(_to, _outputAmount);
    }
}
