// SPDX-License-Identifier: BSD-3-Clause
// Copyright (c) 2025 Lux Industries Inc.
pragma solidity ^0.8.31;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title LiquidYield
 * @author Lux Industries
 * @notice Yield manager for self-repaying bridged asset loans
 * @dev Part of the Liquid system for self-repaying bridged ETH loans
 *
 * Flow:
 * 1. Teleporter mints yield LETH here (from remote strategy harvests)
 * 2. LiquidYield burns the LETH (reducing supply)
 * 3. Notifies LiquidETH to credit debt repayment pro-rata
 *
 * The burn mechanism:
 * - Yield LETH is burned, reducing total LETH supply
 * - LiquidETH reduces user debts proportionally
 * - Net effect: debts decrease while collateral stays same
 * - Users' positions become healthier automatically
 */
contract LiquidYield is Ownable, AccessControl, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // ═══════════════════════════════════════════════════════════════════════
    // ROLES
    // ═══════════════════════════════════════════════════════════════════════

    bytes32 public constant TELEPORTER_ROLE = keccak256("TELEPORTER_ROLE");
    bytes32 public constant KEEPER_ROLE = keccak256("KEEPER_ROLE");

    // ═══════════════════════════════════════════════════════════════════════
    // TYPES
    // ═══════════════════════════════════════════════════════════════════════

    struct YieldEvent {
        uint256 amount;
        uint256 srcChainId;
        uint256 timestamp;
        bool processed;
    }

    // ═══════════════════════════════════════════════════════════════════════
    // STATE
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice LETH token (burnable)
    ILETHBurnable public immutable leth;

    /// @notice LiquidETH vault for debt notifications
    ILiquidETH public liquidETH;

    /// @notice DEX router for swapping (if yield comes in different token)
    address public dexRouter;

    /// @notice Total yield received
    uint256 public totalYieldReceived;

    /// @notice Total yield burned (sent to debt repayment)
    uint256 public totalYieldBurned;

    /// @notice Pending yield to process
    uint256 public pendingYield;

    /// @notice Yield events for tracking
    YieldEvent[] public yieldEvents;

    /// @notice Minimum batch size for processing
    uint256 public minBatchSize = 0.1 ether;

    /// @notice Paused state
    bool public paused;

    // ═══════════════════════════════════════════════════════════════════════
    // EVENTS
    // ═══════════════════════════════════════════════════════════════════════

    event YieldReceived(
        uint256 indexed eventId,
        uint256 amount,
        uint256 srcChainId,
        uint256 timestamp
    );

    event YieldProcessed(
        uint256 indexed eventId,
        uint256 amountBurned,
        uint256 timestamp
    );

    event BatchProcessed(
        uint256 amountBurned,
        uint256 eventsProcessed
    );

    event LiquidETHSet(address indexed liquidETH);
    event DEXRouterSet(address indexed router);

    // ═══════════════════════════════════════════════════════════════════════
    // ERRORS
    // ═══════════════════════════════════════════════════════════════════════

    error ZeroAmount();
    error ZeroAddress();
    error YieldPaused();
    error InsufficientYield();
    error AlreadyProcessed();
    error LiquidETHNotSet();
    error InsufficientBalance();

    // ═══════════════════════════════════════════════════════════════════════
    // MODIFIERS
    // ═══════════════════════════════════════════════════════════════════════

    modifier whenNotPaused() {
        if (paused) revert YieldPaused();
        _;
    }

    // ═══════════════════════════════════════════════════════════════════════
    // CONSTRUCTOR
    // ═══════════════════════════════════════════════════════════════════════

    constructor(address _leth) Ownable(msg.sender) {
        if (_leth == address(0)) revert ZeroAddress();
        leth = ILETHBurnable(_leth);
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // YIELD RECEIVING (from Teleporter)
    // ═══════════════════════════════════════════════════════════════════════

    /**
     * @notice Called by Teleporter when yield LETH is minted
     * @param amount Amount of yield LETH received
     * @param srcChainId Source chain ID (e.g., Base = 8453)
     */
    function onYieldReceived(
        uint256 amount,
        uint256 srcChainId
    ) external onlyRole(TELEPORTER_ROLE) whenNotPaused {
        if (amount == 0) revert ZeroAmount();

        uint256 eventId = yieldEvents.length;
        
        yieldEvents.push(YieldEvent({
            amount: amount,
            srcChainId: srcChainId,
            timestamp: block.timestamp,
            processed: false
        }));

        totalYieldReceived += amount;
        pendingYield += amount;

        emit YieldReceived(eventId, amount, srcChainId, block.timestamp);

        // Auto-process if we have enough pending yield
        if (pendingYield >= minBatchSize) {
            _processPendingYield();
        }
    }

    // ═══════════════════════════════════════════════════════════════════════
    // YIELD PROCESSING
    // ═══════════════════════════════════════════════════════════════════════

    /**
     * @notice Process pending yield - burn LETH and notify LiquidETH
     * @dev Can be called by keepers or anyone
     */
    function processYield() external nonReentrant whenNotPaused {
        _processPendingYield();
    }

    /**
     * @notice Process specific yield event
     * @param eventId Event ID to process
     * @dev H-06 fix: Added balance check before burn
     */
    function processYieldEvent(uint256 eventId) external nonReentrant whenNotPaused {
        if (eventId >= yieldEvents.length) revert InsufficientYield();

        YieldEvent storage yieldEvent = yieldEvents[eventId];
        if (yieldEvent.processed) revert AlreadyProcessed();
        if (address(liquidETH) == address(0)) revert LiquidETHNotSet();

        uint256 amount = yieldEvent.amount;

        // H-06 fix: Check balance before burn
        if (leth.balanceOf(address(this)) < amount) revert InsufficientBalance();

        // Mark as processed
        yieldEvent.processed = true;
        pendingYield -= amount;

        // Burn LETH
        leth.burn(amount);
        totalYieldBurned += amount;

        // Notify LiquidETH to credit debt repayment
        liquidETH.notifyYieldBurn(amount);

        emit YieldProcessed(eventId, amount, block.timestamp);
    }

    /**
     * @notice Force process all pending yield (keeper function)
     */
    function forceProcess() external onlyRole(KEEPER_ROLE) nonReentrant {
        _processPendingYield();
    }

    // ═══════════════════════════════════════════════════════════════════════
    // VIEW FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════

    /**
     * @notice Get number of yield events
     */
    function getYieldEventCount() external view returns (uint256) {
        return yieldEvents.length;
    }

    /**
     * @notice Get yield event details
     */
    function getYieldEvent(uint256 eventId) external view returns (YieldEvent memory) {
        return yieldEvents[eventId];
    }

    /**
     * @notice Get yield statistics
     */
    function getYieldStats() external view returns (
        uint256 received,
        uint256 burned,
        uint256 pending,
        uint256 eventCount
    ) {
        received = totalYieldReceived;
        burned = totalYieldBurned;
        pending = pendingYield;
        eventCount = yieldEvents.length;
    }

    /**
     * @notice Get unprocessed events count
     */
    function getUnprocessedCount() external view returns (uint256 count) {
        for (uint256 i = 0; i < yieldEvents.length; i++) {
            if (!yieldEvents[i].processed) {
                count++;
            }
        }
    }

    // ═══════════════════════════════════════════════════════════════════════
    // ADMIN FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════

    /**
     * @notice Set LiquidETH vault
     */
    function setLiquidETH(address _liquidETH) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (_liquidETH == address(0)) revert ZeroAddress();
        liquidETH = ILiquidETH(_liquidETH);
        emit LiquidETHSet(_liquidETH);
    }

    /**
     * @notice Set DEX router for swaps
     */
    function setDEXRouter(address _router) external onlyRole(DEFAULT_ADMIN_ROLE) {
        dexRouter = _router;
        emit DEXRouterSet(_router);
    }

    /**
     * @notice Set minimum batch size for auto-processing
     */
    function setMinBatchSize(uint256 _minBatchSize) external onlyRole(DEFAULT_ADMIN_ROLE) {
        minBatchSize = _minBatchSize;
    }

    /**
     * @notice Grant teleporter role
     */
    function grantTeleporter(address teleporter) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _grantRole(TELEPORTER_ROLE, teleporter);
    }

    /**
     * @notice Grant keeper role
     */
    function grantKeeper(address keeper) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _grantRole(KEEPER_ROLE, keeper);
    }

    /**
     * @notice Set paused state
     */
    function setPaused(bool _paused) external onlyRole(DEFAULT_ADMIN_ROLE) {
        paused = _paused;
    }

    /**
     * @notice Emergency recover tokens sent to this contract
     * @dev Only for tokens other than LETH
     */
    function emergencyRecover(
        address token,
        address recipient,
        uint256 amount
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(token != address(leth), "LiquidYield: cannot recover LETH");
        IERC20(token).safeTransfer(recipient, amount);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // INTERNAL FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════

    /**
     * @notice Process all pending yield
     * @dev H-06 fix: Added balance check before burn
     */
    function _processPendingYield() internal {
        if (pendingYield == 0) return;
        if (address(liquidETH) == address(0)) revert LiquidETHNotSet();

        uint256 amountToProcess = pendingYield;

        // H-06 fix: Check balance before burn
        if (leth.balanceOf(address(this)) < amountToProcess) revert InsufficientBalance();

        uint256 eventsProcessed = 0;

        // Mark all unprocessed events as processed
        for (uint256 i = 0; i < yieldEvents.length; i++) {
            if (!yieldEvents[i].processed) {
                yieldEvents[i].processed = true;
                eventsProcessed++;
                emit YieldProcessed(i, yieldEvents[i].amount, block.timestamp);
            }
        }

        // Reset pending
        pendingYield = 0;

        // Burn LETH
        leth.burn(amountToProcess);
        totalYieldBurned += amountToProcess;

        // Notify LiquidETH to credit debt repayment
        liquidETH.notifyYieldBurn(amountToProcess);

        emit BatchProcessed(amountToProcess, eventsProcessed);
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// INTERFACES
// ═══════════════════════════════════════════════════════════════════════════

/**
 * @notice Interface for LETH token with burn
 */
interface ILETHBurnable {
    function burn(uint256 amount) external;
    function balanceOf(address account) external view returns (uint256);
}

/**
 * @notice Interface for LiquidETH vault
 */
interface ILiquidETH {
    function notifyYieldBurn(uint256 amount) external;
}
