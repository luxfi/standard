// SPDX-License-Identifier: BSD-3-Clause
// Copyright (c) 2025 Lux Industries Inc.
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";

/**
 * @title TeleportProposalBridge
 * @author Lux Industries
 * @notice Cross-chain governance bridge for teleporting proposals between chains
 * @dev Routes governance actions between Lux (home) and teleport locales (Base, etc.)
 *
 * Architecture:
 * - Lux C-Chain: Primary governance hub
 * - Lux T-Chain: FHE private voting
 * - Lux Z-Chain: ZK-UTXO shielded treasury
 * - Base/Others: Teleport locales for asset bridging/listing
 *
 * Message Types:
 * - PROPOSAL_CREATE: New proposal from teleport locale → Lux
 * - VOTE_BATCH: Encrypted votes → T-Chain for FHE tallying
 * - TALLY_RESULT: Decrypted tally → C-Chain governance
 * - SPEND_AUTH: Treasury spend authorization → Z-Chain
 * - ASSET_TELEPORT: Asset bridge between locales
 */
contract TeleportProposalBridge is AccessControl, ReentrancyGuard {
    using ECDSA for bytes32;
    using MessageHashUtils for bytes32;

    // ═══════════════════════════════════════════════════════════════════════
    // ROLES
    // ═══════════════════════════════════════════════════════════════════════

    bytes32 public constant RELAYER_ROLE = keccak256("RELAYER_ROLE");
    bytes32 public constant VALIDATOR_ROLE = keccak256("VALIDATOR_ROLE");
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");

    // ═══════════════════════════════════════════════════════════════════════
    // CHAIN IDENTIFIERS
    // ═══════════════════════════════════════════════════════════════════════

    uint256 public constant LUX_C_CHAIN = 96369;
    uint256 public constant LUX_T_CHAIN = 96370;
    uint256 public constant LUX_Z_CHAIN = 96371;
    uint256 public constant BASE_MAINNET = 8453;
    uint256 public constant BASE_SEPOLIA = 84532;

    // ═══════════════════════════════════════════════════════════════════════
    // TYPES
    // ═══════════════════════════════════════════════════════════════════════

    enum MessageType {
        PROPOSAL_CREATE,
        VOTE_BATCH,
        TALLY_RESULT,
        SPEND_AUTH,
        ASSET_TELEPORT
    }

    struct TeleportLocale {
        uint256 chainId;
        string name;
        address bridgeEndpoint;
        bool active;
        uint256 messageNonce;
    }

    struct CrossChainMessage {
        bytes32 messageId;
        uint256 sourceChainId;
        uint256 destChainId;
        MessageType messageType;
        bytes payload;
        uint256 timestamp;
        uint256 nonce;
        bool executed;
    }

    struct ProposalRoute {
        bytes32 proposalId;
        uint256 originChainId;
        bytes32[] targetDAOs;
        bool votingStarted;
        bool tallyReceived;
        uint256 routedAt;
    }

    struct ValidatorSet {
        address[] validators;
        uint256 threshold;           // Required signatures
        uint256 rotationPeriod;
        uint256 lastRotation;
    }

    // ═══════════════════════════════════════════════════════════════════════
    // CONSTANTS
    // ═══════════════════════════════════════════════════════════════════════

    uint256 public constant MESSAGE_EXPIRY = 7 days;
    uint256 public constant MIN_CONFIRMATIONS = 3;

    // ═══════════════════════════════════════════════════════════════════════
    // STATE
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice Current chain ID
    uint256 public immutable currentChainId;

    /// @notice Registered teleport locales
    mapping(uint256 => TeleportLocale) public locales;
    uint256[] public localeChainIds;

    /// @notice Pending messages
    mapping(bytes32 => CrossChainMessage) public messages;
    bytes32[] public pendingMessageIds;

    /// @notice Message signatures (messageId => validator => signed)
    mapping(bytes32 => mapping(address => bool)) public messageSignatures;
    mapping(bytes32 => uint256) public signatureCount;

    /// @notice Proposal routing
    mapping(bytes32 => ProposalRoute) public proposalRoutes;

    /// @notice Validator set
    ValidatorSet public validatorSet;

    /// @notice Governance contract on this chain
    address public governanceContract;

    /// @notice T-Chain voting contract
    address public tChainVoting;

    /// @notice Z-Chain treasury
    address public zChainTreasury;

    /// @notice Emergency pause
    bool public paused;

    // ═══════════════════════════════════════════════════════════════════════
    // EVENTS
    // ═══════════════════════════════════════════════════════════════════════

    event LocaleRegistered(uint256 indexed chainId, string name, address bridgeEndpoint);
    event LocaleUpdated(uint256 indexed chainId, address newEndpoint);
    event LocaleDeactivated(uint256 indexed chainId);

    event MessageQueued(
        bytes32 indexed messageId,
        uint256 sourceChainId,
        uint256 destChainId,
        MessageType messageType
    );
    event MessageSigned(bytes32 indexed messageId, address indexed validator);
    event MessageExecuted(bytes32 indexed messageId, bool success);
    event MessageExpired(bytes32 indexed messageId);

    event ProposalRouted(bytes32 indexed proposalId, uint256 sourceChainId, uint256 destChainId);
    event VoteBatchRouted(bytes32 indexed proposalId, uint256 voteCount);
    event TallyRouted(bytes32 indexed proposalId, bytes32 indexed daoId, bool passed);
    event SpendAuthRouted(bytes32 indexed authorizationId, uint256 amount);
    event AssetTeleported(address indexed token, uint256 amount, uint256 destChainId);

    // ═══════════════════════════════════════════════════════════════════════
    // ERRORS
    // ═══════════════════════════════════════════════════════════════════════

    error LocaleNotFound();
    error LocaleAlreadyExists();
    error MessageNotFound();
    error MessageAlreadyExecuted();
    error MessageExpiredError();
    error InsufficientSignatures();
    error AlreadySigned();
    error InvalidSignature();
    error InvalidDestination();
    error Unauthorized();
    error BridgePaused();
    error InvalidPayload();

    // ═══════════════════════════════════════════════════════════════════════
    // CONSTRUCTOR
    // ═══════════════════════════════════════════════════════════════════════

    constructor(
        address _admin,
        address[] memory _validators,
        uint256 _threshold
    ) {
        currentChainId = block.chainid;

        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        _grantRole(OPERATOR_ROLE, _admin);

        validatorSet.validators = _validators;
        validatorSet.threshold = _threshold;
        validatorSet.lastRotation = block.timestamp;

        for (uint256 i = 0; i < _validators.length; i++) {
            _grantRole(VALIDATOR_ROLE, _validators[i]);
        }

        _initializeLuxLocales();
    }

    // ═══════════════════════════════════════════════════════════════════════
    // INITIALIZATION
    // ═══════════════════════════════════════════════════════════════════════

    function _initializeLuxLocales() internal {
        // Register Lux chains as locales
        _registerLocale(LUX_C_CHAIN, "Lux C-Chain", address(0));
        _registerLocale(LUX_T_CHAIN, "Lux T-Chain (TFHE)", address(0));
        _registerLocale(LUX_Z_CHAIN, "Lux Z-Chain (zkVM)", address(0));
        _registerLocale(BASE_MAINNET, "Base Mainnet", address(0));
    }

    function _registerLocale(
        uint256 chainId,
        string memory name,
        address bridgeEndpoint
    ) internal {
        locales[chainId] = TeleportLocale({
            chainId: chainId,
            name: name,
            bridgeEndpoint: bridgeEndpoint,
            active: true,
            messageNonce: 0
        });
        localeChainIds.push(chainId);
        emit LocaleRegistered(chainId, name, bridgeEndpoint);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // MESSAGE QUEUEING
    // ═══════════════════════════════════════════════════════════════════════

    /**
     * @notice Queue a proposal creation message for cross-chain routing
     * @param destChainId Destination chain (typically Lux C-Chain)
     * @param proposalPayload Encoded proposal data
     */
    function queueProposalCreate(
        uint256 destChainId,
        bytes calldata proposalPayload
    ) external nonReentrant returns (bytes32 messageId) {
        if (paused) revert BridgePaused();
        if (!locales[destChainId].active) revert LocaleNotFound();

        messageId = _queueMessage(destChainId, MessageType.PROPOSAL_CREATE, proposalPayload);

        emit ProposalRouted(
            keccak256(proposalPayload),
            currentChainId,
            destChainId
        );
    }

    /**
     * @notice Queue encrypted vote batch for T-Chain FHE processing
     * @param proposalId Proposal being voted on
     * @param encryptedVotes Encrypted vote data (TFHE ciphertext)
     */
    function queueVoteBatch(
        bytes32 proposalId,
        bytes calldata encryptedVotes
    ) external onlyRole(RELAYER_ROLE) nonReentrant returns (bytes32 messageId) {
        if (paused) revert BridgePaused();

        bytes memory payload = abi.encode(proposalId, encryptedVotes);
        messageId = _queueMessage(LUX_T_CHAIN, MessageType.VOTE_BATCH, payload);

        emit VoteBatchRouted(proposalId, 1); // Batch count
    }

    /**
     * @notice Queue tally result from T-Chain back to C-Chain governance
     * @param proposalId Proposal that was tallied
     * @param daoId DAO that voted
     * @param forVotes Decrypted for votes
     * @param againstVotes Decrypted against votes
     * @param abstainVotes Decrypted abstain votes
     */
    function queueTallyResult(
        bytes32 proposalId,
        bytes32 daoId,
        uint256 forVotes,
        uint256 againstVotes,
        uint256 abstainVotes
    ) external onlyRole(RELAYER_ROLE) nonReentrant returns (bytes32 messageId) {
        if (paused) revert BridgePaused();

        bytes memory payload = abi.encode(
            proposalId,
            daoId,
            forVotes,
            againstVotes,
            abstainVotes
        );
        messageId = _queueMessage(LUX_C_CHAIN, MessageType.TALLY_RESULT, payload);

        bool passed = forVotes > againstVotes;
        emit TallyRouted(proposalId, daoId, passed);
    }

    /**
     * @notice Queue treasury spend authorization for Z-Chain
     * @param authorizationId Authorization ID from governance
     * @param recipient Recipient address
     * @param amount Amount to spend
     * @param token Token address (or zero for native)
     */
    function queueSpendAuth(
        bytes32 authorizationId,
        address recipient,
        uint256 amount,
        address token
    ) external onlyRole(RELAYER_ROLE) nonReentrant returns (bytes32 messageId) {
        if (paused) revert BridgePaused();

        bytes memory payload = abi.encode(authorizationId, recipient, amount, token);
        messageId = _queueMessage(LUX_Z_CHAIN, MessageType.SPEND_AUTH, payload);

        emit SpendAuthRouted(authorizationId, amount);
    }

    /**
     * @notice Queue asset teleport between locales
     * @param token Token address
     * @param amount Amount to teleport
     * @param destChainId Destination chain
     * @param recipient Recipient on destination
     */
    function queueAssetTeleport(
        address token,
        uint256 amount,
        uint256 destChainId,
        address recipient
    ) external nonReentrant returns (bytes32 messageId) {
        if (paused) revert BridgePaused();
        if (!locales[destChainId].active) revert LocaleNotFound();

        bytes memory payload = abi.encode(token, amount, recipient);
        messageId = _queueMessage(destChainId, MessageType.ASSET_TELEPORT, payload);

        emit AssetTeleported(token, amount, destChainId);
    }

    function _queueMessage(
        uint256 destChainId,
        MessageType messageType,
        bytes memory payload
    ) internal returns (bytes32 messageId) {
        uint256 nonce = ++locales[destChainId].messageNonce;

        messageId = keccak256(abi.encodePacked(
            currentChainId,
            destChainId,
            messageType,
            payload,
            nonce,
            block.timestamp
        ));

        messages[messageId] = CrossChainMessage({
            messageId: messageId,
            sourceChainId: currentChainId,
            destChainId: destChainId,
            messageType: messageType,
            payload: payload,
            timestamp: block.timestamp,
            nonce: nonce,
            executed: false
        });

        pendingMessageIds.push(messageId);

        emit MessageQueued(messageId, currentChainId, destChainId, messageType);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // MESSAGE SIGNING & EXECUTION
    // ═══════════════════════════════════════════════════════════════════════

    /**
     * @notice Validator signs a message
     */
    function signMessage(bytes32 messageId) external onlyRole(VALIDATOR_ROLE) {
        CrossChainMessage storage message = messages[messageId];
        if (message.messageId == bytes32(0)) revert MessageNotFound();
        if (message.executed) revert MessageAlreadyExecuted();
        if (messageSignatures[messageId][msg.sender]) revert AlreadySigned();

        messageSignatures[messageId][msg.sender] = true;
        signatureCount[messageId]++;

        emit MessageSigned(messageId, msg.sender);
    }

    /**
     * @notice Execute a message once threshold signatures reached
     */
    function executeMessage(bytes32 messageId) external nonReentrant {
        CrossChainMessage storage message = messages[messageId];
        if (message.messageId == bytes32(0)) revert MessageNotFound();
        if (message.executed) revert MessageAlreadyExecuted();
        if (block.timestamp > message.timestamp + MESSAGE_EXPIRY) {
            message.executed = true; // Mark as executed (expired)
            emit MessageExpired(messageId);
            revert MessageExpiredError();
        }
        if (signatureCount[messageId] < validatorSet.threshold) {
            revert InsufficientSignatures();
        }

        message.executed = true;

        bool success = _processMessage(message);
        emit MessageExecuted(messageId, success);
    }

    function _processMessage(CrossChainMessage storage message) internal returns (bool) {
        if (message.messageType == MessageType.TALLY_RESULT) {
            return _processTallyResult(message.payload);
        } else if (message.messageType == MessageType.SPEND_AUTH) {
            return _processSpendAuth(message.payload);
        }
        // Other message types handled by destination chain contracts
        return true;
    }

    function _processTallyResult(bytes memory payload) internal returns (bool) {
        (
            bytes32 proposalId,
            bytes32 daoId,
            uint256 forVotes,
            uint256 againstVotes,
            uint256 abstainVotes
        ) = abi.decode(payload, (bytes32, bytes32, uint256, uint256, uint256));

        if (governanceContract == address(0)) return false;

        // Call governance contract's receiveTally function
        (bool success, ) = governanceContract.call(
            abi.encodeWithSignature(
                "receiveTally(bytes32,bytes32,uint256,uint256,uint256,bytes)",
                proposalId,
                daoId,
                forVotes,
                againstVotes,
                abstainVotes,
                ""
            )
        );

        return success;
    }

    function _processSpendAuth(bytes memory payload) internal returns (bool) {
        (
            bytes32 authorizationId,
            address recipient,
            uint256 amount,
            address token
        ) = abi.decode(payload, (bytes32, address, uint256, address));

        if (zChainTreasury == address(0)) return false;

        // Call treasury's execute function
        (bool success, ) = zChainTreasury.call(
            abi.encodeWithSignature(
                "executeAuthorization(bytes32,address,uint256,address)",
                authorizationId,
                recipient,
                amount,
                token
            )
        );

        return success;
    }

    // ═══════════════════════════════════════════════════════════════════════
    // VIEW FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════

    function getLocale(uint256 chainId) external view returns (TeleportLocale memory) {
        return locales[chainId];
    }

    function getLocaleCount() external view returns (uint256) {
        return localeChainIds.length;
    }

    function getMessage(bytes32 messageId) external view returns (CrossChainMessage memory) {
        return messages[messageId];
    }

    function getPendingMessageCount() external view returns (uint256) {
        return pendingMessageIds.length;
    }

    function getValidators() external view returns (address[] memory) {
        return validatorSet.validators;
    }

    function isMessageReady(bytes32 messageId) external view returns (bool) {
        CrossChainMessage storage message = messages[messageId];
        if (message.messageId == bytes32(0)) return false;
        if (message.executed) return false;
        if (block.timestamp > message.timestamp + MESSAGE_EXPIRY) return false;
        return signatureCount[messageId] >= validatorSet.threshold;
    }

    // ═══════════════════════════════════════════════════════════════════════
    // ADMIN FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════

    function registerLocale(
        uint256 chainId,
        string calldata name,
        address bridgeEndpoint
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (locales[chainId].active) revert LocaleAlreadyExists();
        _registerLocale(chainId, name, bridgeEndpoint);
    }

    function updateLocaleEndpoint(
        uint256 chainId,
        address newEndpoint
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (!locales[chainId].active) revert LocaleNotFound();
        locales[chainId].bridgeEndpoint = newEndpoint;
        emit LocaleUpdated(chainId, newEndpoint);
    }

    function deactivateLocale(uint256 chainId) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (!locales[chainId].active) revert LocaleNotFound();
        // Cannot deactivate Lux chains
        require(
            chainId != LUX_C_CHAIN &&
            chainId != LUX_T_CHAIN &&
            chainId != LUX_Z_CHAIN,
            "Cannot deactivate Lux chains"
        );
        locales[chainId].active = false;
        emit LocaleDeactivated(chainId);
    }

    function setGovernanceContract(address _governance) external onlyRole(DEFAULT_ADMIN_ROLE) {
        governanceContract = _governance;
    }

    function setTChainVoting(address _voting) external onlyRole(DEFAULT_ADMIN_ROLE) {
        tChainVoting = _voting;
    }

    function setZChainTreasury(address _treasury) external onlyRole(DEFAULT_ADMIN_ROLE) {
        zChainTreasury = _treasury;
    }

    function updateValidatorSet(
        address[] calldata _validators,
        uint256 _threshold
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        // Revoke old validators
        for (uint256 i = 0; i < validatorSet.validators.length; i++) {
            _revokeRole(VALIDATOR_ROLE, validatorSet.validators[i]);
        }

        // Set new validators
        validatorSet.validators = _validators;
        validatorSet.threshold = _threshold;
        validatorSet.lastRotation = block.timestamp;

        for (uint256 i = 0; i < _validators.length; i++) {
            _grantRole(VALIDATOR_ROLE, _validators[i]);
        }
    }

    function setPaused(bool _paused) external onlyRole(OPERATOR_ROLE) {
        paused = _paused;
    }
}
