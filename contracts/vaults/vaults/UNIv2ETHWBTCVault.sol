// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "../ValueVaultV2.sol";

contract UNIv2ETHWBTCVault is ValueVaultV2 {
    constructor (
        ValueVaultMaster _master,
        IStrategyV2 _univ2ethwbtcStrategy
    ) ValueVaultV2(_master, "Value Vaults: UNIv2ETHWBTC", "vUNIv2ETHWBTC") public  {
        setStrategy(_univ2ethwbtcStrategy);
        uint256[] memory _poolStrategyIds = new uint256[](1);
        _poolStrategyIds[0] = 0;
        setPoolStrategyIds(_poolStrategyIds);
    }
}
