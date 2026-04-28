// SPDX-License-Identifier: MIT
pragma solidity ^0.8.31;

/**
 * @title IFuturesMargin
 * @author Lux Industries
 * @notice Interface for the futures margin engine
 * @dev Handles initial margin, variation margin, maintenance checks, and cross-margin
 */
interface IFuturesMargin {
    // ═══════════════════════════════════════════════════════════════════════
    // TYPES
    // ═══════════════════════════════════════════════════════════════════════

    /**
     * @notice Margin account for a trader on a specific contract
     * @param deposited Total margin deposited
     * @param variationDebit Cumulative variation margin debited (losses from daily settlement)
     * @param variationCredit Cumulative variation margin credited (gains from daily settlement)
     * @param lastSettlementPrice Price at last daily settlement
     * @param frozen True if margin call is active (withdrawals blocked)
     */
    struct MarginAccount {
        uint256 deposited;
        uint256 variationDebit;
        uint256 variationCredit;
        uint256 lastSettlementPrice;
        bool frozen;
    }

    /**
     * @notice Cross-margin group linking related futures (same underlying, different expiries)
     * @param underlying Underlying asset defining the group
     * @param trader Trader address
     * @param contractIds Array of contract IDs in this cross-margin group
     * @param enabled Whether cross-margin is active
     */
    struct CrossMarginGroup {
        address underlying;
        address trader;
        uint256[] contractIds;
        bool enabled;
    }

    // ═══════════════════════════════════════════════════════════════════════
    // ERRORS
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice Thrown when margin deposit is below initial requirement
    error BelowInitialMargin();

    /// @notice Thrown when withdrawal would breach maintenance margin
    error WithdrawalBreachesMargin();

    /// @notice Thrown when margin account is frozen (margin call active)
    error MarginFrozen();

    /// @notice Thrown when position is not below liquidation threshold
    error NotLiquidatable();

    /// @notice Thrown when liquidation penalty exceeds remaining margin
    error InsufficientMarginForPenalty();

    /// @notice Thrown when cross-margin group already exists
    error CrossMarginGroupExists();

    /// @notice Thrown when cross-margin group does not exist
    error CrossMarginGroupNotFound();

    /// @notice Thrown when contract is not in the cross-margin group
    error ContractNotInGroup();

    /// @notice Thrown when amount is zero
    error ZeroAmount();

    /// @notice Thrown when caller is not the Futures contract
    error OnlyFutures();

    // ═══════════════════════════════════════════════════════════════════════
    // EVENTS
    // ═══════════════════════════════════════════════════════════════════════

    /**
     * @notice Emitted when margin is deposited
     * @param contractId Futures contract ID
     * @param trader Trader address
     * @param amount Amount deposited
     * @param newBalance New margin balance
     */
    event MarginDeposited(uint256 indexed contractId, address indexed trader, uint256 amount, uint256 newBalance);

    /**
     * @notice Emitted when margin is withdrawn
     * @param contractId Futures contract ID
     * @param trader Trader address
     * @param amount Amount withdrawn
     * @param newBalance New margin balance
     */
    event MarginWithdrawn(uint256 indexed contractId, address indexed trader, uint256 amount, uint256 newBalance);

    /**
     * @notice Emitted when daily variation margin is applied
     * @param contractId Futures contract ID
     * @param trader Trader address
     * @param amount Variation margin amount (positive = credit, negative = debit)
     * @param settlementPrice Daily settlement price
     */
    event VariationMarginApplied(
        uint256 indexed contractId, address indexed trader, int256 amount, uint256 settlementPrice
    );

    /**
     * @notice Emitted when a margin call is triggered
     * @param contractId Futures contract ID
     * @param trader Trader address
     * @param deficit Margin deficit below maintenance requirement
     */
    event MarginCallTriggered(uint256 indexed contractId, address indexed trader, uint256 deficit);

    /**
     * @notice Emitted when a margin call is resolved
     * @param contractId Futures contract ID
     * @param trader Trader address
     */
    event MarginCallResolved(uint256 indexed contractId, address indexed trader);

    /**
     * @notice Emitted when a position is liquidated via margin engine
     * @param contractId Futures contract ID
     * @param trader Trader address
     * @param marginSeized Margin seized
     * @param penalty Liquidation penalty
     */
    event Liquidated(uint256 indexed contractId, address indexed trader, uint256 marginSeized, uint256 penalty);

