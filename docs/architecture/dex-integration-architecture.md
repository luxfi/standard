# Lux DEX Integration Architecture

**Version**: 1.0.0
**Date**: 2025-12-29
**Author**: Architecture Team
**Status**: Design Document

## Executive Summary

This document defines the complete integration architecture between four core Lux systems:

1. **DEX Backend** (`~/work/lux/dex`) - Off-chain orderbook, price aggregation, keepers
2. **Smart Contracts** (`~/work/lux/standard`) - On-chain oracles, perps, AMM, lending
3. **Exchange Frontend** (`~/work/lux/exchange`) - Web UI for trading
4. **Lux Node** (`~/work/lux/node`) - EVM precompiles, RPC endpoints

---

## System Architecture Overview

```
+--------------------------------------------------------------------------------------------+
|                                    USER LAYER                                               |
+--------------------------------------------------------------------------------------------+
|                                                                                             |
|    +-----------------------+    +-----------------------+    +-----------------------+     |
|    |    Web Browser        |    |    Mobile App         |    |    API Clients        |     |
|    |    (lux.exchange)     |    |    (Future)           |    |    (Traders/Bots)     |     |
|    +-----------+-----------+    +-----------+-----------+    +-----------+-----------+     |
|                |                            |                            |                  |
+--------------------------------------------------------------------------------------------+
                 |                            |                            |
                 v                            v                            v
+--------------------------------------------------------------------------------------------+
|                                 FRONTEND LAYER (exchange)                                   |
+--------------------------------------------------------------------------------------------+
|                                                                                             |
|    +-----------------------------------------------------------------------------------+   |
|    |                         Exchange UI (Next.js + React)                              |   |
|    |                                                                                     |   |
|    |  +---------------+  +---------------+  +---------------+  +---------------+       |   |
|    |  | AMM Interface |  | Perps UI      |  | Portfolio     |  | Chart/Data    |       |   |
|    |  | (V2/V3 Swap)  |  | (Positions)   |  | (Balances)    |  | (TradingView) |       |   |
|    |  +---------------+  +---------------+  +---------------+  +---------------+       |   |
|    |                                                                                     |   |
|    |  Providers: wagmi + viem | RainbowKit | ethers.js                                  |   |
|    +-----------------------------------------------------------------------------------+   |
|                                                                                             |
|    Endpoints:                                                                               |
|      - https://lux.exchange (main UI)                                                       |
|      - https://dex.lux.network (order book sidecar)                                        |
|      - https://amm.lux.network (AMM V3 interface)                                          |
+--------------------------------------------------------------------------------------------+
                 |                            |                            |
                 | HTTP/WS                    | JSON-RPC                   | WebSocket
                 v                            v                            v
+--------------------------------------------------------------------------------------------+
|                                  API GATEWAY LAYER                                          |
+--------------------------------------------------------------------------------------------+
|                                                                                             |
|    +----------------------------------+    +----------------------------------+            |
|    |        DEX WebSocket API         |    |        DEX JSON-RPC API         |            |
|    |    (pkg/api/websocket_server)    |    |    (pkg/api/jsonrpc.go)         |            |
|    +----------------------------------+    +----------------------------------+            |
|                                                                                             |
|    WebSocket Messages:                      JSON-RPC Methods:                              |
|    - subscribe/unsubscribe                  - orderbook.getBestBid                         |
|    - place_order, cancel_order              - orderbook.getBestAsk                         |
|    - open_position, close_position          - orderbook.getStats                           |
|    - vault_deposit, vault_withdraw          - price.getLatest                              |
|    - lending_supply, lending_borrow         - market.getTrades                             |
|                                                                                             |
|    Rate Limiting: 100 req/sec per IP                                                       |
|    CORS Origins: lux.exchange, dex.lux.network, amm.lux.network                           |
+--------------------------------------------------------------------------------------------+
                 |                            |                            |
                 v                            v                            v
+--------------------------------------------------------------------------------------------+
|                               DEX BACKEND LAYER (dex)                                       |
+--------------------------------------------------------------------------------------------+
|                                                                                             |
|  +------------------+  +------------------+  +------------------+  +------------------+    |
|  |  Trading Engine  |  |  Price Oracle    |  |  Margin Engine   |  |  Oracle Keeper   |    |
|  |  (pkg/lx)        |  |  (pkg/price)     |  |  (pkg/lx)        |  |  (pkg/keeper)    |    |
|  +--------+---------+  +--------+---------+  +--------+---------+  +--------+---------+    |
|           |                     |                     |                     |              |
|  Components:            Components:            Components:            Components:          |
|  - OrderBook            - Aggregator           - Positions              - Writer           |
|  - MatchingEngine       - Chainlink Source     - Liquidation            - Scheduler        |
|  - ClearingHouse        - Pyth Source          - Collateral             - Circuit Breaker  |
|  - RiskEngine           - C-Chain TWAP         - Funding                - Gas Manager      |
|  - VaultManager         - Q-Chain Finality     - Insurance              - Retry Logic      |
|                                                                                             |
|  Data Flow:                                                                                |
|    1. Price sources push to Aggregator (50ms refresh)                                      |
|    2. Aggregator calculates weighted median with circuit breakers                          |
|    3. Keeper batches price updates and writes to OracleHub on-chain                       |
|    4. Trading Engine uses off-chain prices for fast matching                               |
|    5. Settlements happen on-chain via smart contracts                                      |
|                                                                                             |
+--------------------------------------------------------------------------------------------+
                 |                            |                            |
                 | gRPC/Internal              | JSON-RPC                   | Warp/P2P
                 v                            v                            v
+--------------------------------------------------------------------------------------------+
|                              BLOCKCHAIN LAYER (node + standard)                             |
+--------------------------------------------------------------------------------------------+
|                                                                                             |
|  +------------------------------+  +------------------------------+                        |
|  |      C-Chain (EVM)           |  |      Q-Chain (Finality)      |                        |
|  |      Chain ID: 96369         |  |      Quantum Safety          |                        |
|  +------------------------------+  +------------------------------+                        |
|                                                                                             |
|  SMART CONTRACTS (~/work/lux/standard/contracts):                                          |
|                                                                                             |
|  +----------------+  +----------------+  +----------------+  +----------------+            |
|  | Oracle System  |  | Perps Protocol |  | AMM V2/V3      |  | Lending/Markets|            |
|  +----------------+  +----------------+  +----------------+  +----------------+            |
|  | Oracle.sol     |  | Vault.sol      |  | AMMV2Router    |  | Markets.sol    |            |
|  | OracleHub.sol  |  | Router.sol     |  | AMMV3Router    |  | LendingPool    |            |
|  | ChainlinkAdapt |  | PositionRouter |  | V3Factory      |  | InterestModel  |            |
|  | PythAdapter    |  | LLPManager     |  | V2Factory      |  | Liquidator     |            |
|  | TWAPSource     |  | FastPriceFeed  |  | NFTPosMgr      |  | Collateral     |            |
|  | DEXSource      |  | VaultPriceFeed |  | Quoter         |  | Oracle (IOracle)|           |
|  | CircuitBreaker |  | OrderBook      |  | TickLens       |  |                |            |
|  +----------------+  +----------------+  +----------------+  +----------------+            |
|                                                                                             |
|  PRECOMPILES (EVM extensions):                                                             |
|  +----------------+  +----------------+  +----------------+  +----------------+            |
|  | FROST          |  | CGGMP21        |  | ML-DSA         |  | Ringtail       |            |
|  | 0x0200...000C  |  | 0x0200...000D  |  | 0x0200...0006  |  | 0x0200...000B  |            |
|  | Threshold Sig  |  | ECDSA Thresh   |  | Post-Quantum   |  | Lattice Thresh |            |
|  +----------------+  +----------------+  +----------------+  +----------------+            |
|                                                                                             |
|  RPC Endpoints:                                                                             |
|    - Mainnet: https://api.lux.network/ext/bc/C/rpc (port 9630)                             |
|    - Testnet: https://api.lux-test.network/ext/bc/C/rpc (port 9640)                        |
|    - Local:   http://localhost:9650/ext/bc/C/rpc (anvil/luxd --dev)                        |
|                                                                                             |
+--------------------------------------------------------------------------------------------+
```

