// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.31;

import {Enum} from "@safe-global/safe-smart-account/interfaces/Enum.sol";
import {ISafe} from "@safe-global/safe-smart-account/interfaces/ISafe.sol";
import {SafeModule} from "./SafeModule.sol";

/**
 * @title SafeThresholdLamportModule
 * @notice T-Chain MPC threshold control with vanilla Lamport verification
 * @author Lux Network Team
 * @dev Threshold lives OFF-CHAIN (T-Chain MPC network jointly controls ONE Lamport key).
 *      On-chain verifies a normal Lamport signature - no changes to verification logic.
 *
 * SECURITY MODEL:
 * - Threshold property (t-of-n) enforced by T-Chain MPC network
 * - On-chain sees ONE standard Lamport signature
 * - Works on ANY EVM chain (no precompiles needed)
 * - Domain separation prevents replay attacks
 *
 * ATTACK MITIGATIONS:
 * - Canonical digest: safeTxHash computed ON-CHAIN (never accept from coordinator)
 * - Domain separation: address(this) + block.chainid in message
 * - One-time keys: pkh = nextPKH rotation after each signature
 * - Init guard: only Safe can initialize
 */
contract SafeThresholdLamportModule is SafeModule {
    // ═══════════════════════════════════════════════════════════════════════
    // State
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice Current Lamport public key hash
    bytes32 public pkh;

    /// @notice Whether the module has been initialized
    bool public initialized;

    /// @notice Nonce for replay protection (independent of Safe nonce)
    uint256 public lamportNonce;

    // ═══════════════════════════════════════════════════════════════════════
    // Events
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice Emitted when Lamport key is rotated
    event LamportKeyRotated(bytes32 indexed oldPkh, bytes32 indexed newPkh);

    /// @notice Emitted when a transaction is executed with Lamport signature
    event LamportExecuted(bytes32 indexed safeTxHash, bytes32 indexed nextPkh, uint256 nonce);

    /// @notice Emitted when module is initialized
    event LamportInitialized(bytes32 indexed initialPkh);

    // ═══════════════════════════════════════════════════════════════════════
    // Errors
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice Error when module is not initialized
    error NotInitialized();

    /// @notice Error when module is already initialized
    error AlreadyInitialized();

    /// @notice Error when public key doesn't match stored hash
    error InvalidPublicKey();

    /// @notice Error when Lamport signature is invalid
    error InvalidLamportSignature();

    // ═══════════════════════════════════════════════════════════════════════
    // Constructor
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice Constructor
    /// @param _safe The Safe address this module is attached to
    constructor(address payable _safe) SafeModule(_safe) {}

    // ═══════════════════════════════════════════════════════════════════════
    // Initialization
    // ═══════════════════════════════════════════════════════════════════════

    /**
     * @notice Initialize with first Lamport public key hash
     * @dev GUARDED: Only Safe can call (prevents random init attacks)
     * @param initialPkh Hash of initial Lamport public key from T-Chain DKG
     */
    function init(bytes32 initialPkh) external onlySafe {
        if (initialized) revert AlreadyInitialized();
        pkh = initialPkh;
        initialized = true;
        emit LamportInitialized(initialPkh);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // Core Lamport Verification
    // ═══════════════════════════════════════════════════════════════════════

    /**
     * @notice Verify Lamport signature (256-bit message)
     * @dev Uses keccak256(sig[i]) directly - sig[i] is already bytes
     * @param bits The 256-bit message to verify
     * @param sig Array of 256 preimages (the revealed private key halves)
     * @param pub 256x2 array of public key hashes
     * @return valid True if signature is valid
     */
    function verify_u256(
        uint256 bits,
        bytes[256] calldata sig,
        bytes32[2][256] calldata pub
    ) public pure returns (bool valid) {
        unchecked {
            for (uint256 i; i < 256; i++) {
                // Select pub[i][0] if bit is 0, pub[i][1] if bit is 1
                // Verify keccak256(sig[i]) == pub[i][bit]
                if (
                    pub[i][((bits & (1 << (255 - i))) > 0) ? 1 : 0] !=
                    keccak256(sig[i])
                ) return false;
            }
            return true;
        }
    }

    // ═══════════════════════════════════════════════════════════════════════
    // Threshold Execution
    // ═══════════════════════════════════════════════════════════════════════

    /**
     * @notice Execute Safe transaction with threshold Lamport signature
     * @dev SECURITY: safeTxHash computed ON-CHAIN from full tx fields
     *      NEVER accepts prepacked hash from coordinator (kills equivocation)
     *
     * @param to Destination address
     * @param value ETH value in wei
     * @param data Call data
     * @param operation 0 = Call, 1 = DelegateCall
     * @param sig Lamport signature (bytes[256]) from T-Chain MPC
     * @param currentPub Current public key (bytes32[2][256])
     * @param nextPKH Hash of next public key (for rotation)
     * @return success True if execution succeeded
     */
    function execWithThresholdLamport(
        address to,
        uint256 value,
        bytes calldata data,
        Enum.Operation operation,
        bytes[256] calldata sig,
        bytes32[2][256] calldata currentPub,
        bytes32 nextPKH
    ) external returns (bool success) {
        if (!initialized) revert NotInitialized();

        // ═══════════════════════════════════════════════════════════════
        // STEP 1: Verify current public key matches stored hash
        // ═══════════════════════════════════════════════════════════════
        if (keccak256(abi.encodePacked(currentPub)) != pkh) {
            revert InvalidPublicKey();
        }

        // ═══════════════════════════════════════════════════════════════
        // STEP 2: Compute safeTxHash ON-CHAIN (SECURITY CRITICAL)
        // FIX: Don't accept prepacked hash from coordinator!
        // ═══════════════════════════════════════════════════════════════
        bytes32 safeTxHash = ISafe(safe).getTransactionHash(
            to,
            value,
            data,
            operation,
            0,              // safeTxGas (0 for module execution)
            0,              // baseGas
            0,              // gasPrice
            address(0),     // gasToken
            payable(0),     // refundReceiver
            lamportNonce
        );

        // ═══════════════════════════════════════════════════════════════
        // STEP 3: Domain-separated message (prevents replay)
        // ═══════════════════════════════════════════════════════════════
        uint256 m = uint256(keccak256(abi.encodePacked(
            safeTxHash,
            nextPKH,
            address(this),   // Prevent cross-contract replay
            block.chainid    // Prevent cross-chain replay
        )));

        // ═══════════════════════════════════════════════════════════════
        // STEP 4: Verify Lamport signature
        // ═══════════════════════════════════════════════════════════════
        if (!verify_u256(m, sig, currentPub)) {
            revert InvalidLamportSignature();
        }

        // ═══════════════════════════════════════════════════════════════
        // STEP 5: Rotate to next key (one-time property)
        // ═══════════════════════════════════════════════════════════════
        bytes32 oldPkh = pkh;
        pkh = nextPKH;
        lamportNonce++;

        emit LamportKeyRotated(oldPkh, nextPKH);
        emit LamportExecuted(safeTxHash, nextPKH, lamportNonce - 1);

        // ═══════════════════════════════════════════════════════════════
        // STEP 6: Execute via Safe
        // ═══════════════════════════════════════════════════════════════
        success = _executeFromModule(to, value, data, operation);
    }

    /**
     * @notice Execute with simplified parameters (gas params = 0)
     * @dev Convenience function for most common use case
     */
    function exec(
        address to,
        uint256 value,
        bytes calldata data,
        bytes[256] calldata sig,
        bytes32[2][256] calldata currentPub,
        bytes32 nextPKH
    ) external returns (bool) {
        return this.execWithThresholdLamport(
            to,
            value,
            data,
            Enum.Operation.Call,
            sig,
            currentPub,
            nextPKH
        );
    }

    // ═══════════════════════════════════════════════════════════════════════
    // View Functions
    // ═══════════════════════════════════════════════════════════════════════

    /**
     * @notice Get current public key hash
     * @return Current pkh
     */
    function getPKH() external view returns (bytes32) {
        return pkh;
    }

    /**
     * @notice Check if module is initialized
     * @return True if initialized
     */
    function isInitialized() external view returns (bool) {
        return initialized;
    }

    /**
     * @notice Compute the message hash that T-Chain MPC should sign
     * @dev Use this off-chain to prepare the signing request
     * @param to Destination address
     * @param value ETH value
     * @param data Call data
     * @param operation Operation type
     * @param nextPKH Next public key hash
     * @return m The message hash to sign (256 bits)
     */
    function computeMessageHash(
        address to,
        uint256 value,
        bytes calldata data,
        Enum.Operation operation,
        bytes32 nextPKH
    ) external view returns (uint256 m) {
        bytes32 safeTxHash = ISafe(safe).getTransactionHash(
            to,
            value,
            data,
            operation,
            0, 0, 0,
            address(0),
            payable(0),
            lamportNonce
        );

        m = uint256(keccak256(abi.encodePacked(
            safeTxHash,
            nextPKH,
            address(this),
            block.chainid
        )));
    }
}