    /**
     * @notice Emitted when a cross-margin group is created
     * @param trader Trader address
     * @param underlying Underlying asset
     * @param contractIds Initial contract IDs
     */
    event CrossMarginGroupCreated(address indexed trader, address indexed underlying, uint256[] contractIds);

    /**
     * @notice Emitted when a contract is added to a cross-margin group
     * @param trader Trader address
     * @param underlying Underlying asset
     * @param contractId Added contract ID
     */
    event CrossMarginContractAdded(address indexed trader, address indexed underlying, uint256 contractId);

    // ═══════════════════════════════════════════════════════════════════════
    // MARGIN OPERATIONS
    // ═══════════════════════════════════════════════════════════════════════

    /**
     * @notice Deposit margin for a position
     * @param contractId Futures contract ID
     * @param trader Trader address
     * @param amount Amount to deposit
     */
    function deposit(uint256 contractId, address trader, uint256 amount) external;

    /**
     * @notice Withdraw excess margin from a position
     * @param contractId Futures contract ID
     * @param trader Trader address
     * @param amount Amount to withdraw
     */
    function withdraw(uint256 contractId, address trader, uint256 amount) external;

    /**
     * @notice Apply daily variation margin for a position
     * @param contractId Futures contract ID
     * @param trader Trader address
     * @param positionSize Number of contracts
     * @param isLong True if long, false if short
     * @param contractSize Size of one contract
     * @param newSettlementPrice New daily settlement price
     */
    function applyVariationMargin(
        uint256 contractId,
        address trader,
        uint256 positionSize,
        bool isLong,
        uint256 contractSize,
        uint256 newSettlementPrice
    ) external;

    /**
     * @notice Execute liquidation and seize margin
     * @param contractId Futures contract ID
     * @param trader Trader address
     * @return seized Margin amount seized
     * @return penalty Liquidation penalty amount
     */
    function executeLiquidation(uint256 contractId, address trader) external returns (uint256 seized, uint256 penalty);

    // ═══════════════════════════════════════════════════════════════════════
    // CROSS-MARGIN
    // ═══════════════════════════════════════════════════════════════════════

    /**
     * @notice Create a cross-margin group for related futures
     * @param underlying Underlying asset (groups contracts with same underlying)
     * @param contractIds Initial contract IDs to group
     */
    function createCrossMarginGroup(address underlying, uint256[] calldata contractIds) external;

    /**
     * @notice Add a contract to an existing cross-margin group
     * @param underlying Underlying asset identifying the group
     * @param contractId Contract ID to add
     */
    function addToCrossMarginGroup(address underlying, uint256 contractId) external;

    // ═══════════════════════════════════════════════════════════════════════
    // VIEW FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════

    /**
     * @notice Get margin account details
     * @param contractId Futures contract ID
     * @param trader Trader address
     * @return Margin account data
     */
    function getMarginAccount(uint256 contractId, address trader) external view returns (MarginAccount memory);

    /**
     * @notice Get available margin (total margin minus unrealised losses)
     * @param contractId Futures contract ID
     * @param trader Trader address
     * @return Available margin
     */
    function getAvailableMargin(uint256 contractId, address trader) external view returns (uint256);

    /**
     * @notice Get effective margin balance considering variation margin
     * @param contractId Futures contract ID
     * @param trader Trader address
     * @return Effective balance
     */
    function getEffectiveBalance(uint256 contractId, address trader) external view returns (uint256);

    /**
     * @notice Check if a position meets maintenance margin
     * @param contractId Futures contract ID
     * @param trader Trader address
     * @param positionSize Number of contracts
     * @param contractSize Size per contract
     * @param markPrice Current mark price
     * @param maintenanceMarginBps Maintenance margin bps
     * @return True if margin is sufficient
     */
    function meetsMaintenanceMargin(
        uint256 contractId,
        address trader,
        uint256 positionSize,
        uint256 contractSize,
        uint256 markPrice,
        uint256 maintenanceMarginBps
    ) external view returns (bool);

    /**
     * @notice Get cross-margin group for a trader and underlying
     * @param trader Trader address
     * @param underlying Underlying asset
     * @return Cross-margin group data
     */
    function getCrossMarginGroup(address trader, address underlying) external view returns (CrossMarginGroup memory);
}
