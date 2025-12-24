// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.28;

import {IOracle} from "../interfaces/IOracle.sol";

/// @notice Pyth price feed interface
interface IPyth {
    struct Price {
        int64 price;
        uint64 conf;
        int32 expo;
        uint256 publishTime;
    }
    
    function getPriceNoOlderThan(bytes32 id, uint256 age) external view returns (Price memory);
    function getPrice(bytes32 id) external view returns (Price memory);
}

/// @title PythOracle
/// @notice Oracle adapter for Pyth Network price feeds
/// @dev Returns price scaled to 1e36 as required by Markets
contract PythOracle is IOracle {
    /// @notice Pyth oracle contract
    IPyth public immutable pyth;
    
    /// @notice Price feed ID for base token
    bytes32 public immutable baseFeedId;
    
    /// @notice Price feed ID for quote token
    bytes32 public immutable quoteFeedId;
    
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

    /// @param _pyth Pyth oracle address
    /// @param _baseFeedId Pyth feed ID for collateral (e.g., ETH/USD)
    /// @param _quoteFeedId Pyth feed ID for loan token (bytes32(0) if USD)
    /// @param _baseTokenDecimals Decimals of collateral token
    /// @param _quoteTokenDecimals Decimals of loan token
    /// @param _maxStaleness Maximum age of price data in seconds
    constructor(
        address _pyth,
        bytes32 _baseFeedId,
        bytes32 _quoteFeedId,
        uint8 _baseTokenDecimals,
        uint8 _quoteTokenDecimals,
        uint256 _maxStaleness
    ) {
        pyth = IPyth(_pyth);
        baseFeedId = _baseFeedId;
        quoteFeedId = _quoteFeedId;
        baseTokenDecimals = _baseTokenDecimals;
        quoteTokenDecimals = _quoteTokenDecimals;
        maxStaleness = _maxStaleness;
    }

    /// @inheritdoc IOracle
    function price() external view override returns (uint256) {
        uint256 basePrice = _getPrice(baseFeedId);
        
        uint256 quotePrice;
        if (quoteFeedId != bytes32(0)) {
            quotePrice = _getPrice(quoteFeedId);
        } else {
            quotePrice = 1e8; // $1 with 8 decimals
        }

        // price = (basePrice / quotePrice) * 10^36 * 10^quoteDecimals / 10^baseDecimals
        return (basePrice * ORACLE_PRICE_SCALE * (10 ** quoteTokenDecimals)) / 
               (quotePrice * (10 ** baseTokenDecimals));
    }

    function _getPrice(bytes32 feedId) internal view returns (uint256) {
        IPyth.Price memory priceData = pyth.getPriceNoOlderThan(feedId, maxStaleness);
        
        if (priceData.price <= 0) revert InvalidPrice();

        // Convert Pyth price (with variable exponent) to 8 decimals
        int32 targetExpo = -8;
        int256 scaledPrice;
        
        if (priceData.expo > targetExpo) {
            // Need to divide
            uint32 diff = uint32(priceData.expo - targetExpo);
            scaledPrice = int256(priceData.price) / int256(10 ** diff);
        } else if (priceData.expo < targetExpo) {
            // Need to multiply
            uint32 diff = uint32(targetExpo - priceData.expo);
            scaledPrice = int256(priceData.price) * int256(10 ** diff);
        } else {
            scaledPrice = int256(priceData.price);
        }

        return uint256(scaledPrice);
    }
}
