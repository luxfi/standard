// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

// =========================================================================
// Currency - Represents a token (native or ERC20)
// =========================================================================

/// @notice Represents a currency (native LUX or ERC20 token)
/// @dev address(0) represents native LUX
type Currency is address;

/// @notice Library for Currency operations
library CurrencyLib {
    /// @notice Get the native currency (address(0))
    function native() internal pure returns (Currency) {
        return Currency.wrap(address(0));
    }

    /// @notice Check if currency is native LUX
    function isNative(Currency currency) internal pure returns (bool) {
        return Currency.unwrap(currency) == address(0);
    }

    /// @notice Convert to address
    function toAddress(Currency currency) internal pure returns (address) {
        return Currency.unwrap(currency);
    }

    /// @notice Create currency from address
    function fromAddress(address addr) internal pure returns (Currency) {
        return Currency.wrap(addr);
    }
}

// =========================================================================
// BalanceDelta - Represents token balance changes
// =========================================================================

/// @notice Represents the change in token balances from an operation
/// @dev Positive amounts mean the user owes the pool
/// @dev Negative amounts mean the pool owes the user
type BalanceDelta is int256;

/// @notice Library for BalanceDelta operations
library BalanceDeltaLib {
    /// @notice Zero balance delta
    function zero() internal pure returns (BalanceDelta) {
        return BalanceDelta.wrap(0);
    }

    /// @notice Get the amount for currency0
    function amount0(BalanceDelta delta) internal pure returns (int256) {
        return BalanceDelta.unwrap(delta);
    }

    /// @notice Get the amount for currency1
    function amount1(BalanceDelta delta) internal pure returns (int256) {
        return -BalanceDelta.unwrap(delta);
    }

    /// @notice Create delta from amounts
    function create(int256 amount0, int256 amount1) internal pure returns (BalanceDelta) {
        return BalanceDelta.wrap(amount0 - amount1);
    }
}

// =========================================================================
// PoolKey - Uniquely identifies a pool
// =========================================================================

/// @notice Defines a pool's characteristics
/// @dev Currencies must be sorted (currency0 < currency1 by address)
struct PoolKey {
    Currency currency0;      // Lower address token
    Currency currency1;      // Higher address token
    uint24 fee;              // Fee in basis points (e.g., 3000 = 0.30%)
    int24 tickSpacing;       // Tick spacing for concentrated liquidity
    address hooks;           // Hook contract address (address(0) = no hooks)
}

/// @notice Library for PoolKey operations
library PoolKeyLib {
    /// @notice Compute the unique ID for a pool key
    /// @dev Uses BLAKE3 hash of the key components
    function ID(PoolKey calldata key) internal pure returns (bytes32) {
        return keccak256(abi.encode(
            key.currency0,
            key.currency1,
            key.fee,
            key.tickSpacing,
            key.hooks
        ));
    }
}

// =========================================================================
// HookPermissions - Bitmap of hook capabilities
// =========================================================================

/// @notice Bitmap of hook capabilities
/// @dev Following Uniswap v4 pattern where permissions are encoded in hook address
type HookPermissions is uint16;

