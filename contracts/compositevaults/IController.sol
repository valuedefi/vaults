// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

interface IController {
    function vault() external view returns (address);

    function strategyLength() external view returns (uint);
    function strategyBalance() external view returns (uint);

    function getStrategyCount() external view returns(uint);
    function strategies(uint _stratId) external view returns (address _strategy, uint _quota, uint _percent);
    function getBestStrategy() external view returns (address _strategy);

    function want() external view returns (address);

    function balanceOf() external view returns (uint);
    function withdraw_fee(uint _amount) external view returns (uint); // eg. 3CRV => pJar: 0.5% (50/10000)
    function investDisabled() external view returns (bool);

    function withdraw(uint) external returns (uint _withdrawFee);
    function earn(address _token, uint _amount) external;

    function harvestStrategy(address _strategy) external;
    function harvestAllStrategies() external;
}
