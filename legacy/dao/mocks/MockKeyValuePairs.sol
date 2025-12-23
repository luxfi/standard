// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.30;

/**
 * @title MockKeyValuePairs
 * @dev Mock implementation of KeyValuePairsV1 for testing purposes.
 * Provides functionality needed for testing UtilityRolesManagementV1.
 */
contract MockKeyValuePairs {
    // Store key-value pairs
    mapping(string => string) private store;

    // Event to track updates
    event ValueUpdated(string key, string value);

    struct KeyValuePair {
        string key;
        string value;
    }

    /**
     * @dev Update multiple key-value pairs
     * @param pairs Array of key-value pairs to update
     */
    function updateValues(KeyValuePair[] calldata pairs) external {
        for (uint256 i = 0; i < pairs.length; i++) {
            store[pairs[i].key] = pairs[i].value;
            emit ValueUpdated(pairs[i].key, pairs[i].value);
        }
    }

    /**
     * @dev Get a value by key
     * @param key The key to look up
     * @return The stored value
     */
    function getValue(
        string calldata key
    ) external view returns (string memory) {
        return store[key];
    }
}
