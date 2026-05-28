// SPDX-License-Identifier: BSD-3-Clause
// Copyright (c) 2026 Lux Industries Inc.
pragma solidity ^0.8.31;

import { AccessControl } from "@openzeppelin/contracts/access/AccessControl.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { Pausable } from "@openzeppelin/contracts/utils/Pausable.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IBridgedToken } from "../../bridge/IBridgedToken.sol";
import { BasketRegistry } from "../../bridge/v4/BasketRegistry.sol";
import { PerAssetLedger } from "../../bridge/v4/PerAssetLedger.sol";
import { SolvencyStateMachineV4 } from "../../bridge/v4/SolvencyStateMachineV4.sol";

/**
 * @title LiquidPool
 * @author Lux Industries
 * @notice Abstract base for unified-basket pools: takes any registered
 *         bridged asset in a basket at 1:1 (with per-asset decimal
 *         normalization), mints the basket's L token; on burn, the user
 *         selects which asset to receive back.
 *
 * Concrete pools (LiquidUSDPool, LiquidBTCPool, LiquidETHPool, …) supply:
 *   - the basket-class enum value
 *   - the L token address (already deployed; pool must hold mint+burn admin)
 *   - the pool's base-unit decimals (USD/ETH = 18, BTC = 8, SOL = 9, etc.)
 *
 * Invariant maintained on every mint/burn:
 *   totalReserveInBaseUnits()  ≥  liquidToken.totalSupply()
 *
 * If the invariant trips into RestrictedMint or Emergency, new mints are
 * blocked; burns are always allowed (user exit guarantee).
 */
