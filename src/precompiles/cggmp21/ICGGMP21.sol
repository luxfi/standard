// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title ICGGMP21
 * @dev Interface for CGGMP21 threshold signature verification precompile
 *
 * CGGMP21 is a modern threshold ECDSA protocol with identifiable aborts.
 * It enables t-of-n threshold signing for ECDSA signatures used in
 * Ethereum, Bitcoin, and other ECDSA-based blockchains.
 *
 * Features:
 * - Modern threshold ECDSA (CGGMP21 protocol)
 * - Identifiable aborts (malicious parties can be detected)
 * - Compatible with standard ECDSA verification
 * - Supports key refresh without changing public key
 *
 * Address: 0x020000000000000000000000000000000000000D
 */
interface ICGGMP21 {
    /**
     * @notice Verify a CGGMP21 threshold signature
     * @param threshold The minimum number of signers required (t)
     * @param totalSigners The total number of parties (n)
     * @param publicKey The aggregated ECDSA public key (65 bytes uncompressed)
     * @param messageHash The hash of the message (32 bytes)
     * @param signature The ECDSA signature (65 bytes: r || s || v)
     * @return valid True if the signature is valid
     */
    function verify(
        uint32 threshold,
        uint32 totalSigners,
        bytes calldata publicKey,
        bytes32 messageHash,
        bytes calldata signature
    ) external view returns (bool valid);
}

/**
 * @title CGGMP21Lib
 * @dev Library for CGGMP21 threshold signature operations
 */
library CGGMP21Lib {
    /// @dev Address of the CGGMP21 precompile
    address constant CGGMP21_PRECOMPILE = 0x020000000000000000000000000000000000000D;

    /// @dev Gas cost constants
    uint256 constant BASE_GAS = 75_000;
    uint256 constant PER_SIGNER_GAS = 10_000;

    error InvalidThreshold();
    error InvalidPublicKey();
    error InvalidSignature();
    error SignatureVerificationFailed();

    /**
     * @notice Verify CGGMP21 signature and revert on failure
     * @param threshold Minimum signers required
     * @param totalSigners Total number of parties
     * @param publicKey Aggregated public key (65 bytes)
     * @param messageHash Message hash
     * @param signature ECDSA signature (65 bytes)
     */
    function verifyOrRevert(
        uint32 threshold,
        uint32 totalSigners,
        bytes calldata publicKey,
        bytes32 messageHash,
        bytes calldata signature
    ) internal view {
        if (threshold == 0 || threshold > totalSigners) {
            revert InvalidThreshold();
        }
        if (publicKey.length != 65) {
            revert InvalidPublicKey();
        }
        if (signature.length != 65) {
            revert InvalidSignature();
        }

        bytes memory input = abi.encodePacked(
            threshold,
            totalSigners,
            publicKey,
            messageHash,
            signature
        );

        (bool success, bytes memory result) = CGGMP21_PRECOMPILE.staticcall(input);
        require(success, "CGGMP21 precompile call failed");

        bool valid = abi.decode(result, (bool));
        if (!valid) {
            revert SignatureVerificationFailed();
        }
    }

    /**
     * @notice Estimate gas for CGGMP21 verification
     * @param totalSigners Total number of parties
     * @return gas Estimated gas cost
     */
    function estimateGas(uint32 totalSigners) internal pure returns (uint256 gas) {
        return BASE_GAS + (uint256(totalSigners) * PER_SIGNER_GAS);
    }

    /**
     * @notice Check if threshold parameters are valid
     * @param threshold Minimum signers required
     * @param totalSigners Total number of parties
     * @return valid True if parameters are valid
     */
    function isValidThreshold(uint32 threshold, uint32 totalSigners) internal pure returns (bool valid) {
        return threshold > 0 && threshold <= totalSigners;
    }

    /**
     * @notice Validate public key format
     * @param publicKey Public key bytes
     * @return valid True if valid uncompressed ECDSA key
     */
    function isValidPublicKey(bytes calldata publicKey) internal pure returns (bool valid) {
        return publicKey.length == 65 && publicKey[0] == 0x04;
    }
}

/**
 * @title CGGMP21Verifier
 * @dev Abstract contract for CGGMP21 signature verification
 */
