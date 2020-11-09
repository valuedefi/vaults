// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

interface IValueMultiVault {
    function cap() external view returns (uint);
    function getConverter(address _want) external view returns (address);
    function getVaultMaster() external view returns (address);
    function balance() external view returns (uint);
    function token() external view returns (address);
    function available(address _want) external view returns (uint);
    function accept(address _input) external view returns (bool);

    function claimInsurance() external;
    function earn(address _want) external;
    function harvest(address reserve, uint amount) external;

    function withdraw_fee(uint _shares) external view returns (uint);
    function calc_token_amount_deposit(uint[] calldata _amounts) external view returns (uint);
    function calc_token_amount_withdraw(uint _shares, address _output) external view returns (uint);
    function convert_rate(address _input, uint _amount) external view returns (uint);
    function getPricePerFullShare() external view returns (uint);
    function get_virtual_price() external view returns (uint); // average dollar value of vault share token

    function deposit(address _input, uint _amount, uint _min_mint_amount) external returns (uint _mint_amount);
    function depositFor(address _account, address _to, address _input, uint _amount, uint _min_mint_amount) external returns (uint _mint_amount);
    function depositAll(uint[] calldata _amounts, uint _min_mint_amount) external returns (uint _mint_amount);
    function depositAllFor(address _account, address _to, uint[] calldata _amounts, uint _min_mint_amount) external returns (uint _mint_amount);
    function withdraw(uint _shares, address _output, uint _min_output_amount) external returns (uint);
    function withdrawFor(address _account, uint _shares, address _output, uint _min_output_amount) external returns (uint _output_amount);

    function harvestStrategy(address _strategy) external;
    function harvestWant(address _want) external;
    function harvestAllStrategies() external;
}
