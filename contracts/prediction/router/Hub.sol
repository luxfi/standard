// SPDX-License-Identifier: MIT
pragma solidity ^0.8.31;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IWarp, WarpLib} from "../../bridge/interfaces/IWarpMessenger.sol";

/**
 * @title Hub
 * @author Lux Industries
 * @notice Central market registry on C-Chain for cross-chain prediction markets
 * @dev Receives market creation messages via Warp from spoke chains (Zoo, Hanzo, etc.)
 *
 * Architecture:
 * - Spoke chains create markets locally and send Warp messages to register on C-Chain
 * - C-Chain maintains global market state and coordinates resolution
 * - Markets can be resolved via Oracle on C-Chain, with resolution broadcast back
 *
 * Message Types:
 * - REGISTER_MARKET: Register a new market from spoke chain
 * - UPDATE_MARKET: Update market metadata
 * - SYNC_STATE: Sync market state across chains
 */
contract Hub is Ownable, ReentrancyGuard {
    // ═══════════════════════════════════════════════════════════════════════
    // TYPES
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice Market status
    enum MarketStatus {
        Unknown,
        Registered,
        Active,
        Paused,
        Resolved,
        Cancelled
    }

    /// @notice Cross-chain market data
    struct Market {
        bytes32 marketId;           // Unique market identifier
        bytes32 sourceChainId;      // Chain where market was created
        address sourceMarket;       // Market contract on source chain
        bytes32 questionId;         // CTF question ID
        bytes32 conditionId;        // Claims condition ID
        address oracle;             // Oracle adapter address (e.g., Resolver)
        uint256 outcomeSlotCount;   // Number of outcomes
        uint256 createdAt;          // Registration timestamp
        uint256 resolvedAt;         // Resolution timestamp (0 if unresolved)
        MarketStatus status;        // Current status
        uint256[] payouts;          // Resolution payouts (empty until resolved)
        bytes ancillaryData;        // Market description/metadata
    }

    /// @notice Warp message types
    enum MessageType {
        REGISTER_MARKET,
        UPDATE_MARKET,
        SYNC_STATE,
        RESOLUTION_BROADCAST
    }

    /// @notice Registered spoke chain
    struct SpokeChain {
        bytes32 chainId;
        address hubContract;        // WarpMarketHub on spoke chain
        bool active;
    }

    // ═══════════════════════════════════════════════════════════════════════
    // STATE
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice This chain's blockchain ID (cached for gas efficiency)
    bytes32 public immutable thisChainId;

    /// @notice Registered markets by ID
    mapping(bytes32 => Market) public markets;

    /// @notice Markets by source chain
    mapping(bytes32 => bytes32[]) public marketsByChain;

    /// @notice Registered spoke chains
    mapping(bytes32 => SpokeChain) public spokeChains;

    /// @notice Allowed spoke chain list
    bytes32[] public spokeChainList;

    /// @notice Total markets registered
    uint256 public totalMarkets;

    /// @notice Oracle relay contract for resolution
    address public oracleRelay;

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

    event SpokeChainRegistered(
        bytes32 indexed chainId,
        address hubContract
    );

    event SpokeChainUpdated(
        bytes32 indexed chainId,
        bool active
    );

    event OracleRelaySet(address indexed oracleRelay);

    event ResolutionBroadcast(
        bytes32 indexed marketId,
        bytes32 indexed targetChainId,
        bytes32 messageId
    );

    // ═══════════════════════════════════════════════════════════════════════
    // ERRORS
    // ═══════════════════════════════════════════════════════════════════════

    error InvalidMessage();
    error UnauthorizedChain();
    error UnauthorizedSender();
    error MarketAlreadyExists();
    error MarketNotFound();
    error MarketAlreadyResolved();
    error InvalidPayouts();
    error ZeroAddress();
    error InvalidOutcomeCount();
    error SpokeChainNotActive();

    // ═══════════════════════════════════════════════════════════════════════
    // CONSTRUCTOR
    // ═══════════════════════════════════════════════════════════════════════

    constructor() Ownable(msg.sender) {
        thisChainId = WarpLib.getBlockchainID();
    }

    // ═══════════════════════════════════════════════════════════════════════
    // WARP MESSAGE RECEIVER
    // ═══════════════════════════════════════════════════════════════════════

    /**
     * @notice Receive and process a Warp message from a spoke chain
     * @param messageIndex Index of the Warp message in the transaction
     */
    function receiveWarpMessage(uint32 messageIndex) external nonReentrant {
        // Get and verify the Warp message
        IWarp.WarpMessage memory message = WarpLib.getVerifiedMessageOrRevert(messageIndex);

        // Verify source chain is registered
        SpokeChain storage spoke = spokeChains[message.sourceChainID];
        if (!spoke.active) revert UnauthorizedChain();

        // Verify sender is the hub contract on source chain
        if (message.originSenderAddress != spoke.hubContract) revert UnauthorizedSender();

        // Decode and process message
        _processMessage(message.sourceChainID, message.payload);
    }

    /**
     * @notice Process a decoded Warp message payload
     * @param sourceChainId Source chain ID
     * @param payload Message payload
     */
    function _processMessage(bytes32 sourceChainId, bytes memory payload) internal {
        // Decode message type
        MessageType msgType = abi.decode(payload, (MessageType));

        if (msgType == MessageType.REGISTER_MARKET) {
            _handleRegisterMarket(sourceChainId, payload);
        } else if (msgType == MessageType.UPDATE_MARKET) {
            _handleUpdateMarket(payload);
        } else if (msgType == MessageType.SYNC_STATE) {
            _handleSyncState(payload);
        } else {
            revert InvalidMessage();
        }
    }

    // ═══════════════════════════════════════════════════════════════════════
    // MESSAGE HANDLERS
    // ═══════════════════════════════════════════════════════════════════════

    /**
     * @notice Handle market registration from spoke chain
     */
    function _handleRegisterMarket(bytes32 sourceChainId, bytes memory payload) internal {
        (
            ,  // MessageType
            bytes32 marketId,
            address sourceMarket,
            bytes32 questionId,
            bytes32 conditionId,
            address oracle,
            uint256 outcomeSlotCount,
            bytes memory ancillaryData
        ) = abi.decode(payload, (MessageType, bytes32, address, bytes32, bytes32, address, uint256, bytes));

        // Validate
        if (markets[marketId].status != MarketStatus.Unknown) revert MarketAlreadyExists();
        if (outcomeSlotCount < 2 || outcomeSlotCount > 256) revert InvalidOutcomeCount();

        // Create market record
        markets[marketId] = Market({
            marketId: marketId,
            sourceChainId: sourceChainId,
            sourceMarket: sourceMarket,
            questionId: questionId,
            conditionId: conditionId,
            oracle: oracle,
            outcomeSlotCount: outcomeSlotCount,
            createdAt: block.timestamp,
            resolvedAt: 0,
            status: MarketStatus.Registered,
            payouts: new uint256[](0),
            ancillaryData: ancillaryData
        });

        marketsByChain[sourceChainId].push(marketId);
        totalMarkets++;

        emit MarketRegistered(
            marketId,
            sourceChainId,
            sourceMarket,
            questionId,
            conditionId,
            outcomeSlotCount
        );
    }

    /**
     * @notice Handle market update from spoke chain
     */
    function _handleUpdateMarket(bytes memory payload) internal {
        (
            ,  // MessageType
            bytes32 marketId,
            MarketStatus newStatus
        ) = abi.decode(payload, (MessageType, bytes32, MarketStatus));

        Market storage market = markets[marketId];
        if (market.status == MarketStatus.Unknown) revert MarketNotFound();
        if (market.status == MarketStatus.Resolved) revert MarketAlreadyResolved();

        MarketStatus oldStatus = market.status;
        market.status = newStatus;

        emit MarketStatusUpdated(marketId, oldStatus, newStatus);
    }

    /**
     * @notice Handle state sync request
     */
    function _handleSyncState(bytes memory payload) internal {
        // Future: Handle state sync for recovery scenarios
        (payload);  // Suppress unused warning
    }

    // ═══════════════════════════════════════════════════════════════════════
    // LOCAL MARKET REGISTRATION (for C-Chain native markets)
    // ═══════════════════════════════════════════════════════════════════════

    /**
     * @notice Register a market created locally on C-Chain
     * @param marketId Unique market identifier
     * @param questionId CTF question ID
     * @param conditionId CTF condition ID
     * @param oracle Oracle adapter address
     * @param outcomeSlotCount Number of outcomes
     * @param ancillaryData Market description
     */
    function registerLocalMarket(
        bytes32 marketId,
        bytes32 questionId,
        bytes32 conditionId,
        address oracle,
        uint256 outcomeSlotCount,
        bytes calldata ancillaryData
    ) external nonReentrant {
        if (markets[marketId].status != MarketStatus.Unknown) revert MarketAlreadyExists();
        if (outcomeSlotCount < 2 || outcomeSlotCount > 256) revert InvalidOutcomeCount();
        if (oracle == address(0)) revert ZeroAddress();

        markets[marketId] = Market({
            marketId: marketId,
            sourceChainId: thisChainId,
            sourceMarket: msg.sender,
            questionId: questionId,
            conditionId: conditionId,
            oracle: oracle,
            outcomeSlotCount: outcomeSlotCount,
            createdAt: block.timestamp,
            resolvedAt: 0,
            status: MarketStatus.Registered,
            payouts: new uint256[](0),
            ancillaryData: ancillaryData
        });

        marketsByChain[thisChainId].push(marketId);
        totalMarkets++;

        emit MarketRegistered(
            marketId,
            thisChainId,
            msg.sender,
            questionId,
            conditionId,
            outcomeSlotCount
        );
    }

    // ═══════════════════════════════════════════════════════════════════════
    // RESOLUTION
    // ═══════════════════════════════════════════════════════════════════════

    /**
     * @notice Record market resolution (called by oracle relay)
     * @param marketId Market ID
     * @param payouts Resolution payouts
     */
    function recordResolution(
        bytes32 marketId,
        uint256[] calldata payouts
    ) external nonReentrant {
        // Only oracle relay can record resolutions
        if (msg.sender != oracleRelay) revert UnauthorizedSender();

        Market storage market = markets[marketId];
        if (market.status == MarketStatus.Unknown) revert MarketNotFound();
        if (market.status == MarketStatus.Resolved) revert MarketAlreadyResolved();
        if (payouts.length != market.outcomeSlotCount) revert InvalidPayouts();

        // Validate at least one non-zero payout
        uint256 totalPayout = 0;
        for (uint256 i = 0; i < payouts.length; i++) {
            totalPayout += payouts[i];
        }
        if (totalPayout == 0) revert InvalidPayouts();

        // Record resolution
        market.status = MarketStatus.Resolved;
        market.resolvedAt = block.timestamp;
        market.payouts = payouts;

        emit MarketResolved(marketId, payouts, block.timestamp);
    }

    /**
     * @notice Broadcast resolution to spoke chain via Warp
     * @param marketId Market ID to broadcast
     * @param targetChainId Target spoke chain
     * @return messageId Warp message ID
     */
    function broadcastResolution(
        bytes32 marketId,
        bytes32 targetChainId
    ) external nonReentrant returns (bytes32 messageId) {
        Market storage market = markets[marketId];
        if (market.status != MarketStatus.Resolved) revert MarketNotFound();

        SpokeChain storage spoke = spokeChains[targetChainId];
        if (!spoke.active) revert SpokeChainNotActive();

        // Encode resolution message
        bytes memory payload = abi.encode(
            MessageType.RESOLUTION_BROADCAST,
            marketId,
            market.questionId,
            market.conditionId,
            market.payouts
        );

        // Send via Warp
        messageId = WarpLib.sendMessage(payload);

        emit ResolutionBroadcast(marketId, targetChainId, messageId);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // ADMIN FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════

    /**
     * @notice Register a spoke chain
     * @param chainId Spoke chain's blockchain ID
     * @param hubContract Hub contract address on spoke chain
     */
    function registerSpokeChain(
        bytes32 chainId,
        address hubContract
    ) external onlyOwner {
        if (hubContract == address(0)) revert ZeroAddress();

        spokeChains[chainId] = SpokeChain({
            chainId: chainId,
            hubContract: hubContract,
            active: true
        });

        spokeChainList.push(chainId);

        emit SpokeChainRegistered(chainId, hubContract);
    }

    /**
     * @notice Update spoke chain status
     * @param chainId Spoke chain's blockchain ID
     * @param active Active status
     */
    function setSpokeChainActive(
        bytes32 chainId,
        bool active
    ) external onlyOwner {
        spokeChains[chainId].active = active;
        emit SpokeChainUpdated(chainId, active);
    }

    /**
     * @notice Set oracle relay contract
     * @param _oracleRelay Oracle relay address
     */
    function setOracleRelay(address _oracleRelay) external onlyOwner {
        if (_oracleRelay == address(0)) revert ZeroAddress();
        oracleRelay = _oracleRelay;
        emit OracleRelaySet(_oracleRelay);
    }

    /**
     * @notice Update market status (admin override)
     * @param marketId Market ID
     * @param newStatus New status
     */
    function setMarketStatus(
        bytes32 marketId,
        MarketStatus newStatus
    ) external onlyOwner {
        Market storage market = markets[marketId];
        if (market.status == MarketStatus.Unknown) revert MarketNotFound();

        MarketStatus oldStatus = market.status;
        market.status = newStatus;

        emit MarketStatusUpdated(marketId, oldStatus, newStatus);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // VIEW FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════

    /**
     * @notice Get market data
     * @param marketId Market ID
     * @return Market data
     */
    function getMarket(bytes32 marketId) external view returns (Market memory) {
        return markets[marketId];
    }

    /**
     * @notice Get markets by source chain
     * @param chainId Source chain ID
     * @return Array of market IDs
     */
    function getMarketsByChain(bytes32 chainId) external view returns (bytes32[] memory) {
        return marketsByChain[chainId];
    }

    /**
     * @notice Get spoke chain count
     * @return Number of registered spoke chains
     */
    function getSpokeChainCount() external view returns (uint256) {
        return spokeChainList.length;
    }

    /**
     * @notice Check if market is resolved
     * @param marketId Market ID
     * @return True if resolved
     */
    function isResolved(bytes32 marketId) external view returns (bool) {
        return markets[marketId].status == MarketStatus.Resolved;
    }

    /**
     * @notice Get resolution payouts
     * @param marketId Market ID
     * @return Payout array
     */
    function getPayouts(bytes32 marketId) external view returns (uint256[] memory) {
        return markets[marketId].payouts;
    }
}
