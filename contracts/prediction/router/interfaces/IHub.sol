// SPDX-License-Identifier: MIT
pragma solidity ^0.8.31;

/**
 * @title IHub
 * @author Lux Industries
 * @notice Interface for the Hub cross-chain market registry
 */
interface IHub {
    // ═══════════════════════════════════════════════════════════════════════
    // TYPES
    // ═══════════════════════════════════════════════════════════════════════

    enum MarketStatus {
        Unknown,
        Registered,
        Active,
        Paused,
        Resolved,
        Cancelled
    }

    struct Market {
        bytes32 marketId;
        bytes32 sourceChainId;
        address sourceMarket;
        bytes32 questionId;
        bytes32 conditionId;
        address oracle;
        uint256 outcomeSlotCount;
        uint256 createdAt;
        uint256 resolvedAt;
        MarketStatus status;
        uint256[] payouts;
        bytes ancillaryData;
    }

    // ═══════════════════════════════════════════════════════════════════════
    // EVENTS
    // ═══════════════════════════════════════════════════════════════════════

    event MarketRegistered(
        bytes32 indexed marketId,
        bytes32 indexed sourceChainId,
        address indexed sourceMarket,
        bytes32 questionId,
        bytes32 conditionId,
        uint256 outcomeSlotCount
    );

    event MarketStatusUpdated(
        bytes32 indexed marketId,
        MarketStatus oldStatus,
        MarketStatus newStatus
    );

    event MarketResolved(
        bytes32 indexed marketId,
        uint256[] payouts,
        uint256 timestamp
    );

    // ═══════════════════════════════════════════════════════════════════════
    // FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════

    /**
     * @notice Receive and process a Warp message from a spoke chain
     * @param messageIndex Index of the Warp message in the transaction
     */
    function receiveWarpMessage(uint32 messageIndex) external;

    /**
     * @notice Register a market created locally on C-Chain
     */
    function registerLocalMarket(
        bytes32 marketId,
        bytes32 questionId,
        bytes32 conditionId,
        address oracle,
        uint256 outcomeSlotCount,
        bytes calldata ancillaryData
    ) external;

    /**
     * @notice Record market resolution (called by oracle relay)
     */
    function recordResolution(
        bytes32 marketId,
        uint256[] calldata payouts
    ) external;

    /**
     * @notice Broadcast resolution to spoke chain via Warp
     */
    function broadcastResolution(
        bytes32 marketId,
        bytes32 targetChainId
    ) external returns (bytes32 messageId);

    /**
     * @notice Get market data
     */
    function getMarket(bytes32 marketId) external view returns (Market memory);

    /**
     * @notice Get markets by source chain
     */
    function getMarketsByChain(bytes32 chainId) external view returns (bytes32[] memory);

    /**
     * @notice Check if market is resolved
     */
    function isResolved(bytes32 marketId) external view returns (bool);

    /**
     * @notice Get resolution payouts
     */
    function getPayouts(bytes32 marketId) external view returns (uint256[] memory);
}
