// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.30;

import {IProposerAdapterBaseV1} from "./IProposerAdapterBaseV1.sol";

/**
 * @title IProposerAdapterHatsV1
 * @notice Proposer adapter that uses Hats Protocol roles for eligibility
 * @dev Determines proposal creation eligibility based on Hats Protocol role ownership.
 * Hats Protocol is a daoralized role management system where "hats" represent
 * roles or permissions that can be dynamically granted and revoked.
 *
 * Eligibility criteria:
 * - Proposer must wear a hat that is whitelisted in this adapter
 * - The specific hat ID must be provided in the data parameter
 * - Checks both: hat is whitelisted AND proposer currently wears it
 * - The data parameter in isProposer() must contain: abi.encode(uint256 hatId)
 *
 * Common use case: DAOs with role-based governance where specific roles
 * (e.g., "Council Member", "Working Group Lead") can create proposals.
 *
 * Integration note: When submitting proposals, the proposerAdapterData must
 * specify which whitelisted hat the proposer is using for authorization.
 */
interface IProposerAdapterHatsV1 is IProposerAdapterBaseV1 {
    // --- Initializer Functions ---

    /**
     * @notice Initializes the adapter with Hats contract and whitelisted roles
     * @param hatsContractAddress_ The Hats Protocol contract address
     * @param whitelistedHats_ Array of hat IDs that are allowed to create proposals
     */
    function initialize(
        address hatsContractAddress_,
        uint256[] calldata whitelistedHats_
    ) external;

    // --- View Functions ---

    /**
     * @notice Returns the Hats Protocol contract address
     * @return hatsContract The Hats contract used for role verification
     */
    function hatsContract() external view returns (address hatsContract);

    /**
     * @notice Returns all hat IDs that are authorized to create proposals
     * @return whitelistedHatIds Array of whitelisted hat IDs
     */
    function whitelistedHatIds()
        external
        view
        returns (uint256[] memory whitelistedHatIds);

    /**
     * @notice Checks if a specific hat ID is whitelisted for proposal creation
     * @param hatId_ The hat ID to check
     * @return bool True if the hat ID is whitelisted
     */
    function hatIdIsWhitelisted(uint256 hatId_) external view returns (bool);
}
