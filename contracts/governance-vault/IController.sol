// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

interface IController {
    function vaults(address) external view returns (address);
    function rewards() external view returns (address);
    function want(address) external view returns (address);
    function balanceOf(address) external view returns (uint);
    function withdraw(address, uint) external;
    function maxAcceptAmount(address) external view returns (uint256);
    function earn(address, uint) external;

    function getStrategyCount(address _vault) external view returns(uint256);
    function depositAvailable(address _vault) external view returns(bool);
    function harvestAllStrategies(address _vault) external;
    function harvestStrategy(address _vault, address _strategy) external;
}
