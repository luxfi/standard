// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title ILXBook
/// @notice LP-9020 precompile: LXBook (permissionless markets + matching + advanced order programs)
/// @dev Singleton at 0x0000000000000000000000000000000000009020.
///      Custody/margin is NOT here (LXVault). This is order lifecycle + matching + scheduling.
///      Hyperliquid-style single execute() endpoint with typed action payloads.
interface ILXBook {
    // -------------------------------------------------------------------------
    // Identifiers / Enums
    // -------------------------------------------------------------------------

    type MarketId is uint32;
    type OrderId  is uint64;
    type TwapId   is uint64;

    /// @notice Time-in-force semantics
    enum TIF {
        GTC, // good-til-canceled (resting)
        IOC, // immediate-or-cancel
        ALO  // add-liquidity-only (post-only)
    }

    /// @notice Order kind (covers limit, market, and trigger variants)
    enum OrderKind {
        LIMIT,
        MARKET,
        STOP_MARKET,
        STOP_LIMIT,
        TAKE_MARKET,
        TAKE_LIMIT
    }

    /// @notice Market status gating
    enum MarketStatus {
        ACTIVE,
        POST_ONLY,
        HALTED
    }

    /// @notice Optional grouping for OCO/bracket-style orders
    enum GroupType {
        NONE,
        OCO,     // one-cancels-other
        BRACKET  // bracket order (entry + TP + SL)
    }

    /// @notice Action types for execute() endpoint
    enum ActionType {
        PLACE,           // place one or many orders
        CANCEL,          // cancel by oid
        CANCEL_BY_CLOID, // cancel by client order id
        MODIFY,          // cancel+replace semantics
        TWAP_CREATE,     // create TWAP program
        TWAP_CANCEL,     // cancel TWAP program
        SCHEDULE_CANCEL, // dead-man switch / cancel-all at time
        NOOP,            // mark nonce used (no-op)
        RESERVE_WEIGHT   // buy extra action weight (optional)
    }

    // -------------------------------------------------------------------------
    // Market Config
    // -------------------------------------------------------------------------

    struct MarketConfig {
        bytes32 baseAsset;       // e.g., keccak256("ETH")
        bytes32 quoteAsset;      // e.g., keccak256("USDC")
        uint128 tickSizeX18;     // minimum price increment (1e18 scaled)
        uint128 lotSizeX18;      // minimum size increment (1e18 scaled)
        uint32  makerFeePpm;     // maker fee in ppm (e.g., 100 = 0.01%)
        uint32  takerFeePpm;     // taker fee in ppm (e.g., 500 = 0.05%)
        bytes32 feedId;          // optional oracle/feed linkage
        MarketStatus initialStatus;
    }

    // -------------------------------------------------------------------------
    // Orders
    // -------------------------------------------------------------------------

    /// @notice Canonical order description
    /// @dev Covers HL-style order types via kind/tif/trigger fields
    struct Order {
        MarketId marketId;
        bool isBuy;
        OrderKind kind;

        uint128 sizeX18;

        /// @dev For LIMIT/STOP_LIMIT/TAKE_LIMIT: limit price. For MARKET: 0.
        uint128 limitPxX18;

        /// @dev For STOP_*/TAKE_*: trigger price. For LIMIT/MARKET: 0.
        uint128 triggerPxX18;

        bool reduceOnly;
        TIF tif;

        /// @dev Client id for idempotency/cancel/modify
        bytes32 cloid;

        /// @dev Optional grouping for OCO/brackets
        bytes32 groupId;
        GroupType groupType;
    }

    /// @notice Order placement result
    struct PlaceResult {
        OrderId oid;
        uint8 status;           // 0=rejected, 1=filled, 2=resting, 3=partial+resting
        uint128 filledSizeX18;
        uint128 avgPxX18;
    }

    /// @notice Cancel by order id
    struct Cancel {
        MarketId marketId;
        OrderId oid;
    }

    /// @notice Cancel by client order id
    struct CancelByCloid {
        MarketId marketId;
        address owner;
        bytes32 cloid;
    }

    /// @notice Modify (cancel+replace)
    struct Modify {
        MarketId marketId;
        OrderId oid;        // if 0, use cloid+owner
        address owner;      // optional selector for cloid path
        bytes32 cloid;
        Order newOrder;
    }

    // -------------------------------------------------------------------------
    // TWAP (book-managed program)
    // -------------------------------------------------------------------------

    struct Twap {
        MarketId marketId;
        bool isBuy;
        OrderKind childKind;     // typically MARKET or LIMIT
        uint128 totalSizeX18;
        uint128 limitPxX18;      // 0 for market child orders
        uint32  durationSec;
        uint32  intervalSec;
        uint32  maxSlippagePpm;  // e.g., 30000 = 3%
        bool    reduceOnly;
        bytes32 cloid;
    }

    // -------------------------------------------------------------------------
    // System Actions
    // -------------------------------------------------------------------------

    /// @notice Dead-man switch: cancel all orders at specified time
    struct ScheduleCancel {
        uint32 time;  // unix seconds; 0 clears schedule
    }

    /// @notice Reserve extra action weight (rate limit credit)
    struct ReserveWeight {
        uint32 weight;
    }

    // -------------------------------------------------------------------------
    // Action Envelope (Hyperliquid-style endpoint)
    // -------------------------------------------------------------------------

