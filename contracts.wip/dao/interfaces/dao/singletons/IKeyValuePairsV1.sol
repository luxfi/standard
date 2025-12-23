// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.28;

/**
 * @title IKeyValuePairsV1
 * @notice Singleton contract for emitting on-chain key-value metadata
 * @dev This contract provides a simple, gas-efficient way to store metadata on-chain
 * through events. It's deployed once per chain and can be used by any address to
 * emit key-value pairs that can be indexed and queried off-chain.
 *
 * Key features:
 * - Stateless - no storage, only events
 * - Permissionless - any address can emit metadata
 * - Gas efficient - uses events instead of storage
 * - Flexible - supports any string key-value pairs
 * - Indexable - events can be efficiently queried
 *
 * Use cases:
 * - DAO metadata (name, description, logo, links)
 * - Configuration parameters readable by frontends
 * - Any other metadata that should be publicly accessible
 *
 * Example usage:
 * - DAOs emit their metadata during setup
 * - DAOs can update their metadata at any time
 */
interface IKeyValuePairsV1 {
    // --- Structs ---

    /**
     * @notice A single key-value pair of metadata
     * @param key The metadata key (e.g., "name", "description", "discord")
     * @param value The metadata value (e.g., "MyDAO", "A great DAO", "https://discord.gg/...")
     */
    struct KeyValuePair {
        string key;
        string value;
    }

    // --- Events ---

    /**
     * @notice Emitted when a key-value pair is published
     * @dev The sender is indexed to allow filtering by address.
     * Off-chain services can build a current state by processing all events.
     * @param sender The address that published this metadata
     * @param key The metadata key
     * @param value The metadata value
     */
    event ValueUpdated(address indexed sender, string key, string value);

    // --- State-Changing Functions ---

    /**
     * @notice Publishes an array of key-value pairs as events
     * @dev This function only emits events and doesn't store any data.
     * Can be called by any address to publish metadata.
     * Gas cost scales linearly with the number of pairs.
     * @param keyValuePairs_ Array of key-value pairs to publish
     * @custom:note Empty arrays are valid and will emit no events
     * @custom:emits ValueUpdated for each key-value pair
     */
    function updateValues(KeyValuePair[] memory keyValuePairs_) external;
}
