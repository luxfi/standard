// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/**
 * @title ITeleportBridge
 * @notice Interface for the Teleport Bridge precompile at address 0x0301
 * @dev Enables cross-chain AI token transfers from Hanzo L1 to supported EVMs
 *
 * Supported destination chains:
 * - Hanzo EVM: Chain ID 36963
 * - Zoo EVM: Chain ID 200200
 * - Lux C-Chain: Chain ID 43114
 *
 * References:
 * - LP-2000: AI Mining Standard
 * - HIP-006: Hanzo AI Mining Protocol
 * - ZIP-005: Zoo AI Mining Integration
 */
interface ITeleportBridge {
    // ============ Structs ============

    struct TeleportTransfer {
        bytes32 teleportId;      // Unique transfer identifier
        uint256 sourceChain;     // Source chain ID (always Hanzo L1 = 0)
        uint256 destChain;       // Destination chain ID
        bytes32 senderPkHash;    // BLAKE3 hash of sender's ML-DSA public key
        address recipient;       // Recipient address on destination chain
        uint256 amount;          // AI token amount in atomic units
        uint64 timestamp;        // Transfer initiation timestamp
        TransferStatus status;   // Current transfer status
    }

    enum TransferStatus {
        Pending,    // Awaiting claim on destination
        Claimed,    // Successfully claimed
        Expired,    // Claim window passed (24 hours)
        Cancelled   // Cancelled by sender (L1 only)
    }

    // ============ Events ============

    /// @notice Emitted when a new teleport is received from Hanzo L1
    event TeleportReceived(
        bytes32 indexed teleportId,
        uint256 indexed sourceChain,
        address indexed recipient,
        uint256 amount
    );

    /// @notice Emitted when a teleport is claimed
    event TeleportClaimed(
        bytes32 indexed teleportId,
        address indexed claimer,
        uint256 amount
    );

    /// @notice Emitted when a teleport expires
    event TeleportExpired(
        bytes32 indexed teleportId,
        address indexed recipient,
        uint256 amount
    );

    // ============ View Functions ============

    /**
     * @notice Get the current chain's ID
     * @return The chain ID
     */
    function getChainId() external view returns (uint256);

    /**
     * @notice Check if a chain is supported for teleport
     * @param chainId The chain ID to check
     * @return True if chain is supported
     */
    function isSupportedChain(uint256 chainId) external view returns (bool);

    /**
     * @notice Get all supported chain IDs
     * @return Array of supported chain IDs
     */
    function getSupportedChains() external view returns (uint256[] memory);

    /**
     * @notice Get teleport transfer details
     * @param teleportId The transfer ID
     * @return transfer The transfer details
     */
    function getTeleport(bytes32 teleportId) external view returns (TeleportTransfer memory transfer);

    /**
     * @notice Get all pending teleports for a recipient
     * @param recipient The recipient address
     * @return Array of pending teleport IDs
     */
    function getPendingTeleports(address recipient) external view returns (bytes32[] memory);

    /**
     * @notice Get total amount of pending teleports for a recipient
     * @param recipient The recipient address
     * @return Total pending amount
     */
    function getPendingAmount(address recipient) external view returns (uint256);

    /**
     * @notice Check if a teleport is claimable
     * @param teleportId The transfer ID
     * @return True if transfer can be claimed
     */
    function isClaimable(bytes32 teleportId) external view returns (bool);

    /**
     * @notice Get the claim deadline for a teleport
     * @param teleportId The transfer ID
     * @return Unix timestamp of claim deadline
     */
    function getClaimDeadline(bytes32 teleportId) external view returns (uint256);

    // ============ State-Changing Functions ============

    /**
     * @notice Claim a teleport transfer
     * @param teleportId The transfer to claim
     * @return amount The claimed amount
     *
     * Requirements:
     * - Transfer must exist and be pending
     * - Caller must be the designated recipient
     * - Must be within 24-hour claim window
     */
    function claim(bytes32 teleportId) external returns (uint256 amount);

    /**
     * @notice Batch claim multiple teleports
     * @param teleportIds Array of transfer IDs
     * @return totalAmount Total amount claimed
     */
    function batchClaim(bytes32[] calldata teleportIds) external returns (uint256 totalAmount);

    /**
     * @notice Claim all pending teleports for caller
     * @return totalAmount Total amount claimed
     * @return claimedCount Number of teleports claimed
     */
    function claimAll() external returns (uint256 totalAmount, uint256 claimedCount);
}

