// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Currency, PoolKey, BalanceDelta, HookPermissions} from "./Types.sol";

/// @title IHooks
/// @notice Interface for DEX hook contracts
/// @dev Hooks can intercept and modify pool operations at specific points
/// @dev Precompile address: 0x0402
interface IHooks {
    // =========================================================================
    // Errors
    // =========================================================================

    error HookNotRegistered();
    error HookCallFailed();
    error HookInvalidAddress();
    error HookUnauthorized();

    // =========================================================================
    // Hook Callback Functions
    // =========================================================================

    /// @notice Called before a pool is initialized
    /// @dev Can modify hookData but not the key parameters
    /// @param key The pool key being initialized
    /// @param sqrtPriceX96 The initial sqrt price
    /// @param hookData Additional data from the caller
    function beforeInitialize(
        PoolKey calldata key,
        uint160 sqrtPriceX96,
        bytes calldata hookData
    ) external;

    /// @notice Called after a pool is initialized
    /// @param key The pool key that was initialized
    /// @param sqrtPriceX96 The initial sqrt price
    /// @param tick The initial tick
    /// @param hookData Additional data from the caller
    function afterInitialize(
        PoolKey calldata key,
        uint160 sqrtPriceX96,
        int24 tick,
        bytes calldata hookData
    ) external;

    /// @notice Called before liquidity is added
    /// @param key The pool key
    /// @param params The modify liquidity parameters
    /// @param hookData Additional data from the caller
    function beforeAddLiquidity(
        PoolKey calldata key,
        ModifyLiquidityParams calldata params,
        bytes calldata hookData
    ) external;

    /// @notice Called after liquidity is added
    /// @param key The pool key
    /// @param params The modify liquidity parameters
    /// @param delta0 The balance delta for currency0
    /// @param delta1 The balance delta for currency1
    /// @param hookData Additional data from the caller
    function afterAddLiquidity(
        PoolKey calldata key,
        ModifyLiquidityParams calldata params,
        BalanceDelta delta0,
        BalanceDelta delta1,
        bytes calldata hookData
    ) external;

    /// @notice Called before liquidity is removed
    /// @param key The pool key
    /// @param params The modify liquidity parameters
    /// @param hookData Additional data from the caller
    function beforeRemoveLiquidity(
        PoolKey calldata key,
        ModifyLiquidityParams calldata params,
        bytes calldata hookData
    ) external;

    /// @notice Called after liquidity is removed
    /// @param key The pool key
    /// @param params The modify liquidity parameters
    /// @param delta0 The balance delta for currency0
    /// @param delta1 The balance delta for currency1
    /// @param hookData Additional data from the caller
    function afterRemoveLiquidity(
        PoolKey calldata key,
        ModifyLiquidityParams calldata params,
        BalanceDelta delta0,
        BalanceDelta delta1,
        bytes calldata hookData
    ) external;

    /// @notice Called before a swap
    /// @dev Can modify the swap params or return a fee override
    /// @param key The pool key
    /// @param params The swap parameters
    /// @param hookData Additional data from the caller
    /// @return feeOverride Optional override for the swap fee (0 = no override)
    function beforeSwap(
        PoolKey calldata key,
        SwapParams calldata params,
        bytes calldata hookData
    ) external returns (uint24 feeOverride);

    /// @notice Called after a swap
    /// @param key The pool key
    /// @param params The swap parameters
    /// @param delta The resulting balance delta
    /// @param hookData Additional data from the caller
    function afterSwap(
        PoolKey calldata key,
        SwapParams calldata params,
        BalanceDelta delta,
        bytes calldata hookData
    ) external;

    /// @notice Called before a donate
    /// @param key The pool key
    /// @param amount0 The amount of currency0
    /// @param amount1 The amount of currency1
    /// @param hookData Additional data from the caller
    function beforeDonate(
        PoolKey calldata key,
        uint256 amount0,
        uint256 amount1,
        bytes calldata hookData
    ) external;

    /// @notice Called after a donate
    /// @param key The pool key
    /// @param amount0 The amount of currency0
    /// @param amount1 The amount of currency1
    /// @param hookData Additional data from the caller
    function afterDonate(
        PoolKey calldata key,
        uint256 amount0,
        uint256 amount1,
        bytes calldata hookData
    ) external;