---

## Data Flow Diagrams

### 1. Price Update Flow

```
+-------------------+     +-------------------+     +-------------------+
|   External        |     |   DEX Backend     |     |   Blockchain      |
|   Price Sources   |     |   (pkg/price)     |     |   (C-Chain)       |
+-------------------+     +-------------------+     +-------------------+
        |                         |                         |
        | 1. Raw prices           |                         |
        | (Chainlink, Pyth,       |                         |
        |  AMM pools, etc.)       |                         |
        +------------------------>|                         |
        |                         |                         |
        |                  2. Aggregate                     |
        |                  (weighted median,                |
        |                   outlier filter,                 |
        |                   circuit breaker)                |
        |                         |                         |
        |                         | 3. Write to OracleHub   |
        |                         | (batch, signed tx)      |
        |                         +------------------------>|
        |                         |                         |
        |                         |                  4. Store price
        |                         |                  (emit PriceWritten)
        |                         |                         |
        |                         |<------------------------+
        |                         |  5. Confirmation        |
        |                         |                         |
        |                  6. Broadcast to                  |
        |                  WebSocket clients                |
        |                         |                         |
        +<------------------------+                         |
        |  7. Price update event  |                         |
        |  to frontend            |                         |
```

### 2. Trading Flow (Order to Settlement)

```
+------------+     +------------+     +------------+     +------------+
|   User     |     |  Exchange  |     |    DEX     |     | Blockchain |
|  (Browser) |     |  Frontend  |     |  Backend   |     |  (C-Chain) |
+------------+     +------------+     +------------+     +------------+
      |                  |                  |                  |
      | 1. Place order   |                  |                  |
      | (WebSocket)      |                  |                  |
      +----------------->|                  |                  |
      |                  |                  |                  |
      |                  | 2. Forward       |                  |
      |                  | (type:place_order)|                 |
      |                  +----------------->|                  |
      |                  |                  |                  |
      |                  |           3. Match order            |
      |                  |           (in-memory orderbook)     |
      |                  |                  |                  |
      |                  |           4. If match found:        |
      |                  |              - Create trade         |
      |                  |              - Update positions     |
      |                  |                  |                  |
      |                  |                  | 5. Settlement    |
      |                  |                  | (if on-chain)    |
      |                  |                  +----------------->|
      |                  |                  |                  |
      |                  |                  |           6. Execute
      |                  |                  |           (Vault.swap,
      |                  |                  |            Router.execute)
      |                  |                  |                  |
      |                  |                  |<-----------------+
      |                  |                  | 7. Tx receipt    |
      |                  |                  |                  |
      |                  |<-----------------+                  |
      |                  | 8. Trade update  |                  |
      |                  |                  |                  |
      |<-----------------+                  |                  |
      | 9. UI update     |                  |                  |
```

### 3. Perpetual Position Flow

