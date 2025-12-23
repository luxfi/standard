// SPDX-License-Identifier: BSD-3-Clause
// Copyright (c) 2025 Lux Industries Inc.
pragma solidity ^0.8.24;

/// @title IOracle
/// @notice Native Oracle Precompile Interface for HFT Price Feeds
/// @dev Precompile Address: 0x0200000000000000000000000000000000000011
/// @custom:precompile-address 0x0200000000000000000000000000000000000011
interface IOracle {
    /*//////////////////////////////////////////////////////////////
                                 TYPES
    //////////////////////////////////////////////////////////////*/

    /// @notice Price feed sources supported
    enum PriceSource {
        NATIVE,         // Lux native HFT DEX TWAP
        CHAINLINK,      // Chainlink aggregator
        PYTH,           // Pyth Network
        BINANCE,        // Binance oracle
        KRAKEN,         // Kraken oracle
        UNISWAP_V3,     // Uniswap V3 TWAP
        AGGREGATE       // Multi-source aggregated
    }

    /// @notice Price data struct
    struct Price {
        uint256 price;          // 1e18 precision
        uint256 confidence;     // Confidence interval (1e18 = 100%)
        uint256 timestamp;      // Last update time
        PriceSource source;     // Price source
        bool isValid;           // Whether price is valid
    }

    /// @notice Aggregated price with multiple sources
    struct AggregatedPrice {
        uint256 price;          // Weighted average (1e18 precision)
        uint256 minPrice;       // Minimum across sources
        uint256 maxPrice;       // Maximum across sources
        uint256 deviation;      // Standard deviation (basis points)
        uint256 confidence;     // Aggregate confidence
        uint256 timestamp;      // Latest update
        uint8 sourceCount;      // Number of sources used
        bool isValid;           // All sources agree within threshold
    }

    /// @notice TWAP configuration
    struct TWAPConfig {
        uint32 window;          // TWAP window in seconds
        uint32 granularity;     // Number of observations
        bool useGeometric;      // Geometric vs arithmetic mean
    }

    /// @notice Historical price point
    struct PricePoint {
        uint256 price;
        uint256 timestamp;
        uint256 volume;         // Trading volume in period
    }

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    event PriceUpdated(
        bytes32 indexed pairId,
        uint256 price,
        uint256 timestamp,
        PriceSource source
    );

    event OracleRegistered(
        bytes32 indexed pairId,
        address indexed oracle,
        PriceSource source
    );

    event PriceDeviation(
        bytes32 indexed pairId,
        uint256 primaryPrice,
        uint256 secondaryPrice,
        uint256 deviationBps
    );

    /*//////////////////////////////////////////////////////////////
                          PRICE FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Get latest price for a token pair
    /// @param base Base token address (e.g., ETH)
    /// @param quote Quote token address (e.g., USD)
    /// @return price Price data
    function getPrice(
        address base,
        address quote
    ) external view returns (Price memory price);

    /// @notice Get price from specific source
    /// @param base Base token address
    /// @param quote Quote token address
    /// @param source Preferred price source
    /// @return price Price from specified source
    function getPriceFromSource(
        address base,
        address quote,
        PriceSource source
    ) external view returns (Price memory price);

    /// @notice Get aggregated price from multiple sources
    /// @param base Base token address
    /// @param quote Quote token address
    /// @return agg Aggregated price with metadata
    function getAggregatedPrice(
        address base,
        address quote
    ) external view returns (AggregatedPrice memory agg);

    /// @notice Get TWAP price
    /// @param base Base token address
    /// @param quote Quote token address
    /// @param config TWAP configuration
    /// @return twap Time-weighted average price
    function getTWAP(
        address base,
        address quote,
        TWAPConfig calldata config
    ) external view returns (uint256 twap);

    /// @notice Get historical prices
    /// @param base Base token address
    /// @param quote Quote token address
    /// @param startTime Start timestamp
    /// @param endTime End timestamp
    /// @param interval Interval in seconds
    /// @return prices Array of historical price points
    function getHistoricalPrices(
        address base,
        address quote,
        uint256 startTime,
        uint256 endTime,
        uint256 interval
    ) external view returns (PricePoint[] memory prices);

    /// @notice Get prices for multiple pairs in one call
    /// @param bases Array of base token addresses
    /// @param quotes Array of quote token addresses
    /// @return prices Array of prices
    function getBatchPrices(
        address[] calldata bases,
        address[] calldata quotes
    ) external view returns (Price[] memory prices);

    /*//////////////////////////////////////////////////////////////
                        VOLATILITY FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Get realized volatility
    /// @param base Base token address
    /// @param quote Quote token address
    /// @param period Period in seconds
    /// @return volatility Annualized volatility (1e18 = 100%)
    function getVolatility(
        address base,
        address quote,
        uint256 period
    ) external view returns (uint256 volatility);

