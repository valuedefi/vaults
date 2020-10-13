// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "../ValueVault.sol";

contract WETHVault is ValueVault {
    constructor (
        ValueVaultMaster _master,
        IStrategy _wethStrategy
    ) ValueVault(_master, "Value Vaults: WETH", "vWETH") public  {
        IStrategy[] memory strategies = new IStrategy[](1);
        strategies[0] = _wethStrategy;
        setStrategies(strategies);
    }
}
