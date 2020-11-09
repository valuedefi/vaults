// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

interface IShareConverter {
    function convert_shares_rate(address _input, address _output, uint _inputAmount) external view returns (uint _outputAmount);

    function convert_shares(address _input, address _output, uint _inputAmount) external returns (uint _outputAmount);
}