    /// @notice Get implied volatility (from options markets)
    /// @param base Base token address
    /// @param quote Quote token address
    /// @return iv Implied volatility (1e18 = 100%)
    function getImpliedVolatility(
        address base,
        address quote
    ) external view returns (uint256 iv);

    /*//////////////////////////////////////////////////////////////
                          ORACLE MANAGEMENT
    //////////////////////////////////////////////////////////////*/

    /// @notice Check if price feed exists
    /// @param base Base token address
    /// @param quote Quote token address
    /// @return exists True if feed exists
    function feedExists(
        address base,
        address quote
    ) external view returns (bool exists);

    /// @notice Get supported sources for a pair
    /// @param base Base token address
    /// @param quote Quote token address
    /// @return sources Array of available price sources
    function getSupportedSources(
        address base,
        address quote
    ) external view returns (PriceSource[] memory sources);

    /// @notice Get oracle address for a source
    /// @param base Base token address
    /// @param quote Quote token address
    /// @param source Price source
    /// @return oracle Oracle contract address
    function getOracleAddress(
        address base,
        address quote,
        PriceSource source
    ) external view returns (address oracle);

    /// @notice Get pair ID for tokens
    /// @param base Base token address
    /// @param quote Quote token address
    /// @return pairId Unique pair identifier
    function getPairId(
        address base,
        address quote
    ) external pure returns (bytes32 pairId);

    /*//////////////////////////////////////////////////////////////
                         CHAINLINK SPECIFIC
    //////////////////////////////////////////////////////////////*/

    /// @notice Get Chainlink round data
    /// @param base Base token address
    /// @param quote Quote token address
    /// @return roundId Chainlink round ID
    /// @return answer Price answer
    /// @return startedAt Round start timestamp
    /// @return updatedAt Round update timestamp
    /// @return answeredInRound Round in which answer was computed
    function getChainlinkRoundData(
        address base,
        address quote
    ) external view returns (
        uint80 roundId,
        int256 answer,
        uint256 startedAt,
        uint256 updatedAt,
        uint80 answeredInRound
    );

    /*//////////////////////////////////////////////////////////////
                           PYTH SPECIFIC
    //////////////////////////////////////////////////////////////*/

    /// @notice Get Pyth price with confidence
    /// @param priceId Pyth price feed ID
    /// @return price Price value
    /// @return conf Confidence interval
    /// @return expo Exponent
    /// @return publishTime Publish timestamp
    function getPythPrice(
        bytes32 priceId
    ) external view returns (
        int64 price,
        uint64 conf,
        int32 expo,
        uint256 publishTime
    );

    /// @notice Update Pyth prices (requires fee)
    /// @param updateData Pyth price update data
    /// @return fee Fee paid
    function updatePythPrices(
        bytes[] calldata updateData
    ) external payable returns (uint256 fee);
}

