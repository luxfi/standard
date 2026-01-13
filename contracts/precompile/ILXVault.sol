// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ILXBook} from "./ILXBook.sol";

/// @title ILXVault
/// @notice LP-9030 precompile: LXVault (custody, margin, positions, liquidations)
/// @dev Singleton at 0x0000000000000000000000000000000000009030.
///      Handles balances, margin, positions, and liquidations for LX.
///      Receives settlement callbacks from LXBook after trade matching.
interface ILXVault {
    // -------------------------------------------------------------------------
    // Identifiers / Enums
    // -------------------------------------------------------------------------

    /// @notice Account identifier (main account = address, subaccount = derived)
    type AccountId is bytes32;

    /// @notice Position identifier
    type PositionId is uint64;

    /// @notice Margin mode for positions
    enum MarginMode {
        CROSS,    // shared margin across positions
        ISOLATED  // margin isolated per position
    }

    /// @notice Account status
    enum AccountStatus {
        ACTIVE,
        LIQUIDATING,
        BANKRUPT
    }

    /// @notice Asset type
    enum AssetType {
        SPOT,     // spot balance (can withdraw)
        MARGIN    // margin balance (locked for positions)
    }

    // -------------------------------------------------------------------------
    // Account Management
    // -------------------------------------------------------------------------

    /// @notice Create a subaccount under the caller's main account
    /// @param subaccountIndex Index for the subaccount (0-255)
    /// @return accountId The derived subaccount ID
    function createSubaccount(uint8 subaccountIndex) external returns (AccountId accountId);

    /// @notice Get account ID for an address (main account)
    function getAccountId(address addr) external pure returns (AccountId);

    /// @notice Get subaccount ID
    function getSubaccountId(address addr, uint8 subaccountIndex) external pure returns (AccountId);

    // -------------------------------------------------------------------------
    // Deposits / Withdrawals
    // -------------------------------------------------------------------------

    /// @notice Deposit collateral into vault
    /// @param token Token address (address(0) for native LUX)
    /// @param amount Amount to deposit (X18 scaled)
    /// @param accountId Target account (use getAccountId(msg.sender) for main)
    function deposit(address token, uint128 amount, AccountId accountId) external payable;

    /// @notice Withdraw collateral from vault
    /// @param token Token address
    /// @param amount Amount to withdraw (X18 scaled)
    /// @param accountId Source account
    function withdraw(address token, uint128 amount, AccountId accountId) external;

    /// @notice Transfer between accounts (same owner only)
    /// @param token Token address
    /// @param amount Amount to transfer
    /// @param from Source account
    /// @param to Destination account
    function transfer(address token, uint128 amount, AccountId from, AccountId to) external;

    // -------------------------------------------------------------------------
    // Balance Queries
    // -------------------------------------------------------------------------

    /// @notice Get balance for a specific token
    struct Balance {
        uint128 available;    // withdrawable
        uint128 locked;       // in open orders
        uint128 margin;       // used as margin
        uint128 total;        // available + locked + margin
    }

    function getBalance(AccountId accountId, address token) external view returns (Balance memory);

    /// @notice Get all balances for an account
    function getBalances(AccountId accountId) external view returns (address[] memory tokens, Balance[] memory balances);

    // -------------------------------------------------------------------------
    // Position Management
    // -------------------------------------------------------------------------

    /// @notice Position data
    struct Position {
        ILXBook.MarketId marketId;
        bool isLong;
        uint128 sizeX18;           // position size
        uint128 entryPriceX18;     // average entry price
        uint128 liquidationPxX18;  // liquidation price
        uint128 marginX18;         // margin allocated (isolated mode)
        int128 unrealizedPnlX18;   // current unrealized PnL
        int128 fundingOwedX18;     // accumulated funding
        MarginMode marginMode;
        uint64 openTimestamp;
    }

    /// @notice Get position for a market
    function getPosition(AccountId accountId, ILXBook.MarketId marketId) external view returns (Position memory);

    /// @notice Get all positions for an account
    function getPositions(AccountId accountId) external view returns (Position[] memory);

    // -------------------------------------------------------------------------
    // Margin Queries
    // -------------------------------------------------------------------------

    /// @notice Account margin summary
    struct MarginSummary {
        uint128 totalCollateralX18;   // total collateral value in USD
        uint128 usedMarginX18;        // margin used by positions
        uint128 freeMarginX18;        // available for new positions
        uint128 marginRatioX18;       // used/total (1e18 = 100%)
        uint128 maintenanceMarginX18; // minimum required margin
        bool canTrade;                // false if below maintenance
        bool canWithdraw;             // false if withdrawal would breach maintenance
    }

    function getMarginSummary(AccountId accountId) external view returns (MarginSummary memory);

    /// @notice Check if an order can be placed (margin pre-check)
    /// @param accountId Account placing the order
    /// @param marketId Market for the order
    /// @param isBuy Order direction
    /// @param sizeX18 Order size
    /// @param priceX18 Order price (for limit orders)
    /// @return canPlace True if margin is sufficient
    /// @return requiredMarginX18 Margin required for this order
    function checkOrderMargin(
        AccountId accountId,
        ILXBook.MarketId marketId,
        bool isBuy,
        uint128 sizeX18,
        uint128 priceX18
    ) external view returns (bool canPlace, uint128 requiredMarginX18);

