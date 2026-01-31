// SPDX-License-Identifier: BSD-3-Clause
// Copyright (c) 2025 Lux Industries Inc.
pragma solidity ^0.8.31;

/**
 * @title ISoulID - Interface for Soulbound Identity Token
 * @notice Interface for non-transferable ERC721 identity and reputation
 * @dev Implements LP-3003 Soul-Bound Token Standard
 */
interface ISoulID {
    // ============ Structs ============

    /// @notice On-chain reputation fields
    struct ReputationFields {
        uint256 karma;                    // Karma balance snapshot
        uint256 humanityScore;            // 0-100: Proof of humanity
        uint256 governanceParticipation;  // 0-100: Governance activity
        uint256 communityContribution;    // 0-100: Community contributions
        uint256 protocolUsage;            // 0-100: Protocol interaction
        uint256 trustLevel;               // 0-100: Composite trust rating
        uint256 lastUpdated;              // Last update timestamp
    }

    /// @notice Badge/attestation structure
    struct Badge {
        bytes32 badgeType;        // Type identifier
        address issuer;           // Who issued the badge
        uint256 issuedAt;         // Issue timestamp
        uint256 expiresAt;        // Expiration (0 = never)
        bytes32 metadata;         // Additional metadata hash
        bool revoked;             // Whether badge is revoked
    }

    // ============ Events ============

    event SoulMinted(address indexed owner, uint256 indexed tokenId);
    event SoulBurned(address indexed owner, uint256 indexed tokenId);
    event ReputationUpdated(uint256 indexed tokenId, string field, uint256 value);
    event DIDLinked(uint256 indexed tokenId, bytes32 indexed did);
    event BadgeIssued(uint256 indexed tokenId, bytes32 indexed badgeType, address issuer, uint256 badgeIndex);
    event BadgeRevoked(uint256 indexed tokenId, uint256 badgeIndex, address revoker);

    // ============ Soul Management ============

    /**
     * @notice Mint a soul for an address
     * @param to Address to mint soul for
     * @return tokenId The minted token ID
     */
    function mintSoul(address to) external returns (uint256 tokenId);

    /**
     * @notice Burn your own soul (opt-out)
     */
    function burnSoul() external;

    /**
     * @notice Get token ID for address
     * @param account Address to query
     * @return tokenId The soul token ID (0 if none)
     */
    function soulOf(address account) external view returns (uint256 tokenId);

    /**
     * @notice Check if address has a soul
     * @param account Address to check
     * @return hasSoul Whether address has a soul
     */
    function hasSoul(address account) external view returns (bool);

    /**
     * @notice Get owner of soul token
     * @param tokenId Token ID to query
     * @return owner Owner address
     */
    function ownerOfSoul(uint256 tokenId) external view returns (address owner);

    // ============ Reputation ============

    /**
     * @notice Get reputation for token ID
     * @param tokenId Token ID to query
     * @return karma Karma balance snapshot
     * @return humanityScore Humanity verification score
     * @return governanceParticipation Governance activity score
     * @return communityContribution Community contribution score
     * @return protocolUsage Protocol usage score
     * @return trustLevel Composite trust rating
     * @return lastUpdated Last update timestamp
     */
    function reputation(uint256 tokenId) external view returns (
        uint256 karma,
        uint256 humanityScore,
        uint256 governanceParticipation,
        uint256 communityContribution,
        uint256 protocolUsage,
        uint256 trustLevel,
        uint256 lastUpdated
    );

    /**
     * @notice Get reputation for an address
     * @param account Address to query
     * @return fields Reputation fields
     */
    function reputationOf(address account) external view returns (ReputationFields memory fields);

    /**
     * @notice Update karma snapshot
     * @param tokenId Soul token ID
     * @param karma New karma value
     */
    function updateKarma(uint256 tokenId, uint256 karma) external;

    /**
     * @notice Update humanity score
     * @param tokenId Soul token ID
     * @param score Humanity score (0-100)
     */
    function updateHumanityScore(uint256 tokenId, uint256 score) external;

    /**
     * @notice Update trust level
     * @param tokenId Soul token ID
     * @param level Trust level (0-100)
     */
    function updateTrustLevel(uint256 tokenId, uint256 level) external;

    /**
     * @notice Update all reputation fields
     * @param tokenId Soul token ID
     * @param fields New reputation fields
     */
    function updateAllReputation(uint256 tokenId, ReputationFields calldata fields) external;

    // ============ DID ============

    /**
     * @notice Link a DID to a soul
     * @param tokenId Soul token ID
     * @param did DID hash to link
     */
    function linkDID(uint256 tokenId, bytes32 did) external;

    /**
     * @notice Get DID for token
     * @param tokenId Token ID to query
     * @return did DID hash
     */
    function didOf(uint256 tokenId) external view returns (bytes32 did);

    /**
     * @notice Get soul for DID
     * @param did DID hash to query
     * @return tokenId Soul token ID
     */
    function soulOfDID(bytes32 did) external view returns (uint256 tokenId);

    // ============ Badges ============

    /**
     * @notice Issue a badge to a soul
     * @param tokenId Soul token ID
     * @param badgeType Badge type identifier
     * @param expiresAt Expiration timestamp (0 = never)
     * @param metadata Additional metadata hash
     * @return badgeIndex Index of the issued badge
     */
    function issueBadge(
        uint256 tokenId,
        bytes32 badgeType,
        uint256 expiresAt,
        bytes32 metadata
    ) external returns (uint256 badgeIndex);

    /**
     * @notice Revoke a badge
     * @param tokenId Soul token ID
     * @param badgeIndex Badge index to revoke
     */
    function revokeBadge(uint256 tokenId, uint256 badgeIndex) external;

    /**
     * @notice Check if a badge is valid
     * @param tokenId Soul token ID
     * @param badgeIndex Badge index
     * @return valid Whether the badge is valid
     */
    function isBadgeValid(uint256 tokenId, uint256 badgeIndex) external view returns (bool valid);

    /**
     * @notice Get all badges for a soul
     * @param tokenId Soul token ID
     * @return allBadges Array of badges
     */
    function getBadges(uint256 tokenId) external view returns (Badge[] memory allBadges);

    /**
     * @notice Check if soul has a specific badge type
     * @param tokenId Soul token ID
     * @param badgeType Badge type to check
     * @return hasBadge Whether soul has a valid badge of this type
     */
    function hasBadgeType(uint256 tokenId, bytes32 badgeType) external view returns (bool hasBadge);

    // ============ View Functions ============

    /**
     * @notice Get trust score for an address
     * @param account Address to query
     * @return score Trust level (0-100)
     */
    function trustScoreOf(address account) external view returns (uint256 score);

    /**
     * @notice Check if address has verified humanity
     * @param account Address to check
     * @return isHuman Whether humanity score > 50
     */
    function isHuman(address account) external view returns (bool);

    /**
     * @notice Get total souls minted
     * @return total Total number of souls
     */
    function totalSouls() external view returns (uint256 total);

    /**
     * @notice Get badge count for soul
     * @param tokenId Soul token ID
     * @return count Number of badges
     */
    function badgeCount(uint256 tokenId) external view returns (uint256 count);
}