/// @notice Library for HookPermissions
library HookPermissionsLib {
    /// @notice No permissions
    function none() internal pure returns (HookPermissions) {
        return HookPermissions.wrap(0);
    }

    /// @notice Check if has beforeInitialize permission
    function hasBeforeInitialize(HookPermissions perms) internal pure returns (bool) {
        return (HookPermissions.unwrap(perms) & 1 << 0) != 0;
    }

    /// @notice Check if has afterInitialize permission
    function hasAfterInitialize(HookPermissions perms) internal pure returns (bool) {
        return (HookPermissions.unwrap(perms) & 1 << 1) != 0;
    }

    /// @notice Check if has beforeAddLiquidity permission
    function hasBeforeAddLiquidity(HookPermissions perms) internal pure returns (bool) {
        return (HookPermissions.unwrap(perms) & 1 << 2) != 0;
    }

    /// @notice Check if has afterAddLiquidity permission
    function hasAfterAddLiquidity(HookPermissions perms) internal pure returns (bool) {
        return (HookPermissions.unwrap(perms) & 1 << 3) != 0;
    }

    /// @notice Check if has beforeRemoveLiquidity permission
    function hasBeforeRemoveLiquidity(HookPermissions perms) internal pure returns (bool) {
        return (HookPermissions.unwrap(perms) & 1 << 4) != 0;
    }

    /// @notice Check if has afterRemoveLiquidity permission
    function hasAfterRemoveLiquidity(HookPermissions perms) internal pure returns (bool) {
        return (HookPermissions.unwrap(perms) & 1 << 5) != 0;
    }

    /// @notice Check if has beforeSwap permission
    function hasBeforeSwap(HookPermissions perms) internal pure returns (bool) {
        return (HookPermissions.unwrap(perms) & 1 << 6) != 0;
    }

    /// @notice Check if has afterSwap permission
    function hasAfterSwap(HookPermissions perms) internal pure returns (bool) {
        return (HookPermissions.unwrap(perms) & 1 << 7) != 0;
    }

    /// @notice Check if has beforeDonate permission
    function hasBeforeDonate(HookPermissions perms) internal pure returns (bool) {
        return (HookPermissions.unwrap(perms) & 1 << 8) != 0;
    }

    /// @notice Check if has afterDonate permission
    function hasAfterDonate(HookPermissions perms) internal pure returns (bool) {
        return (HookPermissions.unwrap(perms) & 1 << 9) != 0;
    }

    /// @notice Check if has beforeFlash permission
    function hasBeforeFlash(HookPermissions perms) internal pure returns (bool) {
        return (HookPermissions.unwrap(perms) & 1 << 10) != 0;
    }

    /// @notice Check if has afterFlash permission
    function hasAfterFlash(HookPermissions perms) internal pure returns (bool) {
        return (HookPermissions.unwrap(perms) & 1 << 11) != 0;
    }

    /// @notice Get all permissions as a bitmap
    function toBitmap(HookPermissions perms) internal pure returns (uint16) {
        return HookPermissions.unwrap(perms);
    }

    /// @notice Create permissions from bitmap
    function fromBitmap(uint16 bitmap) internal pure returns (HookPermissions) {
        return HookPermissions.wrap(bitmap);
    }
}

// =========================================================================
// Parameter Types (re-exported for convenience)
// =========================================================================

/// @notice Parameters for a swap (must match IPoolManager.sol)
struct SwapParams {
    bool zeroForOne;           // Direction: true = currency0 -> currency1
    int256 amountSpecified;    // Amount to swap (positive = exact input, negative = exact output)
    uint160 sqrtPriceLimitX96; // Price limit (0 = no limit)
}

/// @notice Parameters for modifying liquidity (must match IPoolManager.sol)
struct ModifyLiquidityParams {
    int24 tickLower;           // Lower tick bound
    int24 tickUpper;           // Upper tick bound
    int128 liquidityDelta;     // Change in liquidity (positive = add, negative = remove)
    bytes32 salt;              // Salt for position key (for uniqueness)
}

// =========================================================================
// Constants
// =========================================================================

/// @notice Fee tier constants (in basis points)
uint24 constant FEE_001 = 100;     // 0.01% - stablecoins
uint24 constant FEE_005 = 500;     // 0.05% - stable pairs
uint24 constant FEE_030 = 3000;    // 0.30% - standard
uint24 constant FEE_100 = 10000;   // 1.00% - exotic pairs
uint24 constant FEE_MAX = 100000;  // 10% max fee

/// @notice Tick spacing constants
int24 constant TICK_SPACING_001 = 1;
int24 constant TICK_SPACING_005 = 10;
int24 constant TICK_SPACING_030 = 60;
int24 constant TICK_SPACING_100 = 200;

/// @notice Price limits
uint160 constant MIN_SQRT_RATIO = 4295128739;
uint160 constant MAX_SQRT_RATIO = 1461446703485210103287273052203988822378723970342;