```
+------------+     +------------+     +------------+     +------------+
|   Trader   |     |  Exchange  |     |    DEX     |     |   Perps    |
|            |     |  Frontend  |     |  Backend   |     |  Contracts |
+------------+     +------------+     +------------+     +------------+
      |                  |                  |                  |
      | 1. Open position |                  |                  |
      | (symbol, size,   |                  |                  |
      |  leverage)       |                  |                  |
      +----------------->|                  |                  |
      |                  |                  |                  |
      |                  | 2. WebSocket     |                  |
      |                  | open_position    |                  |
      |                  +----------------->|                  |
      |                  |                  |                  |
      |                  |           3. MarginEngine           |
      |                  |           - Check collateral        |
      |                  |           - Calculate margin req    |
      |                  |           - Risk check              |
      |                  |                  |                  |
      |                  |                  | 4. On-chain:     |
      |                  |                  | PositionRouter.  |
      |                  |                  | createIncreasePosition
      |                  |                  +----------------->|
      |                  |                  |                  |
      |                  |                  |           5. Vault receives
      |                  |                  |              collateral
      |                  |                  |                  |
      |                  |                  |           6. Position
      |                  |                  |              created
      |                  |                  |                  |
      |                  |<-----------------+<-----------------+
      |                  | 7. Position confirmed               |
      |                  |                  |                  |
      |<-----------------+                  |                  |
      | 8. UI shows      |                  |                  |
      |    position      |                  |                  |
      |                  |                  |                  |
      |                  |           BACKGROUND:               |
      |                  |           - Funding rate calc       |
      |                  |           - Mark price updates      |
      |                  |           - Liquidation checks      |
      |                  |                  |                  |
      |<-----------------+<-----------------+<-----------------+
      | 9. Real-time     |                  |                  |
      |    P&L updates   |                  |                  |
```

---

## API Contract Definitions

### 1. WebSocket API (DEX Backend -> Frontend)

```typescript
// Connection URL
// Production: wss://dex.lux.network/ws
// Development: ws://localhost:8080/ws

// Message Types
interface WebSocketMessage {
  type: string;
  data?: Record<string, unknown>;
  error?: string;
  request_id?: string;
  timestamp: number;
}

// Authentication
interface AuthRequest {
  type: "auth";
  apiKey: string;
  apiSecret: string;
  request_id?: string;
}

interface AuthResponse {
  type: "auth_success";
  data: { user_id: string };
  request_id?: string;
  timestamp: number;
}

// Subscriptions
interface SubscribeRequest {
  type: "subscribe";
  channel: "orderbook" | "trades" | "prices" | "positions";
  symbols: string[]; // e.g., ["BTC-USDT", "ETH-USDT"]
  request_id?: string;
}

// Order Operations
interface PlaceOrderRequest {
  type: "place_order";
  order: {
    symbol: string;
    side: "buy" | "sell";
    type: "limit" | "market" | "stop" | "stop_limit";
    price: number;
    size: number;
    stop_price?: number;
    time_in_force?: "GTC" | "IOC" | "FOK";
  };
  request_id?: string;
}

interface OrderUpdate {
  type: "order_update";
  data: {
    order: Order;
    status: "submitted" | "filled" | "partial" | "cancelled" | "rejected";
    fills?: Trade[];
  };
  request_id?: string;
  timestamp: number;
}

// Position Operations
interface OpenPositionRequest {
  type: "open_position";
  symbol: string;
  side: "buy" | "sell";
  size: number;
  leverage: number;
  request_id?: string;
}

interface PositionUpdate {
  type: "position_update";
  data: {
    position: MarginPosition;
    action: "opened" | "closed" | "liquidated" | "updated";
    realizedPnL?: number;
  };
  request_id?: string;
  timestamp: number;
}

// Market Data Broadcasts
interface OrderBookUpdate {
  type: "orderbook_update";
  data: {
    symbol: string;
    bids: [price: number, size: number][];
    asks: [price: number, size: number][];
    sequence: number;
  };
  timestamp: number;
}

interface PriceUpdate {
  type: "price_update";
  data: {
    symbol: string;
    price: number;
    bid: number;
    ask: number;
    volume_24h: number;
    change_24h: number;
  };
  timestamp: number;
}

interface TradeUpdate {
  type: "trade_update";
  data: {
    trade: Trade;
  };
  timestamp: number;
}
```

### 2. JSON-RPC API (DEX Backend)

```typescript
// Endpoint: POST https://dex.lux.network/rpc
// Content-Type: application/json

// Request format
interface JSONRPCRequest {
  jsonrpc: "2.0";
  method: string;
  params?: unknown;
  id: string | number;
}

// Methods

// orderbook.getBestBid
// Returns best bid for a symbol
interface GetBestBidParams {
  symbol: string;
}
interface GetBestBidResult {
  price: number;
  size: number;
}

// orderbook.getBestAsk
// Returns best ask for a symbol
interface GetBestAskParams {
  symbol: string;
}
interface GetBestAskResult {
  price: number;
  size: number;
}

// orderbook.getStats
// Returns order book statistics
interface GetStatsParams {
  symbol: string;
}
interface GetStatsResult {
  symbol: string;
  orders: number;
  trades: number;
  bid_depth: number;
  ask_depth: number;
  spread: number;
}

// price.getLatest
// Returns latest aggregated price
interface GetLatestPriceParams {
  symbol: string;
}
interface GetLatestPriceResult {
  symbol: string;
  price: number;
  confidence: number;
  timestamp: number;
  sources: string[];
}

// price.getTWAP
// Returns time-weighted average price
interface GetTWAPParams {
  symbol: string;
  window: number; // seconds
}
interface GetTWAPResult {
  symbol: string;
  twap: number;
  window: number;
}
```

