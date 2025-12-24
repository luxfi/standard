// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.28;

import {IOracle} from "../interfaces/IOracle.sol";

/// @notice Chainlink price feed interface
interface AggregatorV3Interface {
    function latestRoundData() external view returns (
        uint80 roundId,
        int256 answer,
        uint256 startedAt,
        uint256 updatedAt,
        uint80 answeredInRound
    );
    function decimals() external view returns (uint8);
}

/// @title ChainlinkOracle
/// @notice Oracle adapter for Chainlink price feeds
/// @dev Returns price scaled to 1e36 as required by Markets
contract ChainlinkOracle is IOracle {
    /// @notice Base token price feed (e.g., ETH/USD)
    AggregatorV3Interface public immutable baseFeed;
    
    /// @notice Quote token price feed (e.g., USDC/USD) - optional
    AggregatorV3Interface public immutable quoteFeed;
    
    /// @notice Base feed decimals
    uint8 public immutable baseFeedDecimals;
    
    /// @notice Quote feed decimals
    uint8 public immutable quoteFeedDecimals;
    
    /// @notice Base token decimals
    uint8 public immutable baseTokenDecimals;
    
    /// @notice Quote token decimals
    uint8 public immutable quoteTokenDecimals;

    /// @notice Maximum staleness for price data
    uint256 public immutable maxStaleness;

    /// @notice Oracle price scale (1e36)
    uint256 public constant ORACLE_PRICE_SCALE = 1e36;

    error StalePrice();
    error InvalidPrice();

    /// @param _baseFeed Chainlink feed for collateral asset
    /// @param _quoteFeed Chainlink feed for loan asset (address(0) if USD)
    /// @param _baseTokenDecimals Decimals of collateral token
    /// @param _quoteTokenDecimals Decimals of loan token
    /// @param _maxStaleness Maximum age of price data in seconds
    constructor(
        address _baseFeed,
        address _quoteFeed,
        uint8 _baseTokenDecimals,
        uint8 _quoteTokenDecimals,
        uint256 _maxStaleness
    ) {
        baseFeed = AggregatorV3Interface(_baseFeed);
        quoteFeed = _quoteFeed != address(0) ? AggregatorV3Interface(_quoteFeed) : AggregatorV3Interface(address(0));
        
        baseFeedDecimals = AggregatorV3Interface(_baseFeed).decimals();
        quoteFeedDecimals = _quoteFeed != address(0) ? AggregatorV3Interface(_quoteFeed).decimals() : 8;
        
        baseTokenDecimals = _baseTokenDecimals;
        quoteTokenDecimals = _quoteTokenDecimals;
        maxStaleness = _maxStaleness;
    }

    /// @inheritdoc IOracle
    /// @dev Returns collateral price in terms of loan asset, scaled by 1e36
    function price() external view override returns (uint256) {
        uint256 basePrice = _getPrice(baseFeed, baseFeedDecimals);
        
        uint256 quotePrice;
        if (address(quoteFeed) != address(0)) {
            quotePrice = _getPrice(quoteFeed, quoteFeedDecimals);
        } else {
            // Quote is USD-denominated stablecoin
            quotePrice = 1e8; // $1 with 8 decimals
        }

        // price = (basePrice / quotePrice) * 10^36 * 10^quoteDecimals / 10^baseDecimals
        // This gives: how many quote tokens per base token, scaled by 1e36
        return (basePrice * ORACLE_PRICE_SCALE * (10 ** quoteTokenDecimals)) / 
               (quotePrice * (10 ** baseTokenDecimals));
    }

    function _getPrice(AggregatorV3Interface feed, uint8 feedDecimals) internal view returns (uint256) {
        (, int256 answer,, uint256 updatedAt,) = feed.latestRoundData();
        
        if (answer <= 0) revert InvalidPrice();
        if (block.timestamp - updatedAt > maxStaleness) revert StalePrice();

        // Normalize to 8 decimals for consistency
        if (feedDecimals > 8) {
            return uint256(answer) / (10 ** (feedDecimals - 8));
        } else if (feedDecimals < 8) {
            return uint256(answer) * (10 ** (8 - feedDecimals));
        }
        return uint256(answer);
    }
}
