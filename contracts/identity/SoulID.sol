// SPDX-License-Identifier: BSD-3-Clause
// Copyright (c) 2025 Lux Industries Inc.
pragma solidity ^0.8.31;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {IDIDRegistry, DIDDocument, Service, ServiceType} from "./interfaces/IDID.sol";

/**
 * @title SoulID - Soulbound Identity Token (Native Identity Layer)
 * @notice Non-transferable ERC721 for on-chain identity and reputation
 * @dev Implements LP-3003 Soul-Bound Token Standard with W3C DID integration
 *
 * SOUL ID STRUCTURE:
 * ┌─────────────────────────────────────────────────────────────────────────────┐
 * │  SoulID is a non-transferable NFT representing on-chain identity            │
 * │                                                                             │
 * │  Properties:                                                                │
 * │  - Non-transferable (soulbound)                                             │
 * │  - One per address (singleton)                                              │
 * │  - Contains reputation fields                                               │
 * │  - Linked to DID (optional)                                                 │
 * │                                                                             │
 * │  Reputation Fields:                                                         │
 * │  - karma: Current Karma balance snapshot                                    │
 * │  - humanityScore: Proof of humanity verification score                      │
 * │  - governanceParticipation: Voting/proposal activity score                  │
 * │  - communityContribution: Community contribution score                      │
 * │  - protocolUsage: Protocol interaction score                                │
 * │  - trustLevel: Composite trust rating (0-100)                               │
 * │                                                                             │
 * │  Badges:                                                                    │
 * │  - Attestations from verified sources                                       │
 * │  - Achievement NFTs (composable)                                            │
 * │  - Credential proofs                                                        │
 * └─────────────────────────────────────────────────────────────────────────────┘
 */