### 3. Smart Contract Interfaces

```solidity
// IOracle.sol - Read interface for all DeFi protocols
interface IOracle {
    /// @notice Get price and timestamp for an asset
    function getPrice(address asset) external view returns (uint256 price, uint256 timestamp);

    /// @notice Get price only if within max age
    function getPriceIfFresh(address asset, uint256 maxAge) external view returns (uint256 price);

    /// @notice Simple price getter
    function price(address asset) external view returns (uint256);

    /// @notice Check if asset is supported
    function isSupported(address asset) external view returns (bool);

    /// @notice Batch price query
    function getPrices(address[] calldata assets)
        external view returns (uint256[] memory prices, uint256[] memory timestamps);

    /// @notice Get price with spread for perps (maximize or minimize)
    function getPriceForPerps(address asset, bool maximize) external view returns (uint256 price);

    /// @notice Check price consistency across sources
    function isPriceConsistent(address asset, uint256 maxDeviationBps) external view returns (bool);

    /// @notice Health check
    function health() external view returns (bool healthy, uint256 activeSourceCount);

    /// @notice Check if circuit breaker is tripped
    function isCircuitBreakerTripped(address asset) external view returns (bool);
}

// IOracleWriter.sol - Write interface for keepers
interface IOracleWriter {
    struct PriceUpdate {
        address asset;
        uint256 price;
        uint256 timestamp;
        uint256 confidence; // basis points 0-10000
        bytes32 source;
    }

    struct SignedPriceUpdate {
        PriceUpdate update;
        address validator;
        bytes signature;
    }

    /// @notice Write single price (keeper role required)
    function writePrice(address asset, uint256 price, uint256 timestamp) external;

    /// @notice Batch write prices
    function writePrices(PriceUpdate[] calldata updates) external;

    /// @notice Write signed price from validator
    function writeSignedPrice(SignedPriceUpdate calldata update) external;

    /// @notice Write quorum price (multiple validators)
    function writeQuorumPrice(SignedPriceUpdate[] calldata updates, uint256 minQuorum) external;

    /// @notice Check if address is authorized writer
    function isWriter(address account) external view returns (bool);

    /// @notice Check if address is validator
    function isValidator(address validator) external view returns (bool);

    /// @notice Get quorum requirement
    function getQuorum(address asset) external view returns (uint256);

    event PriceWritten(address indexed asset, uint256 price, uint256 timestamp, bytes32 source);
    event ValidatorPriceWritten(address indexed asset, uint256 price, address indexed validator);
    event QuorumPriceWritten(address indexed asset, uint256 price, uint256 validatorCount);
}
```

### 4. Keeper Service Configuration

```go
// pkg/keeper/keeper.go

// Config for the Oracle Keeper
type Config struct {
    // RPC endpoint for C-Chain
    RPCURL string `json:"rpc_url"`

    // OracleHub contract address
    ContractAddress string `json:"contract_address"`

    // Private key for signing transactions (hex, no 0x prefix)
    PrivateKey string `json:"private_key"`

    // Update interval (default: 30s)
    Interval time.Duration `json:"interval"`

    // Minimum price change to trigger update (basis points, default: 50 = 0.5%)
    MinChangeBps uint64 `json:"min_change_bps"`

    // Assets to track (token addresses)
    Assets []string `json:"assets"`

    // Maximum gas price (wei, 0 = no limit)
    MaxGasPrice uint64 `json:"max_gas_price"`
}

// Example configuration
var ExampleConfig = Config{
    RPCURL:          "http://localhost:9650/ext/bc/C/rpc",
    ContractAddress: "0x...", // OracleHub address
    PrivateKey:      "...",   // Keeper private key (KEEPER_ROLE)
    Interval:        30 * time.Second,
    MinChangeBps:    50,      // 0.5% minimum change
    Assets: []string{
        "0x...", // WLUX
        "0x...", // LETH
        "0x...", // LBTC
        "0x...", // LUSD
    },
    MaxGasPrice: 100_000_000_000, // 100 gwei
}
```

---

## Event Subscriptions

### 1. On-Chain Events (Smart Contracts)

```solidity
// OracleHub Events
event PriceWritten(address indexed asset, uint256 price, uint256 timestamp, bytes32 source);
event ValidatorPriceWritten(address indexed asset, uint256 price, address indexed validator);
event QuorumPriceWritten(address indexed asset, uint256 price, uint256 validatorCount);

// Oracle Events
event CircuitTripped(address indexed asset, uint256 oldPrice, uint256 newPrice, uint256 changeBps);
event CircuitReset(address indexed asset);
event SourceAdded(address indexed source, string name);
event SourceRemoved(address indexed source);

// Perps Vault Events
event IncreasePosition(bytes32 indexed key, address account, address collateralToken,
    address indexToken, uint256 collateralDelta, uint256 sizeDelta, bool isLong, uint256 price, uint256 fee);
event DecreasePosition(bytes32 indexed key, address account, address collateralToken,
    address indexToken, uint256 collateralDelta, uint256 sizeDelta, bool isLong, uint256 price, uint256 fee);
event LiquidatePosition(bytes32 indexed key, address account, address collateralToken,
    address indexToken, bool isLong, uint256 size, uint256 collateral, uint256 reserveAmount,
    int256 realisedPnl, uint256 markPrice);

// FastPriceFeed Events
event PriceData(address token, uint256 refPrice, uint256 fastPrice,
    uint256 cumulativeRefDelta, uint256 cumulativeFastDelta);
event MaxCumulativeDeltaDiffExceeded(address token, uint256 refPrice, uint256 fastPrice,
    uint256 cumulativeRefDelta, uint256 cumulativeFastDelta);
```

