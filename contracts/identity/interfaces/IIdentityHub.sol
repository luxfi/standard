// SPDX-License-Identifier: BSD-3-Clause
// Copyright (c) 2025 Lux Industries Inc.
pragma solidity ^0.8.31;

/**
 * @title IIdentityHub - Native Identity Interface for Governance
 * @notice Single interface for all identity operations
 * @dev Governance contracts use this for voting power, proposals, and human verification
 *
 * USAGE IN GOVERNANCE:
 * ┌─────────────────────────────────────────────────────────────────────────────┐
 * │  // In Governor.sol                                                         │
 * │  IIdentityHub public identityHub;                                           │
 * │                                                                             │
 * │  function _getVotes(address account) internal view returns (uint256) {      │
 * │      return identityHub.getVotingPower(account);                            │
 * │  }                                                                          │
 * │                                                                             │
 * │  function propose(...) external {                                           │
 * │      require(identityHub.canPropose(msg.sender), "Insufficient karma");     │
 * │      require(identityHub.isHuman(msg.sender), "Human verification required");│
 * │      ...                                                                    │
 * │  }                                                                          │
 * │                                                                             │
 * │  function _afterVote(address voter) internal {                              │
 * │      identityHub.recordGovernanceActivity(voter);                           │
 * │  }                                                                          │
 * └─────────────────────────────────────────────────────────────────────────────┘
 */
interface IIdentityHub {
    // ============ Structs ============

    /// @notice Complete identity view
    struct Identity {
        // DID Layer
        string did;                       // W3C DID string
        bool hasDID;                      // Whether DID exists

        // SoulID Layer
        uint256 soulId;                   // SoulID token ID
        bool hasSoul;                     // Whether soul exists

        // Karma Layer
        uint256 karma;                    // Current karma balance
        bool isVerified;                  // DID verified in Karma

        // Reputation (from SoulID)
        uint256 humanityScore;            // 0-100
        uint256 governanceParticipation;  // 0-100
        uint256 communityContribution;    // 0-100
        uint256 protocolUsage;            // 0-100
        uint256 trustLevel;               // 0-100 composite

        // Governance
        uint256 votingPower;              // Calculated voting power
        bool canPropose;                  // Can create proposals
        bool isHuman;                     // Passed humanity check
    }

    // ============ Events ============

    event IdentityCreated(address indexed account, string did, uint256 soulId);
    event IdentityLinked(address indexed account, string did, uint256 soulId);
    event VotingPowerCalculated(address indexed account, uint256 votingPower);

    // ============ Identity Creation ============

    /**
     * @notice Create complete identity (DID + SoulID)
     * @param identifier DID identifier (e.g., "alice" for did:lux:alice)
     * @return did The created DID string
     * @return soulId The minted SoulID token
     */
    function createIdentity(string calldata identifier) external returns (string memory did, uint256 soulId);

    /**
     * @notice Link existing DID to SoulID
     * @param did Existing DID string
     */
    function linkExistingDID(string calldata did) external;

    // ============ Governance Functions ============

    /**
     * @notice Get voting power for governance
     * @param account Address to query
     * @return votingPower Calculated voting power
     * @dev votingPower = karma * trustMultiplier
     */
    function getVotingPower(address account) external view returns (uint256 votingPower);

    /**
     * @notice Check if account can create proposals
     * @param account Address to check
     * @return canPropose Whether account has minimum karma
     */
    function canPropose(address account) external view returns (bool);

    /**
     * @notice Check if account is verified human
     * @param account Address to check
     * @return isHuman Whether account passes humanity check
     */
    function isHuman(address account) external view returns (bool);

    /**
     * @notice Get complete identity for account
     * @param account Address to query
     * @return identity Complete identity struct
     */
    function getIdentity(address account) external view returns (Identity memory identity);

    /**
     * @notice Record governance activity (updates karma decay timer)
     * @param account Address that participated
     */
    function recordGovernanceActivity(address account) external;

    // ============ Sync Functions ============

    /**
     * @notice Sync karma balance to SoulID reputation
     * @param account Address to sync
     */
    function syncKarmaToSoulID(address account) external;

    // ============ View Functions ============

    /**
     * @notice Get DID string for account
     * @param account Address to query
     * @return did DID string (empty if none)
     */
    function didOf(address account) external view returns (string memory did);

    /**
     * @notice Minimum karma to create proposals
     */
    function MIN_PROPOSE_KARMA() external view returns (uint256);

    /**
     * @notice Minimum humanity score to be considered human
     */
    function MIN_HUMANITY_SCORE() external view returns (uint256);

    /**
     * @notice Network name (lux, asha, cyrus, miga, pars)
     */
    function networkName() external view returns (string memory);

    /**
     * @notice Whether this is the primary chain
     */
    function isPrimaryChain() external view returns (bool);
}
