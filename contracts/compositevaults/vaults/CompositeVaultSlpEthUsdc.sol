// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "./CompositeVaultBase.sol";

contract CompositeVaultSlpEthUsdc is CompositeVaultBase {
    function _getName() internal override view returns (string memory) {
        return "CompositeVault:SlpEthUsdc";
    }

    function _getSymbol() internal override view returns (string memory) {
        return "cvETH-USDC:SLP";
    }
}