### 2. WebSocket Event Channels

```typescript
// Channel subscriptions
const channels = {
  // Market Data Channels (public)
  "orderbook:{symbol}": "Order book updates for symbol",
  "trades:{symbol}": "Trade executions for symbol",
  "prices:{symbol}": "Price updates for symbol",
  "liquidations": "Public liquidation events",
  "funding": "Funding rate updates",

  // Account Channels (authenticated)
  "orders": "User's order updates",
  "positions": "User's position updates",
  "balances": "User's balance updates",
  "fills": "User's trade fills",
  "margin": "Margin/collateral updates",
};

// Example subscription flow
const subscribeMessages = [
  // Public - order book for BTC and ETH
  { type: "subscribe", channel: "orderbook", symbols: ["BTC-USDT", "ETH-USDT"] },

  // Public - trades
  { type: "subscribe", channel: "trades", symbols: ["BTC-USDT"] },

  // Private - user's orders (requires auth)
  { type: "subscribe", channel: "orders", symbols: ["*"] },

  // Private - user's positions
  { type: "subscribe", channel: "positions", symbols: ["*"] },
];
```

### 3. Frontend Event Handling (React Hooks)

```typescript
// hooks/useWebSocket.ts
export function useDEXWebSocket() {
  const [socket, setSocket] = useState<WebSocket | null>(null);
  const [connected, setConnected] = useState(false);
  const [authenticated, setAuthenticated] = useState(false);

  // Subscription states
  const [orderbook, setOrderbook] = useState<OrderBookData | null>(null);
  const [prices, setPrices] = useState<Map<string, PriceData>>(new Map());
  const [positions, setPositions] = useState<Position[]>([]);

  useEffect(() => {
    const ws = new WebSocket(DEX_WS_URL);

    ws.onopen = () => {
      setConnected(true);
      // Auto-subscribe to default channels
      ws.send(JSON.stringify({
        type: "subscribe",
        channel: "prices",
        symbols: ["BTC-USDT", "ETH-USDT", "LUX-USDT"],
      }));
    };

    ws.onmessage = (event) => {
      const msg = JSON.parse(event.data);

      switch (msg.type) {
        case "auth_success":
          setAuthenticated(true);
          break;
        case "orderbook_update":
          setOrderbook(msg.data);
          break;
        case "price_update":
          setPrices(prev => new Map(prev).set(msg.data.symbol, msg.data));
          break;
        case "position_update":
          handlePositionUpdate(msg.data);
          break;
        case "error":
          console.error("DEX Error:", msg.error);
          break;
      }
    };

    setSocket(ws);
    return () => ws.close();
  }, []);

  return { socket, connected, authenticated, orderbook, prices, positions };
}
```

---

## Failover and Redundancy

### 1. Oracle Keeper High Availability

```
+-------------------------------------------------------------------+
|                    ORACLE KEEPER CLUSTER                           |
+-------------------------------------------------------------------+
|                                                                     |
|  +------------------+  +------------------+  +------------------+  |
|  |  Primary Keeper  |  |  Backup Keeper 1 |  |  Backup Keeper 2 |  |
|  |  (Region: US-W)  |  |  (Region: US-E)  |  |  (Region: EU)    |  |
|  +--------+---------+  +--------+---------+  +--------+---------+  |
|           |                     |                     |            |
|           v                     v                     v            |
|  +-------------------------------------------------------------+  |
|  |                    COORDINATION LAYER                        |  |
|  |  - Leader election (via Redis/etcd)                          |  |
|  |  - Health checks every 5s                                    |  |
|  |  - Automatic failover in <10s                                |  |
|  +-------------------------------------------------------------+  |
|           |                     |                     |            |
|           v                     v                     v            |
|  +-------------------------------------------------------------+  |
|  |                    PRICE SOURCES                             |  |
|  |  Primary:    Chainlink, Pyth Network                         |  |
|  |  Secondary:  C-Chain AMM TWAP, X-Chain orderbook             |  |
|  |  Tertiary:   External APIs (Binance, Coinbase)               |  |
|  +-------------------------------------------------------------+  |
|                                                                     |
+-------------------------------------------------------------------+
```

### 2. Failover Strategy

```yaml
# keeper-ha-config.yaml
cluster:
  name: "lux-oracle-keepers"
  coordination:
    type: "redis"  # or etcd
    endpoints:
      - "redis-1.lux.network:6379"
      - "redis-2.lux.network:6379"
      - "redis-3.lux.network:6379"

  nodes:
    - id: "keeper-1"
      region: "us-west-2"
      priority: 1  # Lower = higher priority
      endpoints:
        rpc: "https://api.lux.network/ext/bc/C/rpc"
        fallback_rpc:
          - "https://backup-1.lux.network/ext/bc/C/rpc"
          - "https://backup-2.lux.network/ext/bc/C/rpc"

    - id: "keeper-2"
      region: "us-east-1"
      priority: 2
      endpoints:
        rpc: "https://api-east.lux.network/ext/bc/C/rpc"

    - id: "keeper-3"
      region: "eu-west-1"
      priority: 3
      endpoints:
        rpc: "https://api-eu.lux.network/ext/bc/C/rpc"

  failover:
    health_check_interval: 5s
    failover_threshold: 3  # Consecutive failures before failover
    failover_timeout: 10s
    cooldown_period: 60s   # Before demoted leader can become leader again

  circuit_breaker:
    enabled: true
    max_price_change_bps: 1000  # 10%
    cooldown_period: 5m
    alert_threshold: 500        # 5% triggers alert

  gas:
    max_gas_price_gwei: 500
    priority_fee_gwei: 2
    gas_buffer_percent: 20

  retry:
    max_attempts: 3
    initial_backoff: 1s
    max_backoff: 30s
    backoff_multiplier: 2
```

