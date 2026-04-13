// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./IHooks.sol";
import "../compliance/gates/IComplianceGate.sol";

/// @title ComplianceHook — v4 hook that gates swaps + liquidity adds by a
///        generic IComplianceGate.
/// @notice Attach to any Uniswap v4 pool that holds a SecurityToken or
///         regulated asset. Works with any provider implementing
///         IComplianceGate (Liquidity.io, any other regulated venue,
///         pure-Solidity test gates).
contract ComplianceHook is IHooksV4 {
    IComplianceGate public immutable gate;
    bool public immutable gateLiquidity;

    event ComplianceDenied(address indexed user, string reason);

    constructor(IComplianceGate _gate, bool _gateLiquidity) {
        gate = _gate;
        gateLiquidity = _gateLiquidity;
    }

    function beforeSwap(address sender, PoolKey calldata, SwapParams calldata, bytes calldata)
        external view override returns (bytes4, int128, uint24)
    {
        _requireCompliant(sender);
        return (IHooksV4.beforeSwap.selector, int128(0), uint24(0));
    }

    function afterSwap(address, PoolKey calldata, SwapParams calldata, int256, int256, bytes calldata)
        external pure override returns (bytes4, int128)
    {
        return (IHooksV4.afterSwap.selector, int128(0));
    }

    function beforeAddLiquidity(address sender, PoolKey calldata, ModifyLiquidityParams calldata, bytes calldata)
        external view override returns (bytes4)
    {
        if (gateLiquidity) _requireCompliant(sender);
        return IHooksV4.beforeAddLiquidity.selector;
    }

    /// @notice Withdraw is ALWAYS allowed. Never strand an LP who is
    ///         mid-position when compliance state changes.
    function beforeRemoveLiquidity(address, PoolKey calldata, ModifyLiquidityParams calldata, bytes calldata)
        external pure override returns (bytes4)
    {
        return IHooksV4.beforeRemoveLiquidity.selector;
    }

    function _requireCompliant(address user) internal view {
        require(gate.checkJurisdiction(user), "ComplianceHook: jurisdiction");
    }
}
