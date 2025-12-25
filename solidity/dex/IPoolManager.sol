// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Currency, PoolKey, BalanceDelta, HookPermissions} from "./Types.sol";

/// @title IPoolManager
/// @notice Interface for the Lux DEX singleton pool manager with flash accounting
/// @dev All pools live in this single contract, enabling unified liquidity across all markets
/// @dev Precompile address: 0x0400
interface IPoolManager {
    // =========================================================================
    // Errors
    // =========================================================================

    error Unauthorized();
    error Reentrant();
    error PoolAlreadyInitialized();
    error PoolNotInitialized();
    error CurrencyNotSorted();
    error InvalidFee();
    error InvalidSqrtPrice();
    error TickOutOfRange();
    error InvalidTickRange();
    error NonZeroDelta();
    error NoLiquidity();

    // =========================================================================
    // Pool Management
    // =========================================================================

    /// @notice Initialize a new pool
    /// @param key The pool key defining the currencies, fee, tick spacing, and hooks
    /// @param sqrtPriceX96 The initial sqrt price (as a Q64.96 value)
    /// @param hookData Additional data passed to hooks
    /// @return tick The initial tick corresponding to the sqrt price
    function initialize(
        PoolKey calldata key,
        uint160 sqrtPriceX96,
        bytes calldata hookData
    ) external returns (int24 tick);

    /// @notice Get the pool state for a given key
    /// @param key The pool key
    /// @return sqrtPriceX96 Current sqrt price
    /// @return tick Current tick
    /// @return liquidity Current liquidity
    function getPool(
        PoolKey calldata key
    ) external view returns (uint160 sqrtPriceX96, int24 tick, uint128 liquidity);

    // =========================================================================
    // Flash Accounting - Lock/Unlock Pattern
    // =========================================================================

    /// @notice Acquire a callback context for flash accounting
    /// @dev All operations within the callback track balance changes but don't execute transfers
    /// @dev At the end, all deltas must net to zero
    /// @param data Additional data passed to the callback
    /// @return result Data returned from the callback
    function lock(bytes calldata data) external returns (bytes memory result);

    /// @notice Settle a currency delta for the current locker
    /// @dev Called by the locker to pay/receive tokens
    /// @param currency The currency to settle
    /// @param amount The amount to settle (positive = pay pool, negative = receive from pool)
    function settle(Currency currency, int256 amount) external;

    /// @notice Take tokens owed to a recipient
    /// @param currency The currency to take
    /// @param to The recipient address
    /// @param amount The amount to take
    function take(Currency currency, address to, uint256 amount) external;

    /// @notice Sync reserves for a currency after external transfer
    function sync(Currency currency) external;

    // =========================================================================
    // Core DEX Operations
    // =========================================================================

    /// @notice Execute a swap in a pool
    /// @param key The pool key
    /// @param params The swap parameters
    /// @param hookData Additional data passed to hooks
    /// @return delta The balance delta (positive = user owes pool, negative = pool owes user)
    function swap(
        PoolKey calldata key,
        SwapParams calldata params,
        bytes calldata hookData
    ) external returns (BalanceDelta delta);

    /// @notice Add or remove liquidity from a pool
    /// @param key The pool key
    /// @param params The modify liquidity parameters
    /// @param hookData Additional data passed to hooks
    /// @return delta0 The balance delta for currency0
    /// @return delta1 The balance delta for currency1
    function modifyLiquidity(
        PoolKey calldata key,
        ModifyLiquidityParams calldata params,
        bytes calldata hookData
    ) external returns (BalanceDelta delta0, BalanceDelta delta1);

    /// @notice Donate tokens to the pool (for protocol revenue)
    /// @param key The pool key
    /// @param amount0 The amount of currency0 to donate
    /// @param amount1 The amount of currency1 to donate
    /// @param hookData Additional data passed to hooks
    function donate(
        PoolKey calldata key,
        uint256 amount0,
        uint256 amount1,
        bytes calldata hookData
    ) external;

    // =========================================================================
    // Flash Loans
    // =========================================================================

    /// @notice Flash loan callback
    /// @param borrower The address to receive the loan
    /// @param currency The currency to borrow
    /// @param amount The amount to borrow
    /// @param data Additional data passed to the callback
    function flash(
        address borrower,
        Currency currency,
        uint256 amount,
        bytes calldata data
    ) external;

    // =========================================================================
    // Protocol Fees
    // =========================================================================

    /// @notice Set the protocol fee for a pool
    /// @param key The pool key
    /// @param newProtocolFee The new protocol fee (in basis points)
    function setProtocolFee(PoolKey calldata key, uint8 newProtocolFee) external;

    /// @notice Collect accumulated protocol fees
    /// @param key The pool key
    /// @param recipient The address to receive the fees
    /// @return amount0 The amount of currency0 collected
    /// @return amount1 The amount of currency1 collected
    function collectProtocol(
        PoolKey calldata key,
        address recipient
    ) external returns (uint256 amount0, uint256 amount1);
}

// =========================================================================
// Parameter Types (embedded for documentation)
// =========================================================================

/// @notice Parameters for a swap
struct SwapParams {
    bool zeroForOne;  // Direction: true = currency0 -> currency1
    int256 amountSpecified;  // Amount to swap (positive = exact input, negative = exact output)
    uint160 sqrtPriceLimitX96;  // Price limit (0 = no limit)
}

/// @notice Parameters for modifying liquidity
struct ModifyLiquidityParams {
    int24 tickLower;  // Lower tick bound
    int24 tickUpper;  // Upper tick bound
    int128 liquidityDelta;  // Change in liquidity (positive = add, negative = remove)
    bytes32 salt;  // Salt for position key (for uniqueness)
}

// =========================================================================
// Events (for off-chain indexing)
// =========================================================================

event PoolInitialized(
    bytes32 indexed poolId,
    PoolKey key,
    uint160 sqrtPriceX96,
    int24 tick
);

event Swap(
    bytes32 indexed poolId,
    address indexed sender,
    int256 amount0,
    int256 amount1,
    uint160 sqrtPriceX96,
    int24 tick
);

event ModifyLiquidity(
    bytes32 indexed poolId,
    address indexed sender,
    int24 tickLower,
    int24 tickUpper,
    int128 liquidityDelta,
    int256 amount0,
    int256 amount1
);

event Donate(
    bytes32 indexed poolId,
    address indexed sender,
    uint256 amount0,
    uint256 amount1
);
