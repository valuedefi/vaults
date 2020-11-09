// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

interface IMultiVaultConverter {
    function token() external returns (address);
    function get_virtual_price() external view returns (uint);

    function convert_rate(address _input, address _output, uint _inputAmount) external view returns (uint _outputAmount);
    function calc_token_amount_deposit(uint[] calldata _amounts) external view returns (uint _shareAmount);
    function calc_token_amount_withdraw(uint _shares, address _output) external view returns (uint _outputAmount);

    function convert(address _input, address _output, uint _inputAmount) external returns (uint _outputAmount);
    function convertAll(uint[] calldata _amounts) external returns (uint _outputAmount);
}