### 3. Price Source Failover

```go
// pkg/price/aggregator.go - Source priority and failover

type SourcePriority struct {
    Primary   []string // Must have at least 1 healthy
    Secondary []string // Used if primary insufficient
    Tertiary  []string // Last resort
}

var DefaultPriority = SourcePriority{
    Primary: []string{
        "chainlink",    // On-chain, decentralized
        "pyth",         // Cross-chain, fast
    },
    Secondary: []string{
        "c-chain-twap", // AMM pools
        "x-chain",      // DEX orderbook
    },
    Tertiary: []string{
        "binance",      // CEX API
        "coinbase",     // CEX API
    },
}

// Aggregation rules:
// 1. At least 1 primary source must be healthy
// 2. Use weighted median across all healthy sources
// 3. If deviation > 5%, use primary sources only
// 4. If all primary fail, fallback to secondary (with alert)
// 5. Never use tertiary alone (emergency fallback only)
```

---

## Configuration Requirements

### 1. DEX Backend Configuration

```yaml
# dex-config.yaml
server:
  http_port: 8080
  ws_port: 8081
  grpc_port: 9090

  cors:
    allowed_origins:
      - "https://lux.exchange"
      - "https://dex.lux.network"
      - "https://amm.lux.network"
      - "http://localhost:3000"  # Development
    allowed_methods: ["GET", "POST", "OPTIONS"]
    allowed_headers: ["Authorization", "Content-Type"]

  rate_limit:
    requests_per_second: 100
    burst: 200

  auth:
    jwt_secret: "${DEX_JWT_SECRET}"
    token_expiry: 24h

blockchain:
  c_chain:
    rpc_url: "${C_CHAIN_RPC_URL}"
    ws_url: "${C_CHAIN_WS_URL}"
    chain_id: 96369

  contracts:
    oracle_hub: "0x..."
    vault: "0x..."
    router: "0x..."
    position_router: "0x..."
    amm_v2_router: "0xAe2cf1E403aAFE6C05A5b8Ef63EB19ba591d8511"
    amm_v3_router: "0x939bC0Bca6F9B9c52E6e3AD8A3C590b5d9B9D10E"

price:
  update_interval: 50ms
  stale_threshold: 5s
  min_sources: 2
  max_deviation_bps: 500

  sources:
    chainlink:
      enabled: true
      endpoint: "https://api.chain.link/..."
      weight: 1.0
    pyth:
      enabled: true
      endpoint: "https://hermes.pyth.network"
      weight: 0.9
    cchain_twap:
      enabled: true
      window: 5m
      weight: 0.7

keeper:
  enabled: true
  private_key: "${KEEPER_PRIVATE_KEY}"
  interval: 30s
  min_change_bps: 50
  max_gas_price_gwei: 500

trading:
  symbols:
    - symbol: "BTC-USDT"
      base: "0x..." # LBTC
      quote: "0x..." # LUSD
      tick_size: 0.01
      lot_size: 0.0001
      max_leverage: 100

    - symbol: "ETH-USDT"
      base: "0x..." # LETH
      quote: "0x..." # LUSD
      tick_size: 0.01
      lot_size: 0.001
      max_leverage: 50

    - symbol: "LUX-USDT"
      base: "0x..." # WLUX
      quote: "0x..." # LUSD
      tick_size: 0.0001
      lot_size: 0.1
      max_leverage: 20

margin:
  initial_margin_bps: 1000   # 10%
  maintenance_margin_bps: 500 # 5%
  liquidation_fee_bps: 50    # 0.5%
  insurance_fund: "0x..."
```

### 2. Exchange Frontend Configuration

```typescript
// constants/config.ts
export const DEX_CONFIG = {
  // Network Configuration
  networks: {
    lux: {
      chainId: 96369,
      name: "Lux C-Chain",
      rpcUrl: "https://api.lux.network/ext/bc/C/rpc",
      wsUrl: "wss://api.lux.network/ext/bc/C/ws",
      explorerUrl: "https://explore.lux.network",
    },
    luxTestnet: {
      chainId: 96368,
      name: "Lux Testnet",
      rpcUrl: "https://api.lux-test.network/ext/bc/C/rpc",
      wsUrl: "wss://api.lux-test.network/ext/bc/C/ws",
      explorerUrl: "https://explore.lux-test.network",
    },
    zoo: {
      chainId: 200200,
      name: "Zoo EVM",
      rpcUrl: "https://api.zoo.network/ext/bc/C/rpc",
      explorerUrl: "https://explore.zoo.network",
    },
  },

  // DEX Backend Endpoints
  dex: {
    http: process.env.NEXT_PUBLIC_DEX_HTTP_URL || "https://dex.lux.network",
    ws: process.env.NEXT_PUBLIC_DEX_WS_URL || "wss://dex.lux.network/ws",
    rpc: process.env.NEXT_PUBLIC_DEX_RPC_URL || "https://dex.lux.network/rpc",
  },

  // Contract Addresses (by chain)
  contracts: {
    96369: { // Lux Mainnet
      WLUX: "0x52c84043cd9c865236f11d9fc9f56aa003c1f922",
      LUSD: "0x...",
      LETH: "0x...",
      LBTC: "0x...",
      V2_FACTORY: "0xD173926A10A0C4eCd3A51B1422270b65Df0551c1",
      V2_ROUTER: "0xAe2cf1E403aAFE6C05A5b8Ef63EB19ba591d8511",
      V3_FACTORY: "0x80bBc7C4C7a59C899D1B37BC14539A22D5830a84",
      V3_ROUTER: "0x939bC0Bca6F9B9c52E6e3AD8A3C590b5d9B9D10E",
      MULTICALL: "0xd25F88CBdAe3c2CCA3Bb75FC4E723b44C0Ea362F",
      QUOTER: "0x12e2B76FaF4dDA5a173a4532916bb6Bfa3645275",
      NFT_POSITION_MANAGER: "0x7a4C48B9dae0b7c396569b34042fcA604150Ee28",
      ORACLE_HUB: "0x...",
      VAULT: "0x...",
      POSITION_ROUTER: "0x...",
    },
    96368: { // Lux Testnet
      // Same pattern
    },
  },

  // Trading Configuration
  trading: {
    defaultSlippageBps: 50, // 0.5%
    maxSlippageBps: 500,    // 5%
    deadlineMinutes: 20,
    refreshInterval: 1000,  // 1 second
  },
};
```

