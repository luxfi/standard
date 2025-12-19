// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.30;

/**
 * @title MockHats
 * @dev Ultra-minimal mock implementation that only provides exactly what's needed
 * for testing HatsProposalCreationWhitelistV1.
 *
 * This mock is designed to be as simple as possible, focusing only on the
 * isWearerOfHat functionality that the contract under test actually needs.
 */
contract MockHats {
    // Simple storage for mock responses
    mapping(address => mapping(uint256 => bool)) public isWearingHat;

    /**
     * @dev Set wearing status directly
     * @param wearer The address to set status for
     * @param hatId The hat ID
     * @param isWearing Whether the address is wearing the hat
     */
    function setWearerStatus(
        address wearer,
        uint256 hatId,
        bool isWearing
    ) external {
        isWearingHat[wearer][hatId] = isWearing;
    }

    /**
     * @dev Check if an address is wearing a hat
     * @param _wearer The address to check
     * @param _hatId The hat ID to check
     * @return bool Whether the address is wearing the hat
     */
    function isWearerOfHat(
        address _wearer,
        uint256 _hatId
    ) external view returns (bool) {
        return isWearingHat[_wearer][_hatId];
    }
}