    /// @notice Called before a flash loan
    /// @param key The pool key
    /// @param borrower The borrower address
    /// @param amount The flash loan amount
    /// @param fee The flash loan fee
    /// @param data Additional data from the caller
    function beforeFlash(
        PoolKey calldata key,
        address borrower,
        uint256 amount,
        uint256 fee,
        bytes calldata data
    ) external;

    /// @notice Called after a flash loan
    /// @param key The pool key
    /// @param borrower The borrower address
    /// @param amount The flash loan amount
    /// @param fee The flash loan fee
    /// @param data Additional data from the caller
    function afterFlash(
        PoolKey calldata key,
        address borrower,
        uint256 amount,
        uint256 fee,
        bytes calldata data
    ) external;
}

/// @title BaseHook
/// @notice Base contract for implementing hooks
/// @dev Handles permission checking and provides default implementations
abstract contract BaseHook is IHooks {
    /// @notice The pool manager address
    address public immutable poolManager;

    /// @notice Constructor
    /// @param _poolManager The address of the pool manager
    constructor(address _poolManager) {
        poolManager = _poolManager;
    }

    /// @notice Modifier to check that caller is the pool manager
    modifier onlyPoolManager() {
        require(msg.sender == poolManager, "BaseHook: only pool manager");
        _;
    }

    /// @notice Get the permissions for this hook
    /// @dev Override to return custom permissions
    function getHookPermissions() public pure virtual returns (HookPermissions memory);

    // Default implementations - these can be overridden

    function beforeInitialize(
        PoolKey calldata,
        uint160,
        bytes calldata
    ) external pure virtual {}

    function afterInitialize(
        PoolKey calldata,
        uint160,
        int24,
        bytes calldata
    ) external pure virtual {}

    function beforeAddLiquidity(
        PoolKey calldata,
        ModifyLiquidityParams calldata,
        bytes calldata
    ) external pure virtual {}

    function afterAddLiquidity(
        PoolKey calldata,
        ModifyLiquidityParams calldata,
        BalanceDelta,
        BalanceDelta,
        bytes calldata
    ) external pure virtual {}

    function beforeRemoveLiquidity(
        PoolKey calldata,
        ModifyLiquidityParams calldata,
        bytes calldata
    ) external pure virtual {}

    function afterRemoveLiquidity(
        PoolKey calldata,
        ModifyLiquidityParams calldata,
        BalanceDelta,
        BalanceDelta,
        bytes calldata
    ) external pure virtual {}

    function beforeSwap(
        PoolKey calldata,
        SwapParams calldata,
        bytes calldata
    ) external pure virtual returns (uint24) {
        return 0;
    }

    function afterSwap(
        PoolKey calldata,
        SwapParams calldata,
        BalanceDelta,
        bytes calldata
    ) external pure virtual {}

    function beforeDonate(
        PoolKey calldata,
        uint256,
        uint256,
        bytes calldata
    ) external pure virtual {}

    function afterDonate(
        PoolKey calldata,
        uint256,
        uint256,
        bytes calldata
    ) external pure virtual {}

    function beforeFlash(
        PoolKey calldata,
        address,
        uint256,
        uint256,
        bytes calldata
    ) external pure virtual {}

    function afterFlash(
        PoolKey calldata,
        address,
        uint256,
        uint256,
        bytes calldata
    ) external pure virtual {}
}

/// @title IHookRegistry
/// @notice Interface for the hooks registry
/// @dev Precompile address: 0x0402
interface IHookRegistry {
    /// @notice Register a hook contract
    /// @param hook The hook address
    function registerHook(address hook) external;

    /// @notice Unregister a hook contract
    /// @param hook The hook address
    function unregisterHook(address hook) external;

    /// @notice Check if a hook is registered
    /// @param hook The hook address
    /// @return True if the hook is registered
    function isRegistered(address hook) external view returns (bool);

    /// @notice Get the permissions for a hook
    /// @param hook The hook address
    /// @return permissions The hook permissions
    function getHookPermissions(address hook) external view returns (HookPermissions memory);
}
