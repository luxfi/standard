// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.31;

import {Ownable2Step, Ownable} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {IIdentifierWhitelist} from "./interfaces/IIdentifierWhitelist.sol";

/**
 * @title IdentifierWhitelist
 * @notice Stores a whitelist of supported identifiers that the oracle can provide prices for.
 */
contract IdentifierWhitelist is IIdentifierWhitelist, Ownable2Step {
    /// @notice Mapping of identifier to supported status
    mapping(bytes32 => bool) private supportedIdentifiers;

    /// @notice Emitted when an identifier is added to the whitelist
    event SupportedIdentifierAdded(bytes32 indexed identifier);

    /// @notice Emitted when an identifier is removed from the whitelist
    event SupportedIdentifierRemoved(bytes32 indexed identifier);

    /**
     * @notice Constructs the IdentifierWhitelist contract.
     * @param initialOwner The initial owner of the contract.
     */
    constructor(address initialOwner) Ownable(initialOwner) {}

    /**
     * @notice Adds the provided identifier as a supported identifier.
     * @dev Price requests using this identifier will succeed after this call.
     * @param identifier unique UTF-8 representation for the feed being added. Eg: BTC/USD.
     */
    function addSupportedIdentifier(bytes32 identifier) external override onlyOwner {
        if (!supportedIdentifiers[identifier]) {
            supportedIdentifiers[identifier] = true;
            emit SupportedIdentifierAdded(identifier);
        }
    }

    /**
     * @notice Removes the identifier from the whitelist.
     * @dev Price requests using this identifier will no longer succeed after this call.
     * @param identifier unique UTF-8 representation for the feed being removed. Eg: BTC/USD.
     */
    function removeSupportedIdentifier(bytes32 identifier) external override onlyOwner {
        if (supportedIdentifiers[identifier]) {
            supportedIdentifiers[identifier] = false;
            emit SupportedIdentifierRemoved(identifier);
        }
    }

    /**
     * @notice Checks whether an identifier is on the whitelist.
     * @param identifier unique UTF-8 representation for the feed being queried. Eg: BTC/USD.
     * @return bool if the identifier is supported (or not).
     */
    function isIdentifierSupported(bytes32 identifier) external view override returns (bool) {
        return supportedIdentifiers[identifier];
    }
}
