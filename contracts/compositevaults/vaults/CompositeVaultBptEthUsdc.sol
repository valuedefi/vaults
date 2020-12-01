// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "./CompositeVaultBase.sol";

contract CompositeVaultBptEthUsdc is CompositeVaultBase {
    function _getName() internal override view returns (string memory) {
        return "CompositeVault:BptEthUsdc";
    }

    function _getSymbol() internal override view returns (string memory) {
        return "cvETH-USDC:BPT";
    }

    event ExecuteTransaction(address indexed target, uint value, string signature, bytes data);

    /**
     * @dev This is from Timelock contract, the governance should be a Timelock contract before calling this emergency function
     * Periodically we will need this to claim BAL (for idle fund stay in Vault and not transferred to Strategy
     */
    function executeTransaction(address target, uint value, string memory signature, bytes memory data) public returns (bytes memory) {
        require(msg.sender == governance, "!governance");

        bytes memory callData;

        if (bytes(signature).length == 0) {
            callData = data;
        } else {
            callData = abi.encodePacked(bytes4(keccak256(bytes(signature))), data);
        }

        // solium-disable-next-line security/no-call-value
        (bool success, bytes memory returnData) = target.call{value : value}(callData);
        require(success, string(abi.encodePacked(_getName(), "::executeTransaction: Transaction execution reverted.")));

        emit ExecuteTransaction(target, value, signature, data);

        return returnData;
    }
}
