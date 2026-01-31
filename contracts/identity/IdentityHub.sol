// SPDX-License-Identifier: BSD-3-Clause
// Copyright (c) 2025 Lux Industries Inc.
pragma solidity ^0.8.31;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IDIDRegistry, DIDDocument} from "./interfaces/IDID.sol";

/// @notice Interface for Karma token
interface IKarma {
    function balanceOf(address account) external view returns (uint256);
    function karmaOf(address account) external view returns (uint256);
    function isVerified(address account) external view returns (bool);
    function didOf(address account) external view returns (bytes32);
    function recordActivity(address account) external;
}

/// @notice Interface for SoulID NFT
interface ISoulIDToken {
    function soulOf(address account) external view returns (uint256);
    function hasSoul(address account) external view returns (bool);
    function mintSoul(address to) external returns (uint256);
    function reputation(uint256 tokenId) external view returns (
        uint256 karma,
        uint256 humanityScore,
        uint256 governanceParticipation,
        uint256 communityContribution,
        uint256 protocolUsage,
        uint256 trustLevel,
        uint256 lastUpdated
    );
    function didOf(uint256 tokenId) external view returns (bytes32);
    function updateKarma(uint256 tokenId, uint256 karma) external;
    function updateTrustLevel(uint256 tokenId, uint256 level) external;
    function updateHumanityScore(uint256 tokenId, uint256 score) external;
    function updateGovernanceScore(uint256 tokenId, uint256 score) external;
}

/**
 * @title IdentityHub - Native Identity Layer for Lux Network
 * @notice Unified identity system: DID + SoulID + Karma = one identity
 * @dev Implements LP-3006 Native Identity Standard
 *
 * ARCHITECTURE:
 * ┌─────────────────────────────────────────────────────────────────────────────┐
 * │                         IDENTITY HUB (this contract)                        │
 * │  ┌───────────────────────────────────────────────────────────────────────┐  │
 * │  │  W3C DID Layer (DIDRegistry)                                          │  │
 * │  │  - did:lux:<identifier>                                               │  │
 * │  │  - Verification methods, services, credentials                        │  │
 * │  └───────────────────────────────────────────────────────────────────────┘  │
 * │                              ▲                                              │
 * │                              │ links to                                     │
 * │                              ▼                                              │
 * │  ┌───────────────────────────────────────────────────────────────────────┐  │
 * │  │  SoulID Layer (SoulID.sol)                                            │  │
 * │  │  - Soulbound NFT (non-transferable)                                   │  │
 * │  │  - Reputation fields (humanity, governance, community, protocol)      │  │
 * │  │  - Badges and attestations                                            │  │
 * │  └───────────────────────────────────────────────────────────────────────┘  │
 * │                              ▲                                              │
 * │                              │ reputation from                              │
 * │                              ▼                                              │
 * │  ┌───────────────────────────────────────────────────────────────────────┐  │
 * │  │  Karma Layer (Karma.sol + KarmaController.sol)                        │  │
 * │  │  - Soul-bound reputation token                                        │  │
 * │  │  - earnKarma / giveKarma / purgeKarma                                 │  │
 * │  │  - Activity-driven decay (1% active, 10% inactive)                    │  │
 * │  └───────────────────────────────────────────────────────────────────────┘  │
 * │                                                                             │
 * │  GOVERNANCE INTEGRATION:                                                    │
 * │  ┌───────────────────────────────────────────────────────────────────────┐  │
 * │  │  getVotingPower(account) = f(karma, soulID.trustLevel)                │  │
 * │  │  canPropose(account) = karma >= MIN_PROPOSE_KARMA                     │  │
 * │  │  isHuman(account) = soulID.humanityScore > 50                         │  │
 * │  │  getIdentity(account) = (did, soulId, karma, reputation)              │  │
 * │  └───────────────────────────────────────────────────────────────────────┘  │
 * └─────────────────────────────────────────────────────────────────────────────┘
 *
 * DEPLOYMENT (one per chain):
 * ┌─────────────┐  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐
 * │    Lux      │  │    ASHA     │  │    CYRUS    │  │    MIGA     │
 * │  Mainnet    │  │   Chain     │  │   Chain     │  │   Chain     │
 * └─────────────┘  └─────────────┘  └─────────────┘  └─────────────┘
 *       │               │               │               │
 *       ▼               ▼               ▼               ▼
 * ┌─────────────────────────────────────────────────────────────────┐
 * │                    IdentityHub (per chain)                      │
 * │  - Same interface, same behavior                                │
 * │  - Karma accrues on primary chain (Lux)                         │
 * │  - SoulID minted once, recognized everywhere                    │
 * └─────────────────────────────────────────────────────────────────┘
 */
