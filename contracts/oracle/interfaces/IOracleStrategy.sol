// SPDX-License-Identifier: MIT
pragma solidity ^0.8.31;

/// @title IOracleStrategy
/// @notice Interface for price aggregation strategies
/// @dev Strategies: MEDIAN (manipulation resistant), MEAN, MIN, MAX
interface IOracleStrategy {
    /// @notice Aggregate prices from multiple sources
    /// @param prices Array of prices (18 decimals)
    /// @param count Number of valid prices in array
    /// @return aggregated The aggregated price
    function aggregate(uint256[] memory prices, uint256 count) external pure returns (uint256 aggregated);

    /// @notice Strategy identifier
    /// @return Strategy name (e.g., "median", "mean", "min", "max")
    function name() external pure returns (string memory);
}

/// @title MedianStrategy
/// @notice Median aggregation - manipulation resistant
contract MedianStrategy is IOracleStrategy {
    function aggregate(uint256[] memory prices, uint256 count) external pure override returns (uint256) {
        if (count == 0) return 0;
        if (count == 1) return prices[0];

        // Copy to avoid modifying input
        uint256[] memory sorted = new uint256[](count);
        for (uint256 i = 0; i < count; i++) {
            sorted[i] = prices[i];
        }

        // Bubble sort (fine for small arrays, typically < 5 sources)
        for (uint256 i = 0; i < count; i++) {
            for (uint256 j = i + 1; j < count; j++) {
                if (sorted[i] > sorted[j]) {
                    (sorted[i], sorted[j]) = (sorted[j], sorted[i]);
                }
            }
        }

        uint256 mid = count / 2;
        if (count % 2 == 0) {
            return (sorted[mid - 1] + sorted[mid]) / 2;
        }
        return sorted[mid];
    }

    function name() external pure override returns (string memory) {
        return "median";
    }
}

/// @title MeanStrategy
/// @notice Simple average aggregation
contract MeanStrategy is IOracleStrategy {
    function aggregate(uint256[] memory prices, uint256 count) external pure override returns (uint256) {
        if (count == 0) return 0;

        uint256 sum = 0;
        for (uint256 i = 0; i < count; i++) {
            sum += prices[i];
        }
        return sum / count;
    }

    function name() external pure override returns (string memory) {
        return "mean";
    }
}

/// @title MinStrategy
/// @notice Minimum price - conservative for liquidations
contract MinStrategy is IOracleStrategy {
    function aggregate(uint256[] memory prices, uint256 count) external pure override returns (uint256) {
        if (count == 0) return 0;

        uint256 minVal = prices[0];
        for (uint256 i = 1; i < count; i++) {
            if (prices[i] < minVal) minVal = prices[i];
        }
        return minVal;
    }

    function name() external pure override returns (string memory) {
        return "min";
    }
}

/// @title MaxStrategy
/// @notice Maximum price - aggressive for borrowing limits
contract MaxStrategy is IOracleStrategy {
    function aggregate(uint256[] memory prices, uint256 count) external pure override returns (uint256) {
        if (count == 0) return 0;

        uint256 maxVal = prices[0];
        for (uint256 i = 1; i < count; i++) {
            if (prices[i] > maxVal) maxVal = prices[i];
        }
        return maxVal;
    }

    function name() external pure override returns (string memory) {
        return "max";
    }
}
