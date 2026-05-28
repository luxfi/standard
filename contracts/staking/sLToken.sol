// SPDX-License-Identifier: BSD-3-Clause
// Copyright (c) 2026 Lux Industries Inc.
pragma solidity ^0.8.31;

import { ERC4626 } from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { AccessControl } from "@openzeppelin/contracts/access/AccessControl.sol";
import { Pausable } from "@openzeppelin/contracts/utils/Pausable.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { IYieldStrategy } from "./IYieldStrategy.sol";

/**
 * @title sLToken
 * @author Lux Industries
 * @notice ERC-4626 yield vault over a Lux L token (LUSD/LBTC/LETH/LSOL/LTON/LXRP/LDOT).
 *
 * Deposit semantics are vanilla ERC-4626 — depositors get shares (sL*) that
 * represent their pro-rata claim on the underlying L tokens held by the vault.
 *
 * Unstake semantics introduce a cooldown for risk-tier discipline:
 *
 *   1. User calls `requestUnstake(shares)` — vault transfers the shares into
 *      escrow inside the same contract under a per-user (cooldownEnd, shares)
 *      record. A user can have at most one active cooldown record; calling
 *      requestUnstake while one is active EXTENDS the cooldown (shares are
 *      added, end is bumped to now + cooldownPeriod).
 *   2. After cooldownPeriod elapses, user calls `claimUnstake()` which redeems
 *      the escrowed shares (ERC-4626 redeem path) and ships the L tokens out.
 *   3. User can `cancelUnstake()` any time before claim to pull shares back.
 *
 * Yield source: a single IYieldStrategy plug. OPERATOR_ROLE calls
 * `harvest()` which calls strategy.harvest() — yield arrives back into the
 * vault as L tokens, raising the per-share value naturally.
 *
 * GOVERNANCE_ROLE can pause new stakes (existing unstakes always claim — exit
 * guarantee) and can swap the strategy.
 */
