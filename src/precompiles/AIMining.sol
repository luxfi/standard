// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/**
 * @title IAIMining
 * @notice Interface for the AI Mining precompile at address 0x0300
 * @dev Enables EVM contracts to interact with the Hanzo AI Mining Protocol
 *
 * This precompile provides:
 * - Mining balance queries for ML-DSA addresses
 * - ML-DSA (FIPS 204) signature verification
 * - Teleport transfer claiming from Hanzo L1
 * - Pending teleport queries
 *
 * References:
 * - LP-2000: AI Mining Standard
 * - HIP-006: Hanzo AI Mining Protocol
 * - ZIP-005: Zoo AI Mining Integration
 * - FIPS 204: Module-Lattice Digital Signature Algorithm (ML-DSA)
 */
interface IAIMining {
    // ============ Events ============

    /// @notice Emitted when mining rewards are claimed via Teleport
    event TeleportClaimed(
        bytes32 indexed teleportId,
        address indexed recipient,
        uint256 amount
    );

    /// @notice Emitted when ML-DSA signature verification is performed
    event MLDSAVerified(
        bytes32 indexed publicKeyHash,
        bytes32 indexed messageHash,
        bool success
    );

    // ============ View Functions ============

    /**
     * @notice Get the mining balance for an address
     * @param miner The address to query (derived from ML-DSA public key)
     * @return The mining balance in AI token atomic units
     */
    function miningBalance(address miner) external view returns (uint256);

    /**
     * @notice Verify an ML-DSA signature (FIPS 204)
     * @param publicKey The ML-DSA public key (1312-4627 bytes depending on security level)
     * @param message The message that was signed
     * @param signature The ML-DSA signature (2420-4627 bytes depending on security level)
     * @return True if signature is valid, false otherwise
     *
     * @dev Supported security levels:
     *   - Level 2 (ML-DSA-44): 1312 byte pk, 2420 byte sig
     *   - Level 3 (ML-DSA-65): 1952 byte pk, 3309 byte sig
     *   - Level 5 (ML-DSA-87): 2592 byte pk, 4627 byte sig
     */
    function verifyMLDSA(
        bytes calldata publicKey,
        bytes calldata message,
        bytes calldata signature
    ) external view returns (bool);

    /**
     * @notice Get the security level of an ML-DSA public key
     * @param publicKey The ML-DSA public key
     * @return level The security level (2, 3, or 5)
     */
    function getSecurityLevel(bytes calldata publicKey) external pure returns (uint8 level);

    /**
     * @notice Derive an address from an ML-DSA public key
     * @param publicKey The ML-DSA public key
     * @return The derived 20-byte address (BLAKE3 hash truncated)
     */
    function deriveAddress(bytes calldata publicKey) external pure returns (address);

    /**
     * @notice Get pending teleport transfers for a recipient
     * @param recipient The recipient address
     * @return Array of pending teleport IDs
     */
    function pendingTeleports(address recipient) external view returns (bytes32[] memory);

    /**
     * @notice Get details of a specific teleport transfer
     * @param teleportId The unique teleport identifier
     * @return sender The sender's ML-DSA public key hash
     * @return recipient The recipient address
     * @return amount The transfer amount
     * @return sourceChain The source chain ID (always Hanzo L1)
     * @return status The transfer status (0=pending, 1=claimed, 2=expired)
     */
    function getTeleportDetails(bytes32 teleportId)
        external
        view
        returns (
            bytes32 sender,
            address recipient,
            uint256 amount,
            uint256 sourceChain,
            uint8 status
        );

    // ============ State-Changing Functions ============

    /**
     * @notice Claim teleported AI rewards from Hanzo L1
     * @param teleportId The unique teleport transfer identifier
     * @return The amount of AI tokens claimed
     *
     * @dev Requirements:
     *   - Teleport must exist and be in pending status
     *   - Caller must be the designated recipient
     *   - Teleport must not be expired (24 hour window)
     */
    function claimTeleport(bytes32 teleportId) external returns (uint256);

    /**
     * @notice Batch claim multiple teleport transfers
     * @param teleportIds Array of teleport IDs to claim
     * @return totalAmount Total AI tokens claimed
     */
    function batchClaimTeleports(bytes32[] calldata teleportIds) external returns (uint256 totalAmount);
}

/**
 * @title AIMiningPrecompile
 * @notice Implementation contract that wraps calls to the precompile at 0x0300
 * @dev This contract provides a convenient wrapper for calling the precompile
 *      with proper error handling and gas estimation
 */
