// SPDX-License-Identifier: MIT
pragma solidity ^0.8.31;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { AccessControl } from "@openzeppelin/contracts/access/AccessControl.sol";

import { IFuturesMargin } from "../interfaces/futures/IFuturesMargin.sol";
import { IFutures } from "../interfaces/futures/IFutures.sol";

/**
 * @title FuturesMargin
 * @author Lux Industries
 * @notice Margin engine for traditional dated futures positions
 * @dev Handles initial margin deposits, daily variation margin (mark-to-market),
 *      maintenance margin checks, liquidation, and cross-margin across related futures
 *
 * Key features:
 * - Initial margin deposit on position open
 * - Daily mark-to-market (variation margin credits/debits)
 * - Maintenance margin check with margin call events
 * - Liquidation engine with penalty redistribution
 * - Cross-margin across same-underlying, different-expiry contracts
 */
contract FuturesMargin is IFuturesMargin, ReentrancyGuard, AccessControl {
    using SafeERC20 for IERC20;

    // ═══════════════════════════════════════════════════════════════════════
    // CONSTANTS
    // ═══════════════════════════════════════════════════════════════════════

    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant FUTURES_ROLE = keccak256("FUTURES_ROLE");

    uint256 public constant PRECISION = 1e18;
    uint256 public constant BPS = 10_000;

    // ═══════════════════════════════════════════════════════════════════════
    // STATE
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice Reference to the Futures contract for reading contract specs
    address public futures;

    /// @notice Quote token used for margin (typically USDL)
    IERC20 public quoteToken;

    /// @notice Liquidation penalty in basis points (taken from seized margin)
    uint256 public liquidationPenaltyBps = 50; // 0.5%

    /// @notice Margin accounts: contractId => trader => MarginAccount
    mapping(uint256 => mapping(address => MarginAccount)) internal _accounts;

    /// @notice Cross-margin groups: trader => underlying => CrossMarginGroup
    mapping(address => mapping(address => CrossMarginGroup)) internal _crossMarginGroups;

    /// @notice Whether a contract is in a cross-margin group for a trader
    mapping(address => mapping(uint256 => bool)) internal _inCrossMargin;

    // ═══════════════════════════════════════════════════════════════════════
    // CONSTRUCTOR
    // ═══════════════════════════════════════════════════════════════════════

    constructor(address _futures, address _quoteToken, address _admin) {
        if (_futures == address(0) || _quoteToken == address(0)) revert ZeroAmount();

        futures = _futures;
        quoteToken = IERC20(_quoteToken);

        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        _grantRole(ADMIN_ROLE, _admin);
        _grantRole(FUTURES_ROLE, _futures);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // MODIFIERS
    // ═══════════════════════════════════════════════════════════════════════

    modifier onlyFutures() {
        if (!hasRole(FUTURES_ROLE, msg.sender)) revert OnlyFutures();
        _;
    }

    // ═══════════════════════════════════════════════════════════════════════
    // MARGIN OPERATIONS
    // ═══════════════════════════════════════════════════════════════════════

    /// @inheritdoc IFuturesMargin
    function deposit(uint256 contractId, address trader, uint256 amount) external onlyFutures {
        if (amount == 0) revert ZeroAmount();

        MarginAccount storage account = _accounts[contractId][trader];

        // Pull funds from Futures contract
        quoteToken.safeTransferFrom(msg.sender, address(this), amount);

        account.deposited += amount;

        // Resolve margin call if margin is now sufficient
        if (account.frozen) {
            uint256 effective = _effectiveBalance(account);
            // Unfreeze if effective balance is positive (actual threshold check done by Futures)
            if (effective > 0) {
                account.frozen = false;
                emit MarginCallResolved(contractId, trader);
            }
        }

        emit MarginDeposited(contractId, trader, amount, account.deposited);
    }

    /// @inheritdoc IFuturesMargin
    function withdraw(uint256 contractId, address trader, uint256 amount) external onlyFutures {
        if (amount == 0) revert ZeroAmount();

        MarginAccount storage account = _accounts[contractId][trader];
        if (account.frozen) revert MarginFrozen();

        uint256 effective = _effectiveBalance(account);
        if (amount > effective) revert WithdrawalBreachesMargin();

        account.deposited -= amount;

        // Transfer to Futures contract (which will forward to trader)
        quoteToken.safeTransfer(msg.sender, amount);

        emit MarginWithdrawn(contractId, trader, amount, account.deposited);
    }

    /// @inheritdoc IFuturesMargin
    function applyVariationMargin(
        uint256 contractId,
        address trader,
        uint256 positionSize,
        bool isLong,
        uint256 contractSize,
        uint256 newSettlementPrice
    ) external onlyFutures {
        MarginAccount storage account = _accounts[contractId][trader];

        uint256 lastPrice = account.lastSettlementPrice;
        if (lastPrice == 0) {
            // First settlement — set baseline, no variation margin
            account.lastSettlementPrice = newSettlementPrice;
            return;
        }

        // Calculate variation margin
        // delta = size * contractSize * (newPrice - lastPrice) / PRECISION
        int256 priceDelta = int256(newSettlementPrice) - int256(lastPrice);
        int256 variation = (int256(positionSize) * int256(contractSize) * priceDelta) / int256(PRECISION);

        // For shorts, variation is inverted
        if (!isLong) {
            variation = -variation;
        }

        // Apply variation margin
        if (variation > 0) {
            account.variationCredit += uint256(variation);
        } else if (variation < 0) {
            account.variationDebit += uint256(-variation);
        }

        account.lastSettlementPrice = newSettlementPrice;

        // Check if margin call should be triggered
        uint256 effective = _effectiveBalance(account);
        if (effective == 0 && account.deposited > 0) {
            // Effective balance wiped out — freeze account
            if (!account.frozen) {
                account.frozen = true;
                uint256 deficit = account.variationDebit > account.variationCredit + account.deposited
                    ? account.variationDebit - account.variationCredit - account.deposited
                    : 0;
                emit MarginCallTriggered(contractId, trader, deficit);
            }
        }

        emit VariationMarginApplied(contractId, trader, variation, newSettlementPrice);
    }

    /// @inheritdoc IFuturesMargin
    function executeLiquidation(uint256 contractId, address trader)
        external
        onlyFutures
        returns (uint256 seized, uint256 penalty)
    {
        MarginAccount storage account = _accounts[contractId][trader];

        // Seize all remaining margin
        seized = _effectiveBalance(account);

        // Calculate liquidation penalty (capped at seized amount)
        penalty = (seized * liquidationPenaltyBps) / BPS;
        if (penalty > seized) {
            penalty = seized;
        }

        // Reset account
        account.deposited = 0;
        account.variationDebit = 0;
        account.variationCredit = 0;
        account.lastSettlementPrice = 0;
        account.frozen = false;

        // Transfer seized funds to Futures contract for distribution
        if (seized > 0) {
            quoteToken.safeTransfer(msg.sender, seized);
        }

        emit Liquidated(contractId, trader, seized, penalty);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // CROSS-MARGIN
    // ═══════════════════════════════════════════════════════════════════════

    /// @inheritdoc IFuturesMargin
    function createCrossMarginGroup(address underlying, uint256[] calldata contractIds) external {
        CrossMarginGroup storage group = _crossMarginGroups[msg.sender][underlying];
        if (group.enabled) revert CrossMarginGroupExists();

        group.underlying = underlying;
        group.trader = msg.sender;
        group.enabled = true;

        for (uint256 i = 0; i < contractIds.length; i++) {
            group.contractIds.push(contractIds[i]);
            _inCrossMargin[msg.sender][contractIds[i]] = true;
        }

        emit CrossMarginGroupCreated(msg.sender, underlying, contractIds);
    }

    /// @inheritdoc IFuturesMargin
    function addToCrossMarginGroup(address underlying, uint256 contractId) external {
        CrossMarginGroup storage group = _crossMarginGroups[msg.sender][underlying];
        if (!group.enabled) revert CrossMarginGroupNotFound();
        if (_inCrossMargin[msg.sender][contractId]) revert ContractNotInGroup();

        group.contractIds.push(contractId);
        _inCrossMargin[msg.sender][contractId] = true;

        emit CrossMarginContractAdded(msg.sender, underlying, contractId);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // VIEW FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════

    /// @inheritdoc IFuturesMargin
    function getMarginAccount(uint256 contractId, address trader) external view returns (MarginAccount memory) {
        return _accounts[contractId][trader];
    }

    /// @inheritdoc IFuturesMargin
    function getAvailableMargin(uint256 contractId, address trader) external view returns (uint256) {
        MarginAccount storage account = _accounts[contractId][trader];
        if (account.frozen) return 0;
        return _effectiveBalance(account);
    }

    /// @inheritdoc IFuturesMargin
    function getEffectiveBalance(uint256 contractId, address trader) external view returns (uint256) {
        return _effectiveBalance(_accounts[contractId][trader]);
    }

    /// @inheritdoc IFuturesMargin
    function meetsMaintenanceMargin(
        uint256 contractId,
        address trader,
        uint256 positionSize,
        uint256 contractSize,
        uint256 markPrice,
        uint256 maintenanceMarginBps
    ) external view returns (bool) {
        uint256 effective = _effectiveBalance(_accounts[contractId][trader]);

        // If in cross-margin group, sum effective balances across group
        IFutures.ContractSpec memory spec = IFutures(futures).getContract(contractId);
        CrossMarginGroup storage group = _crossMarginGroups[trader][spec.underlying];

        if (group.enabled && _inCrossMargin[trader][contractId]) {
            effective = _crossMarginEffectiveBalance(trader, group);
        }

        // Required = positionSize * contractSize * markPrice * maintenanceMarginBps / (PRECISION * BPS)
        uint256 required = (positionSize * contractSize * markPrice * maintenanceMarginBps) / (PRECISION * BPS);

        return effective >= required;
    }

    /// @inheritdoc IFuturesMargin
    function getCrossMarginGroup(address trader, address underlying) external view returns (CrossMarginGroup memory) {
        return _crossMarginGroups[trader][underlying];
    }

    // ═══════════════════════════════════════════════════════════════════════
    // ADMIN FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════

    function setLiquidationPenalty(uint256 _penaltyBps) external onlyRole(ADMIN_ROLE) {
        liquidationPenaltyBps = _penaltyBps;
    }

    function setFutures(address _futures) external onlyRole(ADMIN_ROLE) {
        futures = _futures;
        _grantRole(FUTURES_ROLE, _futures);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // INTERNAL FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════

    /**
     * @dev Calculate effective balance: deposited + credits - debits
     *      Returns 0 if balance would be negative (underwater)
     */
    function _effectiveBalance(MarginAccount storage account) internal view returns (uint256) {
        uint256 gross = account.deposited + account.variationCredit;
        if (account.variationDebit >= gross) return 0;
        return gross - account.variationDebit;
    }

    /**
     * @dev Sum effective balances across a cross-margin group
     */
    function _crossMarginEffectiveBalance(address trader, CrossMarginGroup storage group)
        internal
        view
        returns (uint256 total)
    {
        for (uint256 i = 0; i < group.contractIds.length; i++) {
            total += _effectiveBalance(_accounts[group.contractIds[i]][trader]);
        }
    }
}
