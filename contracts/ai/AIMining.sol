// SPDX-License-Identifier: BSD-3-Clause
// Copyright (c) 2025 Lux Industries Inc.
// Copyright (C) 2019-2025, Lux Industries Inc. All rights reserved.
pragma solidity ^0.8.31;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";

import "./AIToken.sol";
import "./ChainConfig.sol";

/**
 * @title AIMining
 * @notice Core mining contract for AI token rewards based on compute work proofs
 * @dev Accepts work proofs, validates against spent set, calculates rewards based on
 *      chain config and GPU tier, and mints tokens via AIToken.
 *
 * Work Proof Structure:
 * - sessionId: Unique compute session identifier
 * - nonce: Proof of work nonce
 * - gpuId: Attested GPU identifier (from TEE)
 * - computeHash: Hash of compute work performed
 * - timestamp: Proof generation time
 * - signature: Miner's signature over proof data
 *
 * Double-Spend Prevention:
 * - Each proof hash is stored in spent set
 * - Duplicate proofs are rejected
 * - Proofs expire after validity window
 *
 * Supported Chains:
 * - C-Chain (96369)
 * - Hanzo EVM (36963)
 * - Zoo EVM (200200)
 */
contract AIMining is Ownable, ReentrancyGuard {
    using ECDSA for bytes32;

    // ============ Types ============

    /// @notice Work proof submitted by miners
    struct WorkProof {
        bytes32 sessionId;      // Unique session identifier
        uint64 nonce;           // PoW nonce
        bytes32 gpuId;          // Attested GPU identifier
        bytes32 computeHash;    // Hash of compute work
        uint64 timestamp;       // Proof timestamp
        ChainConfig.GPUTier tier; // GPU hardware tier
        bytes signature;        // ECDSA signature
    }

    /// @notice Miner registration info
    struct MinerInfo {
        bool registered;
        uint256 totalRewards;
        uint256 proofsSubmitted;
        uint64 lastProofTime;
        bytes32 lastGpuId;
    }

    // ============ Constants ============

    /// @notice Proof validity window (1 hour)
    uint256 public constant PROOF_VALIDITY_WINDOW = 3600;

    /// @notice Minimum time between proofs from same miner (30 seconds)
    uint256 public constant MIN_PROOF_INTERVAL = 30;

    /// @notice Maximum proofs per block per miner
    uint256 public constant MAX_PROOFS_PER_BLOCK = 10;

    // ============ State ============

    /// @notice AI Token contract
    AIToken public immutable aiToken;

    /// @notice Chain configuration contract
    ChainConfig public immutable chainConfig;

    /// @notice This chain's ID
    uint256 public immutable CHAIN_ID;

    /// @notice Spent proof hashes (double-spend prevention)
    mapping(bytes32 => bool) public spentProofs;

    /// @notice Miner information
    mapping(address => MinerInfo) public miners;

    /// @notice Proof count per miner per block (rate limiting)
    mapping(address => mapping(uint256 => uint256)) public proofsPerBlock;

    /// @notice Total proofs submitted
    uint256 public totalProofs;

    /// @notice Total rewards distributed
    uint256 public totalRewards;

    /// @notice Mining enabled flag
    bool public miningEnabled;

    /// @notice Trusted attestation verifiers
    mapping(address => bool) public trustedVerifiers;

    // ============ Events ============

    event ProofSubmitted(
        address indexed miner,
        bytes32 indexed proofHash,
        uint256 reward,
        ChainConfig.GPUTier tier
    );
    event MinerRegistered(address indexed miner, bytes32 gpuId);
    event MiningEnabled(bool enabled);
    event VerifierUpdated(address indexed verifier, bool trusted);

    // ============ Errors ============

    error MiningDisabled();
    error InvalidChainId(uint256 expected, uint256 actual);
    error ProofAlreadySpent(bytes32 proofHash);
    error ProofExpired(uint64 timestamp, uint256 currentTime);
    error ProofTooFuture(uint64 timestamp, uint256 currentTime);
    error InvalidSignature();
    error ProofIntervalTooShort(uint64 lastTime, uint64 currentTime);
    error TooManyProofsPerBlock(uint256 count, uint256 max);
    error DifficultyNotMet(bytes32 proofHash, uint256 target);
    error ZeroReward();
    error MinerNotRegistered(address miner);

    // ============ Constructor ============

    /**
     * @notice Deploy AIMining contract
     * @param _aiToken AI Token contract address
     * @param _chainConfig Chain configuration contract address
     */
    constructor(
        address _aiToken,
        address _chainConfig
    ) Ownable(msg.sender) {
        aiToken = AIToken(_aiToken);
        chainConfig = ChainConfig(_chainConfig);
        CHAIN_ID = block.chainid;

        // Validate chain ID
        if (!chainConfig.isValidChainId(CHAIN_ID)) {
            revert InvalidChainId(96369, CHAIN_ID); // Show expected
        }
    }

    // ============ Mining Functions ============

    /**
     * @notice Submit work proof and receive mining reward
     * @param proof The work proof to submit
     * @return reward Amount of AI tokens minted
     */
    function submitProof(WorkProof calldata proof) external nonReentrant returns (uint256 reward) {
        if (!miningEnabled) revert MiningDisabled();

        // Validate chain
        if (!chainConfig.isValidChainId(CHAIN_ID)) {
            revert InvalidChainId(chainConfig.CHAIN_C(), CHAIN_ID);
        }

        // Compute proof hash for deduplication
        bytes32 proofHash = _computeProofHash(proof);

        // Check spent set
        if (spentProofs[proofHash]) {
            revert ProofAlreadySpent(proofHash);
        }

        // Validate timestamp
        uint256 currentTime = block.timestamp;
        if (proof.timestamp + PROOF_VALIDITY_WINDOW < currentTime) {
            revert ProofExpired(proof.timestamp, currentTime);
        }
        if (proof.timestamp > currentTime + 60) {
            revert ProofTooFuture(proof.timestamp, currentTime);
        }

        // Validate signature
        address signer = _recoverSigner(proofHash, proof.signature);
        if (signer != msg.sender) {
            revert InvalidSignature();
        }

        // Check miner registration
        MinerInfo storage miner = miners[msg.sender];
        if (!miner.registered) {
            // Auto-register on first proof
            miner.registered = true;
            miner.lastGpuId = proof.gpuId;
            emit MinerRegistered(msg.sender, proof.gpuId);
        }

        // Rate limiting: proof interval
        if (miner.lastProofTime > 0) {
            if (proof.timestamp < miner.lastProofTime + MIN_PROOF_INTERVAL) {
                revert ProofIntervalTooShort(miner.lastProofTime, proof.timestamp);
            }
        }

        // Rate limiting: proofs per block
        uint256 blockProofs = proofsPerBlock[msg.sender][block.number];
        if (blockProofs >= MAX_PROOFS_PER_BLOCK) {
            revert TooManyProofsPerBlock(blockProofs, MAX_PROOFS_PER_BLOCK);
        }

        // Validate difficulty
        ChainConfig.Config memory config = chainConfig.getConfig(CHAIN_ID);
        if (uint256(proofHash) > config.difficultyTarget) {
            revert DifficultyNotMet(proofHash, config.difficultyTarget);
        }

        // Mark proof as spent
        spentProofs[proofHash] = true;

        // Calculate reward
        reward = calculateReward(proof, config);
        if (reward == 0) revert ZeroReward();

        // Update state
        miner.totalRewards += reward;
        miner.proofsSubmitted++;
        miner.lastProofTime = proof.timestamp;
        proofsPerBlock[msg.sender][block.number]++;
        totalProofs++;
        totalRewards += reward;

        // Record proof for difficulty adjustment
        chainConfig.recordProof(CHAIN_ID);

        // Mint reward
        aiToken.mintReward(msg.sender, reward);

        emit ProofSubmitted(msg.sender, proofHash, reward, proof.tier);

        return reward;
    }

    /**
     * @notice Calculate reward for a work proof
     * @param proof The work proof
     * @param config Chain configuration
     * @return reward Calculated reward amount
     */
    function calculateReward(
        WorkProof calldata proof,
        ChainConfig.Config memory config
    ) public view returns (uint256 reward) {
        // Get base reward from chain config (with halving applied)
        uint256 baseReward = chainConfig.getCurrentReward(CHAIN_ID);

        // Apply GPU tier multiplier
        uint256 multiplier = chainConfig.gpuMultipliers(proof.tier);
        reward = (baseReward * multiplier) / 10000;

        // Treasury deduction handled by AIToken
        return reward;
    }

    /**
     * @notice Estimate reward for a given tier (view function)
     * @param tier GPU hardware tier
     * @return reward Estimated reward amount
     */
    function estimateReward(ChainConfig.GPUTier tier) external view returns (uint256 reward) {
        uint256 baseReward = chainConfig.getCurrentReward(CHAIN_ID);
        uint256 multiplier = chainConfig.gpuMultipliers(tier);
        return (baseReward * multiplier) / 10000;
    }

    // ============ Batch Operations ============

    /**
     * @notice Submit multiple proofs in one transaction
     * @param proofs Array of work proofs
     * @return rewards Array of rewards minted
     */
    function submitProofsBatch(
        WorkProof[] calldata proofs
    ) external nonReentrant returns (uint256[] memory rewards) {
        rewards = new uint256[](proofs.length);

        for (uint256 i = 0; i < proofs.length; i++) {
            rewards[i] = _submitProofInternal(proofs[i]);
        }

        return rewards;
    }

    // ============ View Functions ============

    /**
     * @notice Check if a proof hash has been spent
     * @param proofHash The proof hash to check
     * @return spent True if proof has been used
     */
    function isProofSpent(bytes32 proofHash) external view returns (bool spent) {
        return spentProofs[proofHash];
    }

    /**
     * @notice Get miner statistics
     * @param miner Miner address
     * @return info Miner information
     */
    function getMinerInfo(address miner) external view returns (MinerInfo memory info) {
        return miners[miner];
    }

    /**
     * @notice Get current difficulty target
     * @return target Current difficulty target
     */
    function getDifficulty() external view returns (uint256 target) {
        ChainConfig.Config memory config = chainConfig.getConfig(CHAIN_ID);
        return config.difficultyTarget;
    }

    /**
     * @notice Get mining statistics
     * @return _totalProofs Total proofs submitted
     * @return _totalRewards Total rewards distributed
     * @return _currentReward Current base reward
     * @return _difficulty Current difficulty
     */
    function getMiningStats() external view returns (
        uint256 _totalProofs,
        uint256 _totalRewards,
        uint256 _currentReward,
        uint256 _difficulty
    ) {
        ChainConfig.Config memory config = chainConfig.getConfig(CHAIN_ID);
        return (
            totalProofs,
            totalRewards,
            chainConfig.getCurrentReward(CHAIN_ID),
            config.difficultyTarget
        );
    }

    // ============ Admin Functions ============

    /**
     * @notice Enable or disable mining
     * @param enabled Whether mining should be enabled
     */
    function setMiningEnabled(bool enabled) external onlyOwner {
        miningEnabled = enabled;
        emit MiningEnabled(enabled);
    }

    /**
     * @notice Add or remove trusted verifier
     * @param verifier Verifier address
     * @param trusted Whether verifier is trusted
     */
    function setTrustedVerifier(address verifier, bool trusted) external onlyOwner {
        trustedVerifiers[verifier] = trusted;
        emit VerifierUpdated(verifier, trusted);
    }

    // ============ Internal Functions ============

    /**
     * @notice Compute proof hash for deduplication
     * @param proof The work proof
     * @return hash Keccak256 hash of proof data
     */
    function _computeProofHash(WorkProof calldata proof) internal view returns (bytes32 hash) {
        return keccak256(abi.encode(
            proof.sessionId,
            proof.nonce,
            proof.gpuId,
            proof.computeHash,
            proof.timestamp,
            proof.tier,
            CHAIN_ID
        ));
    }

    /**
     * @notice Recover signer from proof hash and signature
     * @param proofHash The proof hash
     * @param signature The ECDSA signature
     * @return signer Recovered signer address
     */
    function _recoverSigner(
        bytes32 proofHash,
        bytes calldata signature
    ) internal pure returns (address signer) {
        bytes32 ethSignedHash = MessageHashUtils.toEthSignedMessageHash(proofHash);
        return ECDSA.recover(ethSignedHash, signature);
    }

    /**
     * @notice Internal proof submission (for batch)
     * @param proof The work proof
     * @return reward Minted reward
     */
    function _submitProofInternal(WorkProof calldata proof) internal returns (uint256 reward) {
        if (!miningEnabled) revert MiningDisabled();

        bytes32 proofHash = _computeProofHash(proof);

        if (spentProofs[proofHash]) {
            return 0; // Skip duplicates in batch
        }

        uint256 currentTime = block.timestamp;
        if (proof.timestamp + PROOF_VALIDITY_WINDOW < currentTime) {
            return 0; // Skip expired
        }
        if (proof.timestamp > currentTime + 60) {
            return 0; // Skip future
        }

        address signer = _recoverSigner(proofHash, proof.signature);
        if (signer != msg.sender) {
            return 0; // Skip invalid sig
        }

        MinerInfo storage miner = miners[msg.sender];
        if (!miner.registered) {
            miner.registered = true;
            miner.lastGpuId = proof.gpuId;
            emit MinerRegistered(msg.sender, proof.gpuId);
        }

        ChainConfig.Config memory config = chainConfig.getConfig(CHAIN_ID);
        if (uint256(proofHash) > config.difficultyTarget) {
            return 0; // Difficulty not met
        }

        spentProofs[proofHash] = true;

        reward = calculateReward(proof, config);
        if (reward == 0) return 0;

        miner.totalRewards += reward;
        miner.proofsSubmitted++;
        miner.lastProofTime = proof.timestamp;
        proofsPerBlock[msg.sender][block.number]++;
        totalProofs++;
        totalRewards += reward;

        chainConfig.recordProof(CHAIN_ID);
        aiToken.mintReward(msg.sender, reward);

        emit ProofSubmitted(msg.sender, proofHash, reward, proof.tier);

        return reward;
    }
}
