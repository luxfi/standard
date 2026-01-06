// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title LX
/// @notice Lux Exchange precompile address constants
/// @dev Address format: 0x0000000000000000000000000000000000LPNUM
///      See LP-9015 for canonical specification
library LX {
    // -------------------------------------------------------------------------
    // Core AMM (LP-9010 series - Uniswap v4 style)
    // -------------------------------------------------------------------------

    /// @notice LXPool (LP-9010) - v4 PoolManager-compatible AMM core
    address internal constant LX_POOL   = 0x0000000000000000000000000000000000009010;

    /// @notice LXOracle (LP-9011) - Multi-source price aggregation
    address internal constant LX_ORACLE = 0x0000000000000000000000000000000000009011;

    /// @notice LXRouter (LP-9012) - Optimized swap routing
    address internal constant LX_ROUTER = 0x0000000000000000000000000000000000009012;

    /// @notice LXHooks (LP-9013) - Hook contract registry
    address internal constant LX_HOOKS  = 0x0000000000000000000000000000000000009013;

    /// @notice LXFlash (LP-9014) - Flash loan facility
    address internal constant LX_FLASH  = 0x0000000000000000000000000000000000009014;

    // -------------------------------------------------------------------------
    // Trading & DeFi Extensions
    // -------------------------------------------------------------------------

    /// @notice LXBook (LP-9020) - Permissionless orderbooks + matching + advanced orders
    address internal constant LX_BOOK   = 0x0000000000000000000000000000000000009020;

    /// @notice LXVault (LP-9030) - Balances, margin, collateral, liquidations
    address internal constant LX_VAULT  = 0x0000000000000000000000000000000000009030;

    /// @notice LXFeed (LP-9040) - Price feed aggregator
    address internal constant LX_FEED   = 0x0000000000000000000000000000000000009040;

    // -------------------------------------------------------------------------
    // Bridge Precompiles (LP-6xxx)
    // -------------------------------------------------------------------------

    /// @notice Teleport (LP-6010) - Cross-chain asset teleportation
    address internal constant TELEPORT  = 0x0000000000000000000000000000000000006010;

    // -------------------------------------------------------------------------
    // Utility Functions
    // -------------------------------------------------------------------------

    /// @notice Generate precompile address from LP number
    /// @param lpNumber The LP number (e.g., 9010)
    /// @return The precompile address
    function fromLP(uint16 lpNumber) internal pure returns (address) {
        return address(uint160(lpNumber));
    }

    /// @notice Extract LP number from precompile address
    /// @param precompile The precompile address
    /// @return The LP number
    function toLP(address precompile) internal pure returns (uint16) {
        return uint16(uint160(precompile));
    }

    /// @notice Check if address is an LX precompile (LP-9xxx)
    /// @param addr The address to check
    /// @return True if address is in LP-9xxx range
    function isLXPrecompile(address addr) internal pure returns (bool) {
        uint16 lp = uint16(uint160(addr));
        return lp >= 9000 && lp < 10000;
    }

    /// @notice Check if address is a Bridge precompile (LP-6xxx)
    /// @param addr The address to check
    /// @return True if address is in LP-6xxx range
    function isBridgePrecompile(address addr) internal pure returns (bool) {
        uint16 lp = uint16(uint160(addr));
        return lp >= 6000 && lp < 7000;
    }
}
