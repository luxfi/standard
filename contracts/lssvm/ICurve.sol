// SPDX-License-Identifier: MIT
pragma solidity ^0.8.31;

/// @title ICurve - Bonding Curve Interface
/// @notice Interface for LSSVM bonding curves (Linear, Exponential, etc.)
/// @dev Based on Sudoswap LSSVM whitepaper bonding curve specification
interface ICurve {
    /// @notice Error codes for curve operations
    error InvalidDelta();
    error InvalidSpotPrice();
    error InvalidNumItems();
    error SpotPriceOverflow();

    /// @notice Validates if delta is valid for this curve
    /// @param delta The delta parameter for the curve
    /// @return valid True if delta is valid
    function validateDelta(uint128 delta) external pure returns (bool valid);

    /// @notice Validates if spot price is valid for this curve
    /// @param spotPrice The spot price to validate
    /// @return valid True if spot price is valid
    function validateSpotPrice(uint128 spotPrice) external pure returns (bool valid);

    /// @notice Calculates the buy price for a number of NFTs
    /// @param spotPrice Current spot price
    /// @param delta Delta parameter
    /// @param numItems Number of NFTs to buy
    /// @param feeMultiplier Fee multiplier in basis points (10000 = 100%)
    /// @param protocolFeeMultiplier Protocol fee in basis points
    /// @return newSpotPrice New spot price after the trade
    /// @return newDelta New delta after the trade (usually unchanged)
    /// @return inputValue Total amount to pay including fees
    /// @return tradeFee Fee paid to pool
    /// @return protocolFee Fee paid to protocol
    function getBuyInfo(
        uint128 spotPrice,
        uint128 delta,
        uint256 numItems,
        uint256 feeMultiplier,
        uint256 protocolFeeMultiplier
    )
        external
        view
        returns (
            uint128 newSpotPrice,
            uint128 newDelta,
            uint256 inputValue,
            uint256 tradeFee,
            uint256 protocolFee
        );

    /// @notice Calculates the sell price for a number of NFTs
    /// @param spotPrice Current spot price
    /// @param delta Delta parameter
    /// @param numItems Number of NFTs to sell
    /// @param feeMultiplier Fee multiplier in basis points (10000 = 100%)
    /// @param protocolFeeMultiplier Protocol fee in basis points
    /// @return newSpotPrice New spot price after the trade
    /// @return newDelta New delta after the trade (usually unchanged)
    /// @return outputValue Total amount received after fees
    /// @return tradeFee Fee paid to pool
    /// @return protocolFee Fee paid to protocol
    function getSellInfo(
        uint128 spotPrice,
        uint128 delta,
        uint256 numItems,
        uint256 feeMultiplier,
        uint256 protocolFeeMultiplier
    )
        external
        view
        returns (
            uint128 newSpotPrice,
            uint128 newDelta,
            uint256 outputValue,
            uint256 tradeFee,
            uint256 protocolFee
        );
}
