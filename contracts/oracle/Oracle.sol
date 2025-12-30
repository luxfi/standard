// SPDX-License-Identifier: MIT
pragma solidity ^0.8.31;

import {IOracle} from "./IOracle.sol";
import {IOracleSource} from "./interfaces/IOracleSource.sol";
import {IOracleStrategy} from "./interfaces/IOracleStrategy.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";

/// @title Oracle
/// @notice THE standard oracle for all Lux DeFi protocols
/// @dev Aggregates Chainlink, Pyth, TWAP, DEX precompile sources
/// @dev Downstream apps (Perps, Lending, AMM, Flash loans) use this single contract
/// @dev Includes circuit breakers, heartbeat monitoring, batch queries
contract Oracle is IOracle, AccessControl, Pausable {
    bytes32 public constant ORACLE_ADMIN = keccak256("ORACLE_ADMIN");
    bytes32 public constant GUARDIAN_ROLE = keccak256("GUARDIAN_ROLE");

    // =========================================================================
    // State
    // =========================================================================

    /// @notice Registered oracle sources
    IOracleSource[] public sources;

    /// @notice Source name to index (1-indexed, 0 = not found)
    mapping(string => uint256) public sourceIndex;

    /// @notice Aggregation strategy (default: median)
    IOracleStrategy public strategy;

    /// @notice Default staleness threshold
    uint256 public defaultMaxAge = 1 hours;

    /// @notice Maximum deviation between sources (basis points)
    uint256 public maxDeviationBps = 500; // 5%

    /// @notice Minimum sources required for valid price
    uint256 public minSources = 1;

    /// @notice Per-asset spread for perps (basis points)
    mapping(address => uint256) public spreadBps;

    /// @notice Default spread for perps
    uint256 public defaultSpreadBps = 10; // 0.1%

    // =========================================================================
    // Circuit Breaker State
    // =========================================================================

    /// @notice Maximum price change per update (basis points)
    uint256 public maxPriceChangeBps = 1000; // 10%

    /// @notice Cooldown after circuit breaker trips
    uint256 public cooldownPeriod = 5 minutes;

    /// @notice Per-asset circuit breaker state
    struct CircuitState {
        uint256 lastPrice;
        uint256 lastUpdate;
        bool tripped;
        uint256 tripTime;
    }
    mapping(address => CircuitState) public circuitState;

    // =========================================================================
    // Heartbeat State
    // =========================================================================

    /// @notice Required heartbeat interval per source
    uint256 public heartbeatInterval = 1 hours;

    /// @notice Last successful heartbeat per source
    mapping(address => uint256) public lastHeartbeat;

    // =========================================================================
    // Errors
    // =========================================================================

    error NoSourcesAvailable();
    error AssetNotSupported(address asset);
    error PriceDeviation(address asset, uint256 deviation);
    error StalePrice(address asset, uint256 age);
    error InsufficientSources(address asset, uint256 count);
    error CircuitBreakerTripped(address asset);
    error InvalidPrice();

    // =========================================================================
    // Events
    // =========================================================================

    event SourceAdded(address indexed source, string name);
    event SourceRemoved(address indexed source);
    event StrategyUpdated(address indexed strategy);
    event ConfigUpdated(uint256 maxAge, uint256 maxDeviationBps, uint256 minSources);
    event CircuitTripped(address indexed asset, uint256 oldPrice, uint256 newPrice, uint256 changeBps);
    event CircuitReset(address indexed asset);

    // =========================================================================
    // Constructor
    // =========================================================================

    constructor(address _strategy) {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(ORACLE_ADMIN, msg.sender);
        _grantRole(GUARDIAN_ROLE, msg.sender);

        if (_strategy != address(0)) {
            strategy = IOracleStrategy(_strategy);
        }
    }

    // =========================================================================
    // Core Price Functions (IOracle)
    // =========================================================================

    /// @inheritdoc IOracle
    function getPrice(address asset) external view override returns (uint256 price_, uint256 timestamp) {
        _checkCircuitBreaker(asset);

        (uint256[] memory prices, uint256[] memory timestamps, uint256 count) = _collectPrices(asset);

        if (count == 0) revert AssetNotSupported(asset);
        if (count < minSources) revert InsufficientSources(asset, count);

        // Aggregate using strategy (default: median)
        price_ = _aggregate(prices, count);
        timestamp = _maxTimestamp(timestamps, count);

        // Validate deviation
        uint256 deviation = _maxDeviation(prices, count, price_);
        if (deviation > maxDeviationBps) revert PriceDeviation(asset, deviation);
    }

    /// @inheritdoc IOracle
    function getPriceIfFresh(address asset, uint256 maxAge) external view override returns (uint256 price_) {
        _checkCircuitBreaker(asset);

        (uint256[] memory prices, uint256[] memory timestamps, uint256 count) = _collectPrices(asset);

        if (count == 0) revert AssetNotSupported(asset);

        // Check freshness
        for (uint256 i = 0; i < count; i++) {
            if (block.timestamp - timestamps[i] > maxAge) {
                revert StalePrice(asset, block.timestamp - timestamps[i]);
            }
        }

        price_ = _aggregate(prices, count);
    }

    /// @inheritdoc IOracle
    function price(address asset) external view override returns (uint256) {
        _checkCircuitBreaker(asset);

        (uint256[] memory prices,, uint256 count) = _collectPrices(asset);
        if (count == 0) revert AssetNotSupported(asset);

        return _aggregate(prices, count);
    }

    /// @inheritdoc IOracle
    function isSupported(address asset) external view override returns (bool) {
        for (uint256 i = 0; i < sources.length; i++) {
            if (sources[i].isSupported(asset)) return true;
        }
        return false;
    }

    // =========================================================================
    // Batch Operations
    // =========================================================================

    /// @inheritdoc IOracle
    function getPrices(address[] calldata assets)
        external view override returns (uint256[] memory prices_, uint256[] memory timestamps)
    {
        prices_ = new uint256[](assets.length);
        timestamps = new uint256[](assets.length);

        for (uint256 i = 0; i < assets.length; i++) {
            try this.getPrice(assets[i]) returns (uint256 p, uint256 t) {
                prices_[i] = p;
                timestamps[i] = t;
            } catch {
                prices_[i] = 0;
                timestamps[i] = 0;
            }
        }
    }

    // =========================================================================
    // Perps-Specific Functions
    // =========================================================================

    /// @inheritdoc IOracle
    function getPriceForPerps(address asset, bool maximize) external view override returns (uint256 price_) {
        _checkCircuitBreaker(asset);

        (uint256[] memory prices,, uint256 count) = _collectPrices(asset);
        if (count == 0) revert AssetNotSupported(asset);

        // For perps, optionally use min/max instead of median
        if (maximize) {
            price_ = _max(prices, count);
        } else {
            price_ = _min(prices, count);
        }

        // Apply spread
        uint256 spread = spreadBps[asset] > 0 ? spreadBps[asset] : defaultSpreadBps;
        if (maximize) {
            price_ = price_ * (10000 + spread) / 10000;
        } else {
            price_ = price_ * (10000 - spread) / 10000;
        }
    }

    /// @inheritdoc IOracle
    function isPriceConsistent(address asset, uint256 _maxDeviationBps) external view override returns (bool) {
        (uint256[] memory prices,, uint256 count) = _collectPrices(asset);
        if (count < 2) return true;

        uint256 median = _median(prices, count);
        return _maxDeviation(prices, count, median) <= _maxDeviationBps;
    }

    // =========================================================================
    // Health & Monitoring
    // =========================================================================

    /// @inheritdoc IOracle
    function health() external view override returns (bool healthy, uint256 activeSourceCount) {
        activeSourceCount = 0;

        for (uint256 i = 0; i < sources.length; i++) {
            (bool srcHealthy, ) = sources[i].health();
            if (srcHealthy) activeSourceCount++;
        }

        healthy = activeSourceCount >= minSources && !paused();
    }

    /// @inheritdoc IOracle
    function isCircuitBreakerTripped(address asset) external view override returns (bool) {
        CircuitState memory state = circuitState[asset];
        return state.tripped && block.timestamp < state.tripTime + cooldownPeriod;
    }

    // =========================================================================
    // Source Management (Admin)
    // =========================================================================

    /// @notice Add an oracle source
    function addSource(IOracleSource _source) external onlyRole(ORACLE_ADMIN) {
        string memory name = _source.source();
        sources.push(_source);
        sourceIndex[name] = sources.length; // 1-indexed
        lastHeartbeat[address(_source)] = block.timestamp;
        emit SourceAdded(address(_source), name);
    }

    /// @notice Remove an oracle source by index
    function removeSource(uint256 index) external onlyRole(ORACLE_ADMIN) {
        require(index < sources.length, "Invalid index");
        address removed = address(sources[index]);
        sources[index] = sources[sources.length - 1];
        sources.pop();
        emit SourceRemoved(removed);
    }

    /// @notice Set aggregation strategy
    function setStrategy(IOracleStrategy _strategy) external onlyRole(ORACLE_ADMIN) {
        strategy = _strategy;
        emit StrategyUpdated(address(_strategy));
    }

    /// @notice Update configuration
    function setConfig(uint256 _maxAge, uint256 _maxDeviationBps, uint256 _minSources)
        external onlyRole(ORACLE_ADMIN)
    {
        defaultMaxAge = _maxAge;
        maxDeviationBps = _maxDeviationBps;
        minSources = _minSources;
        emit ConfigUpdated(_maxAge, _maxDeviationBps, _minSources);
    }

    /// @notice Set per-asset spread for perps
    function setSpread(address asset, uint256 _spreadBps) external onlyRole(ORACLE_ADMIN) {
        spreadBps[asset] = _spreadBps;
    }

    /// @notice Set circuit breaker parameters
    function setCircuitBreakerConfig(uint256 _maxPriceChangeBps, uint256 _cooldownPeriod)
        external onlyRole(GUARDIAN_ROLE)
    {
        maxPriceChangeBps = _maxPriceChangeBps;
        cooldownPeriod = _cooldownPeriod;
    }

    /// @notice Manually reset circuit breaker
    function resetCircuitBreaker(address asset) external onlyRole(GUARDIAN_ROLE) {
        circuitState[asset].tripped = false;
        emit CircuitReset(asset);
    }

    /// @notice Pause oracle (emergency)
    function pause() external onlyRole(GUARDIAN_ROLE) {
        _pause();
    }

    /// @notice Unpause oracle
    function unpause() external onlyRole(GUARDIAN_ROLE) {
        _unpause();
    }

    // =========================================================================
    // Circuit Breaker Logic (for writes)
    // =========================================================================

    /// @notice Update circuit breaker state (called by keepers after price changes)
    /// @param asset The asset to update
    /// @param newPrice The new price
    /// @return accepted True if price is within circuit breaker limits
    function updateCircuitBreaker(address asset, uint256 newPrice) external returns (bool accepted) {
        CircuitState storage state = circuitState[asset];

        // Check cooldown
        if (state.tripped && block.timestamp < state.tripTime + cooldownPeriod) {
            return false;
        }

        // Auto-reset after cooldown
        if (state.tripped) {
            state.tripped = false;
            emit CircuitReset(asset);
        }

        // First price - always accept
        if (state.lastPrice == 0) {
            state.lastPrice = newPrice;
            state.lastUpdate = block.timestamp;
            return true;
        }

        // Calculate change
        uint256 changeBps = _calculateChangeBps(state.lastPrice, newPrice);

        if (changeBps > maxPriceChangeBps) {
            state.tripped = true;
            state.tripTime = block.timestamp;
            emit CircuitTripped(asset, state.lastPrice, newPrice, changeBps);
            return false;
        }

        // Accept price
        state.lastPrice = newPrice;
        state.lastUpdate = block.timestamp;
        return true;
    }

    // =========================================================================
    // View Functions
    // =========================================================================

    /// @notice Get all prices from all sources for an asset
    function getAllPrices(address asset)
        external view returns (uint256[] memory allPrices, string[] memory sourceNames)
    {
        allPrices = new uint256[](sources.length);
        sourceNames = new string[](sources.length);

        for (uint256 i = 0; i < sources.length; i++) {
            sourceNames[i] = sources[i].source();
            if (sources[i].isSupported(asset)) {
                try sources[i].getPrice(asset) returns (uint256 p, uint256) {
                    allPrices[i] = p;
                } catch {
                    allPrices[i] = 0;
                }
            }
        }
    }

    /// @notice Get number of sources
    function sourceCount() external view returns (uint256) {
        return sources.length;
    }

    // =========================================================================
    // Internal Functions
    // =========================================================================

    function _checkCircuitBreaker(address asset) internal view {
        CircuitState memory state = circuitState[asset];
        if (state.tripped && block.timestamp < state.tripTime + cooldownPeriod) {
            revert CircuitBreakerTripped(asset);
        }
    }

    function _collectPrices(address asset)
        internal view returns (uint256[] memory prices, uint256[] memory timestamps, uint256 count)
    {
        prices = new uint256[](sources.length);
        timestamps = new uint256[](sources.length);
        count = 0;

        for (uint256 i = 0; i < sources.length; i++) {
            if (sources[i].isSupported(asset)) {
                try sources[i].getPrice(asset) returns (uint256 p, uint256 t) {
                    if (p > 0) {
                        prices[count] = p;
                        timestamps[count] = t;
                        count++;
                    }
                } catch {}
            }
        }
    }

    function _aggregate(uint256[] memory prices, uint256 count) internal view returns (uint256) {
        if (count == 0) return 0;
        if (count == 1) return prices[0];

        // Use strategy if configured, otherwise default to median
        if (address(strategy) != address(0)) {
            return strategy.aggregate(prices, count);
        }
        return _median(prices, count);
    }

    function _median(uint256[] memory arr, uint256 len) internal pure returns (uint256) {
        if (len == 0) return 0;
        if (len == 1) return arr[0];

        // Copy and sort
        uint256[] memory sorted = new uint256[](len);
        for (uint256 i = 0; i < len; i++) {
            sorted[i] = arr[i];
        }

        for (uint256 i = 0; i < len; i++) {
            for (uint256 j = i + 1; j < len; j++) {
                if (sorted[i] > sorted[j]) {
                    (sorted[i], sorted[j]) = (sorted[j], sorted[i]);
                }
            }
        }

        uint256 mid = len / 2;
        if (len % 2 == 0) {
            return (sorted[mid - 1] + sorted[mid]) / 2;
        }
        return sorted[mid];
    }

    function _min(uint256[] memory arr, uint256 len) internal pure returns (uint256) {
        uint256 minVal = arr[0];
        for (uint256 i = 1; i < len; i++) {
            if (arr[i] < minVal) minVal = arr[i];
        }
        return minVal;
    }

    function _max(uint256[] memory arr, uint256 len) internal pure returns (uint256) {
        uint256 maxVal = arr[0];
        for (uint256 i = 1; i < len; i++) {
            if (arr[i] > maxVal) maxVal = arr[i];
        }
        return maxVal;
    }

    function _maxTimestamp(uint256[] memory arr, uint256 len) internal pure returns (uint256 max) {
        for (uint256 i = 0; i < len; i++) {
            if (arr[i] > max) max = arr[i];
        }
    }

    function _maxDeviation(uint256[] memory arr, uint256 len, uint256 refPrice)
        internal pure returns (uint256 maxDev)
    {
        for (uint256 i = 0; i < len; i++) {
            uint256 dev = arr[i] > refPrice
                ? ((arr[i] - refPrice) * 10000) / refPrice
                : ((refPrice - arr[i]) * 10000) / refPrice;
            if (dev > maxDev) maxDev = dev;
        }
    }

    function _calculateChangeBps(uint256 oldPrice, uint256 newPrice) internal pure returns (uint256) {
        if (oldPrice == 0) return 0;
        uint256 diff = newPrice > oldPrice ? newPrice - oldPrice : oldPrice - newPrice;
        return (diff * 10000) / oldPrice;
    }
}
