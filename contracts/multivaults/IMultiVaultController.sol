// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

interface IMultiVaultController {
    function vault() external view returns (address);

    function wantQuota(address _want) external view returns (uint);
    function wantStrategyLength(address _want) external view returns (uint);
    function wantStrategyBalance(address _want) external view returns (uint);

    function getStrategyCount() external view returns(uint);
    function strategies(address _want, uint _stratId) external view returns (address _strategy, uint _quota, uint _percent);
    function getBestStrategy(address _want) external view returns (address _strategy);

    function basedWant() external view returns (address);
    function want() external view returns (address);
    function wantLength() external view returns (uint);

    function balanceOf(address _want, bool _sell) external view returns (uint);
    function withdraw_fee(address _want, uint _amount) external view returns (uint); // eg. 3CRV => pJar: 0.5% (50/10000)
    function investDisabled(address _want) external view returns (bool);

    function withdraw(address _want, uint) external returns (uint _withdrawFee);
    function earn(address _token, uint _amount) external;

    function harvestStrategy(address _strategy) external;
    function harvestWant(address _want) external;
    function harvestAllStrategies() external;
}