/**
 * @title TeleportBridgePrecompile
 * @notice Wrapper contract for the Teleport Bridge precompile
 */
contract TeleportBridgePrecompile {
    /// @notice The precompile address
    address public constant PRECOMPILE_ADDRESS = address(0x0301);

    /// @notice Hanzo L1 chain identifier (source of all teleports)
    uint256 public constant HANZO_L1_CHAIN_ID = 0;

    /// @notice Supported destination chain IDs
    uint256 public constant HANZO_EVM_CHAIN_ID = 36963;
    uint256 public constant ZOO_EVM_CHAIN_ID = 200200;
    uint256 public constant LUX_CCHAIN_CHAIN_ID = 96369;

    /// @notice Claim window duration (24 hours)
    uint256 public constant CLAIM_WINDOW = 24 hours;

    // ============ Errors ============

    error PrecompileCallFailed();
    error TeleportNotFound();
    error TeleportNotClaimable();
    error NotRecipient();
    error ClaimWindowExpired();

    // ============ Events ============

    event ClaimedViaWrapper(
        bytes32 indexed teleportId,
        address indexed claimer,
        uint256 amount
    );

    // ============ External Functions ============

    /**
     * @notice Get current chain ID
     */
    function chainId() external view returns (uint256) {
        return block.chainid;
    }

    /**
     * @notice Check if running on a supported chain
     */
    function onSupportedChain() external view returns (bool) {
        return block.chainid == HANZO_EVM_CHAIN_ID ||
               block.chainid == ZOO_EVM_CHAIN_ID ||
               block.chainid == LUX_CCHAIN_CHAIN_ID;
    }

    /**
     * @notice Claim teleport with validation
     */
    function claimTeleport(bytes32 teleportId) external returns (uint256 amount) {
        (bool success, bytes memory result) = PRECOMPILE_ADDRESS.call(
            abi.encodeWithSelector(ITeleportBridge.claim.selector, teleportId)
        );

        if (!success) revert PrecompileCallFailed();
        amount = abi.decode(result, (uint256));

        emit ClaimedViaWrapper(teleportId, msg.sender, amount);
        return amount;
    }

    /**
     * @notice Get all pending teleports for caller
     */
    function myPendingTeleports() external view returns (bytes32[] memory) {
        (bool success, bytes memory result) = PRECOMPILE_ADDRESS.staticcall(
            abi.encodeWithSelector(ITeleportBridge.getPendingTeleports.selector, msg.sender)
        );

        if (!success) revert PrecompileCallFailed();
        return abi.decode(result, (bytes32[]));
    }

    /**
     * @notice Get total pending amount for caller
     */
    function myPendingAmount() external view returns (uint256) {
        (bool success, bytes memory result) = PRECOMPILE_ADDRESS.staticcall(
            abi.encodeWithSelector(ITeleportBridge.getPendingAmount.selector, msg.sender)
        );

        if (!success) revert PrecompileCallFailed();
        return abi.decode(result, (uint256));
    }

    /**
     * @notice Claim all pending teleports
     */
    function claimAllPending() external returns (uint256 totalAmount, uint256 count) {
        (bool success, bytes memory result) = PRECOMPILE_ADDRESS.call(
            abi.encodeWithSelector(ITeleportBridge.claimAll.selector)
        );

        if (!success) revert PrecompileCallFailed();
        return abi.decode(result, (uint256, uint256));
    }
}

/**
 * @title TeleportReceiver
 * @notice Abstract contract for receiving teleported AI tokens
 * @dev Inherit this contract to add teleport receiving capabilities
 */
abstract contract TeleportReceiver {
    ITeleportBridge public immutable teleportBridge;

    constructor(address _bridge) {
        teleportBridge = ITeleportBridge(_bridge);
    }

    /**
     * @notice Called after a teleport is claimed
     * @dev Override to implement custom logic
     */
    function onTeleportReceived(
        bytes32 teleportId,
        uint256 amount
    ) internal virtual;

    /**
     * @notice Claim teleport and trigger callback
     */
    function receiveTeleport(bytes32 teleportId) external returns (uint256 amount) {
        amount = teleportBridge.claim(teleportId);
        onTeleportReceived(teleportId, amount);
        return amount;
    }
}
