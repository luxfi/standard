// SPDX-License-Identifier: MIT
pragma solidity ^0.8.31;

/// @title IPriceOracle
/// @author Lux Industries
/// @notice Unified price oracle interface for all asset types
/// @dev Compatible with IOracle (getPrice) — extends with cross-rate and TWAP
/// @dev All prices are 18 decimals in USD terms
interface IPriceOracle {
    // ═══════════════════════════════════════════════════════════════════════
    // CORE PRICE FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice Get the latest price for an asset in USD
    /// @param asset The asset address (token contract)
    /// @return price The price in USD with 18 decimals
    /// @return timestamp When the price was last updated
    function getPrice(address asset) external view returns (uint256 price, uint256 timestamp);

    /// @notice Get the exchange rate between two assets
    /// @dev Computes cross-rate via USD: rate = price(base) / price(quote)
    /// @param base The base asset (numerator, e.g., EUR token)
    /// @param quote The quote asset (denominator, e.g., USD token)
    /// @return rate The exchange rate with 18 decimals (how much quote per 1 base)
    /// @return timestamp The older of the two price timestamps
    function getRate(address base, address quote) external view returns (uint256 rate, uint256 timestamp);

    // ═══════════════════════════════════════════════════════════════════════
    // STALENESS & FRESHNESS
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice Get price with staleness check
    /// @param asset The asset address
    /// @param maxAge Maximum acceptable age in seconds
    /// @return price The validated price
    function getPriceIfFresh(address asset, uint256 maxAge) external view returns (uint256 price);

    /// @notice Get rate with staleness check
    /// @param base The base asset
    /// @param quote The quote asset
    /// @param maxAge Maximum acceptable age in seconds
    /// @return rate The validated rate
    function getRateIfFresh(address base, address quote, uint256 maxAge) external view returns (uint256 rate);

    // ═══════════════════════════════════════════════════════════════════════
    // TWAP
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice Get time-weighted average price over a window
    /// @param asset The asset address
    /// @param window The TWAP window in seconds
    /// @return twap The time-weighted average price (18 decimals)
    function getTWAP(address asset, uint256 window) external view returns (uint256 twap);

    // ═══════════════════════════════════════════════════════════════════════
    // FEED MANAGEMENT (view)
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice Check if oracle supports an asset
    /// @param asset The asset address
    /// @return True if asset has at least one feed configured
    function isSupported(address asset) external view returns (bool);
}
