// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.30;

/**
 * @title IProposerAdapterBaseV1
 * @notice Base interface for proposer adapters that determine proposal creation eligibility
 * @dev Proposer adapters implement access control for who can submit proposals in the
 * Governor governance system. Different implementations support various mechanisms
 * including token holdings, NFT ownership, or role-based permissions.
 *
 * Integration with Governor:
 * - Called by Strategy when validating proposal submissions
 * - Each adapter implements its own eligibility criteria
 * - Multiple adapters can be configured in a single Strategy
 */
interface IProposerAdapterBaseV1 {
    // --- View Functions ---

    /**
     * @notice Checks if an address is eligible to create proposals
     * @dev Implementation varies by adapter type. The data parameter usage depends on
     * the specific adapter (e.g., unused for ERC20/721, required for Hats).
     * @param address_ The address to check for proposer eligibility
     * @param data_ Adapter-specific data (e.g., hat ID for Hats adapter)
     * @return isProposer True if the address can create proposals
     */
    function isProposer(
        address address_,
        bytes calldata data_
    ) external view returns (bool isProposer);
}