contract AIMiningPrecompile {
    /// @notice The precompile address for AI Mining operations
    address public constant PRECOMPILE_ADDRESS = address(0x0300);

    /// @notice Chain IDs supported by Teleport
    uint256 public constant HANZO_EVM_CHAIN_ID = 36963;
    uint256 public constant ZOO_EVM_CHAIN_ID = 200200;
    uint256 public constant LUX_CCHAIN_CHAIN_ID = 96369;

    /// @notice ML-DSA security levels
    uint8 public constant SECURITY_LEVEL_2 = 2;
    uint8 public constant SECURITY_LEVEL_3 = 3;
    uint8 public constant SECURITY_LEVEL_5 = 5;

    /// @notice ML-DSA public key sizes per security level
    uint256 public constant PK_SIZE_LEVEL_2 = 1312;
    uint256 public constant PK_SIZE_LEVEL_3 = 1952;
    uint256 public constant PK_SIZE_LEVEL_5 = 2592;

    /// @notice ML-DSA signature sizes per security level
    uint256 public constant SIG_SIZE_LEVEL_2 = 2420;
    uint256 public constant SIG_SIZE_LEVEL_3 = 3309;
    uint256 public constant SIG_SIZE_LEVEL_5 = 4627;

    // ============ Errors ============

    error PrecompileCallFailed();
    error InvalidPublicKeySize();
    error InvalidSignatureSize();
    error TeleportNotFound();
    error TeleportAlreadyClaimed();
    error TeleportExpired();
    error NotTeleportRecipient();

    // ============ Events ============

    event TeleportClaimedViaWrapper(
        bytes32 indexed teleportId,
        address indexed claimer,
        uint256 amount
    );

    // ============ External Functions ============

    /**
     * @notice Get mining balance for an address
     * @param miner The miner address to query
     * @return balance The mining balance
     */
    function getMiningBalance(address miner) external view returns (uint256 balance) {
        (bool success, bytes memory result) = PRECOMPILE_ADDRESS.staticcall(
            abi.encodeWithSelector(IAIMining.miningBalance.selector, miner)
        );

        if (!success) revert PrecompileCallFailed();
        return abi.decode(result, (uint256));
    }

    /**
     * @notice Verify an ML-DSA signature
     * @param publicKey The signer's public key
     * @param message The signed message
     * @param signature The ML-DSA signature
     * @return isValid True if signature is valid
     */
    function verifySignature(
        bytes calldata publicKey,
        bytes calldata message,
        bytes calldata signature
    ) external view returns (bool isValid) {
        // Validate public key size
        if (publicKey.length != PK_SIZE_LEVEL_2 &&
            publicKey.length != PK_SIZE_LEVEL_3 &&
            publicKey.length != PK_SIZE_LEVEL_5) {
            revert InvalidPublicKeySize();
        }

        // Validate signature size matches public key level
        uint8 level = _getSecurityLevelFromPKSize(publicKey.length);
        uint256 expectedSigSize = _getSignatureSizeForLevel(level);
        if (signature.length != expectedSigSize) {
            revert InvalidSignatureSize();
        }

        (bool success, bytes memory result) = PRECOMPILE_ADDRESS.staticcall(
            abi.encodeWithSelector(
                IAIMining.verifyMLDSA.selector,
                publicKey,
                message,
                signature
            )
        );

        if (!success) revert PrecompileCallFailed();
        return abi.decode(result, (bool));
    }

    /**
     * @notice Claim a teleport transfer
     * @param teleportId The teleport to claim
     * @return amount The claimed amount
     */
    function claim(bytes32 teleportId) external returns (uint256 amount) {
        (bool success, bytes memory result) = PRECOMPILE_ADDRESS.call(
            abi.encodeWithSelector(IAIMining.claimTeleport.selector, teleportId)
        );

        if (!success) revert PrecompileCallFailed();
        amount = abi.decode(result, (uint256));

        emit TeleportClaimedViaWrapper(teleportId, msg.sender, amount);
        return amount;
    }

    /**
     * @notice Get all pending teleports for caller
     * @return teleportIds Array of pending teleport IDs
     */
    function getMyPendingTeleports() external view returns (bytes32[] memory teleportIds) {
        (bool success, bytes memory result) = PRECOMPILE_ADDRESS.staticcall(
            abi.encodeWithSelector(IAIMining.pendingTeleports.selector, msg.sender)
        );

        if (!success) revert PrecompileCallFailed();
        return abi.decode(result, (bytes32[]));
    }

    /**
     * @notice Derive address from ML-DSA public key
     * @param publicKey The public key bytes
     * @return addr The derived address
     */
    function addressFromPublicKey(bytes calldata publicKey) external view returns (address addr) {
        (bool success, bytes memory result) = PRECOMPILE_ADDRESS.staticcall(
            abi.encodeWithSelector(IAIMining.deriveAddress.selector, publicKey)
        );

        if (!success) revert PrecompileCallFailed();
        return abi.decode(result, (address));
    }

    // ============ Internal Functions ============

    function _getSecurityLevelFromPKSize(uint256 size) internal pure returns (uint8) {
        if (size == PK_SIZE_LEVEL_2) return SECURITY_LEVEL_2;
        if (size == PK_SIZE_LEVEL_3) return SECURITY_LEVEL_3;
        if (size == PK_SIZE_LEVEL_5) return SECURITY_LEVEL_5;
        revert InvalidPublicKeySize();
    }

    function _getSignatureSizeForLevel(uint8 level) internal pure returns (uint256) {
        if (level == SECURITY_LEVEL_2) return SIG_SIZE_LEVEL_2;
        if (level == SECURITY_LEVEL_3) return SIG_SIZE_LEVEL_3;
        if (level == SECURITY_LEVEL_5) return SIG_SIZE_LEVEL_5;
        revert InvalidPublicKeySize();
    }
}

/**
 * @title AIMiningHelper
 * @notice Helper library for AI Mining integration
 */
library AIMiningHelper {
    address constant PRECOMPILE = address(0x0300);

    /**
     * @notice Quick check if an address has mining balance
     * @param miner The address to check
     * @return hasFunds True if balance > 0
     */
    function hasMiningFunds(address miner) internal view returns (bool hasFunds) {
        (bool success, bytes memory result) = PRECOMPILE.staticcall(
            abi.encodeWithSelector(IAIMining.miningBalance.selector, miner)
        );

        if (!success) return false;
        return abi.decode(result, (uint256)) > 0;
    }

    /**
     * @notice Verify ML-DSA signature (returns false on failure instead of reverting)
     */
    function safeVerifyMLDSA(
        bytes memory publicKey,
        bytes memory message,
        bytes memory signature
    ) internal view returns (bool) {
        (bool success, bytes memory result) = PRECOMPILE.staticcall(
            abi.encodeWithSelector(
                IAIMining.verifyMLDSA.selector,
                publicKey,
                message,
                signature
            )
        );

        if (!success) return false;
        return abi.decode(result, (bool));
    }
}