### 3. Smart Contract Deployment Configuration

```typescript
// script/DeployFullStack.s.sol configuration

// Required Environment Variables
const DEPLOYMENT_CONFIG = {
  // Deployer
  DEPLOYER_PRIVATE_KEY: process.env.DEPLOYER_PRIVATE_KEY,
  DEPLOYER_ADDRESS: "Derived from private key",

  // Treasury
  TREASURY_ADDRESS: "0x9011E888251AB053B7bD1cdB598Db4f9DEd94714",

  // Oracle Configuration
  ORACLE_CONFIG: {
    defaultMaxAge: 3600,        // 1 hour
    maxDeviationBps: 500,       // 5%
    minSources: 1,
    defaultSpreadBps: 10,       // 0.1%
    circuitBreakerMaxChangeBps: 1000, // 10%
    cooldownPeriod: 300,        // 5 minutes
  },

  // Perps Configuration
  PERPS_CONFIG: {
    maxLeverage: 100,
    initialMarginBps: 1000,     // 10%
    maintenanceMarginBps: 500,  // 5%
    liquidationFeeBps: 50,      // 0.5%
    fundingInterval: 3600,      // 1 hour
    maxFundingRateBps: 100,     // 1%
  },

  // Fee Configuration
  FEE_CONFIG: {
    swapFeeBps: 30,             // 0.3%
    stableSwapFeeBps: 4,        // 0.04%
    marginFeeBps: 10,           // 0.1%
    performanceFeeBps: 1000,    // 10% of profits
  },
};
```

---

## Deployment Sequence

### Phase 1: Infrastructure Setup

```bash
# 1. Start local development environment
anvil --chain-id 96369 --mnemonic "$LUX_MNEMONIC" --balance 10000000000

# 2. Deploy core token contracts
forge script script/DeployFullStack.s.sol:DeployFullStack \
  --rpc-url http://127.0.0.1:8545 \
  --broadcast -vvv \
  --sig "deployPhase1()"

# Deploys: WLUX, LUSD, LETH, LBTC
```

### Phase 2: Oracle System

```bash
# 3. Deploy Oracle contracts
forge script script/DeployFullStack.s.sol:DeployFullStack \
  --rpc-url http://127.0.0.1:8545 \
  --broadcast -vvv \
  --sig "deployPhase2()"

# Deploys: Oracle, OracleHub, ChainlinkAdapter, PythAdapter

# 4. Configure Oracle sources
cast send $ORACLE_HUB "addSource(address)" $CHAINLINK_ADAPTER --rpc-url ... --private-key ...
cast send $ORACLE_HUB "addWriter(address)" $KEEPER_ADDRESS --rpc-url ... --private-key ...
```

### Phase 3: DEX Contracts

```bash
# 5. Deploy AMM contracts
forge script script/DeployFullStack.s.sol:DeployFullStack \
  --rpc-url http://127.0.0.1:8545 \
  --broadcast -vvv \
  --sig "deployPhase3()"

# Deploys: AMMV2Factory, AMMV2Router, AMMV3Factory, AMMV3Router, etc.

# 6. Create initial LP pools
cast send $V2_FACTORY "createPair(address,address)" $WLUX $LUSD --rpc-url ... --private-key ...
```

### Phase 4: Perps Protocol

```bash
# 7. Deploy Perps contracts
forge script script/DeployFullStack.s.sol:DeployFullStack \
  --rpc-url http://127.0.0.1:8545 \
  --broadcast -vvv \
  --sig "deployPhase4()"

# Deploys: Vault, Router, PositionRouter, LLPManager, FastPriceFeed, etc.

# 8. Configure Perps
cast send $VAULT "setTokenConfig(...)" --rpc-url ... --private-key ...
cast send $FAST_PRICE_FEED "setVaultPriceFeed(address)" $VAULT_PRICE_FEED --rpc-url ... --private-key ...
```

### Phase 5: DEX Backend

```bash
# 9. Start DEX backend
cd ~/work/lux/dex
go build -o lxdex ./cmd/main.go

# 10. Configure and run
export C_CHAIN_RPC_URL="http://127.0.0.1:8545"
export ORACLE_HUB_ADDRESS="0x..."
export KEEPER_PRIVATE_KEY="..."

./lxdex --config dex-config.yaml

# 11. Verify keeper is writing prices
curl -X POST http://localhost:8080/rpc \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"price.getLatest","params":{"symbol":"BTC-USDT"},"id":1}'
```

### Phase 6: Frontend

