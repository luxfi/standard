// SPDX-License-Identifier: MIT
pragma solidity ^0.8.31;

/// @title IOracle
/// @notice THE standard oracle interface for all Lux DeFi protocols
/// @dev Downstream apps (Perps, Lending, AMM) should use this interface
/// @dev All prices are 18 decimals in USD terms
interface IOracle {
    // =========================================================================
    // Core Price Functions
    // =========================================================================

    /// @notice Get the latest price for an asset
    /// @param asset The asset address (address(0) for native LUX)
    /// @return price The price in USD with 18 decimals
    /// @return timestamp When the price was last updated
    function getPrice(address asset) external view returns (uint256 price, uint256 timestamp);

    /// @notice Get price with staleness check
    /// @param asset The asset address
    /// @param maxAge Maximum acceptable age in seconds
    /// @return price The validated price
    function getPriceIfFresh(address asset, uint256 maxAge) external view returns (uint256 price);

    /// @notice Simple price getter (convenience)
    /// @param asset The asset address
    /// @return price The price in USD with 18 decimals
    function price(address asset) external view returns (uint256 price);

    /// @notice Check if oracle supports an asset
    /// @param asset The asset address
    /// @return True if asset is supported
    function isSupported(address asset) external view returns (bool);

    // =========================================================================
    // Batch Operations (gas efficient)
    // =========================================================================

    /// @notice Get prices for multiple assets
    /// @param assets Array of asset addresses
    /// @return prices Array of prices (18 decimals USD)
    /// @return timestamps Array of update timestamps
    function getPrices(address[] calldata assets)
        external view returns (uint256[] memory prices, uint256[] memory timestamps);

    // =========================================================================
    // Perps-Specific Functions
    // =========================================================================

    /// @notice Get price with max/min selection for perps
    /// @dev Perps use maximize=true for longs, false for shorts
    /// @param asset The asset address
    /// @param maximize If true, return higher price (bad for longs liquidation)
    /// @return price The price with spread applied
    function getPriceForPerps(address asset, bool maximize) external view returns (uint256 price);

    /// @notice Check price deviation across sources
    /// @param asset The asset address
    /// @param maxDeviationBps Maximum allowed deviation (e.g., 100 = 1%)
    /// @return consistent True if all sources within deviation
    function isPriceConsistent(address asset, uint256 maxDeviationBps) external view returns (bool consistent);

    // =========================================================================
    // Health & Monitoring
    // =========================================================================

    /// @notice Get oracle health status
    /// @return healthy True if oracle is operational
    /// @return activeSourceCount Number of active price sources
    function health() external view returns (bool healthy, uint256 activeSourceCount);

    /// @notice Check if circuit breaker is tripped for an asset
    /// @param asset The asset address
    /// @return tripped True if circuit breaker is active
    function isCircuitBreakerTripped(address asset) external view returns (bool tripped);
}
