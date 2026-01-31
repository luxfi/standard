// SPDX-License-Identifier: BSD-3-Clause
// Copyright (c) 2025 Lux Industries Inc.
pragma solidity ^0.8.31;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";

/**
 * @title TeleportVault
 * @author Lux Industries
 * @notice Abstract base contract for MPC-controlled collateral custody on external chains
 * @dev Part of the Teleport system for cross-chain bridged assets
 *
 * Architecture:
 * - Deposits assets on source chain (Base/Ethereum), emits event for Lux bridge
 * - MPC controls withdrawals via signature verification
 * - Concrete implementations add asset-specific logic (ETH, ERC20)
 * - LiquidVault extends this with yield strategy routing
 *
 * Inheritance:
 *   TeleportVault (abstract)
 *     ├── LiquidVault (ETH + strategies)
 *     ├── LiquidUSDVault (USDC/USDT/DAI + strategies)
 *     └── SimpleTeleportVault (basic custody, no strategies)
 */
abstract contract TeleportVault is Ownable, AccessControl, ReentrancyGuard {

    // ═══════════════════════════════════════════════════════════════════════
    // ROLES
    // ═══════════════════════════════════════════════════════════════════════

    bytes32 public constant MPC_ROLE = keccak256("MPC_ROLE");

    // ═══════════════════════════════════════════════════════════════════════
    // TYPES
    // ═══════════════════════════════════════════════════════════════════════

    struct DepositProof {
        uint256 nonce;
        address luxRecipient;
        uint256 amount;
        uint256 timestamp;
        bool bridged;              // Has been bridged to Lux
    }

    // ═══════════════════════════════════════════════════════════════════════
    // CONSTANTS
    // ═══════════════════════════════════════════════════════════════════════

    uint256 public constant BASIS_POINTS = 10_000;

    /// @notice Lux C-Chain ID for cross-chain messaging
    uint256 public constant LUX_CHAIN_ID = 96369;

    // ═══════════════════════════════════════════════════════════════════════
    // STATE
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice Total assets deposited
    uint256 public totalDeposited;

    /// @notice Deposit nonce for unique identification
    uint256 public depositNonce;

    /// @notice Withdraw nonce for replay protection
    uint256 public withdrawNonce;

    /// @notice Deposit proofs by nonce
    mapping(uint256 => DepositProof) public deposits;

    /// @notice Processed withdraw nonces (replay protection)
    mapping(uint256 => bool) public processedWithdraws;

    /// @notice MPC Oracle addresses
    mapping(address => bool) public mpcOracles;

    // ═══════════════════════════════════════════════════════════════════════
    // EVENTS
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice Emitted on asset deposit - bridge monitors for this
    event Deposit(
        uint256 indexed nonce,
        address indexed luxRecipient,
        uint256 amount,
        uint256 srcChainId
    );

    /// @notice Emitted on asset release for Lux withdrawals
    event Release(
        uint256 indexed withdrawNonce,
        address indexed recipient,
        uint256 amount
    );

    /// @notice Emitted when MPC oracle updated
    event MPCOracleSet(address indexed oracle, bool active);

    /// @notice Emitted when deposit marked as bridged
    event DepositBridged(uint256 indexed nonce);

    // ═══════════════════════════════════════════════════════════════════════
    // ERRORS
    // ═══════════════════════════════════════════════════════════════════════

    error ZeroAmount();
    error ZeroAddress();
    error InsufficientBalance();
    error InvalidSignature();
    error NonceAlreadyProcessed();
    error TransferFailed();
    error NotMPCOracle();
    error DepositNotFound();
    error AlreadyBridged();

    // ═══════════════════════════════════════════════════════════════════════
    // CONSTRUCTOR
    // ═══════════════════════════════════════════════════════════════════════

    constructor(address _mpcOracle) Ownable(msg.sender) {
        if (_mpcOracle == address(0)) revert ZeroAddress();

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(MPC_ROLE, _mpcOracle);
        mpcOracles[_mpcOracle] = true;

        emit MPCOracleSet(_mpcOracle, true);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // MPC SIGNATURE VERIFICATION
    // ═══════════════════════════════════════════════════════════════════════

    /**
     * @notice Verify MPC signature for a message
     * @param messageHash Hash of the message to verify
     * @param signature MPC signature
     * @return signer Address that signed the message
     */
    function _verifyMPCSignature(
        bytes32 messageHash,
        bytes calldata signature
    ) internal view returns (address signer) {
        bytes32 ethSignedHash = MessageHashUtils.toEthSignedMessageHash(messageHash);
        signer = ECDSA.recover(ethSignedHash, signature);

        if (!mpcOracles[signer]) revert InvalidSignature();
    }

    /**
     * @notice Build release message hash
     * @param recipient Recipient address
     * @param amount Amount to release
     * @param _withdrawNonce Withdraw nonce
     * @return messageHash Message hash for signature
     * @dev Uses abi.encode instead of abi.encodePacked to prevent hash collision attacks
     */
    function _buildReleaseHash(
        address recipient,
        uint256 amount,
        uint256 _withdrawNonce
    ) internal view returns (bytes32) {
        return keccak256(abi.encode(
            "RELEASE",
            recipient,
            amount,
            _withdrawNonce,
            block.chainid
        ));
    }

    // ═══════════════════════════════════════════════════════════════════════
    // DEPOSIT TRACKING
    // ═══════════════════════════════════════════════════════════════════════

    /**
     * @notice Record a deposit
     * @param luxRecipient Recipient on Lux
     * @param amount Amount deposited
     * @return nonce Unique deposit identifier
     */
    function _recordDeposit(
        address luxRecipient,
        uint256 amount
    ) internal returns (uint256 nonce) {
        if (amount == 0) revert ZeroAmount();
        if (luxRecipient == address(0)) revert ZeroAddress();

        nonce = ++depositNonce;

        deposits[nonce] = DepositProof({
            nonce: nonce,
            luxRecipient: luxRecipient,
            amount: amount,
            timestamp: block.timestamp,
            bridged: false
        });

        totalDeposited += amount;

        emit Deposit(nonce, luxRecipient, amount, block.chainid);
    }

    /**
     * @notice Record a release and update accounting
     * @param recipient Recipient address
     * @param amount Amount released
     * @param _withdrawNonce Withdraw nonce
     */
    function _recordRelease(
        address recipient,
        uint256 amount,
        uint256 _withdrawNonce
    ) internal {
        if (processedWithdraws[_withdrawNonce]) revert NonceAlreadyProcessed();

        processedWithdraws[_withdrawNonce] = true;
        withdrawNonce = _withdrawNonce;
        totalDeposited -= amount;

        emit Release(_withdrawNonce, recipient, amount);
    }

    /**
     * @notice Mark deposit as bridged (MPC only)
     * @param nonce Deposit nonce
     */
    function markBridged(uint256 nonce) external onlyRole(MPC_ROLE) {
        DepositProof storage proof = deposits[nonce];
        if (proof.nonce == 0) revert DepositNotFound();
        if (proof.bridged) revert AlreadyBridged();

        proof.bridged = true;
        emit DepositBridged(nonce);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // ADMIN FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════

    /**
     * @notice Set MPC oracle status
     * @param oracle Oracle address
     * @param active Active status
     */
    function setMPCOracle(address oracle, bool active) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (oracle == address(0)) revert ZeroAddress();

        mpcOracles[oracle] = active;

        if (active) {
            _grantRole(MPC_ROLE, oracle);
        } else {
            _revokeRole(MPC_ROLE, oracle);
        }

        emit MPCOracleSet(oracle, active);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // VIEW FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════

    /**
     * @notice Get deposit info by nonce
     */
    function getDeposit(uint256 nonce) external view returns (DepositProof memory) {
        return deposits[nonce];
    }

    /**
     * @notice Check if a withdraw nonce has been processed
     */
    function isWithdrawProcessed(uint256 _withdrawNonce) external view returns (bool) {
        return processedWithdraws[_withdrawNonce];
    }

    /**
     * @notice Check if an address is an MPC oracle
     */
    function isMPCOracle(address addr) external view returns (bool) {
        return mpcOracles[addr];
    }

    // ═══════════════════════════════════════════════════════════════════════
    // ABSTRACT FUNCTIONS (implement in derived contracts)
    // ═══════════════════════════════════════════════════════════════════════

    /**
     * @notice Get the underlying asset address (address(0) for ETH)
     */
    function asset() external view virtual returns (address);

    /**
     * @notice Get current vault balance
     */
    function vaultBalance() external view virtual returns (uint256);
}