contract IdentityHub is AccessControl, ReentrancyGuard {
    // ============ Roles ============

    /// @notice Role for identity operators
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");

    /// @notice Role for governance contracts
    bytes32 public constant GOVERNANCE_ROLE = keccak256("GOVERNANCE_ROLE");

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

    // ============ Constants ============

    /// @notice Minimum karma to create proposals
    uint256 public constant MIN_PROPOSE_KARMA = 100e18;

    /// @notice Minimum humanity score to be considered human
    uint256 public constant MIN_HUMANITY_SCORE = 50;

    /// @notice Chain identifier
    uint256 public immutable CHAIN_ID;

    /// @notice Network name (lux, asha, cyrus, miga, pars)
    string public networkName;

    // ============ State ============

    /// @notice DID Registry contract
    IDIDRegistry public didRegistry;

    /// @notice Karma contract
    IKarma public karma;

    /// @notice SoulID contract
    ISoulIDToken public soulID;

    /// @notice Whether this is the primary chain (where karma accrues)
    bool public isPrimaryChain;

    /// @notice Address to DID string cache
    mapping(address => string) public didOf;

    // ============ Events ============

    event IdentityCreated(address indexed account, string did, uint256 soulId);
    event IdentityLinked(address indexed account, string did, uint256 soulId);
    event VotingPowerCalculated(address indexed account, uint256 votingPower);
    event ContractsUpdated(address didRegistry, address karma, address soulID);

    // ============ Errors ============

    error ZeroAddress();
    error IdentityAlreadyExists();
    error NoIdentity();
    error NotPrimaryChain();
    error ContractNotSet();

    // ============ Constructor ============

    /**
     * @notice Initialize the Identity Hub
     * @param admin Admin address
     * @param _networkName Network identifier (lux, asha, cyrus, miga, pars)
     * @param _isPrimaryChain Whether this is the primary chain
     */
    constructor(
        address admin,
        string memory _networkName,
        bool _isPrimaryChain
    ) {
        if (admin == address(0)) revert ZeroAddress();

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(OPERATOR_ROLE, admin);

        CHAIN_ID = block.chainid;
        networkName = _networkName;
        isPrimaryChain = _isPrimaryChain;
    }

    // ============ Identity Creation ============

    /**
     * @notice Create complete identity (DID + SoulID)
     * @param identifier DID identifier (e.g., "alice" for did:lux:alice)
     * @return did The created DID string
     * @return soulId The minted SoulID token
     */
    function createIdentity(
        string calldata identifier
    ) external nonReentrant returns (string memory did, uint256 soulId) {
        if (address(didRegistry) == address(0)) revert ContractNotSet();
        if (address(soulID) == address(0)) revert ContractNotSet();

        // Check no existing identity
        if (soulID.hasSoul(msg.sender)) revert IdentityAlreadyExists();

        // Create DID
        did = didRegistry.createDID(networkName, identifier);
        didOf[msg.sender] = did;

        // Mint SoulID
        soulId = soulID.mintSoul(msg.sender);

        // Link DID to SoulID
        bytes32 didHash = keccak256(bytes(did));
        // Note: SoulID.linkDID would be called by attestor

        emit IdentityCreated(msg.sender, did, soulId);
    }

    /**
     * @notice Link existing DID to SoulID
     * @param did Existing DID string
     */
    function linkExistingDID(string calldata did) external nonReentrant {
        if (address(didRegistry) == address(0)) revert ContractNotSet();
        if (address(soulID) == address(0)) revert ContractNotSet();

        // Verify caller owns the DID
        address controller = didRegistry.controllerOf(did);
        require(controller == msg.sender, "Not DID controller");

        // Mint SoulID if needed
        uint256 soulId;
        if (!soulID.hasSoul(msg.sender)) {
            soulId = soulID.mintSoul(msg.sender);
        } else {
            soulId = soulID.soulOf(msg.sender);
        }

        didOf[msg.sender] = did;

        emit IdentityLinked(msg.sender, did, soulId);
    }

    // ============ Governance Functions ============

    /**
     * @notice Get voting power for governance
     * @param account Address to query
     * @return votingPower Calculated voting power
     * @dev votingPower = karma * (trustLevel / 100)
     */
    function getVotingPower(address account) external view returns (uint256 votingPower) {
        if (address(karma) == address(0)) return 0;
        if (address(soulID) == address(0)) return karma.karmaOf(account);

        uint256 karmaBalance = karma.karmaOf(account);

        if (!soulID.hasSoul(account)) {
            // No SoulID = karma only, no multiplier
            return karmaBalance;
        }

        uint256 soulId = soulID.soulOf(account);
        (,,,,,uint256 trustLevel,) = soulID.reputation(soulId);

        // votingPower = karma * (50 + trustLevel/2) / 100
        // This gives range: karma * 0.5 (trust=0) to karma * 1.0 (trust=100)
        votingPower = (karmaBalance * (50 + trustLevel / 2)) / 100;
    }

    /**
     * @notice Check if account can create proposals
     * @param account Address to check
     * @return canPropose Whether account meets requirements
     */
    function canPropose(address account) external view returns (bool) {
        if (address(karma) == address(0)) return false;
        return karma.karmaOf(account) >= MIN_PROPOSE_KARMA;
    }

    /**
     * @notice Check if account is verified human
     * @param account Address to check
     * @return isHuman Whether account passes humanity check
     */
    function isHuman(address account) external view returns (bool) {
        if (address(soulID) == address(0)) return false;
        if (!soulID.hasSoul(account)) return false;

        uint256 soulId = soulID.soulOf(account);
        (,uint256 humanityScore,,,,,) = soulID.reputation(soulId);

        return humanityScore >= MIN_HUMANITY_SCORE;
    }

    /**
     * @notice Get complete identity for account
     * @param account Address to query
     * @return identity Complete identity struct
     */
    function getIdentity(address account) external view returns (Identity memory identity) {
        // DID Layer
        identity.did = didOf[account];
        identity.hasDID = bytes(identity.did).length > 0;

        // SoulID Layer
        if (address(soulID) != address(0) && soulID.hasSoul(account)) {
            identity.hasSoul = true;
            identity.soulId = soulID.soulOf(account);

            (
                identity.karma,
                identity.humanityScore,
                identity.governanceParticipation,
                identity.communityContribution,
                identity.protocolUsage,
                identity.trustLevel,
            ) = soulID.reputation(identity.soulId);
        }

        // Karma Layer (authoritative)
        if (address(karma) != address(0)) {
            identity.karma = karma.karmaOf(account);
            identity.isVerified = karma.isVerified(account);
        }

        // Governance calculations
        identity.votingPower = this.getVotingPower(account);
        identity.canPropose = identity.karma >= MIN_PROPOSE_KARMA;
        identity.isHuman = identity.humanityScore >= MIN_HUMANITY_SCORE;
    }

    /**
     * @notice Record governance activity (updates karma decay timer)
     * @param account Address that participated
     */
    function recordGovernanceActivity(address account) external onlyRole(GOVERNANCE_ROLE) {
        if (address(karma) != address(0)) {
            karma.recordActivity(account);
        }

        // Update governance participation score in SoulID
        if (address(soulID) != address(0) && soulID.hasSoul(account)) {
            uint256 soulId = soulID.soulOf(account);
            (,, uint256 currentScore,,,,) = soulID.reputation(soulId);

            // Increment governance participation (cap at 100)
            uint256 newScore = currentScore < 99 ? currentScore + 1 : 100;
            soulID.updateGovernanceScore(soulId, newScore);
        }
    }

    // ============ Sync Functions ============

    /**
     * @notice Sync karma balance to SoulID reputation
     * @param account Address to sync
     */
    function syncKarmaToSoulID(address account) external {
        if (address(karma) == address(0)) revert ContractNotSet();
        if (address(soulID) == address(0)) revert ContractNotSet();
        if (!soulID.hasSoul(account)) revert NoIdentity();

        uint256 soulId = soulID.soulOf(account);
        uint256 karmaBalance = karma.karmaOf(account);

        soulID.updateKarma(soulId, karmaBalance);

        // Update trust level based on karma (linear mapping)
        uint256 trustLevel = karmaBalance > 1000e18 ? 100 : (karmaBalance * 100) / 1000e18;
        soulID.updateTrustLevel(soulId, trustLevel);
    }

    // ============ Admin Functions ============

    /**
     * @notice Set contract addresses
     * @param _didRegistry DID Registry address
     * @param _karma Karma contract address
     * @param _soulID SoulID contract address
     */
    function setContracts(
        address _didRegistry,
        address _karma,
        address _soulID
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (_didRegistry != address(0)) {
            didRegistry = IDIDRegistry(_didRegistry);
        }
        if (_karma != address(0)) {
            karma = IKarma(_karma);
        }
        if (_soulID != address(0)) {
            soulID = ISoulIDToken(_soulID);
        }

        emit ContractsUpdated(_didRegistry, _karma, _soulID);
    }

    /**
     * @notice Grant governance role to a contract
     * @param governance Governance contract address
     */
    function addGovernance(address governance) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _grantRole(GOVERNANCE_ROLE, governance);
    }
}
