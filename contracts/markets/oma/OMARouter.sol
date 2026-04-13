// SPDX-License-Identifier: MIT
pragma solidity ^0.8.31;

import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { SafeERC20, IERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { AccessControl } from "@openzeppelin/contracts/access/AccessControl.sol";
import { OracleMirroredAMM } from "./OracleMirroredAMM.sol";

/// @title OMARouter
/// @author Lux Industries
/// @notice Multi-pool router that aggregates OMA instances and routes to best price.
///         When multiple OMA pools exist (different oracles, margins, or base tokens),
///         the router finds the best execution price across all of them.
contract OMARouter is ReentrancyGuard, AccessControl {
    using SafeERC20 for IERC20;

    // ═══════════════════════════════════════════════════════════════════════
    // CONSTANTS
    // ═══════════════════════════════════════════════════════════════════════

    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");

    // ═══════════════════════════════════════════════════════════════════════
    // STATE
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice Registered OMA pools
    OracleMirroredAMM[] public pools;

    /// @notice Quick lookup: pool address -> index + 1 (0 = not registered)
    mapping(address => uint256) public poolIndex;

    // ═══════════════════════════════════════════════════════════════════════
    // EVENTS
    // ═══════════════════════════════════════════════════════════════════════

    event PoolAdded(address indexed pool, uint256 index);
    event PoolRemoved(address indexed pool);
    event RouterSwap(
        address indexed user,
        string symbol,
        bool isBuy,
        uint256 amountIn,
        uint256 amountOut,
        uint256 poolUsed
    );

    // ═══════════════════════════════════════════════════════════════════════
    // ERRORS
    // ═══════════════════════════════════════════════════════════════════════

    error ZeroAddress();
    error NoPools();
    error NoPoolSupportsSymbol(string symbol);
    error PoolAlreadyAdded(address pool);
    error PoolNotFound(address pool);

    // ═══════════════════════════════════════════════════════════════════════
    // CONSTRUCTOR
    // ═══════════════════════════════════════════════════════════════════════

    constructor(address admin) {
        if (admin == address(0)) revert ZeroAddress();
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(ADMIN_ROLE, admin);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // ROUTER
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice Get the best execution price across all pools for a symbol
    /// @param symbol Asset symbol
    /// @param isBuy True for buy (want lowest price), false for sell (want highest price)
    /// @return bestPrice Best execution price found (18 decimals)
    /// @return bestPoolIndex Index of the pool with best price
    function getBestPrice(string calldata symbol, bool isBuy)
        external
        view
        returns (uint256 bestPrice, uint256 bestPoolIndex)
    {
        if (pools.length == 0) revert NoPools();

        bool found = false;
        for (uint256 i = 0; i < pools.length; i++) {
            // Check if pool has this symbol registered
            address token = pools[i].getToken(symbol);
            if (token == address(0)) continue;

            (uint256 execPrice,) = pools[i].getExecutionPrice(symbol, isBuy);

            if (!found) {
                bestPrice = execPrice;
                bestPoolIndex = i;
                found = true;
            } else if (isBuy && execPrice < bestPrice) {
                // Buy: lower price is better for buyer
                bestPrice = execPrice;
                bestPoolIndex = i;
            } else if (!isBuy && execPrice > bestPrice) {
                // Sell: higher price is better for seller
                bestPrice = execPrice;
                bestPoolIndex = i;
            }
        }

        if (!found) revert NoPoolSupportsSymbol(symbol);
    }

    /// @notice Swap through the pool with the best price
    /// @param symbol Asset symbol
    /// @param isBuy True for buy, false for sell
    /// @param amountIn Amount of input token
    /// @param minAmountOut Minimum output (slippage protection)
    /// @return amountOut Actual output amount
    function swap(string calldata symbol, bool isBuy, uint256 amountIn, uint256 minAmountOut)
        external
        nonReentrant
        returns (uint256 amountOut)
    {
        if (pools.length == 0) revert NoPools();

        // Find best pool
        uint256 bestPoolIndex;
        uint256 bestPrice;
        bool found = false;

        for (uint256 i = 0; i < pools.length; i++) {
            address token = pools[i].getToken(symbol);
            if (token == address(0)) continue;

            (uint256 execPrice,) = pools[i].getExecutionPrice(symbol, isBuy);

            if (!found) {
                bestPrice = execPrice;
                bestPoolIndex = i;
                found = true;
            } else if (isBuy && execPrice < bestPrice) {
                bestPrice = execPrice;
                bestPoolIndex = i;
            } else if (!isBuy && execPrice > bestPrice) {
                bestPrice = execPrice;
                bestPoolIndex = i;
            }
        }

        if (!found) revert NoPoolSupportsSymbol(symbol);

        // Execute swap on best pool
        // Caller must have approved the pool's base token (for buys) or security token (for sells)
        amountOut = pools[bestPoolIndex].swap(symbol, isBuy, amountIn, minAmountOut);

        emit RouterSwap(msg.sender, symbol, isBuy, amountIn, amountOut, bestPoolIndex);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // ADMIN
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice Add an OMA pool to the router
    /// @param pool OMA pool address
    function addPool(address pool) external onlyRole(ADMIN_ROLE) {
        if (pool == address(0)) revert ZeroAddress();
        if (poolIndex[pool] != 0) revert PoolAlreadyAdded(pool);

        pools.push(OracleMirroredAMM(pool));
        poolIndex[pool] = pools.length; // 1-indexed
        emit PoolAdded(pool, pools.length - 1);
    }

    /// @notice Remove an OMA pool from the router
    /// @param pool OMA pool address
    function removePool(address pool) external onlyRole(ADMIN_ROLE) {
        uint256 idx = poolIndex[pool];
        if (idx == 0) revert PoolNotFound(pool);

        uint256 arrayIdx = idx - 1;
        uint256 lastIdx = pools.length - 1;

        if (arrayIdx != lastIdx) {
            // Swap with last element
            pools[arrayIdx] = pools[lastIdx];
            poolIndex[address(pools[arrayIdx])] = idx;
        }

        pools.pop();
        delete poolIndex[pool];
        emit PoolRemoved(pool);
    }

    /// @notice Get the number of registered pools
    /// @return count Number of pools
    function poolCount() external view returns (uint256 count) {
        return pools.length;
    }
}
