// SPDX-License-Identifier: MIT
pragma solidity ^0.8.31;

import "./ICurve.sol";

/// @title ExponentialCurve - Exponential Bonding Curve
/// @notice Implements exponential price changes for NFT AMM
/// @dev Price changes by a fixed percentage (delta) per trade
///      Buy: price *= delta after each item (delta > 1e18)
///      Sell: price /= delta after each item (delta > 1e18)
///      Delta is stored as 1e18 + percentage (e.g., 1.1e18 = 10% increase)
contract ExponentialCurve is ICurve {
    uint256 internal constant WAD = 1e18;
    uint256 internal constant MIN_PRICE = 1 gwei;

    /// @notice Validates delta (must be > 1e18 for exponential growth)
    function validateDelta(uint128 delta) external pure override returns (bool) {
        return delta > WAD;
    }

    /// @notice Validates spot price (any value > MIN_PRICE is valid)
    function validateSpotPrice(uint128 spotPrice) external pure override returns (bool) {
        return spotPrice >= MIN_PRICE;
    }

    /// @notice Get buy info for exponential curve
    /// @dev For buying n items starting at price p with multiplier delta:
    ///      Total = p*delta + p*delta^2 + ... + p*delta^n
    ///            = p * delta * (delta^n - 1) / (delta - 1)
    function getBuyInfo(
        uint128 spotPrice,
        uint128 delta,
        uint256 numItems,
        uint256 feeMultiplier,
        uint256 protocolFeeMultiplier
    )
        external
        pure
        override
        returns (
            uint128 newSpotPrice,
            uint128 newDelta,
            uint256 inputValue,
            uint256 tradeFee,
            uint256 protocolFee
        )
    {
        if (numItems == 0) revert InvalidNumItems();

        // Calculate delta^numItems
        uint256 deltaPowN = _fpow(delta, numItems, WAD);

        // New spot price = spotPrice * delta^numItems
        uint256 newSpotPrice256 = (uint256(spotPrice) * deltaPowN) / WAD;
        if (newSpotPrice256 > type(uint128).max) revert SpotPriceOverflow();
        newSpotPrice = uint128(newSpotPrice256);

        // Delta doesn't change
        newDelta = delta;

        // Calculate total input (geometric series)
        // Sum = p*delta + p*delta^2 + ... + p*delta^n
        // Sum = p * delta * (delta^n - 1) / (delta - 1)
        uint256 buySpotPrice = (uint256(spotPrice) * delta) / WAD;
        if (delta == WAD) {
            // Edge case: no change in price
            inputValue = numItems * buySpotPrice;
        } else {
            // Geometric series sum
            inputValue = (buySpotPrice * (deltaPowN - WAD)) / (delta - WAD);
        }

        // Calculate fees
        tradeFee = (inputValue * feeMultiplier) / 10000;
        protocolFee = (inputValue * protocolFeeMultiplier) / 10000;

        // Add fees to input
        inputValue += tradeFee + protocolFee;
    }

    /// @notice Get sell info for exponential curve
    /// @dev For selling n items starting at price p with multiplier delta:
    ///      Total = p + p/delta + p/delta^2 + ... + p/delta^(n-1)
    ///            = p * (1 - (1/delta)^n) / (1 - 1/delta)
    function getSellInfo(
        uint128 spotPrice,
        uint128 delta,
        uint256 numItems,
        uint256 feeMultiplier,
        uint256 protocolFeeMultiplier
    )
        external
        pure
        override
        returns (
            uint128 newSpotPrice,
            uint128 newDelta,
            uint256 outputValue,
            uint256 tradeFee,
            uint256 protocolFee
        )
    {
        if (numItems == 0) revert InvalidNumItems();

        // Calculate (1/delta)^numItems = WAD^numItems / delta^numItems
        uint256 deltaPowN = _fpow(delta, numItems, WAD);
        uint256 invDeltaPowN = (WAD * WAD) / deltaPowN;

        // New spot price = spotPrice / delta^numItems
        uint256 newSpotPrice256 = (uint256(spotPrice) * WAD) / deltaPowN;
        if (newSpotPrice256 < MIN_PRICE) {
            newSpotPrice256 = MIN_PRICE;
        }
        newSpotPrice = uint128(newSpotPrice256);

        // Delta doesn't change
        newDelta = delta;

        // Calculate total output (geometric series)
        // Sum = p + p/delta + p/delta^2 + ... + p/delta^(n-1)
        // Sum = p * (1 - (1/delta)^n) / (1 - 1/delta)
        // Sum = p * delta * (1 - (1/delta)^n) / (delta - 1)
        if (delta == WAD) {
            // Edge case: no change in price
            outputValue = numItems * uint256(spotPrice);
        } else {
            uint256 numerator = uint256(spotPrice) * delta * (WAD - invDeltaPowN);
            uint256 denominator = WAD * (delta - WAD);
            outputValue = numerator / denominator;
        }

        // Calculate fees
        tradeFee = (outputValue * feeMultiplier) / 10000;
        protocolFee = (outputValue * protocolFeeMultiplier) / 10000;

        // Subtract fees from output
        outputValue -= tradeFee + protocolFee;
    }

    /// @notice Fixed-point power function
    /// @dev Calculates base^exp with fixed-point arithmetic
    function _fpow(uint256 base, uint256 exp, uint256 unit) internal pure returns (uint256 result) {
        result = unit;
        while (exp > 0) {
            if (exp & 1 == 1) {
                result = (result * base) / unit;
            }
            exp >>= 1;
            base = (base * base) / unit;
        }
    }
}