abstract contract CGGMP21Verifier {
    using CGGMP21Lib for *;

    event CGGMP21SignatureVerified(
        uint32 threshold,
        uint32 totalSigners,
        bytes publicKey,
        bytes32 indexed messageHash
    );

    /**
     * @notice Verify CGGMP21 threshold signature
     * @param threshold Minimum signers required
     * @param totalSigners Total number of parties
     * @param publicKey Aggregated public key
     * @param messageHash Message hash
     * @param signature ECDSA signature
     */
    function verifyCGGMP21Signature(
        uint32 threshold,
        uint32 totalSigners,
        bytes calldata publicKey,
        bytes32 messageHash,
        bytes calldata signature
    ) internal view {
        CGGMP21Lib.verifyOrRevert(
            threshold,
            totalSigners,
            publicKey,
            messageHash,
            signature
        );
    }

    /**
     * @notice Verify CGGMP21 signature with event emission
     */
    function verifyCGGMP21SignatureWithEvent(
        uint32 threshold,
        uint32 totalSigners,
        bytes calldata publicKey,
        bytes32 messageHash,
        bytes calldata signature
    ) internal {
        verifyCGGMP21Signature(threshold, totalSigners, publicKey, messageHash, signature);
        emit CGGMP21SignatureVerified(threshold, totalSigners, publicKey, messageHash);
    }

    /**
     * @notice Verify CGGMP21 signature with event emission (memory version)
     * @dev Use this when passing storage data that has been copied to memory
     */
    function verifyCGGMP21SignatureWithEventMem(
        uint32 threshold,
        uint32 totalSigners,
        bytes memory publicKey,
        bytes32 messageHash,
        bytes calldata signature
    ) internal {
        // Encode input for precompile
        bytes memory input = abi.encodePacked(
            threshold,
            totalSigners,
            publicKey,
            messageHash,
            signature
        );

        // Call precompile
        (bool success, bytes memory result) = CGGMP21Lib.CGGMP21_PRECOMPILE.staticcall(input);

        if (!success || result.length != 32) {
            revert CGGMP21Lib.SignatureVerificationFailed();
        }

        bool verified = abi.decode(result, (bool));
        if (!verified) {
            revert CGGMP21Lib.InvalidSignature();
        }

        emit CGGMP21SignatureVerified(threshold, totalSigners, publicKey, messageHash);
    }
}

/**
 * @title ThresholdWallet
 * @dev Example threshold wallet using CGGMP21
 */
contract ThresholdWallet is CGGMP21Verifier {
    struct WalletConfig {
        uint32 threshold;
        uint32 totalSigners;
        bytes publicKey;
        uint256 nonce;
    }

    WalletConfig public config;
    mapping(bytes32 => bool) public executedTxs;

    event WalletInitialized(uint32 threshold, uint32 totalSigners);
    event TransactionExecuted(bytes32 indexed txHash, address indexed to, uint256 value);

    /**
     * @notice Initialize threshold wallet
     * @param threshold Minimum signers required
     * @param totalSigners Total number of signers
     * @param publicKey Aggregated ECDSA public key
     */
    function initialize(
        uint32 threshold,
        uint32 totalSigners,
        bytes calldata publicKey
    ) external {
        require(config.threshold == 0, "Already initialized");
        require(CGGMP21Lib.isValidThreshold(threshold, totalSigners), "Invalid threshold");
        require(CGGMP21Lib.isValidPublicKey(publicKey), "Invalid public key");

        config = WalletConfig({
            threshold: threshold,
            totalSigners: totalSigners,
            publicKey: publicKey,
            nonce: 0
        });

        emit WalletInitialized(threshold, totalSigners);
    }

    /**
     * @notice Execute transaction with threshold signature
     * @param to Destination address
     * @param value Amount to send
     * @param data Transaction data
     * @param signature CGGMP21 threshold signature
     */
    function executeTransaction(
        address to,
        uint256 value,
        bytes calldata data,
        bytes calldata signature
    ) external {
        // Create transaction hash
        bytes32 txHash = keccak256(abi.encodePacked(
            address(this),
            to,
            value,
            data,
            config.nonce
        ));

        // Ensure not already executed
        require(!executedTxs[txHash], "Transaction already executed");

        // Verify threshold signature (copy storage to memory for internal call)
        bytes memory pubKey = config.publicKey;
        verifyCGGMP21SignatureWithEventMem(
            config.threshold,
            config.totalSigners,
            pubKey,
            txHash,
            signature
        );

        // Mark as executed
        executedTxs[txHash] = true;
        config.nonce++;

        // Execute transaction
        (bool success, ) = to.call{value: value}(data);
        require(success, "Transaction failed");

        emit TransactionExecuted(txHash, to, value);
    }

    receive() external payable {}
}
