// SPDX-License-Identifier: MIT
pragma solidity ^0.8.31;

/// @title IOracleSource
/// @notice Interface for individual price feed sources
/// @dev Implemented by Chainlink, Pyth, TWAP, DEX adapters
/// @dev All prices normalized to 18 decimals in USD terms
interface IOracleSource {
    /// @notice Get the latest price for an asset
    /// @param asset The asset address (address(0) for native LUX)
    /// @return price The price in USD with 18 decimals
    /// @return timestamp When the price was last updated
    function getPrice(address asset) external view returns (uint256 price, uint256 timestamp);

    /// @notice Check if source supports an asset
    /// @param asset The asset address
    /// @return True if asset is supported
    function isSupported(address asset) external view returns (bool);

    /// @notice Source identifier
    /// @return Source name (e.g., "chainlink", "pyth", "twap", "dex")
    function source() external view returns (string memory);

    /// @notice Get source health status
    /// @return healthy True if source is operational
    /// @return lastHeartbeat Last successful price update timestamp
    function health() external view returns (bool healthy, uint256 lastHeartbeat);
}
