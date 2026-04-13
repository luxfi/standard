// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title IHooksV4 — minimal Uniswap v4 hook callbacks.
/// @notice Subset of v4-core's IHooks that the standard ComplianceHook
///         needs. Avoids dragging the full v4 type system into this repo.
interface IHooksV4 {
    struct PoolKey {
        address currency0;
        address currency1;
        uint24 fee;
        int24 tickSpacing;
        address hooks;
    }
    struct SwapParams {
        bool zeroForOne;
        int256 amountSpecified;
        uint160 sqrtPriceLimitX96;
    }
    struct ModifyLiquidityParams {
        int24 tickLower;
        int24 tickUpper;
        int256 liquidityDelta;
        bytes32 salt;
    }

    function beforeSwap(address sender, PoolKey calldata key, SwapParams calldata params, bytes calldata hookData)
        external returns (bytes4 selector, int128 deltaUnspecified, uint24 feeOverride);
    function afterSwap(address sender, PoolKey calldata key, SwapParams calldata params, int256 delta0, int256 delta1, bytes calldata hookData)
        external returns (bytes4 selector, int128 hookDelta);
    function beforeAddLiquidity(address sender, PoolKey calldata key, ModifyLiquidityParams calldata params, bytes calldata hookData)
        external returns (bytes4 selector);
    function beforeRemoveLiquidity(address sender, PoolKey calldata key, ModifyLiquidityParams calldata params, bytes calldata hookData)
        external returns (bytes4 selector);
}
