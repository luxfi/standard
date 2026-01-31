// SPDX-License-Identifier: BSD-3-Clause
// Copyright (c) 2025 Lux Industries Inc.
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title ShieldedTreasury
 * @author Lux Industries
 * @notice ZK-UTXO treasury vault with governance-controlled spending authorizations
 * @dev Extends privacy model for DAO treasury disbursements on Z-Chain
 *
 * Features:
 * - Shielded deposits (public aggregate, private individual)
 * - Governance-authorized spending caps
 * - View keys for selective transparency
 * - Rate limiting and custody policies
 * - Multi-asset support
 */
contract ShieldedTreasury is AccessControl, ReentrancyGuard {

    // ═══════════════════════════════════════════════════════════════════════
    // ROLES
    // ═══════════════════════════════════════════════════════════════════════

    bytes32 public constant DEPOSIT_ROLE = keccak256("DEPOSIT_ROLE");
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");
    bytes32 public constant AUTHORIZATION_ROLE = keccak256("AUTHORIZATION_ROLE");
    bytes32 public constant VIEW_KEY_ROLE = keccak256("VIEW_KEY_ROLE");
    bytes32 public constant VERIFIER_ROLE = keccak256("VERIFIER_ROLE");

    // ═══════════════════════════════════════════════════════════════════════
    // TYPES
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice Shielded UTXO commitment
    struct Commitment {
        bytes32 hash;           // H(value || blinding || owner)
        uint64 timestamp;
        bytes encryptedData;    // Encrypted note details
        bool spent;
    }

    /// @notice Spending authorization from governance
    struct Authorization {
        bytes32 id;
        bytes32 programId;      // Sub-DAO or program identifier
        uint256 cap;            // Maximum spend amount
        uint256 spent;          // Amount spent so far
        uint256 expiry;         // Authorization expiry timestamp
        bytes32[] categoryTags; // Allowed spend categories
        address[] operators;    // Authorized operators
        bytes attestation;      // Governance attestation signature
        bool active;
    }

    /// @notice View key holder
    struct ViewKeyHolder {
        address holder;
        bytes32 encryptedViewKey;
        string scope;           // e.g., "security-dao", "all-treasury"
        uint64 grantedAt;
        uint64 expiresAt;
        bool active;
    }

    /// @notice Custody policy
    struct CustodyPolicy {
        uint256 maxPerTransaction;
        uint256 maxPerDay;
        uint256 cooldownMinutes;
        uint256 dailySpent;
        uint256 lastResetTimestamp;
    }

    // ═══════════════════════════════════════════════════════════════════════
    // CONSTANTS
    // ═══════════════════════════════════════════════════════════════════════

    uint256 public constant TREE_DEPTH = 32;
    uint256 public constant DEFAULT_MAX_PER_TX = 500_000 ether;
    uint256 public constant DEFAULT_MAX_PER_DAY = 2_000_000 ether;
    uint256 public constant DEFAULT_COOLDOWN = 60; // minutes

    // ═══════════════════════════════════════════════════════════════════════
    // STATE
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice Vault identity
    bytes32 public vaultId;
    bytes32 public ownerId;
    string public assetType;

    /// @notice Threshold parameters for decryption
    uint8 public thresholdMin;
    uint8 public thresholdTotal;

    /// @notice Commitment Merkle tree
    bytes32[TREE_DEPTH] public filledSubtrees;
    bytes32 public merkleRoot;
    uint256 public nextCommitmentIndex;
    mapping(bytes32 => bool) public knownRoots;

    /// @notice Commitments and nullifiers
    mapping(bytes32 => Commitment) public commitments;
    mapping(uint256 => bytes32) public commitmentsByIndex;
    mapping(bytes32 => bool) public nullifiers;

    /// @notice Aggregate balance (public)
    uint256 public aggregateBalance;

    /// @notice Authorizations
    mapping(bytes32 => Authorization) public authorizations;
    bytes32[] public authorizationIds;

    /// @notice View key holders
    mapping(address => ViewKeyHolder) public viewKeyHolders;
    address[] public viewKeyHolderList;

    /// @notice Custody policy
    CustodyPolicy public custodyPolicy;

    /// @notice ZK verifier contract
    address public zkVerifier;

    // ═══════════════════════════════════════════════════════════════════════
    // EVENTS
    // ═══════════════════════════════════════════════════════════════════════

    event ShieldedDeposit(
        bytes32 indexed commitment,
        uint256 indexed index,
        uint256 aggregateBalanceAfter
    );
    event ShieldedSpend(
        bytes32 indexed nullifier,
        bytes32 indexed authorizationId,
        bytes32 newCommitment
    );
    event AuthorizationCreated(
        bytes32 indexed id,
        bytes32 indexed programId,
        uint256 cap,
        uint256 expiry
    );
    event AuthorizationRevoked(bytes32 indexed id);
    event ViewKeyGranted(address indexed holder, string scope);
    event ViewKeyRevoked(address indexed holder);
    event CustodyPolicyUpdated(uint256 maxPerTx, uint256 maxPerDay, uint256 cooldown);

    // ═══════════════════════════════════════════════════════════════════════
    // ERRORS
    // ═══════════════════════════════════════════════════════════════════════

    error CommitmentExists();
    error NullifierSpent();
    error InvalidProof();
    error AuthorizationNotFound();
    error AuthorizationExpired();
    error AuthorizationCapExceeded();
    error RateLimitExceeded();
    error CooldownActive();
    error InvalidExpiry();
    error Unauthorized();

    // ═══════════════════════════════════════════════════════════════════════
    // CONSTRUCTOR
    // ═══════════════════════════════════════════════════════════════════════

    constructor(
        bytes32 _vaultId,
        bytes32 _ownerId,
        string memory _assetType,
        address _admin,
        address _zkVerifier,
        uint8 _thresholdMin,
        uint8 _thresholdTotal
    ) {
        vaultId = _vaultId;
        ownerId = _ownerId;
        assetType = _assetType;
        zkVerifier = _zkVerifier;
        thresholdMin = _thresholdMin;
        thresholdTotal = _thresholdTotal;

        _grantRole(DEFAULT_ADMIN_ROLE, _admin);

        // Initialize custody policy
        custodyPolicy = CustodyPolicy({
            maxPerTransaction: DEFAULT_MAX_PER_TX,
            maxPerDay: DEFAULT_MAX_PER_DAY,
            cooldownMinutes: DEFAULT_COOLDOWN,
            dailySpent: 0,
            lastResetTimestamp: block.timestamp
        });

        // Initialize Merkle tree with zeros
        _initializeMerkleTree();
    }

    function _initializeMerkleTree() internal {
        bytes32 currentZero = bytes32(0);
        for (uint256 i = 0; i < TREE_DEPTH; i++) {
            filledSubtrees[i] = currentZero;
            currentZero = keccak256(abi.encodePacked(currentZero, currentZero));
        }
        merkleRoot = currentZero;
        knownRoots[merkleRoot] = true;
    }

    // ═══════════════════════════════════════════════════════════════════════
    // DEPOSITS
    // ═══════════════════════════════════════════════════════════════════════

    /**
     * @notice Create shielded deposit (commitment)
     * @param commitment Pedersen commitment H(value || blinding)
     * @param amount Amount being deposited (for aggregate tracking)
     */
    function deposit(
        bytes32 commitment,
        uint256 amount
    ) external onlyRole(DEPOSIT_ROLE) nonReentrant {
        if (commitments[commitment].hash != bytes32(0)) revert CommitmentExists();

        // Store commitment
        uint256 index = nextCommitmentIndex++;
        commitments[commitment] = Commitment({
            hash: commitment,
            timestamp: uint64(block.timestamp),
            encryptedData: "",
            spent: false
        });
        commitmentsByIndex[index] = commitment;

        // Update Merkle tree
        _insertIntoMerkleTree(commitment, index);

        // Update aggregate balance (public)
        aggregateBalance += amount;

        emit ShieldedDeposit(commitment, index, aggregateBalance);
    }

    /**
     * @notice Deposit with encrypted note data
     */
    function depositWithNote(
        bytes32 commitment,
        uint256 amount,
        bytes calldata encryptedNote
    ) external onlyRole(DEPOSIT_ROLE) nonReentrant {
        if (commitments[commitment].hash != bytes32(0)) revert CommitmentExists();

        uint256 index = nextCommitmentIndex++;
        commitments[commitment] = Commitment({
            hash: commitment,
            timestamp: uint64(block.timestamp),
            encryptedData: encryptedNote,
            spent: false
        });
        commitmentsByIndex[index] = commitment;

        _insertIntoMerkleTree(commitment, index);
        aggregateBalance += amount;

        emit ShieldedDeposit(commitment, index, aggregateBalance);
    }

    function _insertIntoMerkleTree(bytes32 leaf, uint256 index) internal {
        bytes32 currentHash = leaf;
        for (uint256 i = 0; i < TREE_DEPTH; i++) {
            if (index % 2 == 0) {
                filledSubtrees[i] = currentHash;
                currentHash = keccak256(abi.encodePacked(currentHash, filledSubtrees[i]));
            } else {
                currentHash = keccak256(abi.encodePacked(filledSubtrees[i], currentHash));
            }
            index /= 2;
        }
        merkleRoot = currentHash;
        knownRoots[merkleRoot] = true;
    }

    // ═══════════════════════════════════════════════════════════════════════
    // AUTHORIZATIONS
    // ═══════════════════════════════════════════════════════════════════════

    /**
     * @notice Create spending authorization from governance
     */
    function createAuthorization(
        bytes32 authId,
        bytes32 programId,
        uint256 cap,
        uint256 expiry,
        bytes32[] calldata categoryTags,
        address[] calldata operators,
        bytes calldata attestation
    ) external onlyRole(AUTHORIZATION_ROLE) {
        if (expiry <= block.timestamp) revert InvalidExpiry();

        authorizations[authId] = Authorization({
            id: authId,
            programId: programId,
            cap: cap,
            spent: 0,
            expiry: expiry,
            categoryTags: categoryTags,
            operators: operators,
            attestation: attestation,
            active: true
        });
        authorizationIds.push(authId);

        emit AuthorizationCreated(authId, programId, cap, expiry);
    }

    /**
     * @notice Revoke authorization
     */
    function revokeAuthorization(bytes32 authId) external onlyRole(AUTHORIZATION_ROLE) {
        if (!authorizations[authId].active) revert AuthorizationNotFound();
        authorizations[authId].active = false;
        emit AuthorizationRevoked(authId);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // SPENDING
    // ═══════════════════════════════════════════════════════════════════════

    /**
     * @notice Execute shielded spend with ZK proof
     * @param authorizationId Authorization to spend against
     * @param nullifier Nullifier for the input note
     * @param newCommitment Output commitment (change)
     * @param amount Spend amount
     * @param zkProof ZK proof of valid spend
     */
    function executeShieldedSpend(
        bytes32 authorizationId,
        bytes32 nullifier,
        bytes32 newCommitment,
        uint256 amount,
        bytes calldata zkProof
    ) external onlyRole(OPERATOR_ROLE) nonReentrant {
        // Verify authorization
        Authorization storage auth = authorizations[authorizationId];
        if (!auth.active) revert AuthorizationNotFound();
        if (block.timestamp > auth.expiry) revert AuthorizationExpired();
        if (auth.spent + amount > auth.cap) revert AuthorizationCapExceeded();

        // Verify operator is authorized
        bool isAuthorized = false;
        for (uint256 i = 0; i < auth.operators.length; i++) {
            if (auth.operators[i] == msg.sender) {
                isAuthorized = true;
                break;
            }
        }
        if (!isAuthorized) revert Unauthorized();

        // Check rate limits
        _checkRateLimits(amount);

        // Verify nullifier not spent
        if (nullifiers[nullifier]) revert NullifierSpent();

        // Verify ZK proof (if verifier set)
        if (zkVerifier != address(0)) {
            // Call external verifier
            (bool success, bytes memory result) = zkVerifier.staticcall(
                abi.encodeWithSignature(
                    "verify(bytes32,bytes32,bytes32,uint256,bytes)",
                    merkleRoot,
                    nullifier,
                    newCommitment,
                    amount,
                    zkProof
                )
            );
            if (!success || !abi.decode(result, (bool))) revert InvalidProof();
        }

        // Mark nullifier as spent
        nullifiers[nullifier] = true;

        // Update authorization
        auth.spent += amount;

        // Update aggregate balance
        aggregateBalance -= amount;

        // Insert new commitment if not zero (change output)
        if (newCommitment != bytes32(0)) {
            uint256 index = nextCommitmentIndex++;
            commitments[newCommitment] = Commitment({
                hash: newCommitment,
                timestamp: uint64(block.timestamp),
                encryptedData: "",
                spent: false
            });
            commitmentsByIndex[index] = newCommitment;
            _insertIntoMerkleTree(newCommitment, index);
        }

        emit ShieldedSpend(nullifier, authorizationId, newCommitment);
    }

    function _checkRateLimits(uint256 amount) internal {
        CustodyPolicy storage policy = custodyPolicy;

        // Reset daily limit if new day
        if (block.timestamp > policy.lastResetTimestamp + 1 days) {
            policy.dailySpent = 0;
            policy.lastResetTimestamp = block.timestamp;
        }

        // Check per-transaction limit
        if (amount > policy.maxPerTransaction) revert RateLimitExceeded();

        // Check daily limit
        if (policy.dailySpent + amount > policy.maxPerDay) revert RateLimitExceeded();

        // Update daily spent
        policy.dailySpent += amount;
    }

    // ═══════════════════════════════════════════════════════════════════════
    // VIEW KEYS
    // ═══════════════════════════════════════════════════════════════════════

    /**
     * @notice Grant view key to auditor/observer
     */
    function grantViewKey(
        address holder,
        bytes32 encryptedViewKey,
        string calldata scope
    ) external onlyRole(VIEW_KEY_ROLE) {
        viewKeyHolders[holder] = ViewKeyHolder({
            holder: holder,
            encryptedViewKey: encryptedViewKey,
            scope: scope,
            grantedAt: uint64(block.timestamp),
            expiresAt: uint64(block.timestamp + 365 days),
            active: true
        });
        viewKeyHolderList.push(holder);

        emit ViewKeyGranted(holder, scope);
    }

    /**
     * @notice Revoke view key
     */
    function revokeViewKey(address holder) external onlyRole(VIEW_KEY_ROLE) {
        viewKeyHolders[holder].active = false;
        emit ViewKeyRevoked(holder);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // ADMIN
    // ═══════════════════════════════════════════════════════════════════════

    function setCustodyPolicy(
        uint256 maxPerTx,
        uint256 maxPerDay,
        uint256 cooldownMinutes
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        custodyPolicy.maxPerTransaction = maxPerTx;
        custodyPolicy.maxPerDay = maxPerDay;
        custodyPolicy.cooldownMinutes = cooldownMinutes;
        emit CustodyPolicyUpdated(maxPerTx, maxPerDay, cooldownMinutes);
    }

    function setZKVerifier(address _verifier) external onlyRole(DEFAULT_ADMIN_ROLE) {
        zkVerifier = _verifier;
    }

    function updateThreshold(uint8 _min, uint8 _total) external onlyRole(DEFAULT_ADMIN_ROLE) {
        thresholdMin = _min;
        thresholdTotal = _total;
    }

    // ═══════════════════════════════════════════════════════════════════════
    // VIEW FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════

    function getVaultInfo() external view returns (
        bytes32 _vaultId,
        bytes32 _ownerId,
        string memory _assetType,
        uint256 _aggregateBalance,
        uint256 _commitmentCount
    ) {
        return (vaultId, ownerId, assetType, aggregateBalance, nextCommitmentIndex);
    }

    function getCustodyPolicy() external view returns (
        uint256 _maxPerTransaction,
        uint256 _maxPerDay,
        uint256 _cooldownMinutes,
        uint256 _dailySpent
    ) {
        return (
            custodyPolicy.maxPerTransaction,
            custodyPolicy.maxPerDay,
            custodyPolicy.cooldownMinutes,
            custodyPolicy.dailySpent
        );
    }

    function getAuthorization(bytes32 authId) external view returns (Authorization memory) {
        return authorizations[authId];
    }

    function isNullifierSpent(bytes32 nullifier) external view returns (bool) {
        return nullifiers[nullifier];
    }

    function isKnownRoot(bytes32 root) external view returns (bool) {
        return knownRoots[root];
    }
}
