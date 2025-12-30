// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.31;

/**
 * @title IProposerAdapter
 * @author Lux Industries Inc
 * @notice Interface for proposer adapters that determine proposal creation eligibility
 * @dev Proposer adapters implement access control for who can submit proposals.
 * Different implementations support various mechanisms:
 * - Token holdings (LRC20)
 * - NFT ownership (LRC721)
 * - Role-based permissions (Hats)
 *
 * Integration with Governor:
 * - Called by Strategy when validating proposal submissions
 * - Each adapter implements its own eligibility criteria
 * - Multiple adapters can be configured in a single Strategy
 *
 * Renamed from IProposerAdapterBaseV1 to align with Lux naming.
 */
interface IProposerAdapter {
    /**
     * @notice Checks if an address is eligible to create proposals
     * @param address_ The address to check for proposer eligibility
     * @param data_ Adapter-specific data (e.g., hat ID for Hats adapter)
     * @return isProposer True if the address can create proposals
     */
    function isProposer(
        address address_,
        bytes calldata data_
    ) external view returns (bool isProposer);
}