    // -------------------------------------------------------------------------
    // Settlement (called by LXBook)
    // -------------------------------------------------------------------------

    /// @notice Settle a trade from LXBook
    /// @dev Only callable by LXBook precompile
    /// @param settlement Trade settlement data
    /// @return success True if settlement succeeded
    function settleTrade(ILXBook.TradeSettlement calldata settlement) external returns (bool success);

    /// @notice Batch settle multiple trades
    function settleTrades(ILXBook.TradeSettlement[] calldata settlements) external returns (bool[] memory successes);

    // -------------------------------------------------------------------------
    // Liquidation
    // -------------------------------------------------------------------------

    /// @notice Check if account is liquidatable
    function isLiquidatable(AccountId accountId) external view returns (bool);

    /// @notice Liquidate an undercollateralized position
    /// @param accountId Account to liquidate
    /// @param marketId Market to liquidate
    /// @param sizeX18 Size to liquidate (0 = full position)
    /// @return liquidatedSizeX18 Actual size liquidated
    /// @return liquidationPriceX18 Price at which liquidation executed
    function liquidate(
        AccountId accountId,
        ILXBook.MarketId marketId,
        uint128 sizeX18
    ) external returns (uint128 liquidatedSizeX18, uint128 liquidationPriceX18);

    /// @notice Auto-deleverage a winning position against a bankrupt account
    /// @dev Called when insurance fund is depleted
    function autoDeleverage(
        AccountId winningAccount,
        AccountId bankruptAccount,
        ILXBook.MarketId marketId,
        uint128 sizeX18
    ) external returns (bool success);

    // -------------------------------------------------------------------------
    // Funding (Perpetuals)
    // -------------------------------------------------------------------------

    /// @notice Get current funding rate for a market
    /// @return rateX18 Funding rate (positive = longs pay shorts)
    /// @return nextFundingTime Next funding settlement timestamp
    function getFundingRate(ILXBook.MarketId marketId) external view returns (int128 rateX18, uint64 nextFundingTime);

    /// @notice Settle funding for an account
    /// @dev Usually called automatically on position change
    function settleFunding(AccountId accountId, ILXBook.MarketId marketId) external returns (int128 fundingPaidX18);

    // -------------------------------------------------------------------------
    // Margin Mode
    // -------------------------------------------------------------------------

    /// @notice Set margin mode for a market position
    /// @param accountId Account
    /// @param marketId Market
    /// @param mode New margin mode
    function setMarginMode(AccountId accountId, ILXBook.MarketId marketId, MarginMode mode) external;

    /// @notice Add/remove margin to isolated position
    function adjustIsolatedMargin(
        AccountId accountId,
        ILXBook.MarketId marketId,
        int128 deltaMarginX18  // positive = add, negative = remove
    ) external;

    // -------------------------------------------------------------------------
    // Collateral Configuration (admin/governance)
    // -------------------------------------------------------------------------

    /// @notice Collateral asset configuration
    struct CollateralConfig {
        address token;
        uint128 weightX18;        // collateral weight (0.8e18 = 80% value counts)
        uint128 maxAmountX18;     // max depositable
        bool enabled;
    }

    function getCollateralConfig(address token) external view returns (CollateralConfig memory);

    // -------------------------------------------------------------------------
    // Events
    // -------------------------------------------------------------------------

    event Deposited(AccountId indexed accountId, address indexed token, uint128 amount);
    event Withdrawn(AccountId indexed accountId, address indexed token, uint128 amount);
    event Transferred(AccountId indexed from, AccountId indexed to, address indexed token, uint128 amount);

    event PositionOpened(AccountId indexed accountId, ILXBook.MarketId indexed marketId, bool isLong, uint128 sizeX18, uint128 priceX18);
    event PositionClosed(AccountId indexed accountId, ILXBook.MarketId indexed marketId, uint128 sizeX18, uint128 priceX18, int128 pnlX18);
    event PositionLiquidated(AccountId indexed accountId, ILXBook.MarketId indexed marketId, uint128 sizeX18, uint128 priceX18, address liquidator);

    event FundingSettled(AccountId indexed accountId, ILXBook.MarketId indexed marketId, int128 fundingPaidX18);
    event MarginModeChanged(AccountId indexed accountId, ILXBook.MarketId indexed marketId, MarginMode mode);

    // -------------------------------------------------------------------------
    // Errors
    // -------------------------------------------------------------------------

    error InsufficientBalance();
    error InsufficientMargin();
    error NotLiquidatable();
    error InvalidAccount();
    error InvalidAmount();
    error WithdrawalWouldBreachMargin();
    error OnlyLXBook();
    error MarketNotFound();
}

/// @dev LXVault precompile address constant
address constant LX_VAULT = 0x0000000000000000000000000000000000009030;