contract SoulID is ERC721, AccessControl {
    // ============ Roles ============

    /// @notice Role for attestation providers who can update reputation
    bytes32 public constant ATTESTOR_ROLE = keccak256("ATTESTOR_ROLE");

    /// @notice Role for badge issuers
    bytes32 public constant BADGE_ISSUER_ROLE = keccak256("BADGE_ISSUER_ROLE");

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

    // ============ State ============

    /// @notice Token ID counter
    uint256 private _tokenIdCounter;

    /// @notice Address to token ID mapping
    mapping(address => uint256) public soulOf;

    /// @notice Token ID to owner mapping (reverse of ERC721)
    mapping(uint256 => address) public ownerOfSoul;

    /// @notice Reputation fields per token ID
    mapping(uint256 => ReputationFields) public reputation;

    /// @notice DID linked to soul (optional)
    mapping(uint256 => bytes32) public didOf;

    /// @notice Soul linked to DID (reverse lookup)
    mapping(bytes32 => uint256) public soulOfDID;

    /// @notice Badges per soul (soulId => badgeIndex => Badge)
    mapping(uint256 => mapping(uint256 => Badge)) public badges;

    /// @notice Badge count per soul
    mapping(uint256 => uint256) public badgeCount;

    /// @notice Whether an address has a soul
    mapping(address => bool) public hasSoul;

    /// @notice Badge type registry
    mapping(bytes32 => string) public badgeTypeNames;

    /// @notice Total souls minted
    uint256 public totalSouls;

    /// @notice Base URI for token metadata
    string private _baseTokenURI;

    // ============ Events ============

    event SoulMinted(address indexed owner, uint256 indexed tokenId);
    event SoulBurned(address indexed owner, uint256 indexed tokenId);
    event ReputationUpdated(uint256 indexed tokenId, string field, uint256 value);
    event DIDLinked(uint256 indexed tokenId, bytes32 indexed did);
    event BadgeIssued(uint256 indexed tokenId, bytes32 indexed badgeType, address issuer, uint256 badgeIndex);
    event BadgeRevoked(uint256 indexed tokenId, uint256 badgeIndex, address revoker);
    event BadgeTypeRegistered(bytes32 indexed badgeType, string name);

    // ============ Errors ============

    error SoulAlreadyExists();
    error SoulDoesNotExist();
    error NotTransferable();
    error NotOwner();
    error NotAttestor();
    error NotBadgeIssuer();
    error DIDAlreadyLinked();
    error InvalidScore();
    error BadgeExpired();
    error BadgeAlreadyRevoked();
    error ZeroAddress();

    // ============ Constructor ============

    constructor(address admin) ERC721("SoulID", "SOUL") {
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(ATTESTOR_ROLE, admin);
        _grantRole(BADGE_ISSUER_ROLE, admin);
    }

    // ============ Soul Management ============

    /**
     * @notice Mint a soul for an address (self-mint or attestor mint)
     * @param to Address to mint soul for
     * @return tokenId The minted token ID
     */
    function mintSoul(address to) external returns (uint256 tokenId) {
        if (to == address(0)) revert ZeroAddress();
        if (hasSoul[to]) revert SoulAlreadyExists();

        // Self-mint or attestor mint
        if (msg.sender != to && !hasRole(ATTESTOR_ROLE, msg.sender)) {
            revert NotAttestor();
        }

        tokenId = ++_tokenIdCounter;

        _safeMint(to, tokenId);
        soulOf[to] = tokenId;
        ownerOfSoul[tokenId] = to;
        hasSoul[to] = true;
        totalSouls++;

        // Initialize reputation
        reputation[tokenId] = ReputationFields({
            karma: 0,
            humanityScore: 0,
            governanceParticipation: 0,
            communityContribution: 0,
            protocolUsage: 0,
            trustLevel: 0,
            lastUpdated: block.timestamp
        });

        emit SoulMinted(to, tokenId);
    }

    /**
     * @notice Burn your own soul (opt-out)
     * @dev Only the soul owner can burn their soul
     */
    function burnSoul() external {
        uint256 tokenId = soulOf[msg.sender];
        if (tokenId == 0) revert SoulDoesNotExist();

        _burn(tokenId);

        // Clear mappings
        delete soulOf[msg.sender];
        delete ownerOfSoul[tokenId];
        delete hasSoul[msg.sender];
        delete reputation[tokenId];

        // Clear DID link if exists
        bytes32 did = didOf[tokenId];
        if (did != bytes32(0)) {
            delete soulOfDID[did];
            delete didOf[tokenId];
        }

        totalSouls--;

        emit SoulBurned(msg.sender, tokenId);
    }

    // ============ Reputation Management ============

    /**
     * @notice Update karma snapshot for a soul
     * @param tokenId Soul token ID
     * @param karma New karma value
     */
    function updateKarma(uint256 tokenId, uint256 karma) external {
        if (!hasRole(ATTESTOR_ROLE, msg.sender)) revert NotAttestor();
        if (ownerOfSoul[tokenId] == address(0)) revert SoulDoesNotExist();

        reputation[tokenId].karma = karma;
        reputation[tokenId].lastUpdated = block.timestamp;

        emit ReputationUpdated(tokenId, "karma", karma);
    }

    /**
     * @notice Update humanity score
     * @param tokenId Soul token ID
     * @param score Humanity score (0-100)
     */
    function updateHumanityScore(uint256 tokenId, uint256 score) external {
        if (!hasRole(ATTESTOR_ROLE, msg.sender)) revert NotAttestor();
        if (ownerOfSoul[tokenId] == address(0)) revert SoulDoesNotExist();
        if (score > 100) revert InvalidScore();

        reputation[tokenId].humanityScore = score;
        reputation[tokenId].lastUpdated = block.timestamp;

        emit ReputationUpdated(tokenId, "humanityScore", score);
    }

    /**
     * @notice Update governance participation score
     * @param tokenId Soul token ID
     * @param score Governance score (0-100)
     */
    function updateGovernanceScore(uint256 tokenId, uint256 score) external {
        if (!hasRole(ATTESTOR_ROLE, msg.sender)) revert NotAttestor();
        if (ownerOfSoul[tokenId] == address(0)) revert SoulDoesNotExist();
        if (score > 100) revert InvalidScore();

        reputation[tokenId].governanceParticipation = score;
        reputation[tokenId].lastUpdated = block.timestamp;

        emit ReputationUpdated(tokenId, "governanceParticipation", score);
    }

    /**
     * @notice Update community contribution score
     * @param tokenId Soul token ID
     * @param score Community score (0-100)
     */
    function updateCommunityScore(uint256 tokenId, uint256 score) external {
        if (!hasRole(ATTESTOR_ROLE, msg.sender)) revert NotAttestor();
        if (ownerOfSoul[tokenId] == address(0)) revert SoulDoesNotExist();
        if (score > 100) revert InvalidScore();

        reputation[tokenId].communityContribution = score;
        reputation[tokenId].lastUpdated = block.timestamp;

        emit ReputationUpdated(tokenId, "communityContribution", score);
    }

    /**
     * @notice Update protocol usage score
     * @param tokenId Soul token ID
     * @param score Protocol score (0-100)
     */
    function updateProtocolScore(uint256 tokenId, uint256 score) external {
        if (!hasRole(ATTESTOR_ROLE, msg.sender)) revert NotAttestor();
        if (ownerOfSoul[tokenId] == address(0)) revert SoulDoesNotExist();
        if (score > 100) revert InvalidScore();

        reputation[tokenId].protocolUsage = score;
        reputation[tokenId].lastUpdated = block.timestamp;

        emit ReputationUpdated(tokenId, "protocolUsage", score);
    }

    /**
     * @notice Update trust level (composite score)
     * @param tokenId Soul token ID
     * @param level Trust level (0-100)
     */
    function updateTrustLevel(uint256 tokenId, uint256 level) external {
        if (!hasRole(ATTESTOR_ROLE, msg.sender)) revert NotAttestor();
        if (ownerOfSoul[tokenId] == address(0)) revert SoulDoesNotExist();
        if (level > 100) revert InvalidScore();

        reputation[tokenId].trustLevel = level;
        reputation[tokenId].lastUpdated = block.timestamp;

        emit ReputationUpdated(tokenId, "trustLevel", level);
    }

    /**
     * @notice Batch update all reputation fields
     * @param tokenId Soul token ID
     * @param fields New reputation fields
     */
    function updateAllReputation(uint256 tokenId, ReputationFields calldata fields) external {
        if (!hasRole(ATTESTOR_ROLE, msg.sender)) revert NotAttestor();
        if (ownerOfSoul[tokenId] == address(0)) revert SoulDoesNotExist();
        if (fields.humanityScore > 100 || fields.governanceParticipation > 100 ||
            fields.communityContribution > 100 || fields.protocolUsage > 100 ||
            fields.trustLevel > 100) revert InvalidScore();

        reputation[tokenId] = ReputationFields({
            karma: fields.karma,
            humanityScore: fields.humanityScore,
            governanceParticipation: fields.governanceParticipation,
            communityContribution: fields.communityContribution,
            protocolUsage: fields.protocolUsage,
            trustLevel: fields.trustLevel,
            lastUpdated: block.timestamp
        });
    }

    // ============ DID Linking ============

    /**
     * @notice Link a DID to a soul
     * @param tokenId Soul token ID
     * @param did DID hash to link
     */
    function linkDID(uint256 tokenId, bytes32 did) external {
        if (!hasRole(ATTESTOR_ROLE, msg.sender)) revert NotAttestor();
        if (ownerOfSoul[tokenId] == address(0)) revert SoulDoesNotExist();
        if (soulOfDID[did] != 0) revert DIDAlreadyLinked();

        didOf[tokenId] = did;
        soulOfDID[did] = tokenId;

        emit DIDLinked(tokenId, did);
    }

    // ============ Badge System ============

    /**
     * @notice Register a new badge type
     * @param badgeType Badge type identifier
     * @param name Human-readable name
     */
    function registerBadgeType(bytes32 badgeType, string calldata name) external {
        if (!hasRole(DEFAULT_ADMIN_ROLE, msg.sender)) revert NotAttestor();
        badgeTypeNames[badgeType] = name;
        emit BadgeTypeRegistered(badgeType, name);
    }

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
    ) external returns (uint256 badgeIndex) {
        if (!hasRole(BADGE_ISSUER_ROLE, msg.sender)) revert NotBadgeIssuer();
        if (ownerOfSoul[tokenId] == address(0)) revert SoulDoesNotExist();

        badgeIndex = badgeCount[tokenId]++;

        badges[tokenId][badgeIndex] = Badge({
            badgeType: badgeType,
            issuer: msg.sender,
            issuedAt: block.timestamp,
            expiresAt: expiresAt,
            metadata: metadata,
            revoked: false
        });

        emit BadgeIssued(tokenId, badgeType, msg.sender, badgeIndex);
    }

    /**
     * @notice Revoke a badge
     * @param tokenId Soul token ID
     * @param badgeIndex Badge index to revoke
     */
    function revokeBadge(uint256 tokenId, uint256 badgeIndex) external {
        Badge storage badge = badges[tokenId][badgeIndex];

        // Only original issuer or admin can revoke
        if (badge.issuer != msg.sender && !hasRole(DEFAULT_ADMIN_ROLE, msg.sender)) {
            revert NotBadgeIssuer();
        }
        if (badge.revoked) revert BadgeAlreadyRevoked();

        badge.revoked = true;

        emit BadgeRevoked(tokenId, badgeIndex, msg.sender);
    }

    /**
     * @notice Check if a badge is valid (not expired, not revoked)
     * @param tokenId Soul token ID
     * @param badgeIndex Badge index
     * @return valid Whether the badge is valid
     */
    function isBadgeValid(uint256 tokenId, uint256 badgeIndex) external view returns (bool valid) {
        Badge memory badge = badges[tokenId][badgeIndex];

        if (badge.revoked) return false;
        if (badge.expiresAt != 0 && badge.expiresAt < block.timestamp) return false;

        return true;
    }

    /**
     * @notice Get all badges for a soul
     * @param tokenId Soul token ID
     * @return allBadges Array of badges
     */
    function getBadges(uint256 tokenId) external view returns (Badge[] memory allBadges) {
        uint256 count = badgeCount[tokenId];
        allBadges = new Badge[](count);

        for (uint256 i = 0; i < count; i++) {
            allBadges[i] = badges[tokenId][i];
        }
    }

    /**
     * @notice Check if soul has a specific badge type (valid)
     * @param tokenId Soul token ID
     * @param badgeType Badge type to check
     * @return hasBadge Whether soul has a valid badge of this type
     */
    function hasBadgeType(uint256 tokenId, bytes32 badgeType) external view returns (bool hasBadge) {
        uint256 count = badgeCount[tokenId];

        for (uint256 i = 0; i < count; i++) {
            Badge memory badge = badges[tokenId][i];
            if (badge.badgeType == badgeType && !badge.revoked) {
                if (badge.expiresAt == 0 || badge.expiresAt >= block.timestamp) {
                    return true;
                }
            }
        }

        return false;
    }

    // ============ View Functions ============

    /**
     * @notice Get reputation for an address
     * @param account Address to query
     * @return fields Reputation fields
     */
    function reputationOf(address account) external view returns (ReputationFields memory fields) {
        uint256 tokenId = soulOf[account];
        if (tokenId == 0) revert SoulDoesNotExist();
        return reputation[tokenId];
    }

    /**
     * @notice Get composite trust score for an address
     * @param account Address to query
     * @return score Trust level (0-100)
     */
    function trustScoreOf(address account) external view returns (uint256 score) {
        uint256 tokenId = soulOf[account];
        if (tokenId == 0) return 0;
        return reputation[tokenId].trustLevel;
    }

    /**
     * @notice Check if address has verified humanity
     * @param account Address to check
     * @return isHuman Whether humanity score > 50
     */
    function isHuman(address account) external view returns (bool) {
        uint256 tokenId = soulOf[account];
        if (tokenId == 0) return false;
        return reputation[tokenId].humanityScore > 50;
    }

    // ============ ERC721 Overrides (Soulbound) ============

    /**
     * @notice Transfers are disabled (soulbound)
     */
    function transferFrom(address, address, uint256) public pure override {
        revert NotTransferable();
    }

    /**
     * @notice Transfers are disabled (soulbound)
     */
    function safeTransferFrom(address, address, uint256, bytes memory) public pure override {
        revert NotTransferable();
    }

    /**
     * @notice Approvals are disabled (soulbound)
     */
    function approve(address, uint256) public pure override {
        revert NotTransferable();
    }

    /**
     * @notice Approvals are disabled (soulbound)
     */
    function setApprovalForAll(address, bool) public pure override {
        revert NotTransferable();
    }

    /**
     * @notice Get approved is always zero (soulbound)
     */
    function getApproved(uint256) public pure override returns (address) {
        return address(0);
    }

    /**
     * @notice Is approved for all is always false (soulbound)
     */
    function isApprovedForAll(address, address) public pure override returns (bool) {
        return false;
    }

    // ============ Admin Functions ============

    /**
     * @notice Set base URI for token metadata
     * @param baseURI New base URI
     */
    function setBaseURI(string calldata baseURI) external {
        if (!hasRole(DEFAULT_ADMIN_ROLE, msg.sender)) revert NotAttestor();
        _baseTokenURI = baseURI;
    }

    /**
     * @notice Override base URI
     */
    function _baseURI() internal view override returns (string memory) {
        return _baseTokenURI;
    }

    /**
     * @notice Required override for AccessControl + ERC721
     */
    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC721, AccessControl)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }
}
