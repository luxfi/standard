// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.28;

/// @notice Market parameters
struct MarketParams {
    address loanToken;
    address collateralToken;
    address oracle;
    address rateModel;
    uint256 lltv;
}

/// @notice User position
struct Position {
    uint256 supplyShares;
    uint256 borrowShares;
    uint256 collateral;
}

/// @notice Market state
struct Market {
    uint128 totalSupplyAssets;
    uint128 totalSupplyShares;
    uint128 totalBorrowAssets;
    uint128 totalBorrowShares;
    uint128 lastUpdate;
    uint128 fee;
}

/// @notice Market ID type
type Id is bytes32;

/// @title IMarkets
/// @notice Interface for Lux Markets lending primitive
interface IMarkets {
    /* SUPPLY */
    
    function supply(
        MarketParams memory marketParams,
        uint256 assets,
        uint256 shares,
        address onBehalf,
        bytes calldata data
    ) external returns (uint256 assetsSupplied, uint256 sharesSupplied);

    function withdraw(
        MarketParams memory marketParams,
        uint256 assets,
        uint256 shares,
        address onBehalf,
        address receiver
    ) external returns (uint256 assetsWithdrawn, uint256 sharesWithdrawn);

    /* BORROW */

    function borrow(
        MarketParams memory marketParams,
        uint256 assets,
        uint256 shares,
        address onBehalf,
        address receiver
    ) external returns (uint256 assetsBorrowed, uint256 sharesBorrowed);

    function repay(
        MarketParams memory marketParams,
        uint256 assets,
        uint256 shares,
        address onBehalf,
        bytes calldata data
    ) external returns (uint256 assetsRepaid, uint256 sharesRepaid);

    /* COLLATERAL */

    function supplyCollateral(
        MarketParams memory marketParams,
        uint256 assets,
        address onBehalf,
        bytes calldata data
    ) external;

    function withdrawCollateral(
        MarketParams memory marketParams,
        uint256 assets,
        address onBehalf,
        address receiver
    ) external;

    /* LIQUIDATION */

    function liquidate(
        MarketParams memory marketParams,
        address borrower,
        uint256 seizedAssets,
        uint256 repaidShares,
        bytes calldata data
    ) external returns (uint256 seizedAssetsOut, uint256 repaidAssetsOut);

    /* FLASH LOANS */

    function flashLoan(address token, uint256 assets, bytes calldata data) external;

    /* MARKET CREATION */

    function createMarket(MarketParams memory marketParams) external;

    /* VIEW */

    function isMarketCreated(Id id) external view returns (bool);
    function totalSupplyAssets(Id id) external view returns (uint256);
    function totalBorrowAssets(Id id) external view returns (uint256);
    function supplyShares(Id id, address user) external view returns (uint256);
    function borrowShares(Id id, address user) external view returns (uint256);
    function collateral(Id id, address user) external view returns (uint256);
}
