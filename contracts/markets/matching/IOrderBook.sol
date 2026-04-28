// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title IOrderBook — generic CLOB matcher interface.
/// @notice Minimal CLOB primitive: submit a limit order that immediately
///         tries to cross, rests the unfilled remainder, and supports
///         cancel + best-price queries. Implementations may add
///         domain-specific wrappers (ATS, darkpool, prediction-market
///         resolver) but the core surface stays uniform.
interface IOrderBook {
    enum Side {
        Buy,
        Sell
    }

    event OrderPlaced(
        bytes32 indexed orderId, address indexed trader, string symbol, Side side, uint256 price, uint256 qty
    );
    event OrderFilled(bytes32 indexed makerId, bytes32 indexed takerId, uint256 price, uint256 qty);
    event OrderCancelled(bytes32 indexed orderId);

    function match_(Side side, string calldata symbol, uint256 price, uint256 qty) external returns (bytes32 orderId);
    function cancel(string calldata symbol, uint64 orderId) external returns (bool);
    function bestPrice(string calldata symbol, Side side) external view returns (uint256);
}
