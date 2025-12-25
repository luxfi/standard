// SPDX-License-Identifier: MIT
pragma solidity ^0.8.31;

import "./ICurve.sol";

/// @title LinearCurve - Linear Bonding Curve
/// @notice Implements linear price changes for NFT AMM
/// @dev Price changes by a fixed delta amount per trade
///      Buy: price increases by delta after each item
///      Sell: price decreases by delta after each item
contract LinearCurve is ICurve {
    /// @notice Validates delta (any value > 0 is valid for linear)
    function validateDelta(uint128 delta) external pure override returns (bool) {
        return delta > 0;
    }

    /// @notice Validates spot price (any value > 0 is valid)
    function validateSpotPrice(uint128 spotPrice) external pure override returns (bool) {
        return spotPrice > 0;
    }

    /// @notice Get buy info for linear curve
    /// @dev For buying n items starting at price p with delta d:
    ///      Total = p + (p+d) + (p+2d) + ... + (p+(n-1)d)
    ///            = n*p + d*(0 + 1 + ... + (n-1))
    ///            = n*p + d*(n*(n-1)/2)
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

        // Calculate new spot price (price after buying all items)
        uint256 priceIncrease = uint256(delta) * numItems;
        uint256 newSpotPrice256 = uint256(spotPrice) + priceIncrease;
        if (newSpotPrice256 > type(uint128).max) revert SpotPriceOverflow();
        newSpotPrice = uint128(newSpotPrice256);

        // Delta doesn't change for linear curve
        newDelta = delta;

        // Calculate total input value (sum of prices for all items)
        // First item costs spotPrice, second costs spotPrice + delta, etc.
        // Sum = n*spotPrice + delta*(0 + 1 + ... + (n-1)) = n*spotPrice + delta*n*(n-1)/2
        uint256 buySpotPrice = uint256(spotPrice) + delta; // First buy is at spotPrice + delta
        inputValue = numItems * buySpotPrice + (numItems * (numItems - 1) * delta) / 2;

        // Calculate fees
        tradeFee = (inputValue * feeMultiplier) / 10000;
        protocolFee = (inputValue * protocolFeeMultiplier) / 10000;

        // Add fees to input
        inputValue += tradeFee + protocolFee;
    }

    /// @notice Get sell info for linear curve
    /// @dev For selling n items starting at price p with delta d:
    ///      Total = p + (p-d) + (p-2d) + ... + (p-(n-1)d)
    ///            = n*p - d*(0 + 1 + ... + (n-1))
    ///            = n*p - d*(n*(n-1)/2)
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

        // Calculate new spot price (price after selling all items)
        uint256 priceDecrease = uint256(delta) * numItems;
        if (priceDecrease >= spotPrice) {
            // Price would go to 0 or negative - cap at 1
            newSpotPrice = 1;
            // Adjust numItems to valid range
            numItems = spotPrice / delta;
            if (numItems == 0) {
                // Can't sell even 1 item
                return (spotPrice, delta, 0, 0, 0);
            }
            priceDecrease = uint256(delta) * numItems;
        }
        newSpotPrice = uint128(uint256(spotPrice) - priceDecrease);

        // Delta doesn't change for linear curve
        newDelta = delta;

        // Calculate total output value (sum of prices for all items)
        // First item sells at spotPrice, second at spotPrice - delta, etc.
        // Sum = n*spotPrice - delta*(0 + 1 + ... + (n-1)) = n*spotPrice - delta*n*(n-1)/2
        outputValue = numItems * uint256(spotPrice) - (numItems * (numItems - 1) * uint256(delta)) / 2;

        // Calculate fees
        tradeFee = (outputValue * feeMultiplier) / 10000;
        protocolFee = (outputValue * protocolFeeMultiplier) / 10000;

        // Subtract fees from output
        outputValue -= tradeFee + protocolFee;
    }
}
