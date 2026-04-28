// SPDX-License-Identifier: MIT
pragma solidity ^0.8.31;

/// @title IForexPair
/// @author Lux Industries
/// @notice Interface for on-chain FX pair spot trading
interface IForexPair {
    // ═══════════════════════════════════════════════════════════════════════
    // TYPES
    // ═══════════════════════════════════════════════════════════════════════

    struct FXPair {
        address base; // Base currency token (e.g., EUR)
        address quote; // Quote currency token (e.g., USD)
        uint256 tickSize; // Minimum price increment (18 decimals)
        uint256 minSize; // Minimum trade size in base (18 decimals)
        uint256 maxSize; // Maximum trade size in base (18 decimals)
        bool active; // Whether pair is tradeable
    }

    // ═══════════════════════════════════════════════════════════════════════
    // EVENTS
    // ═══════════════════════════════════════════════════════════════════════

    event PairCreated(uint256 indexed pairId, address indexed base, address indexed quote);
    event PairUpdated(uint256 indexed pairId, uint256 tickSize, uint256 minSize, uint256 maxSize, bool active);
    event SpotTrade(
        uint256 indexed pairId,
        address indexed trader,
        bool buyBase,
        uint256 baseAmount,
        uint256 quoteAmount,
        uint256 rate
    );

    // ═══════════════════════════════════════════════════════════════════════
    // ERRORS
    // ═══════════════════════════════════════════════════════════════════════

    error PairNotFound();
    error PairNotActive();
    error PairAlreadyExists();
    error BelowMinSize();
    error AboveMaxSize();
    error ZeroAmount();
    error ZeroAddress();
    error InvalidTickSize();
    error SlippageExceeded();
    error JurisdictionRestricted();

    // ═══════════════════════════════════════════════════════════════════════
    // TRADING
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice Swap base for quote at current oracle rate
    /// @param pairId The FX pair ID
    /// @param baseAmount Amount of base currency to sell
    /// @param minQuoteAmount Minimum quote to receive (slippage protection)
    /// @return quoteAmount Amount of quote currency received
    function sellBase(uint256 pairId, uint256 baseAmount, uint256 minQuoteAmount) external returns (uint256 quoteAmount);

    /// @notice Swap quote for base at current oracle rate
    /// @param pairId The FX pair ID
    /// @param quoteAmount Amount of quote currency to sell
    /// @param minBaseAmount Minimum base to receive (slippage protection)
    /// @return baseAmount Amount of base currency received
    function buyBase(uint256 pairId, uint256 quoteAmount, uint256 minBaseAmount) external returns (uint256 baseAmount);

    // ═══════════════════════════════════════════════════════════════════════
    // VIEW
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice Get pair details
    function getPair(uint256 pairId) external view returns (FXPair memory);

    /// @notice Get current exchange rate for a pair from oracle
    function getRate(uint256 pairId) external view returns (uint256 rate, uint256 timestamp);

    /// @notice Get pair ID by base and quote tokens
    function getPairId(address base, address quote) external view returns (uint256);
}
