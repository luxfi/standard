// SPDX-License-Identifier: BSD-3-Clause
// Copyright (c) 2025 Lux Industries Inc.

pragma solidity ^0.8.28;

/// @title Bridge Route
/// @notice Information about a bridging route
struct BridgeRoute {
    uint256 srcChainId;       // Source chain ID
    uint256 dstChainId;       // Destination chain ID
    address srcToken;         // Token on source chain
    address dstToken;         // Token on destination chain
    uint256 minAmount;        // Minimum bridge amount
    uint256 maxAmount;        // Maximum bridge amount
    uint256 estimatedTime;    // Estimated time in seconds
    bool isActive;            // Route is active
}

/// @title Bridge Parameters
struct BridgeParams {
    uint256 dstChainId;       // Destination chain ID
    address token;            // Token to bridge
    uint256 amount;           // Amount to bridge
    address recipient;        // Recipient on destination chain
    uint256 minAmountOut;     // Minimum amount on destination
    bytes extraData;          // Protocol-specific extra data
}

/// @title Bridge Status
/// @notice Status of a bridge transaction
struct BridgeStatus {
    bytes32 txHash;           // Source transaction hash
    uint256 srcChainId;       // Source chain
    uint256 dstChainId;       // Destination chain
    address token;            // Bridged token
    uint256 amount;           // Amount bridged
    address sender;           // Sender address
    address recipient;        // Recipient address
    uint8 status;             // 0=pending, 1=confirmed, 2=completed, 3=failed
    uint256 timestamp;        // Initiation timestamp
}

/// @title IBridgeAdapter
/// @author Lux Industries Inc.
/// @notice Standard interface for cross-chain bridge adapters
/// @dev Implement for LayerZero, Warp, Stargate, Across, Hop, etc.
interface IBridgeAdapter {
    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    event BridgeInitiated(
        bytes32 indexed bridgeId,
        address indexed sender,
        uint256 srcChainId,
        uint256 dstChainId,
        address token,
        uint256 amount
    );

    event BridgeCompleted(
        bytes32 indexed bridgeId,
        address indexed recipient,
        uint256 dstChainId,
        address token,
        uint256 amount
    );

    /*//////////////////////////////////////////////////////////////
                              METADATA
    //////////////////////////////////////////////////////////////*/

    /// @notice Returns the adapter version
    function version() external view returns (string memory);

    /// @notice Returns the bridge protocol name
    function protocol() external view returns (string memory);

    /// @notice Returns this chain's ID
    function chainId() external view returns (uint256);

    /// @notice Returns the core bridge endpoint
    function endpoint() external view returns (address);

    /*//////////////////////////////////////////////////////////////
                            ROUTE INFO
    //////////////////////////////////////////////////////////////*/

    /// @notice Get supported destination chains
    function supportedChains() external view returns (uint256[] memory);

    /// @notice Check if a route is supported
    function isRouteSupported(
        uint256 dstChainId,
        address token
    ) external view returns (bool);

    /// @notice Get route information
    function getRoute(
        uint256 dstChainId,
        address token
    ) external view returns (BridgeRoute memory);

    /// @notice Get all available routes
    function getRoutes() external view returns (BridgeRoute[] memory);

    /*//////////////////////////////////////////////////////////////
                          BRIDGE OPERATIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Initiate a bridge transfer
    /// @param params Bridge parameters
    /// @return bridgeId Unique identifier for the bridge tx
    function bridge(BridgeParams calldata params)
        external
        payable
        returns (bytes32 bridgeId);

    /// @notice Get bridge transaction status
    /// @param bridgeId Bridge transaction ID
    /// @return BridgeStatus struct
    function getStatus(bytes32 bridgeId) 
        external 
        view 
        returns (BridgeStatus memory);

    /*//////////////////////////////////////////////////////////////
                             ESTIMATION
    //////////////////////////////////////////////////////////////*/

    /// @notice Estimate bridge fees
    /// @param dstChainId Destination chain
    /// @param token Token to bridge
    /// @param amount Amount to bridge
    /// @return bridgeFee Fee in native token
    /// @return protocolFee Additional protocol fees
    function estimateFees(
        uint256 dstChainId,
        address token,
        uint256 amount
    ) external view returns (uint256 bridgeFee, uint256 protocolFee);

    /// @notice Estimate amount received on destination
    /// @param dstChainId Destination chain
    /// @param token Token to bridge
    /// @param amount Amount to bridge
    /// @return amountOut Expected amount on destination
    function estimateOutput(
        uint256 dstChainId,
        address token,
        uint256 amount
    ) external view returns (uint256 amountOut);

    /// @notice Estimate bridge time
    /// @param dstChainId Destination chain
    /// @return Estimated time in seconds
    function estimateTime(uint256 dstChainId) 
        external 
        view 
        returns (uint256);
}
