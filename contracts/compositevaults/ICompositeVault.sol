// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

interface ICompositeVault {
    function cap() external view returns (uint);
    function getConverter() external view returns (address);
    function getVaultMaster() external view returns (address);
    function balance() external view returns (uint);
    function tvl() external view returns (uint); // total dollar value
    function token() external view returns (address);
    function available() external view returns (uint);
    function accept(address _input) external view returns (bool);

    function earn() external;
    function harvest(address reserve, uint amount) external;
    function addNewCompound(uint, uint) external;

    function withdraw_fee(uint _shares) external view returns (uint);
    function calc_token_amount_deposit(address _input, uint _amount) external view returns (uint);
    function calc_add_liquidity(uint _amount0, uint _amount1) external view returns (uint);
    function calc_token_amount_withdraw(uint _shares, address _output) external view returns (uint);
    function calc_remove_liquidity(uint _shares) external view returns (uint _amount0, uint _amount1);

    function getPricePerFullShare() external view returns (uint);
    function get_virtual_price() external view returns (uint); // average dollar value of vault share token

    function deposit(address _input, uint _amount, uint _min_mint_amount) external returns (uint);
    function depositFor(address _account, address _to, address _input, uint _amount, uint _min_mint_amount) external returns (uint _mint_amount);
    function addLiquidity(uint _amount0, uint _amount1, uint _min_mint_amount) external returns (uint);
    function addLiquidityFor(address _account, address _to, uint _amount0, uint _amount1, uint _min_mint_amount) external returns (uint _mint_amount);
    function withdraw(uint _shares, address _output, uint _min_output_amount) external returns (uint);
    function withdrawFor(address _account, uint _shares, address _output, uint _min_output_amount) external returns (uint _output_amount);

    function harvestStrategy(address _strategy) external;
    function harvestAllStrategies() external;
}
