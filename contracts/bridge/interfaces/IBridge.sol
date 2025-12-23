// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title IBridge
 * @author Lux Industries Inc
 * @notice Interface for the Lux Bridge contract
 * @dev Defines the standard bridge operations for cross-chain transfers
 */
interface IBridge {
    /// @notice Bridge transfer status
    enum TransferStatus {
        Pending,
        Completed,
        Failed,
        Refunded
    }

    /// @notice Bridge transfer details
    struct Transfer {
        bytes32 id;
        address sender;
        address receiver;
        address token;
        uint256 amount;
        uint32 sourceChainId;
        uint32 destChainId;
        TransferStatus status;
        uint256 timestamp;
    }

    /**
     * @notice Lock tokens for bridging
     * @param token The token address
     * @param amount The amount to bridge
     * @param destChainId The destination chain ID
     * @param receiver The receiver address on destination chain
     * @return transferId The unique transfer identifier
     */
    function lock(
        address token,
        uint256 amount,
        uint32 destChainId,
        address receiver
    ) external returns (bytes32 transferId);

    /**
     * @notice Mint bridged tokens (called by relayer)
     * @param transferId The transfer identifier
     * @param token The token address
     * @param receiver The receiver address
     * @param amount The amount to mint
     */
    function mint(
        bytes32 transferId,
        address token,
        address receiver,
        uint256 amount
    ) external;

    /**
     * @notice Burn tokens for unlocking on source chain
     * @param token The token address
     * @param amount The amount to burn
     * @param destChainId The destination chain ID
     * @param receiver The receiver address
     * @return transferId The unique transfer identifier
     */
    function burn(
        address token,
        uint256 amount,
        uint32 destChainId,
        address receiver
    ) external returns (bytes32 transferId);

    /**
     * @notice Unlock tokens (called by relayer)
     * @param transferId The transfer identifier
     * @param token The token address
     * @param receiver The receiver address
     * @param amount The amount to unlock
     */
    function unlock(
        bytes32 transferId,
        address token,
        address receiver,
        uint256 amount
    ) external;

    /**
     * @notice Get transfer details
     * @param transferId The transfer identifier
     * @return The transfer details
     */
    function getTransfer(bytes32 transferId) external view returns (Transfer memory);

    /**
     * @notice Check if a token is supported
     * @param token The token address
     * @return Whether the token is supported
     */
    function isTokenSupported(address token) external view returns (bool);

    /// @notice Emitted when tokens are locked
    event TokensLocked(
        bytes32 indexed transferId,
        address indexed sender,
        address indexed token,
        uint256 amount,
        uint32 destChainId,
        address receiver
    );

    /// @notice Emitted when tokens are minted
    event TokensMinted(
        bytes32 indexed transferId,
        address indexed receiver,
        address indexed token,
        uint256 amount
    );

    /// @notice Emitted when tokens are burned
    event TokensBurned(
        bytes32 indexed transferId,
        address indexed sender,
        address indexed token,
        uint256 amount,
        uint32 destChainId,
        address receiver
    );

    /// @notice Emitted when tokens are unlocked
    event TokensUnlocked(
        bytes32 indexed transferId,
        address indexed receiver,
        address indexed token,
        uint256 amount
    );
}