contract sLToken is ERC4626, AccessControl, Pausable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    bytes32 public constant GOVERNANCE_ROLE = keccak256("GOVERNANCE_ROLE");
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");

    /// @notice Cooldown duration in seconds. Default 7 days.
    uint256 public cooldownPeriod = 7 days;

    /// @notice Max cooldown a governance call can set. Hard cap, not configurable.
    uint256 public constant MAX_COOLDOWN = 30 days;

    /// @notice Per-user cooldown record
    struct CooldownRecord {
        uint256 shares;
        uint256 cooldownEnd;
    }

    mapping(address => CooldownRecord) public cooldownOf;

    /// @notice Attached yield strategy (zero = no strategy)
    IYieldStrategy public strategy;

    event Strategy_Set(address indexed newStrategy);
    event Strategy_Detached(address indexed prevStrategy, uint256 drained);
    event Harvested(uint256 amount);
    event CooldownStarted(address indexed user, uint256 shares, uint256 cooldownEnd);
    event CooldownCancelled(address indexed user, uint256 shares);
    event CooldownClaimed(address indexed user, uint256 shares, uint256 assets);
    event CooldownPeriodSet(uint256 newPeriod);

    error sLToken_NoCooldown();
    error sLToken_CooldownNotMet();
    error sLToken_ZeroAmount();
    error sLToken_CooldownTooLong();
    error sLToken_StrategyMismatch();
    error sLToken_DepositPaused();

    /// @param liquidToken  underlying L token
    /// @param name_        vault token name ("Staked LiquidUSD")
    /// @param symbol_      vault token symbol ("sLUSD")
    /// @param admin        governance + default admin
    constructor(IERC20 liquidToken, string memory name_, string memory symbol_, address admin)
        ERC20(name_, symbol_)
        ERC4626(liquidToken)
    {
        require(admin != address(0), "zero admin");
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(GOVERNANCE_ROLE, admin);
        _grantRole(OPERATOR_ROLE, admin);
    }

    // ─────────────────────────────────────────────────────────────────────
    //  DECIMALS — mirror the underlying L token's decimals
    // ─────────────────────────────────────────────────────────────────────

    function decimals() public view override(ERC4626) returns (uint8) {
        return ERC4626.decimals();
    }

    // ─────────────────────────────────────────────────────────────────────
    //  TOTAL ASSETS — vault balance + strategy externalBalance
    // ─────────────────────────────────────────────────────────────────────

    function totalAssets() public view override returns (uint256) {
        uint256 inVault = IERC20(asset()).balanceOf(address(this));
        uint256 inStrategy = address(strategy) == address(0) ? 0 : strategy.externalBalance();
        return inVault + inStrategy;
    }

    // ─────────────────────────────────────────────────────────────────────
    //  DEPOSIT — paused when paused; otherwise vanilla 4626
    // ─────────────────────────────────────────────────────────────────────

    function _deposit(address caller, address receiver, uint256 assets, uint256 shares) internal override {
        if (paused()) revert sLToken_DepositPaused();
        super._deposit(caller, receiver, assets, shares);
    }

    // ─────────────────────────────────────────────────────────────────────
    //  COOLDOWN UNSTAKE
    // ─────────────────────────────────────────────────────────────────────

    /// @notice Lock `shares` for cooldown. Pulls them into vault escrow.
    function requestUnstake(uint256 shares) external nonReentrant {
        if (shares == 0) revert sLToken_ZeroAmount();
        // Transfer shares into the vault contract itself (escrow).
        _transfer(msg.sender, address(this), shares);
        CooldownRecord storage r = cooldownOf[msg.sender];
        r.shares += shares;
        r.cooldownEnd = block.timestamp + cooldownPeriod;
        emit CooldownStarted(msg.sender, r.shares, r.cooldownEnd);
    }

    /// @notice Cancel an in-progress cooldown and return shares to the user.
    function cancelUnstake() external nonReentrant {
        CooldownRecord storage r = cooldownOf[msg.sender];
        if (r.shares == 0) revert sLToken_NoCooldown();
        uint256 shares = r.shares;
        delete cooldownOf[msg.sender];
        _transfer(address(this), msg.sender, shares);
        emit CooldownCancelled(msg.sender, shares);
    }

    /// @notice Claim cooled-down shares as underlying L tokens.
    function claimUnstake() external nonReentrant returns (uint256 assets) {
        CooldownRecord storage r = cooldownOf[msg.sender];
        if (r.shares == 0) revert sLToken_NoCooldown();
        if (block.timestamp < r.cooldownEnd) revert sLToken_CooldownNotMet();

        uint256 shares = r.shares;
        delete cooldownOf[msg.sender];

        // Convert shares → assets, then redeem.
        assets = previewRedeem(shares);

        // We need enough liquid L in the vault — pull from strategy if needed.
        uint256 inVault = IERC20(asset()).balanceOf(address(this));
        if (inVault < assets && address(strategy) != address(0)) {
            strategy.unwindTo(address(this), assets - inVault);
        }

        // Burn the escrowed shares (transfer from escrow then burn).
        _burn(address(this), shares);
        IERC20(asset()).safeTransfer(msg.sender, assets);

        emit CooldownClaimed(msg.sender, shares, assets);
    }

    // ─────────────────────────────────────────────────────────────────────
    //  YIELD HARVEST
    // ─────────────────────────────────────────────────────────────────────

    function harvest() external onlyRole(OPERATOR_ROLE) nonReentrant returns (uint256 harvested) {
        if (address(strategy) == address(0)) return 0;
        harvested = strategy.harvest();
        emit Harvested(harvested);
    }

    // ─────────────────────────────────────────────────────────────────────
    //  GOVERNANCE
    // ─────────────────────────────────────────────────────────────────────

    function setCooldownPeriod(uint256 newPeriod) external onlyRole(GOVERNANCE_ROLE) {
        if (newPeriod > MAX_COOLDOWN) revert sLToken_CooldownTooLong();
        cooldownPeriod = newPeriod;
        emit CooldownPeriodSet(newPeriod);
    }

    function pause() external onlyRole(GOVERNANCE_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(GOVERNANCE_ROLE) {
        _unpause();
    }

    /// @notice Attach a yield strategy. Strategy's underlying must match.
    function setStrategy(IYieldStrategy newStrategy) external onlyRole(GOVERNANCE_ROLE) {
        if (newStrategy.liquidToken() != asset()) revert sLToken_StrategyMismatch();
        strategy = newStrategy;
        emit Strategy_Set(address(newStrategy));
    }

    /// @notice Detach the strategy. Drains externalBalance back to the vault.
    function detachStrategy() external onlyRole(GOVERNANCE_ROLE) returns (uint256 drained) {
        IYieldStrategy s = strategy;
        if (address(s) == address(0)) return 0;
        uint256 ext = s.externalBalance();
        if (ext > 0) drained = s.unwindTo(address(this), ext);
        strategy = IYieldStrategy(address(0));
        emit Strategy_Detached(address(s), drained);
    }
}
