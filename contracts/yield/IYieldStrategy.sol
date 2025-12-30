// SPDX-License-Identifier: BSD-3-Clause
// Copyright (c) 2025 Lux Industries Inc.
pragma solidity ^0.8.31;

/**
 * @title IYieldStrategy
 * @notice Interface for yield strategies across all chains and protocols
 * @dev Each strategy wraps a yield source and exposes unified deposit/withdraw/harvest
 *
 * Implemented Strategies:
 * ┌─────────────────────────────────────────────────────────────────────────────┐
 * │ CATEGORY              │ STRATEGIES                                          │
 * ├─────────────────────────────────────────────────────────────────────────────┤
 * │ Liquid Staking        │ Lido, RocketPool, Frax (stETH, rETH, sfrxETH)       │
 * │ Restaking             │ EigenLayer, Symbiotic, Karak                         │
 * │ Lending               │ Aave V3, Compound V3, Morpho, Spark                  │
 * │ Curve/Convex          │ CurveStrategy, ConvexStrategy                        │
 * │ Stablecoins           │ MakerDAO DSR, sUSDS, Fraxlend                        │
 * │ Perps                 │ GMX GM, GNS gDAI, DLUX vaults                        │
 * │ L2 DEX                │ Aerodrome, Velodrome, Camelot                        │
 * │ Cross-chain           │ Solana, TON, Babylon (BTC)                           │
 * │ Institutional         │ MapleFinance, Pendle                                  │
 * └─────────────────────────────────────────────────────────────────────────────┘
 *
 * Usage with LiquidVault:
 *   LiquidVault.addStrategy(strategyAddress)
 *   LiquidVault.allocateToStrategy(0, amount, sig)
 *   LiquidVault.harvestYield(sig) → calls strategy.harvest()
 */
interface IYieldStrategy {
    // ═══════════════════════════════════════════════════════════════════════
    // EVENTS
    // ═══════════════════════════════════════════════════════════════════════

    event Deposited(address indexed caller, uint256 amount, uint256 shares);
    event Withdrawn(address indexed caller, uint256 shares, uint256 assets);
    event Harvested(uint256 yieldAmount);
    event StrategyPaused();
    event StrategyUnpaused();

    // ═══════════════════════════════════════════════════════════════════════
    // ERRORS
    // ═══════════════════════════════════════════════════════════════════════

    error ZeroAmount();
    error InsufficientBalance();
    error StrategyPausedError();
    error NotVault();
    error WithdrawFailed();

    // ═══════════════════════════════════════════════════════════════════════
    // CORE FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════

    /**
     * @notice Deposit assets into the yield strategy
     * @param amount Amount of underlying to deposit
     * @return shares Amount of strategy shares received
     */
    function deposit(uint256 amount) external payable returns (uint256 shares);

    /**
     * @notice Withdraw assets from the yield strategy
     * @param shares Amount of shares to redeem
     * @return assets Amount of underlying received
     */
    function withdraw(uint256 shares) external returns (uint256 assets);

    /**
     * @notice Harvest yield and return amount harvested
     * @return harvested Amount of yield harvested in underlying terms
     */
    function harvest() external returns (uint256 harvested);

    // ═══════════════════════════════════════════════════════════════════════
    // VIEW FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════

    /**
     * @notice Get total assets managed by this strategy
     * @return Total assets in underlying terms
     */
    function totalAssets() external view returns (uint256);

    /**
     * @notice Get total deposited (tracked separately for accounting)
     * @return Total deposited amount
     */
    function totalDeposited() external view returns (uint256);

    /**
     * @notice Get current yield rate (APY in basis points, e.g., 500 = 5%)
     * @return APY in basis points
     */
    function currentAPY() external view returns (uint256);

    /**
     * @notice Get the underlying asset address (address(0) for native ETH)
     * @return Underlying asset address
     */
    function asset() external view returns (address);

    /**
     * @notice Check if strategy is active
     * @return True if strategy is accepting deposits
     */
    function isActive() external view returns (bool);

    /**
     * @notice Get strategy name for identification
     * @return Strategy name
     */
    function name() external view returns (string memory);

    /**
     * @notice Get strategy version
     * @return Version string
     */
    function version() external view returns (string memory);

    /**
     * @notice Get the vault address that controls this strategy
     * @return Vault address
     */
    function vault() external view returns (address);

    /**
     * @notice Get pending yield (not yet harvested)
     * @return Estimated pending yield
     */
    function pendingYield() external view returns (uint256);
}

// Strategy type identifiers (file-level constants)
bytes32 constant STRATEGY_LIDO = keccak256("LIDO");
bytes32 constant STRATEGY_ROCKET_POOL = keccak256("ROCKET_POOL");
bytes32 constant STRATEGY_AAVE_V3 = keccak256("AAVE_V3");
bytes32 constant STRATEGY_COMPOUND_V3 = keccak256("COMPOUND_V3");
bytes32 constant STRATEGY_MORPHO = keccak256("MORPHO");
bytes32 constant STRATEGY_EIGENLAYER = keccak256("EIGENLAYER");
bytes32 constant STRATEGY_CONVEX = keccak256("CONVEX");
bytes32 constant STRATEGY_CURVE = keccak256("CURVE");
bytes32 constant STRATEGY_YEARN_V3 = keccak256("YEARN_V3");
bytes32 constant STRATEGY_PENDLE = keccak256("PENDLE");

/**
 * @title IYieldStrategyFactory
 * @notice Factory for deploying yield strategies
 */
interface IYieldStrategyFactory {
    event StrategyDeployed(
        bytes32 indexed strategyType,
        address indexed strategy,
        address indexed underlying
    );

    /**
     * @notice Deploy a new yield strategy
     * @param strategyType Type of strategy (LIDO, AAVE_V3, etc.)
     * @param underlying Underlying asset address
     * @param params Strategy-specific parameters
     * @return strategy Address of deployed strategy
     */
    function deploy(
        bytes32 strategyType,
        address underlying,
        bytes calldata params
    ) external returns (address strategy);

    /**
     * @notice Get all deployed strategies for an underlying
     */
    function getStrategies(address underlying) external view returns (address[] memory);
}
