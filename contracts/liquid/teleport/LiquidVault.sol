// SPDX-License-Identifier: BSD-3-Clause
// Copyright (c) 2025 Lux Industries Inc.
pragma solidity ^0.8.31;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {TeleportVault} from "./TeleportVault.sol";
import {IYieldStrategy} from "../../yield/IYieldStrategy.sol";

// Note: LiquidVault deploys on external chains (Base/Ethereum) where yield strategies run

/**
 * @title LiquidVault
 * @author Lux Industries
 * @notice MPC-controlled ETH custody vault with yield strategy routing
 * @dev Extends TeleportVault with ETH-specific deposit/release and yield strategies
 *
 * Architecture:
 * - Deposits ETH on Base/Ethereum, emits event for Lux bridge
 * - MPC controls withdrawals and strategy allocations
 * - Strategies earn yield that flows to Lux for debt repayment
 * - Maintains liquidity buffer for withdrawals
 *
 * Invariants:
 * - totalDeposited = strategyBalances + buffer + pending
 * - Only MPC can release ETH or manage strategies
 * - Minimum buffer maintained for withdrawals
 */
contract LiquidVault is TeleportVault, Pausable {
    using SafeERC20 for IERC20;

    // ═══════════════════════════════════════════════════════════════════════
    // ROLES
    // ═══════════════════════════════════════════════════════════════════════

    bytes32 public constant STRATEGY_ROLE = keccak256("STRATEGY_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    // ═══════════════════════════════════════════════════════════════════════
    // TYPES
    // ═══════════════════════════════════════════════════════════════════════

    struct Strategy {
        address adapter;           // Strategy adapter address
        uint256 allocated;         // Amount allocated to this strategy
        uint256 lastHarvest;       // Last harvest timestamp
        bool active;               // Is strategy active
    }

    // ═══════════════════════════════════════════════════════════════════════
    // CONSTANTS
    // ═══════════════════════════════════════════════════════════════════════

    uint256 public constant MIN_BUFFER_BPS = 1000;       // 10% minimum buffer
    uint256 public constant MAX_STRATEGIES = 10;

    /// @notice Maximum withdrawal per address per period (H-03 fix)
    uint256 public constant MAX_WITHDRAWAL_PER_PERIOD = 100 ether;

    /// @notice Withdrawal rate limit period
    uint256 public constant WITHDRAWAL_PERIOD = 1 hours;

    // ═══════════════════════════════════════════════════════════════════════
    // STATE
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice Yield nonce for yield proof separation
    uint256 public yieldNonce;

    /// @notice Operation nonce for MPC signature replay protection (H-03 fix)
    uint256 public operationNonce;

    /// @notice Buffer percentage (in basis points)
    uint256 public bufferBps = 2000; // 20% default

    /// @notice Yield strategies
    Strategy[] public strategies;

    /// @notice Withdrawal amount per recipient in current period (H-03 rate limit)
    mapping(address => uint256) public withdrawalAmount;

    /// @notice Last withdrawal timestamp per recipient (H-03 rate limit)
    mapping(address => uint256) public lastWithdrawalTime;

    // ═══════════════════════════════════════════════════════════════════════
    // EVENTS
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice Emitted when funds allocated to strategy
    event StrategyAllocated(
        uint256 indexed strategyIndex,
        uint256 amount
    );

    /// @notice Emitted when funds deallocated from strategy
    event StrategyDeallocated(
        uint256 indexed strategyIndex,
        uint256 amount
    );

    /// @notice Emitted when yield harvested
    event YieldHarvested(
        uint256 indexed yieldNonce,
        uint256 totalYield,
        uint256 timestamp
    );

    /// @notice Emitted when strategy added
    event StrategyAdded(
        uint256 indexed index,
        address adapter
    );

    /// @notice Emitted when strategy removed
    event StrategyRemoved(uint256 indexed index);

    /// @notice Emitted when buffer updated
    event BufferUpdated(uint256 oldBuffer, uint256 newBuffer);

    // ═══════════════════════════════════════════════════════════════════════
    // ERRORS
    // ═══════════════════════════════════════════════════════════════════════

    error InsufficientBuffer();
    error StrategyNotActive();
    error ExceedsMaxStrategies();
    error StrategyHasFunds();
    error BufferTooLow();
    error BufferTooHigh();
    error ExceedsWithdrawalLimit();

    // ═══════════════════════════════════════════════════════════════════════
    // CONSTRUCTOR
    // ═══════════════════════════════════════════════════════════════════════

    constructor(address _mpcOracle) TeleportVault(_mpcOracle) {}

    // ═══════════════════════════════════════════════════════════════════════
    // DEPOSIT (PUBLIC)
    // ═══════════════════════════════════════════════════════════════════════

    /**
     * @notice Deposit ETH to be bridged to Lux
     * @param luxRecipient Address to receive LETH on Lux
     * @return nonce Unique deposit identifier
     */
    function depositETH(address luxRecipient) external payable nonReentrant returns (uint256 nonce) {
        nonce = _recordDeposit(luxRecipient, msg.value);
    }

    /**
     * @notice Deposit ETH for self (msg.sender receives on Lux)
     * @return nonce Unique deposit identifier
     */
    function depositETH() external payable nonReentrant returns (uint256 nonce) {
        nonce = _recordDeposit(msg.sender, msg.value);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // RELEASE (MPC ONLY)
    // ═══════════════════════════════════════════════════════════════════════

    /**
     * @notice Release ETH for Lux withdrawal (MPC only)
     * @param recipient ETH recipient address
     * @param amount Amount to release
     * @param _withdrawNonce Unique withdraw nonce for replay protection
     * @param signature MPC signature authorizing release
     * @dev H-03 fix: Added rate limiting, pause capability, and operation nonce
     */
    function releaseETH(
        address recipient,
        uint256 amount,
        uint256 _withdrawNonce,
        bytes calldata signature
    ) external nonReentrant whenNotPaused {
        if (recipient == address(0)) revert ZeroAddress();
        if (amount == 0) revert ZeroAmount();

        // H-03 fix: Validate withdrawal rate limit
        _validateWithdrawal(recipient, amount);

        // H-03 fix: Include operationNonce in signature hash for replay protection
        bytes32 messageHash = keccak256(abi.encodePacked(
            "RELEASE",
            recipient,
            amount,
            _withdrawNonce,
            operationNonce,
            block.chainid
        ));
        _verifyMPCSignature(messageHash, signature);

        // H-03 fix: Increment operation nonce after verification
        operationNonce++;

        // Check buffer constraints and deallocate if needed
        _ensureBuffer(amount);

        if (address(this).balance < amount) revert InsufficientBalance();

        // Record release
        _recordRelease(recipient, amount, _withdrawNonce);

        // Transfer ETH
        (bool success, ) = recipient.call{value: amount}("");
        if (!success) revert TransferFailed();
    }

    // ═══════════════════════════════════════════════════════════════════════
    // STRATEGY MANAGEMENT (MPC ONLY)
    // ═══════════════════════════════════════════════════════════════════════

    /**
     * @notice Allocate ETH to a yield strategy (MPC only)
     * @param strategyIndex Strategy index
     * @param amount Amount to allocate
     * @param signature MPC signature
     */
    function allocateToStrategy(
        uint256 strategyIndex,
        uint256 amount,
        bytes calldata signature
    ) external nonReentrant onlyRole(MPC_ROLE) {
        Strategy storage strategy = strategies[strategyIndex];
        if (!strategy.active) revert StrategyNotActive();
        if (amount == 0) revert ZeroAmount();

        // Verify MPC signature
        bytes32 messageHash = keccak256(abi.encodePacked(
            "ALLOCATE",
            strategyIndex,
            amount,
            block.timestamp
        ));
        _verifyMPCSignature(messageHash, signature);

        // Ensure minimum buffer
        uint256 bufferRequired = totalDeposited * bufferBps / BASIS_POINTS;
        if (address(this).balance - amount < bufferRequired) revert InsufficientBuffer();

        // Deposit to strategy
        IYieldStrategy(strategy.adapter).deposit{value: amount}(amount);
        strategy.allocated += amount;

        emit StrategyAllocated(strategyIndex, amount);
    }

    /**
     * @notice Deallocate ETH from a yield strategy (MPC only)
     * @param strategyIndex Strategy index
     * @param amount Amount to deallocate
     * @param signature MPC signature
     */
    function deallocateFromStrategy(
        uint256 strategyIndex,
        uint256 amount,
        bytes calldata signature
    ) external nonReentrant onlyRole(MPC_ROLE) {
        Strategy storage strategy = strategies[strategyIndex];
        if (!strategy.active) revert StrategyNotActive();
        if (amount == 0) revert ZeroAmount();

        // Verify MPC signature
        bytes32 messageHash = keccak256(abi.encodePacked(
            "DEALLOCATE",
            strategyIndex,
            amount,
            block.timestamp
        ));
        _verifyMPCSignature(messageHash, signature);

        // Withdraw from strategy
        uint256 withdrawn = IYieldStrategy(strategy.adapter).withdraw(amount);
        strategy.allocated -= withdrawn;

        emit StrategyDeallocated(strategyIndex, withdrawn);
    }

    /**
     * @notice Harvest yield from all strategies (MPC only)
     * @param signature MPC signature
     * @return totalYield Total yield harvested
     */
    function harvestYield(bytes calldata signature) external nonReentrant onlyRole(MPC_ROLE) returns (uint256 totalYield) {
        // Verify MPC signature
        bytes32 messageHash = keccak256(abi.encodePacked(
            "HARVEST",
            block.timestamp
        ));
        _verifyMPCSignature(messageHash, signature);

        uint256 balanceBefore = address(this).balance;

        for (uint256 i = 0; i < strategies.length; i++) {
            if (strategies[i].active) {
                IYieldStrategy(strategies[i].adapter).harvest();
                strategies[i].lastHarvest = block.timestamp;
            }
        }

        totalYield = address(this).balance - balanceBefore;

        uint256 currentYieldNonce = ++yieldNonce;

        emit YieldHarvested(currentYieldNonce, totalYield, block.timestamp);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // ADMIN FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════

    /**
     * @notice Add a new yield strategy
     * @param adapter Strategy adapter address
     */
    function addStrategy(address adapter) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (strategies.length >= MAX_STRATEGIES) revert ExceedsMaxStrategies();
        if (adapter == address(0)) revert ZeroAddress();

        strategies.push(Strategy({
            adapter: adapter,
            allocated: 0,
            lastHarvest: block.timestamp,
            active: true
        }));

        emit StrategyAdded(strategies.length - 1, adapter);
    }

    /**
     * @notice Remove a strategy (must be fully deallocated first)
     * @param index Strategy index
     */
    function removeStrategy(uint256 index) external onlyRole(DEFAULT_ADMIN_ROLE) {
        Strategy storage strategy = strategies[index];
        if (strategy.allocated != 0) revert StrategyHasFunds();

        strategy.active = false;

        emit StrategyRemoved(index);
    }

    /**
     * @notice Update buffer percentage
     * @param _bufferBps New buffer in basis points
     */
    function setBufferBps(uint256 _bufferBps) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (_bufferBps < MIN_BUFFER_BPS) revert BufferTooLow();
        if (_bufferBps > BASIS_POINTS) revert BufferTooHigh();

        uint256 oldBuffer = bufferBps;
        bufferBps = _bufferBps;

        emit BufferUpdated(oldBuffer, _bufferBps);
    }

    /**
     * @notice Pause all withdrawals (emergency) (H-03 fix)
     * @dev Can be called by PAUSER_ROLE or DEFAULT_ADMIN_ROLE
     */
    function pause() external {
        if (!hasRole(PAUSER_ROLE, msg.sender) && !hasRole(DEFAULT_ADMIN_ROLE, msg.sender)) {
            revert AccessControlUnauthorizedAccount(msg.sender, PAUSER_ROLE);
        }
        _pause();
    }

    /**
     * @notice Unpause withdrawals (H-03 fix)
     * @dev Only DEFAULT_ADMIN_ROLE can unpause
     */
    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }

    // ═══════════════════════════════════════════════════════════════════════
    // VIEW FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════

    /**
     * @notice Get the underlying asset (ETH = address(0))
     */
    function asset() external pure override returns (address) {
        return address(0); // ETH
    }

    /**
     * @notice Get current vault balance (ETH in contract)
     */
    function vaultBalance() external view override returns (uint256) {
        return address(this).balance;
    }

    /**
     * @notice Get current ETH buffer amount
     */
    function currentBuffer() external view returns (uint256) {
        return address(this).balance;
    }

    /**
     * @notice Get required buffer amount
     */
    function requiredBuffer() external view returns (uint256) {
        return totalDeposited * bufferBps / BASIS_POINTS;
    }

    /**
     * @notice Get total allocated to strategies
     */
    function totalAllocated() external view returns (uint256 total) {
        for (uint256 i = 0; i < strategies.length; i++) {
            if (strategies[i].active) {
                total += strategies[i].allocated;
            }
        }
    }

    /**
     * @notice Get strategy count
     */
    function strategyCount() external view returns (uint256) {
        return strategies.length;
    }

    /**
     * @notice Get strategy info
     */
    function getStrategy(uint256 index) external view returns (Strategy memory) {
        return strategies[index];
    }

    // ═══════════════════════════════════════════════════════════════════════
    // INTERNAL FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════

    /**
     * @notice Validate withdrawal against rate limits (H-03 fix)
     * @param recipient Address receiving the withdrawal
     * @param amount Amount being withdrawn
     * @dev Resets rate limit period if enough time has passed
     */
    function _validateWithdrawal(address recipient, uint256 amount) internal {
        // Reset period if enough time has passed
        if (block.timestamp > lastWithdrawalTime[recipient] + WITHDRAWAL_PERIOD) {
            withdrawalAmount[recipient] = 0;
            lastWithdrawalTime[recipient] = block.timestamp;
        }

        // Check rate limit
        if (withdrawalAmount[recipient] + amount > MAX_WITHDRAWAL_PER_PERIOD) {
            revert ExceedsWithdrawalLimit();
        }

        withdrawalAmount[recipient] += amount;
    }

    /**
     * @notice Ensure sufficient buffer for withdrawal, deallocating if needed
     * @param withdrawAmount Amount being withdrawn
     */
    function _ensureBuffer(uint256 withdrawAmount) internal {
        uint256 bufferRequired = totalDeposited * MIN_BUFFER_BPS / BASIS_POINTS;
        uint256 currentBal = address(this).balance;

        if (currentBal >= withdrawAmount + bufferRequired) {
            return; // Sufficient buffer
        }

        // Need to deallocate from strategies
        uint256 needed = withdrawAmount + bufferRequired - currentBal;
        _deallocateForWithdraw(needed);
    }

    /**
     * @notice Deallocate funds from strategies for withdrawal
     * @param needed Amount needed from strategies
     */
    function _deallocateForWithdraw(uint256 needed) internal {
        uint256 remaining = needed;

        for (uint256 i = 0; i < strategies.length && remaining > 0; i++) {
            Strategy storage strategy = strategies[i];
            if (!strategy.active || strategy.allocated == 0) continue;

            uint256 withdrawAmount = remaining > strategy.allocated
                ? strategy.allocated
                : remaining;

            uint256 withdrawn = IYieldStrategy(strategy.adapter).withdraw(withdrawAmount);
            strategy.allocated -= withdrawn;
            remaining -= withdrawn;

            emit StrategyDeallocated(i, withdrawn);
        }
    }

    /**
     * @notice Receive ETH
     */
    receive() external payable {}
}

// IYieldStrategy interface imported from contracts/yield/IYieldStrategy.sol