/// @title OracleLib
/// @notice Library for interacting with Oracle Precompile
library OracleLib {
    /// @notice Oracle Precompile address
    IOracle internal constant ORACLE = IOracle(0x0200000000000000000000000000000000000011);

    /// @notice USD address constant (for price pairs)
    address internal constant USD = address(0xFFfFfFffFFfffFFfFFfFFFFFffFFFffffFfFFFfF);

    /// @notice Get USD price for a token
    function getUSDPrice(address token) internal view returns (uint256 price) {
        IOracle.Price memory p = ORACLE.getPrice(token, USD);
        require(p.isValid, "Oracle: invalid price");
        return p.price;
    }

    /// @notice Get aggregated USD price
    function getAggregatedUSDPrice(address token) internal view returns (uint256 price) {
        IOracle.AggregatedPrice memory agg = ORACLE.getAggregatedPrice(token, USD);
        require(agg.isValid, "Oracle: invalid aggregated price");
        return agg.price;
    }

    /// @notice Get price with staleness check
    function getPriceWithStalenessCheck(
        address base,
        address quote,
        uint256 maxAge
    ) internal view returns (uint256 price) {
        IOracle.Price memory p = ORACLE.getPrice(base, quote);
        require(p.isValid, "Oracle: invalid price");
        require(block.timestamp - p.timestamp <= maxAge, "Oracle: stale price");
        return p.price;
    }

    /// @notice Get TWAP with default config (30 min window)
    function getTWAP30Min(
        address base,
        address quote
    ) internal view returns (uint256 twap) {
        return ORACLE.getTWAP(
            base,
            quote,
            IOracle.TWAPConfig({
                window: 1800,       // 30 minutes
                granularity: 30,    // 30 observations
                useGeometric: true  // Geometric mean
            })
        );
    }

    /// @notice Check price deviation between two sources
    function checkDeviation(
        address base,
        address quote,
        IOracle.PriceSource source1,
        IOracle.PriceSource source2,
        uint256 maxDeviationBps
    ) internal view returns (bool withinBounds) {
        IOracle.Price memory p1 = ORACLE.getPriceFromSource(base, quote, source1);
        IOracle.Price memory p2 = ORACLE.getPriceFromSource(base, quote, source2);

        require(p1.isValid && p2.isValid, "Oracle: invalid sources");

        uint256 deviation;
        if (p1.price > p2.price) {
            deviation = (p1.price - p2.price) * 10000 / p1.price;
        } else {
            deviation = (p2.price - p1.price) * 10000 / p2.price;
        }

        return deviation <= maxDeviationBps;
    }
}

/// @title ChainlinkCompatible
/// @notice Chainlink AggregatorV3 compatible wrapper for Oracle precompile
/// @dev Use this for contracts expecting Chainlink interface
abstract contract ChainlinkCompatible {
    IOracle internal constant ORACLE = IOracle(0x0200000000000000000000000000000000000011);

    address public immutable base;
    address public immutable quote;
    uint8 public immutable decimals;

    constructor(address _base, address _quote, uint8 _decimals) {
        base = _base;
        quote = _quote;
        decimals = _decimals;
    }

    function latestRoundData() external view returns (
        uint80 roundId,
        int256 answer,
        uint256 startedAt,
        uint256 updatedAt,
        uint80 answeredInRound
    ) {
        return ORACLE.getChainlinkRoundData(base, quote);
    }

    function latestAnswer() external view returns (int256) {
        IOracle.Price memory p = ORACLE.getPrice(base, quote);
        // Convert from 1e18 to decimals
        return int256(p.price / (10 ** (18 - decimals)));
    }

    function latestTimestamp() external view returns (uint256) {
        IOracle.Price memory p = ORACLE.getPrice(base, quote);
        return p.timestamp;
    }
}

/// @title PythCompatible
/// @notice Pyth Network compatible wrapper for Oracle precompile
abstract contract PythCompatible {
    IOracle internal constant ORACLE = IOracle(0x0200000000000000000000000000000000000011);

    function getPrice(bytes32 priceId) external view returns (
        int64 price,
        uint64 conf,
        int32 expo,
        uint256 publishTime
    ) {
        return ORACLE.getPythPrice(priceId);
    }

    function updatePriceFeeds(bytes[] calldata updateData) external payable {
        ORACLE.updatePythPrices{value: msg.value}(updateData);
    }

    function getUpdateFee(bytes[] calldata updateData) external pure returns (uint256) {
        // Estimate 1 wei per byte
        uint256 fee = 0;
        for (uint256 i = 0; i < updateData.length; i++) {
            fee += updateData[i].length;
        }
        return fee;
    }
}