```bash
# 12. Start Exchange frontend
cd ~/work/lux/exchange
pnpm install

# 13. Configure environment
cat > .env.local << EOF
NEXT_PUBLIC_DEX_HTTP_URL=http://localhost:8080
NEXT_PUBLIC_DEX_WS_URL=ws://localhost:8081
NEXT_PUBLIC_C_CHAIN_RPC_URL=http://localhost:8545
NEXT_PUBLIC_CHAIN_ID=96369
EOF

# 14. Start development server
pnpm dev

# 15. Verify integration
open http://localhost:3000
```

### Deployment Verification Checklist

```markdown
## Infrastructure
- [ ] Anvil/luxd running on correct chain ID
- [ ] All deployer accounts funded

## Smart Contracts
- [ ] Core tokens deployed (WLUX, LUSD, LETH, LBTC)
- [ ] Oracle system deployed and sources configured
- [ ] AMM V2/V3 deployed with initial pools
- [ ] Perps protocol deployed and configured
- [ ] All roles and permissions set correctly

## DEX Backend
- [ ] Keeper writing prices to OracleHub
- [ ] WebSocket server accepting connections
- [ ] JSON-RPC API responding
- [ ] Price sources healthy
- [ ] Trading engine processing orders

## Frontend
- [ ] Connects to correct RPC endpoint
- [ ] WebSocket subscription working
- [ ] AMM swaps executing
- [ ] Perps positions opening/closing
- [ ] Price feeds updating in UI
```

---

## Security Considerations

### 1. Access Control

| Component | Role | Permissions |
|-----------|------|-------------|
| OracleHub | ADMIN_ROLE | Configure quorum, add/remove writers |
| OracleHub | WRITER_ROLE | Write prices (keepers) |
| OracleHub | VALIDATOR_ROLE | Submit signed prices |
| Oracle | ORACLE_ADMIN | Add/remove sources, set config |
| Oracle | GUARDIAN_ROLE | Pause, reset circuit breakers |
| FastPriceFeed | gov | Configure parameters |
| FastPriceFeed | updater | Submit prices |
| FastPriceFeed | signer | Vote to disable fast price |

### 2. Price Manipulation Protection

1. **Circuit Breakers**: Max 10% price change per update
2. **Quorum Requirement**: Multiple validators must agree
3. **Deviation Checks**: Reject prices >5% from median
4. **Staleness Checks**: Reject prices older than threshold
5. **Source Diversity**: Require multiple independent sources

### 3. Key Security Practices

1. **Keeper Keys**: Use HSM or secure key management
2. **API Keys**: Rotate regularly, use short-lived JWTs
3. **RPC Endpoints**: Use private endpoints for sensitive operations
4. **Rate Limiting**: Prevent DoS on all public endpoints
5. **Input Validation**: Sanitize all user inputs

---

## Monitoring and Alerts

### Metrics to Monitor

```yaml
# Prometheus metrics endpoints

oracle_keeper:
  - oracle_price_write_total
  - oracle_price_write_latency_seconds
  - oracle_price_staleness_seconds
  - oracle_circuit_breaker_trips_total
  - oracle_source_health

dex_backend:
  - dex_orders_total
  - dex_trades_total
  - dex_ws_connections_active
  - dex_api_requests_total
  - dex_api_latency_seconds

perps:
  - perps_positions_open
  - perps_liquidations_total
  - perps_funding_rate
  - perps_open_interest_usd

alerts:
  - name: "Oracle Price Stale"
    condition: "oracle_price_staleness_seconds > 300"
    severity: "critical"

  - name: "Circuit Breaker Tripped"
    condition: "oracle_circuit_breaker_trips_total increase > 0"
    severity: "warning"

  - name: "High Liquidation Rate"
    condition: "rate(perps_liquidations_total[5m]) > 10"
    severity: "warning"
```

---

## Appendix

### A. Contract Addresses (Production)

| Contract | Lux Mainnet (96369) | Lux Testnet (96368) | Zoo (200200) |
|----------|---------------------|---------------------|--------------|
| WLUX | `0x52c84043cd9c865236f11d9fc9f56aa003c1f922` | TBD | TBD |
| V2 Factory | `0xD173926A10A0C4eCd3A51B1422270b65Df0551c1` | Same | Same |
| V2 Router | `0xAe2cf1E403aAFE6C05A5b8Ef63EB19ba591d8511` | Same | Same |
| V3 Factory | `0x80bBc7C4C7a59C899D1B37BC14539A22D5830a84` | Same | Same |
| V3 Router | `0x939bC0Bca6F9B9c52E6e3AD8A3C590b5d9B9D10E` | Same | Same |
| Multicall | `0xd25F88CBdAe3c2CCA3Bb75FC4E723b44C0Ea362F` | Same | Same |
| Quoter | `0x12e2B76FaF4dDA5a173a4532916bb6Bfa3645275` | Same | Same |

### B. RPC Endpoints

| Network | HTTP RPC | WebSocket | Chain ID |
|---------|----------|-----------|----------|
| Lux Mainnet | `https://api.lux.network/ext/bc/C/rpc` | `wss://api.lux.network/ext/bc/C/ws` | 96369 |
| Lux Testnet | `https://api.lux-test.network/ext/bc/C/rpc` | `wss://api.lux-test.network/ext/bc/C/ws` | 96368 |
| Zoo Mainnet | `https://api.zoo.network/ext/bc/C/rpc` | TBD | 200200 |
| Local (Anvil) | `http://localhost:8545` | `ws://localhost:8545` | 96369 |
| Local (luxd) | `http://localhost:9650/ext/bc/C/rpc` | `ws://localhost:9650/ext/bc/C/ws` | 96369 |

### C. WebSocket API Reference

See full WebSocket API documentation in section "API Contract Definitions".

---

*Document End*