    /// @notice Generic action envelope for execute()
    struct Action {
        ActionType actionType;
        uint64 nonce;         // anti-replay (recommended: ms timestamp or monotonic)
        uint64 expiresAfter;  // unix seconds; 0 = no expiry
        bytes data;           // ABI-encoded payload based on actionType
    }

    // -------------------------------------------------------------------------
    // Execute Endpoint
    // -------------------------------------------------------------------------

    /// @notice Execute a single action
    /// @param action The action to execute
    /// @return result ABI-encoded result based on actionType:
    ///   - PLACE:           abi.encode(PlaceResult[])
    ///   - CANCEL:          abi.encode(bool[])
    ///   - CANCEL_BY_CLOID: abi.encode(bool[])
    ///   - MODIFY:          abi.encode(PlaceResult[])
    ///   - TWAP_CREATE:     abi.encode(TwapId)
    ///   - TWAP_CANCEL:     abi.encode(bool)
    ///   - SCHEDULE_CANCEL: abi.encode(bool)
    ///   - NOOP:            abi.encode(true)
    ///   - RESERVE_WEIGHT:  abi.encode(bool)
    function execute(Action calldata action) external returns (bytes memory result);

    /// @notice Execute multiple actions atomically
    function executeBatch(Action[] calldata actions) external returns (bytes[] memory results);

    // -------------------------------------------------------------------------
    // Market Lifecycle
    // -------------------------------------------------------------------------

    /// @notice Create a new permissionless market
    function createMarket(MarketConfig calldata cfg) external returns (MarketId marketId);

    /// @notice Read market configuration
    function getMarketConfig(MarketId marketId) external view returns (MarketConfig memory cfg);

    /// @notice Get market status
    function getMarketStatus(MarketId marketId) external view returns (MarketStatus);

    // -------------------------------------------------------------------------
    // Views
    // -------------------------------------------------------------------------

    /// @notice Level-1 book view
    struct L1 {
        uint128 bestBidPxX18;
        uint128 bestBidSzX18;
        uint128 bestAskPxX18;
        uint128 bestAskSzX18;
        uint128 lastTradePxX18;
    }

    /// @notice Order info view
    struct OrderInfo {
        address owner;
        Order order;
        uint128 remainingSizeX18;
        bool active;
    }

    /// @notice Get L1 (best bid/ask + last trade)
    function getL1(MarketId marketId) external view returns (L1 memory l1);

    /// @notice Get order info by oid
    function getOrder(MarketId marketId, OrderId oid) external view returns (OrderInfo memory info);

    /// @notice Resolve oid by (owner, cloid)
    function getOrderIdByCloid(MarketId marketId, address owner, bytes32 cloid) external view returns (OrderId oid);

    // -------------------------------------------------------------------------
    // Errors
    // -------------------------------------------------------------------------

    error InvalidAction();
    error InvalidOrder();
    error MarketNotFound(MarketId marketId);
    error MarketNotActive(MarketId marketId);
    error NotOrderOwner();
    error NotFound();
    error Expired();
    error Replay();

    // -------------------------------------------------------------------------
    // Settlement Callback (called by LXBook → LXVault)
    // -------------------------------------------------------------------------

    /// @notice Trade settlement data passed to LXVault
    /// @dev LXBook emits this to LXVault.settleTrade() after matching
    struct TradeSettlement {
        MarketId marketId;
        OrderId makerOid;
        OrderId takerOid;
        address maker;
        address taker;
        bool takerIsBuy;         // taker's direction
        uint128 sizeX18;         // base amount
        uint128 priceX18;        // execution price
        uint128 quoteAmountX18;  // quote amount (size * price)
        uint128 makerFeeX18;     // fee charged to maker
        uint128 takerFeeX18;     // fee charged to taker
        bytes32 makerCloid;
        bytes32 takerCloid;
    }

    /// @notice Emitted when a trade is settled (for indexers/UIs)
    /// @dev LXVault listens to this or receives direct callback
    event TradeSettled(
        MarketId indexed marketId,
        address indexed maker,
        address indexed taker,
        uint128 sizeX18,
        uint128 priceX18
    );

    // -------------------------------------------------------------------------
    // Events
    // -------------------------------------------------------------------------

    event MarketCreated(
        MarketId indexed marketId,
        bytes32 indexed baseAsset,
        bytes32 indexed quoteAsset,
        uint128 tickSizeX18,
        uint128 lotSizeX18
    );

    event OrderPlaced(
        MarketId indexed marketId,
        OrderId indexed oid,
        address indexed owner,
        bool isBuy,
        OrderKind kind,
        uint128 limitPxX18,
        uint128 sizeX18,
        bytes32 cloid
    );

    event OrderCanceled(
        MarketId indexed marketId,
        OrderId indexed oid,
        address indexed owner,
        bytes32 cloid
    );

    event Trade(
        MarketId indexed marketId,
        OrderId indexed makerOid,
        OrderId indexed takerOid,
        address maker,
        address taker,
        uint128 pxX18,
        uint128 szX18
    );

    event TwapCreated(
        MarketId indexed marketId,
        TwapId indexed twapId,
        address indexed owner,
        uint128 totalSizeX18,
        uint32 durationSec
    );

    event TwapCanceled(
        MarketId indexed marketId,
        TwapId indexed twapId,
        address indexed owner
    );
}

/// @notice LXBook precompile address constant
address constant LX_BOOK = 0x0000000000000000000000000000000000009020;
