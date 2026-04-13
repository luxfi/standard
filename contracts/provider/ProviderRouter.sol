// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./IRegulatedProvider.sol";

/// @title ProviderRouter — dispatches swaps between Lux native liquidity
///        and an external regulated provider.
/// @notice The router is the single entry point every exchange frontend
///         calls. It asks the configured provider if a symbol is regulated;
///         if so, it delegates. Otherwise it falls through to the caller-
///         supplied native AMM pool address.
///
/// White-label operators deploy one ProviderRouter per chain:
///   - Regulated venue: constructor takes a real IRegulatedProvider.
///   - Pure DeFi venue: constructor takes a NullProvider (or address(0),
///     treated as "no provider").
interface IAMMPool {
    function swap(bool baseIn, uint256 amountIn, uint256 minOut) external returns (uint256);
}

contract ProviderRouter {
    IRegulatedProvider public immutable provider;

    /// @notice Set once at deploy; swap between regimes by deploying a
    ///         new router rather than rotating state. Immutability is a
    ///         regulator ask.
    bool public immutable hasProvider;

    event RegulatedSwap(address indexed trader, string symbol, uint256 amountIn, uint256 amountOut);
    event NativeSwap(address indexed trader, address pool, uint256 amountIn, uint256 amountOut);

    constructor(IRegulatedProvider _provider) {
        provider = _provider;
        hasProvider = address(_provider) != address(0);
    }

    /// @notice Dispatch a swap. If the symbol is regulated, route to the
    ///         provider; otherwise execute against the supplied native pool.
    /// @param nativePool address of a Lux AMM pool to use for open flow.
    function swap(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 minOut,
        string calldata symbol,
        address nativePool,
        bool baseIn
    ) external returns (uint256 amountOut) {
        if (hasProvider && provider.handles(symbol)) {
            (bool ok, uint8 reason) = provider.isEligible(msg.sender, symbol);
            require(ok, _reasonToMessage(reason));
            amountOut = provider.routedSwap(msg.sender, tokenIn, tokenOut, amountIn, minOut, symbol);
            emit RegulatedSwap(msg.sender, symbol, amountIn, amountOut);
        } else {
            require(nativePool != address(0), "ProviderRouter: no pool");
            amountOut = IAMMPool(nativePool).swap(baseIn, amountIn, minOut);
            emit NativeSwap(msg.sender, nativePool, amountIn, amountOut);
        }
    }

    /// @notice Read the best price from whichever venue owns the symbol.
    function quote(string calldata symbol, IRegulatedProvider.Side side)
        external
        view
        returns (uint256 price, bool regulated)
    {
        if (hasProvider && provider.handles(symbol)) {
            return (provider.bestPrice(symbol, side), true);
        }
        return (0, false);
    }

    // ─────────────────────────── errors ───────────────────────────────

    function _reasonToMessage(uint8 code) private pure returns (string memory) {
        if (code == 0) return "";
        if (code == 6) return "provider: jurisdiction blocked";
        if (code == 7) return "provider: accreditation required";
        if (code == 16 || code == 17) return "provider: not whitelisted";
        if (code == 18) return "provider: lockup active";
        if (code >= 19 && code <= 22) return "provider: jurisdiction blocked";
        if (code == 32) return "provider: max holders reached";
        if (code == 33) return "provider: transfer limit exceeded";
        if (code == 255) return "provider: disabled";
        return "provider: not eligible";
    }
}
