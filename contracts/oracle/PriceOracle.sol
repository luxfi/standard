// SPDX-License-Identifier: MIT
pragma solidity ^0.8.31;

import { AccessControl } from "@openzeppelin/contracts/access/AccessControl.sol";
import { Pausable } from "@openzeppelin/contracts/utils/Pausable.sol";
import { IPriceOracle } from "../interfaces/oracle/IPriceOracle.sol";

/**
 * @title PriceOracle
 * @author Lux Industries
 * @notice Unified price oracle supporting equities, commodities, FX, and crypto
 * @dev Aggregates prices from Chainlink, Pyth, or custom feed sources with
 *      staleness checks, fallback feeds, and TWAP computation
 *
 * Key features:
 * - Primary + fallback feed per asset for redundancy
 * - Configurable staleness threshold per asset (default 1 hour)
 * - Cross-rate computation for FX pairs (base/quote via USD)
 * - Time-weighted average price (TWAP) over configurable window
 * - Compatible with IOracle (Options.sol, Futures.sol) via getPrice(asset)
 */
contract PriceOracle is IPriceOracle, AccessControl, Pausable {
    // ═══════════════════════════════════════════════════════════════════════
    // TYPES
    // ═══════════════════════════════════════════════════════════════════════

    /// @dev AggregatorV3-compatible feed interface (Chainlink, Pyth adapters)
    struct FeedConfig {
        address primary; // Primary price feed address
        address fallback_; // Fallback price feed address (0 = none)
        uint256 maxAge; // Max staleness in seconds (0 = use default)
        uint8 decimals; // Feed decimals (for normalization to 18)
    }

    /// @dev TWAP observation stored per asset
    struct Observation {
        uint256 price;
        uint256 timestamp;
    }

    // ═══════════════════════════════════════════════════════════════════════
    // CONSTANTS
    // ═══════════════════════════════════════════════════════════════════════

    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant KEEPER_ROLE = keccak256("KEEPER_ROLE");

    uint256 public constant PRECISION = 1e18;
    uint256 public constant DEFAULT_MAX_AGE = 1 hours;
    uint256 public constant MAX_OBSERVATIONS = 24;

    // ═══════════════════════════════════════════════════════════════════════
    // STATE
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice Feed configuration per asset
    mapping(address => FeedConfig) public feeds;

    /// @notice Circular buffer of TWAP observations per asset
    mapping(address => Observation[MAX_OBSERVATIONS]) public observations;

    /// @notice Current observation index per asset
    mapping(address => uint256) public observationIndex;

    /// @notice Number of observations stored per asset (up to MAX_OBSERVATIONS)
    mapping(address => uint256) public observationCount;

    // ═══════════════════════════════════════════════════════════════════════
    // EVENTS
    // ═══════════════════════════════════════════════════════════════════════

    event FeedSet(address indexed asset, address primary, address fallback_, uint256 maxAge, uint8 decimals);
    event FeedRemoved(address indexed asset);
    event PriceObserved(address indexed asset, uint256 price, uint256 timestamp);

    // ═══════════════════════════════════════════════════════════════════════
    // ERRORS
    // ═══════════════════════════════════════════════════════════════════════

    error AssetNotSupported(address asset);
    error StalePrice(address asset, uint256 age, uint256 maxAge);
    error FeedCallFailed(address feed);
    error InvalidFeed();
    error ZeroAddress();
    error InvalidWindow();

    // ═══════════════════════════════════════════════════════════════════════
    // CONSTRUCTOR
    // ═══════════════════════════════════════════════════════════════════════

    constructor(address _admin) {
        if (_admin == address(0)) revert ZeroAddress();

        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        _grantRole(ADMIN_ROLE, _admin);
        _grantRole(KEEPER_ROLE, _admin);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // CORE PRICE FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════

    /// @inheritdoc IPriceOracle
    function getPrice(address asset) external view override whenNotPaused returns (uint256 price, uint256 timestamp) {
        return _getPrice(asset);
    }

    /// @inheritdoc IPriceOracle
    function getRate(address base, address quote)
        external
        view
        override
        whenNotPaused
        returns (uint256 rate, uint256 timestamp)
    {
        return _getRate(base, quote);
    }

    /// @inheritdoc IPriceOracle
    function getPriceIfFresh(address asset, uint256 maxAge)
        external
        view
        override
        whenNotPaused
        returns (uint256 price)
    {
        uint256 ts;
        (price, ts) = _getPrice(asset);
        uint256 age = block.timestamp - ts;
        if (age > maxAge) revert StalePrice(asset, age, maxAge);
    }

    /// @inheritdoc IPriceOracle
    function getRateIfFresh(address base, address quote, uint256 maxAge)
        external
        view
        override
        whenNotPaused
        returns (uint256 rate)
    {
        uint256 ts;
        (rate, ts) = _getRate(base, quote);
        uint256 age = block.timestamp - ts;
        if (age > maxAge) revert StalePrice(base, age, maxAge);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // TWAP
    // ═══════════════════════════════════════════════════════════════════════

    /// @inheritdoc IPriceOracle
    function getTWAP(address asset, uint256 window) external view override whenNotPaused returns (uint256 twap) {
        if (window == 0) revert InvalidWindow();
        if (!isSupported(asset)) revert AssetNotSupported(asset);

        uint256 count = observationCount[asset];
        if (count == 0) {
            // No observations — fall back to current price
            (twap,) = _getPrice(asset);
            return twap;
        }

        uint256 cutoff = block.timestamp > window ? block.timestamp - window : 0;
        uint256 weightedSum;
        uint256 totalWeight;
        uint256 idx = observationIndex[asset];

        for (uint256 i = 0; i < count; i++) {
            // Walk backwards through circular buffer
            uint256 pos = idx >= i ? idx - i : MAX_OBSERVATIONS - (i - idx);
            Observation memory obs = observations[asset][pos];

            if (obs.timestamp < cutoff) break;

            // Weight = time the price was valid (until next observation or now)
            uint256 nextTs;
            if (i == 0) {
                nextTs = block.timestamp;
            } else {
                uint256 prevPos = idx >= (i - 1) ? idx - (i - 1) : MAX_OBSERVATIONS - ((i - 1) - idx);
                nextTs = observations[asset][prevPos].timestamp;
            }
            uint256 duration = nextTs - obs.timestamp;
            weightedSum += obs.price * duration;
            totalWeight += duration;
        }

        if (totalWeight == 0) {
            (twap,) = _getPrice(asset);
            return twap;
        }

        twap = weightedSum / totalWeight;
    }

    /// @inheritdoc IPriceOracle
    function isSupported(address asset) public view override returns (bool) {
        return feeds[asset].primary != address(0);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // KEEPER FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice Record a TWAP observation for an asset from its current feed price
    /// @param asset The asset to observe
    function observe(address asset) external onlyRole(KEEPER_ROLE) {
        if (!isSupported(asset)) revert AssetNotSupported(asset);

        (uint256 price, uint256 timestamp) = _getPrice(asset);

        uint256 nextIdx = (observationIndex[asset] + 1) % MAX_OBSERVATIONS;
        observations[asset][nextIdx] = Observation({ price: price, timestamp: timestamp });
        observationIndex[asset] = nextIdx;
        if (observationCount[asset] < MAX_OBSERVATIONS) {
            observationCount[asset]++;
        }

        emit PriceObserved(asset, price, timestamp);
    }

    /// @notice Batch observe multiple assets
    /// @param assets Array of assets to observe
    function observeBatch(address[] calldata assets) external onlyRole(KEEPER_ROLE) {
        for (uint256 i = 0; i < assets.length; i++) {
            if (!isSupported(assets[i])) revert AssetNotSupported(assets[i]);

            (uint256 price, uint256 timestamp) = _getPrice(assets[i]);

            uint256 nextIdx = (observationIndex[assets[i]] + 1) % MAX_OBSERVATIONS;
            observations[assets[i]][nextIdx] = Observation({ price: price, timestamp: timestamp });
            observationIndex[assets[i]] = nextIdx;
            if (observationCount[assets[i]] < MAX_OBSERVATIONS) {
                observationCount[assets[i]]++;
            }

            emit PriceObserved(assets[i], price, timestamp);
        }
    }

    // ═══════════════════════════════════════════════════════════════════════
    // ADMIN FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice Set price feed for an asset
    /// @param asset Asset address
    /// @param primary Primary feed address (Chainlink AggregatorV3, Pyth adapter, etc.)
    /// @param fallback_ Fallback feed address (address(0) for none)
    /// @param maxAge Max staleness in seconds (0 = use DEFAULT_MAX_AGE)
    /// @param decimals Feed price decimals (typically 8 for Chainlink, 18 for Pyth)
    function setPriceFeed(address asset, address primary, address fallback_, uint256 maxAge, uint8 decimals)
        external
        onlyRole(ADMIN_ROLE)
    {
        if (asset == address(0)) revert ZeroAddress();
        if (primary == address(0)) revert InvalidFeed();

        feeds[asset] = FeedConfig({
            primary: primary, fallback_: fallback_, maxAge: maxAge == 0 ? DEFAULT_MAX_AGE : maxAge, decimals: decimals
        });

        emit FeedSet(asset, primary, fallback_, maxAge, decimals);
    }

    /// @notice Remove price feed for an asset
    /// @param asset Asset address
    function removePriceFeed(address asset) external onlyRole(ADMIN_ROLE) {
        delete feeds[asset];
        emit FeedRemoved(asset);
    }

    function pause() external onlyRole(ADMIN_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(ADMIN_ROLE) {
        _unpause();
    }

    // ═══════════════════════════════════════════════════════════════════════
    // INTERNAL FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════

    /// @dev Get price from primary feed, fall back to secondary on failure
    function _getPrice(address asset) internal view returns (uint256 price, uint256 timestamp) {
        FeedConfig storage feed = feeds[asset];
        if (feed.primary == address(0)) revert AssetNotSupported(asset);

        // Try primary feed
        (bool ok, uint256 p, uint256 ts) = _queryFeed(feed.primary, feed.decimals);
        if (ok) {
            uint256 maxAge = feed.maxAge;
            uint256 age = block.timestamp - ts;
            if (age <= maxAge) {
                return (p, ts);
            }
        }

        // Try fallback feed
        if (feed.fallback_ != address(0)) {
            (ok, p, ts) = _queryFeed(feed.fallback_, feed.decimals);
            if (ok) {
                uint256 age = block.timestamp - ts;
                if (age <= feed.maxAge) {
                    return (p, ts);
                }
            }
        }

        // If both feeds returned data but stale, return primary anyway (let caller check)
        (ok, p, ts) = _queryFeed(feed.primary, feed.decimals);
        if (ok) {
            return (p, ts);
        }

        revert FeedCallFailed(feed.primary);
    }

    /// @dev Compute cross-rate: base/quote = price(base) / price(quote)
    function _getRate(address base, address quote) internal view returns (uint256 rate, uint256 timestamp) {
        (uint256 basePrice, uint256 baseTs) = _getPrice(base);
        (uint256 quotePrice, uint256 quoteTs) = _getPrice(quote);

        // rate = basePrice / quotePrice, scaled to 18 decimals
        rate = (basePrice * PRECISION) / quotePrice;
        // Return the older timestamp (weakest link)
        timestamp = baseTs < quoteTs ? baseTs : quoteTs;
    }

    /// @dev Query an AggregatorV3-compatible feed: latestRoundData()
    /// @return ok Whether the call succeeded and returned valid data
    /// @return price Normalized to 18 decimals
    /// @return timestamp When the price was updated
    function _queryFeed(address feed, uint8 feedDecimals)
        internal
        view
        returns (bool ok, uint256 price, uint256 timestamp)
    {
        // AggregatorV3Interface.latestRoundData() → (roundId, answer, startedAt, updatedAt, answeredInRound)
        (bool success, bytes memory data) = feed.staticcall(abi.encodeWithSignature("latestRoundData()"));

        if (!success || data.length < 160) return (false, 0, 0);

        (, int256 answer,, uint256 updatedAt,) = abi.decode(data, (uint80, int256, uint256, uint256, uint80));

        if (answer <= 0) return (false, 0, 0);

        // Normalize to 18 decimals
        if (feedDecimals < 18) {
            price = uint256(answer) * (10 ** (18 - feedDecimals));
        } else if (feedDecimals > 18) {
            price = uint256(answer) / (10 ** (feedDecimals - 18));
        } else {
            price = uint256(answer);
        }

        return (true, price, updatedAt);
    }
}
