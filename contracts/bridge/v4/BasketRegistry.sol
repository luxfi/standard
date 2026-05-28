// SPDX-License-Identifier: BSD-3-Clause
// Copyright (c) 2026 Lux Industries Inc.
pragma solidity ^0.8.31;

import { AccessControl } from "@openzeppelin/contracts/access/AccessControl.sol";

/**
 * @title BasketRegistry
 * @author Lux Industries
 * @notice Canonical mapping of basket-class → accepted bridged assets for BridgeV4.
 *
 * A "basket" is a synthetic unit-of-account that a LiquidX pool denominates in:
 *   USD basket  → LiquidUSD (LUSD)
 *   BTC basket  → LiquidBTC (LBTC)
 *   ETH basket  → LiquidETH (LETH)
 *   SOL basket  → LiquidSOL (LSOL)
 *   TON basket  → LiquidTON (LTON)
 *   XRP basket  → LiquidXRP (LXRP)
 *   DOT basket  → LiquidDOT (LDOT)
 *   LUX basket  → LUX/sLUX (native, reserved)
 *
 * A pool accepts deposits of any registered asset in its basket and credits LX
 * 1:1 (after decimal normalization). On burn, the user selects which asset to
 * receive back. Inventory is tracked per-asset by PerAssetLedger so the pool
 * can refuse a burn that would drain a specific asset below zero.
 *
 * Governance (DEFAULT_ADMIN_ROLE on this registry) can add new basket members
 * or remove existing ones, with the rule that a member can only be removed if
 * its reserves at the calling pool are zero. The pool address is consulted via
 * a (basket, asset, pool) → reserves view passed into removeAssetFromBasket so
 * the registry itself stays storage-light.
 */
contract BasketRegistry is AccessControl {
    /// @notice Canonical basket classes. Extendable via governance proposal
    ///         (compile-time add a new entry; deploy upgraded registry; migrate).
    enum BasketClass {
        USD,
        BTC,
        ETH,
        SOL,
        TON,
        XRP,
        DOT,
        LUX
    }

    /// @notice Per-asset entry in a basket
    struct AssetEntry {
        /// @notice True iff this slot is currently registered
        bool registered;
        /// @notice Index in `_members[basket]` for O(1) removal
        uint256 memberIndex;
        /// @notice Optional oracle/price-feed index; the pool resolves into a
        ///         per-asset price oracle (e.g. Pyth feed id). Zero means
        ///         "no oracle, treat as 1:1 with basket unit" — only valid
        ///         for tightly-pegged basket members (USDT/USDC/DAI/PYUSD/etc.).
        uint8 priceFeedIdx;
    }

    /// @notice basket → asset → entry
    mapping(BasketClass => mapping(address => AssetEntry)) internal _entries;

    /// @notice basket → ordered list of member addresses (for view iteration)
    mapping(BasketClass => address[]) internal _members;

    /// @notice Emitted when an asset is registered to a basket
    event AssetAdded(BasketClass indexed basket, address indexed asset, uint8 priceFeedIdx);

    /// @notice Emitted when an asset is removed from a basket
    event AssetRemoved(BasketClass indexed basket, address indexed asset);

    error BasketRegistry_ZeroAddress();
    error BasketRegistry_AlreadyRegistered();
    error BasketRegistry_NotRegistered();
    error BasketRegistry_NonZeroReserve();

    constructor(address admin) {
        if (admin == address(0)) revert BasketRegistry_ZeroAddress();
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
    }

    /// @notice Register an asset as a member of a basket
    /// @param basket         basket class to add to
    /// @param asset          bridged-asset contract address (LRC20B descendant)
    /// @param priceFeedIdx   oracle index, 0 = treat as 1:1 with basket unit
    function addAssetToBasket(BasketClass basket, address asset, uint8 priceFeedIdx)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        if (asset == address(0)) revert BasketRegistry_ZeroAddress();
        AssetEntry storage e = _entries[basket][asset];
        if (e.registered) revert BasketRegistry_AlreadyRegistered();

        e.registered = true;
        e.memberIndex = _members[basket].length;
        e.priceFeedIdx = priceFeedIdx;
        _members[basket].push(asset);

        emit AssetAdded(basket, asset, priceFeedIdx);
    }

    /// @notice Remove an asset from a basket. Caller MUST supply the current
    ///         pool-side reserve for that asset; the registry refuses removal
    ///         while reserve > 0 (no orphan funds).
    /// @dev The reserve is read off-chain by the governance proposer and
    ///      attested here. The pool is the source of truth via
    ///      PerAssetLedger.assetReserve(); a malicious admin could lie about
    ///      the reserve, but they hold DEFAULT_ADMIN_ROLE and could rug
    ///      otherwise, so the on-chain guard targets honest-mistake
    ///      protection only. For trust-minimised removal, governance can call
    ///      pool.assetReserve(asset) on-chain and pass the result here in the
    ///      same multicall.
    /// @param basket             basket class to remove from
    /// @param asset              bridged-asset contract address
    /// @param attestedReserve    pool's PerAssetLedger.assetReserve(asset)
    function removeAssetFromBasket(BasketClass basket, address asset, uint256 attestedReserve)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        AssetEntry storage e = _entries[basket][asset];
        if (!e.registered) revert BasketRegistry_NotRegistered();
        if (attestedReserve != 0) revert BasketRegistry_NonZeroReserve();

        uint256 idx = e.memberIndex;
        address[] storage list = _members[basket];
        uint256 lastIdx = list.length - 1;

        if (idx != lastIdx) {
            address swapped = list[lastIdx];
            list[idx] = swapped;
            _entries[basket][swapped].memberIndex = idx;
        }
        list.pop();

        delete _entries[basket][asset];

        emit AssetRemoved(basket, asset);
    }

    // ─────────────────────────────────────────────────────────────────────
    //  VIEWS
    // ─────────────────────────────────────────────────────────────────────

    /// @notice Check whether an asset belongs to a basket
    function isInBasket(BasketClass basket, address asset) external view returns (bool) {
        return _entries[basket][asset].registered;
    }

    /// @notice Get the ordered list of members of a basket
    function getBasketMembers(BasketClass basket) external view returns (address[] memory) {
        return _members[basket];
    }

    /// @notice Number of members in a basket
    function basketSize(BasketClass basket) external view returns (uint256) {
        return _members[basket].length;
    }

    /// @notice Get the priceFeedIdx for a registered (basket, asset) pair.
    /// @dev Reverts if not registered.
    function priceFeedIdxOf(BasketClass basket, address asset) external view returns (uint8) {
        AssetEntry storage e = _entries[basket][asset];
        if (!e.registered) revert BasketRegistry_NotRegistered();
        return e.priceFeedIdx;
    }
}