abstract contract LiquidPool is AccessControl, ReentrancyGuard, Pausable, PerAssetLedger, SolvencyStateMachineV4 {
    using SafeERC20 for IERC20;

    bytes32 public constant GOVERNANCE_ROLE = keccak256("GOVERNANCE_ROLE");
    bytes32 public constant BRIDGE_ROLE = keccak256("BRIDGE_ROLE");

    /// @notice The L token this pool issues (LUSD/LBTC/LETH/…)
    IBridgedToken public immutable liquidToken;

    /// @notice The pool's base-unit decimals (LUSD/LETH=18, LBTC=8, LSOL/LTON=9, LXRP=6, LDOT=10)
    uint8 public immutable poolDecimals;

    /// @notice Basket class id (BasketClass cast to uint8) used by the solvency machine
    uint8 public immutable basketId;

    /// @notice Registry of accepted bridged assets per basket
    BasketRegistry public immutable basketRegistry;

    event Deposited(address indexed user, address indexed asset, uint256 rawIn, uint256 lOut);
    event Burned(address indexed user, address indexed preferredAsset, uint256 lIn, uint256 rawOut);

    error LiquidPool_NotInBasket();
    error LiquidPool_ZeroAmount();
    error LiquidPool_DecimalsTooHigh();
    error LiquidPool_MintRestricted();
    error LiquidPool_DustOutput();

    /// @param admin            governance admin (governance role + default admin)
    /// @param _liquidToken     L token address; the pool must already be granted
    ///                         DEFAULT_ADMIN_ROLE / MINTER_ROLE on it
    /// @param _basketRegistry  basket registry (LUSD pool reads BasketClass.USD, etc.)
    /// @param _basketId        basket id (BasketClass cast to uint8)
    /// @param _poolDecimals    pool base-unit decimals
    constructor(
        address admin,
        address _liquidToken,
        address _basketRegistry,
        uint8 _basketId,
        uint8 _poolDecimals
    ) {
        require(admin != address(0), "zero admin");
        require(_liquidToken != address(0), "zero liquidToken");
        require(_basketRegistry != address(0), "zero basketRegistry");

        liquidToken = IBridgedToken(_liquidToken);
        basketRegistry = BasketRegistry(_basketRegistry);
        basketId = _basketId;
        poolDecimals = _poolDecimals;

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(GOVERNANCE_ROLE, admin);

        // Pool reserves are 1:1 with the L token supply by construction
        // (every L mint pulls real reserve in; every burn ships reserve out),
        // so the RestrictedMint band of the V4 graduated solvency model
        // collapses to "Healthy iff backing >= liabilities, else Emergency".
        // Governance can re-widen the band via setBasketThresholds if it
        // adds external (yield-buffer) backing later.
        _setBasketThresholds(_basketId, 10_000, 10_000);
    }

    // ─────────────────────────────────────────────────────────────────────
    //  DEPOSIT (any basket member → L token at 1:1, decimal-normalized)
    // ─────────────────────────────────────────────────────────────────────

    /**
     * @notice Deposit a registered basket asset and receive the L token.
     * @param asset      bridged asset contract (must be in this pool's basket)
     * @param rawAmount  amount in the asset's own decimals
     * @return lAmount   amount of L minted to the caller (in pool decimals)
     */
    function deposit(address asset, uint256 rawAmount)
        external
        nonReentrant
        whenNotPaused
        returns (uint256 lAmount)
    {
        if (rawAmount == 0) revert LiquidPool_ZeroAmount();
        if (!basketRegistry.isInBasket(_basketClassEnum(), asset)) {
            revert LiquidPool_NotInBasket();
        }
        if (!basketMintAllowed(basketId)) revert LiquidPool_MintRestricted();

        // Pull the deposit. The pool holds the basket's reserve directly.
        IERC20(asset).safeTransferFrom(msg.sender, address(this), rawAmount);

        // Convert to pool base units
        lAmount = _normalizeUp(asset, rawAmount);
        if (lAmount == 0) revert LiquidPool_DustOutput();

        _recordDeposit(asset, rawAmount, lAmount);

        liquidToken.mint(msg.sender, lAmount);

        _updateBasketSolvency(basketId, totalReserveInBaseUnits(), IERC20(address(liquidToken)).totalSupply());

        emit Deposited(msg.sender, asset, rawAmount, lAmount);
    }

    /**
     * @notice Burn L tokens; receive `preferredAsset` from the basket inventory.
     * @param lAmount         amount of L to burn (in pool decimals)
     * @param preferredAsset  basket member to return — must have enough reserve
     * @return rawOut         amount paid out in preferredAsset's raw decimals
     */
    function burnFor(uint256 lAmount, address preferredAsset)
        external
        nonReentrant
        whenNotPaused
        returns (uint256 rawOut)
    {
        if (lAmount == 0) revert LiquidPool_ZeroAmount();
        if (!basketRegistry.isInBasket(_basketClassEnum(), preferredAsset)) {
            revert LiquidPool_NotInBasket();
        }

        rawOut = _normalizeDown(preferredAsset, lAmount);
        if (rawOut == 0) revert LiquidPool_DustOutput();

        // Reserve check happens inside _recordWithdraw (reverts if insufficient).
        _recordWithdraw(preferredAsset, rawOut, lAmount);

        // Burn-with-allowance: caller must approve pool to spend their L tokens.
        liquidToken.burn(msg.sender, lAmount);

        IERC20(preferredAsset).safeTransfer(msg.sender, rawOut);

        _updateBasketSolvency(basketId, totalReserveInBaseUnits(), IERC20(address(liquidToken)).totalSupply());

        emit Burned(msg.sender, preferredAsset, lAmount, rawOut);
    }

    // ─────────────────────────────────────────────────────────────────────
    //  DECIMAL NORMALIZATION
    // ─────────────────────────────────────────────────────────────────────

    /// @dev raw asset units → pool base units (scale up or down to match poolDecimals)
    function _normalizeUp(address asset, uint256 rawAmount) internal view returns (uint256) {
        uint8 d = IERC20Metadata(asset).decimals();
        if (d > poolDecimals) {
            // asset has more decimals: down-scale
            uint256 factor = 10 ** uint256(d - poolDecimals);
            return rawAmount / factor;
        }
        if (d < poolDecimals) {
            uint256 factor = 10 ** uint256(poolDecimals - d);
            return rawAmount * factor;
        }
        return rawAmount;
    }

    /// @dev pool base units → raw asset units (inverse of _normalizeUp)
    function _normalizeDown(address asset, uint256 lAmount) internal view returns (uint256) {
        uint8 d = IERC20Metadata(asset).decimals();
        if (d > poolDecimals) {
            uint256 factor = 10 ** uint256(d - poolDecimals);
            return lAmount * factor;
        }
        if (d < poolDecimals) {
            uint256 factor = 10 ** uint256(poolDecimals - d);
            return lAmount / factor;
        }
        return lAmount;
    }

    // ─────────────────────────────────────────────────────────────────────
    //  HOOKS
    // ─────────────────────────────────────────────────────────────────────

    /// @dev Concrete pools return their BasketClass enum value here. We don't
    ///      expose BasketClass on the base because solidity enums aren't
    ///      cross-typeable; instead the concrete pool casts its compile-time
    ///      constant in.
    function _basketClassEnum() internal view virtual returns (BasketRegistry.BasketClass);

    // ─────────────────────────────────────────────────────────────────────
    //  GOVERNANCE
    // ─────────────────────────────────────────────────────────────────────

    function pause() external onlyRole(GOVERNANCE_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(GOVERNANCE_ROLE) {
        _unpause();
    }

    /// @notice Update per-basket healthy/emergency thresholds in basis points.
    function setBasketThresholds(uint16 _healthyBp, uint16 _emergencyBp) external onlyRole(GOVERNANCE_ROLE) {
        _setBasketThresholds(basketId, _healthyBp, _emergencyBp);
    }

    /// @notice Enter Recovery from Emergency. Governance-only.
    function enterRecovery() external onlyRole(GOVERNANCE_ROLE) {
        _enterBasketRecovery(basketId);
    }

    /// @notice Exit Recovery — reverts unless backing >= liabilities.
    function exitRecovery() external onlyRole(GOVERNANCE_ROLE) {
        _exitBasketRecovery(basketId, totalReserveInBaseUnits(), IERC20(address(liquidToken)).totalSupply());
    }
}
