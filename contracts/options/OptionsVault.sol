// SPDX-License-Identifier: MIT
pragma solidity ^0.8.31;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { AccessControl } from "@openzeppelin/contracts/access/AccessControl.sol";
import { Pausable } from "@openzeppelin/contracts/utils/Pausable.sol";
import { Options } from "./Options.sol";
import { IOptionsVault } from "../interfaces/options/IOptionsVault.sol";

/**
 * @title OptionsVault
 * @author Lux Industries
 * @notice Collateral vault managing margin for option writers with spread margin support
 * @dev Supports multi-token deposits and spread margin calculations where long options
 *      reduce collateral requirements to max-loss. Designed to be authorized by an
 *      Options contract for lock/release operations.
 *
 * Key features:
 * - Multi-token collateral deposits and withdrawals
 * - Lock/release collateral called by authorized Options contract
 * - Spread margin: long options reduce collateral to max-loss
 * - Maintenance margin check with liquidation threshold
 * - Liquidation for under-margined positions
 */
contract OptionsVault is IOptionsVault, ReentrancyGuard, AccessControl, Pausable {
    using SafeERC20 for IERC20;

    // ═══════════════════════════════════════════════════════════════════════
    // CONSTANTS
    // ═══════════════════════════════════════════════════════════════════════

    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");

    /// @notice Basis points denominator
    uint256 public constant BPS = 10000;

    /// @notice Precision for margin calculations
    uint256 public constant PRECISION = 1e18;

    // ═══════════════════════════════════════════════════════════════════════
    // STATE
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice The Options contract authorized to lock/release collateral
    Options public immutable options;

    /// @notice Maintenance margin ratio in BPS (e.g., 7500 = 75% of initial margin)
    uint256 public maintenanceMarginBps = 7500;

    /// @notice Liquidation penalty in BPS (e.g., 500 = 5%)
    uint256 public liquidationPenaltyBps = 500;

    /// @notice User accounts: user => token => Account
    mapping(address => mapping(address => Account)) private _accounts;

    /// @notice Supported tokens
    mapping(address => bool) public supportedTokens;

    // ═══════════════════════════════════════════════════════════════════════
    // CONSTRUCTOR
    // ═══════════════════════════════════════════════════════════════════════

    constructor(address _options, address _admin) {
        if (_options == address(0)) revert ZeroAddress();
        if (_admin == address(0)) revert ZeroAddress();

        options = Options(_options);

        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        _grantRole(ADMIN_ROLE, _admin);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // MODIFIERS
    // ═══════════════════════════════════════════════════════════════════════

    modifier onlyOptions() {
        if (msg.sender != address(options)) revert UnauthorizedCaller();
        _;
    }

    modifier onlySupportedToken(address token) {
        if (!supportedTokens[token]) revert UnsupportedToken();
        _;
    }

    // ═══════════════════════════════════════════════════════════════════════
    // USER OPERATIONS
    // ═══════════════════════════════════════════════════════════════════════

    /// @inheritdoc IOptionsVault
    function deposit(address token, uint256 amount)
        external
        nonReentrant
        whenNotPaused
        onlySupportedToken(token)
    {
        if (amount == 0) revert ZeroAmount();

        _accounts[msg.sender][token].deposited += amount;
        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);

        emit Deposited(msg.sender, token, amount);
    }

    /// @inheritdoc IOptionsVault
    function withdraw(address token, uint256 amount)
        external
        nonReentrant
        onlySupportedToken(token)
    {
        if (amount == 0) revert ZeroAmount();

        Account storage acct = _accounts[msg.sender][token];
        uint256 available = acct.deposited - acct.locked;
        if (amount > available) revert InsufficientAvailable();

        acct.deposited -= amount;
        IERC20(token).safeTransfer(msg.sender, amount);

        emit Withdrawn(msg.sender, token, amount);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // OPTIONS CONTRACT OPERATIONS
    // ═══════════════════════════════════════════════════════════════════════

    /// @inheritdoc IOptionsVault
    function lockCollateral(address user, address token, uint256 amount) external onlyOptions {
        Account storage acct = _accounts[user][token];
        uint256 available = acct.deposited - acct.locked;
        if (amount > available) revert InsufficientAvailable();

        acct.locked += amount;

        emit CollateralLocked(user, token, amount);
    }

    /// @inheritdoc IOptionsVault
    function releaseCollateral(address user, address token, uint256 amount) external onlyOptions {
        Account storage acct = _accounts[user][token];
        // Cannot release more than locked, but clamp to prevent underflow
        uint256 toRelease = amount > acct.locked ? acct.locked : amount;
        acct.locked -= toRelease;

        emit CollateralReleased(user, token, toRelease);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // LIQUIDATION
    // ═══════════════════════════════════════════════════════════════════════

    /**
     * @notice Liquidate an under-margined user position
     * @param user User to liquidate
     * @param token Collateral token
     * @dev Caller receives liquidation penalty as reward. Only callable when
     *      user's deposited collateral falls below maintenance margin.
     */
    function liquidate(address user, address token)
        external
        nonReentrant
        onlySupportedToken(token)
    {
        Account storage acct = _accounts[user][token];
        uint256 maintenance = getMaintenanceRequirement(user, token);

        // Can only liquidate if deposited < maintenance
        if (acct.deposited >= maintenance) revert AboveLiquidationThreshold();

        uint256 penalty = (acct.locked * liquidationPenaltyBps) / BPS;
        uint256 liquidatorReward = penalty > acct.deposited ? acct.deposited : penalty;

        acct.deposited -= liquidatorReward;
        acct.locked = 0;

        if (liquidatorReward > 0) {
            IERC20(token).safeTransfer(msg.sender, liquidatorReward);
        }

        emit Liquidated(user, token, liquidatorReward, msg.sender);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // VIEW FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════

    /// @inheritdoc IOptionsVault
    function getAvailableCollateral(address user, address token) external view returns (uint256) {
        Account storage acct = _accounts[user][token];
        if (acct.deposited <= acct.locked) return 0;
        return acct.deposited - acct.locked;
    }

    /// @inheritdoc IOptionsVault
    function getMaintenanceRequirement(address user, address token) public view returns (uint256) {
        Account storage acct = _accounts[user][token];
        return (acct.locked * maintenanceMarginBps) / BPS;
    }

    /// @inheritdoc IOptionsVault
    function getAccount(address user, address token) external view returns (Account memory) {
        return _accounts[user][token];
    }

    /// @inheritdoc IOptionsVault
    function calculateSpreadMargin(
        address user,
        uint256 shortSeriesId,
        uint256 longSeriesId,
        uint256 quantity
    ) external view returns (uint256 reduction) {
        Options.OptionSeries memory shortSeries = options.getSeries(shortSeriesId);
        Options.OptionSeries memory longSeries = options.getSeries(longSeriesId);

        // Both must exist, same underlying, same quote, same type, same expiry
        if (!shortSeries.exists || !longSeries.exists) return 0;
        if (shortSeries.underlying != longSeries.underlying) return 0;
        if (shortSeries.quote != longSeries.quote) return 0;
        if (shortSeries.optionType != longSeries.optionType) return 0;
        if (shortSeries.expiry != longSeries.expiry) return 0;

        // User must hold long position (ERC1155 balance)
        uint256 longBalance = options.balanceOf(user, longSeriesId);
        uint256 effectiveQty = quantity > longBalance ? longBalance : quantity;
        if (effectiveQty == 0) return 0;

        // Spread margin = full collateral - max loss
        // For vertical call spread (short high strike, long low strike):
        //   max loss = (short_strike - long_strike) * qty   [if short strike > long strike]
        //   max loss = 0                                    [if short strike <= long strike, it's a credit spread]
        // For vertical put spread (short low strike, long high strike):
        //   max loss = (long_strike - short_strike) * qty   [if long strike > short strike, debit spread]
        //   max loss = 0                                    [credit spread]

        uint256 fullCollateral = options.calculateCollateral(shortSeriesId, effectiveQty);

        uint256 maxLoss;
        if (shortSeries.optionType == Options.OptionType.CALL) {
            // Call spread: max loss = max(0, shortStrike - longStrike) * qty (simplified)
            if (shortSeries.strikePrice > longSeries.strikePrice) {
                uint256 strikeDiff = shortSeries.strikePrice - longSeries.strikePrice;
                uint8 underlyingDec = options.tokenDecimals(shortSeries.underlying);
                maxLoss = (effectiveQty * strikeDiff) / (10 ** underlyingDec);
            }
            // else: credit spread, max loss is 0 if long strike >= short strike
        } else {
            // Put spread: max loss = max(0, longStrike - shortStrike) * qty
            if (longSeries.strikePrice > shortSeries.strikePrice) {
                uint256 strikeDiff = longSeries.strikePrice - shortSeries.strikePrice;
                uint8 underlyingDec = options.tokenDecimals(shortSeries.underlying);
                maxLoss = (effectiveQty * strikeDiff) / (10 ** underlyingDec);
            }
        }

        // Reduction = full collateral - max loss (capped at full collateral)
        if (maxLoss >= fullCollateral) return 0;
        reduction = fullCollateral - maxLoss;
    }

    // ═══════════════════════════════════════════════════════════════════════
    // ADMIN FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════

    /**
     * @notice Add a supported token
     * @param token Token address to support
     */
    function addSupportedToken(address token) external onlyRole(ADMIN_ROLE) {
        if (token == address(0)) revert ZeroAddress();
        supportedTokens[token] = true;
    }

    /**
     * @notice Remove a supported token
     * @param token Token address to remove
     */
    function removeSupportedToken(address token) external onlyRole(ADMIN_ROLE) {
        supportedTokens[token] = false;
    }

    /**
     * @notice Set maintenance margin ratio
     * @param _maintenanceMarginBps New ratio in BPS
     */
    function setMaintenanceMarginBps(uint256 _maintenanceMarginBps) external onlyRole(ADMIN_ROLE) {
        maintenanceMarginBps = _maintenanceMarginBps;
    }

    /**
     * @notice Set liquidation penalty
     * @param _liquidationPenaltyBps New penalty in BPS
     */
    function setLiquidationPenaltyBps(uint256 _liquidationPenaltyBps) external onlyRole(ADMIN_ROLE) {
        liquidationPenaltyBps = _liquidationPenaltyBps;
    }

    function pause() external onlyRole(ADMIN_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(ADMIN_ROLE) {
        _unpause();
    }
}
