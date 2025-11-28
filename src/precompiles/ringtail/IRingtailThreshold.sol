// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title IRingtailThreshold
 * @notice Interface for the Ringtail Threshold Signature precompile
 * @dev Precompile address: 0x020000000000000000000000000000000000000B
 *
 * This precompile verifies LWE-based threshold signatures from the Ringtail protocol
 * (https://eprint.iacr.org/2024/1113) used in Quasar quantum consensus.
 *
 * Key Features:
 * - Post-quantum security (LWE-based lattice cryptography)
 * - Two-round threshold signature protocol
 * - Configurable t-of-n threshold
 * - Compatible with Quasar consensus validators
 *
 * Security Level:
 * - Classical: >128-bit
 * - Quantum: Resistant to Shor's algorithm
 * - Based on Learning With Errors (LWE) problem
 */
interface IRingtailThreshold {
    /**
     * @notice Verify a Ringtail threshold signature
     * @param threshold The minimum number of parties required (t)
     * @param totalParties The total number of parties in the protocol (n)
     * @param messageHash The 32-byte hash of the message that was signed
     * @param signature The threshold signature bytes
     * @return valid True if the signature is valid and threshold is met
     *
     * @dev Input format:
     *      [0:4]       = threshold t (uint32)
     *      [4:8]       = total parties n (uint32)
     *      [8:40]      = message hash (32 bytes)
     *      [40:...]    = threshold signature (~4KB)
     *
     * @dev Gas cost: 150,000 + (n * 10,000)
     *      - 2 parties: 170,000 gas
     *      - 3 parties: 180,000 gas
     *      - 5 parties: 200,000 gas
     *      - 10 parties: 250,000 gas
     */
    function verifyThreshold(
        uint32 threshold,
        uint32 totalParties,
        bytes32 messageHash,
        bytes calldata signature
    ) external view returns (bool valid);

    /**
     * @notice Estimate gas for threshold verification
     * @param parties The number of parties in the threshold signature
     * @return gasEstimate The estimated gas cost
     */
    function estimateGas(uint32 parties) external pure returns (uint256 gasEstimate);
}

/**
 * @title RingtailThresholdLib
 * @notice Library for interacting with the Ringtail Threshold precompile
 */
library RingtailThresholdLib {
    /// @notice Address of the Ringtail threshold precompile
    address constant RINGTAIL_THRESHOLD = 0x020000000000000000000000000000000000000B;

    /// @notice Gas costs
    uint256 constant BASE_GAS = 150_000;
    uint256 constant PER_PARTY_GAS = 10_000;

    /// @notice Errors
    error InvalidThreshold();
    error SignatureVerificationFailed();
    error InsufficientGas();

    /**
     * @notice Verify a threshold signature, reverting on failure
     * @param threshold Minimum number of parties required
     * @param totalParties Total number of parties
     * @param messageHash Hash of the signed message
     * @param signature Threshold signature bytes
     */
    function verifyOrRevert(
        uint32 threshold,
        uint32 totalParties,
        bytes32 messageHash,
        bytes calldata signature
    ) internal view {
        if (threshold == 0 || threshold > totalParties) {
            revert InvalidThreshold();
        }

        bool valid = IRingtailThreshold(RINGTAIL_THRESHOLD).verifyThreshold(
            threshold,
            totalParties,
            messageHash,
            signature
        );

        if (!valid) {
            revert SignatureVerificationFailed();
        }
    }

    /**
     * @notice Estimate gas required for verification
     * @param parties Number of parties in threshold
     * @return Gas estimate
     */
    function estimateGas(uint32 parties) internal pure returns (uint256) {
        return BASE_GAS + (uint256(parties) * PER_PARTY_GAS);
    }

    /**
     * @notice Check if threshold parameters are valid
     * @param threshold Minimum parties required
     * @param totalParties Total parties
     * @return True if valid
     */
    function isValidThreshold(uint32 threshold, uint32 totalParties) internal pure returns (bool) {
        return threshold > 0 && threshold <= totalParties;
    }
}

/**
 * @title RingtailThresholdVerifier
 * @notice Abstract contract for using Ringtail threshold signatures
 */
abstract contract RingtailThresholdVerifier {
    using RingtailThresholdLib for *;

    /// @notice Emitted when a threshold signature is verified
    event ThresholdSignatureVerified(
        uint32 indexed threshold,
        uint32 indexed totalParties,
        bytes32 messageHash,
        bool valid
    );

    /**
     * @notice Verify a threshold signature
     * @param threshold Minimum number of parties required
     * @param totalParties Total number of parties
     * @param messageHash Hash of the signed message
     * @param signature Threshold signature bytes
     * @return True if valid
     */
    function verifyThresholdSignature(
        uint32 threshold,
        uint32 totalParties,
        bytes32 messageHash,
        bytes calldata signature
    ) internal view returns (bool) {
        return IRingtailThreshold(RingtailThresholdLib.RINGTAIL_THRESHOLD).verifyThreshold(
            threshold,
            totalParties,
            messageHash,
            signature
        );
    }

    /**
     * @notice Verify a threshold signature with event emission
     * @param threshold Minimum number of parties required
     * @param totalParties Total number of parties
     * @param messageHash Hash of the signed message
     * @param signature Threshold signature bytes
     */
    function verifyThresholdSignatureWithEvent(
        uint32 threshold,
        uint32 totalParties,
        bytes32 messageHash,
        bytes calldata signature
    ) internal {
        bool valid = verifyThresholdSignature(threshold, totalParties, messageHash, signature);
        emit ThresholdSignatureVerified(threshold, totalParties, messageHash, valid);
    }
}

/**
 * @title QuasarValidator
 * @notice Example contract using Ringtail threshold signatures for Quasar consensus
 */
contract QuasarValidator is RingtailThresholdVerifier {
    struct Validator {
        address addr;
        bytes publicKey;
        bool active;
    }

    uint32 public constant CONSENSUS_THRESHOLD = 2; // 2/3 threshold
    uint32 public constant TOTAL_VALIDATORS = 3;

    mapping(address => Validator) public validators;

    /**
     * @notice Verify consensus signature from validators
     * @param messageHash Hash of the consensus message
     * @param signature Aggregated threshold signature
     */
    function verifyConsensus(
        bytes32 messageHash,
        bytes calldata signature
    ) external view returns (bool) {
        return verifyThresholdSignature(
            CONSENSUS_THRESHOLD,
            TOTAL_VALIDATORS,
            messageHash,
            signature
        );
    }

    /**
     * @notice Submit a consensus decision with threshold signature
     * @param messageHash Hash of the consensus message
     * @param signature Aggregated threshold signature from validators
     */
    function submitConsensus(
        bytes32 messageHash,
        bytes calldata signature
    ) external {
        RingtailThresholdLib.verifyOrRevert(
            CONSENSUS_THRESHOLD,
            TOTAL_VALIDATORS,
            messageHash,
            signature
        );

        // Process consensus decision
        emit ThresholdSignatureVerified(
            CONSENSUS_THRESHOLD,
            TOTAL_VALIDATORS,
            messageHash,
            true
        );
    }

    /**
     * @notice Estimate gas for consensus verification
     * @return Gas estimate
     */
    function estimateConsensusGas() external pure returns (uint256) {
        return RingtailThresholdLib.estimateGas(TOTAL_VALIDATORS);
    }
}
