// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.31;

import {IMarkets, MarketParams, Id} from "./interfaces/IMarkets.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IWETH} from "./interfaces/IWETH.sol";

/// @title Router
/// @notice User-friendly router for Markets operations
/// @dev Handles approvals, native ETH wrapping, and batch operations
contract Router {
    using SafeERC20 for IERC20;

    /* STORAGE */

    /// @notice Markets contract
    IMarkets public immutable markets;

    /// @notice Wrapped native token (WLUX)
    IWETH public immutable weth;

    /* ERRORS */

    error InsufficientBalance();
    error TransferFailed();

    /* CONSTRUCTOR */

    constructor(address _markets, address _weth) {
        markets = IMarkets(_markets);
        weth = IWETH(_weth);
    }

    /* RECEIVE */

    receive() external payable {}

    /* SUPPLY */

    /// @notice Supply assets to a market
    function supply(
        MarketParams calldata marketParams,
        uint256 assets,
        address onBehalf
    ) external returns (uint256 assetsSupplied, uint256 shares) {
        IERC20(marketParams.loanToken).safeTransferFrom(msg.sender, address(this), assets);
        IERC20(marketParams.loanToken).approve(address(markets), assets);
        
        return markets.supply(marketParams, assets, 0, onBehalf, "");
    }

    /// @notice Supply native ETH (wraps to WETH)
    function supplyETH(
        MarketParams calldata marketParams,
        address onBehalf
    ) external payable returns (uint256 assetsSupplied, uint256 shares) {
        require(marketParams.loanToken == address(weth), "Not WETH market");
        
        weth.deposit{value: msg.value}();
        IERC20(address(weth)).approve(address(markets), msg.value);
        
        return markets.supply(marketParams, msg.value, 0, onBehalf, "");
    }

    /* WITHDRAW */

    /// @notice Withdraw assets from a market
    function withdraw(
        MarketParams calldata marketParams,
        uint256 assets,
        address receiver
    ) external returns (uint256 assetsWithdrawn, uint256 shares) {
        return markets.withdraw(marketParams, assets, 0, msg.sender, receiver);
    }

    /// @notice Withdraw and unwrap to native ETH
    function withdrawETH(
        MarketParams calldata marketParams,
        uint256 assets,
        address receiver
    ) external returns (uint256 assetsWithdrawn, uint256 shares) {
        require(marketParams.loanToken == address(weth), "Not WETH market");
        
        (assetsWithdrawn, shares) = markets.withdraw(marketParams, assets, 0, msg.sender, address(this));
        
        weth.withdraw(assetsWithdrawn);
        (bool success,) = receiver.call{value: assetsWithdrawn}("");
        if (!success) revert TransferFailed();
    }

    /* COLLATERAL */

    /// @notice Supply collateral to a market
    function supplyCollateral(
        MarketParams calldata marketParams,
        uint256 assets,
        address onBehalf
    ) external {
        IERC20(marketParams.collateralToken).safeTransferFrom(msg.sender, address(this), assets);
        IERC20(marketParams.collateralToken).approve(address(markets), assets);
        
        markets.supplyCollateral(marketParams, assets, onBehalf, "");
    }

    /// @notice Supply native ETH as collateral
    function supplyCollateralETH(
        MarketParams calldata marketParams,
        address onBehalf
    ) external payable {
        require(marketParams.collateralToken == address(weth), "Not WETH collateral");
        
        weth.deposit{value: msg.value}();
        IERC20(address(weth)).approve(address(markets), msg.value);
        
        markets.supplyCollateral(marketParams, msg.value, onBehalf, "");
    }

    /// @notice Withdraw collateral
    function withdrawCollateral(
        MarketParams calldata marketParams,
        uint256 assets,
        address receiver
    ) external {
        markets.withdrawCollateral(marketParams, assets, msg.sender, receiver);
    }

    /* BORROW */

    /// @notice Borrow assets from a market
    function borrow(
        MarketParams calldata marketParams,
        uint256 assets,
        address receiver
    ) external returns (uint256 assetsBorrowed, uint256 shares) {
        return markets.borrow(marketParams, assets, 0, msg.sender, receiver);
    }

    /// @notice Borrow and unwrap to native ETH
    function borrowETH(
        MarketParams calldata marketParams,
        uint256 assets,
        address receiver
    ) external returns (uint256 assetsBorrowed, uint256 shares) {
        require(marketParams.loanToken == address(weth), "Not WETH market");
        
        (assetsBorrowed, shares) = markets.borrow(marketParams, assets, 0, msg.sender, address(this));
        
        weth.withdraw(assetsBorrowed);
        (bool success,) = receiver.call{value: assetsBorrowed}("");
        if (!success) revert TransferFailed();
    }

    /* REPAY */

    /// @notice Repay borrowed assets
    function repay(
        MarketParams calldata marketParams,
        uint256 assets,
        address onBehalf
    ) external returns (uint256 assetsRepaid, uint256 shares) {
        IERC20(marketParams.loanToken).safeTransferFrom(msg.sender, address(this), assets);
        IERC20(marketParams.loanToken).approve(address(markets), assets);
        
        return markets.repay(marketParams, assets, 0, onBehalf, "");
    }

    /// @notice Repay with native ETH
    function repayETH(
        MarketParams calldata marketParams,
        address onBehalf
    ) external payable returns (uint256 assetsRepaid, uint256 shares) {
        require(marketParams.loanToken == address(weth), "Not WETH market");
        
        weth.deposit{value: msg.value}();
        IERC20(address(weth)).approve(address(markets), msg.value);
        
        return markets.repay(marketParams, msg.value, 0, onBehalf, "");
    }

    /* BATCH */

    /// @notice Execute multiple operations atomically
    function multicall(bytes[] calldata data) external payable returns (bytes[] memory results) {
        results = new bytes[](data.length);
        for (uint256 i = 0; i < data.length; i++) {
            (bool success, bytes memory result) = address(this).delegatecall(data[i]);
            require(success, "Multicall failed");
            results[i] = result;
        }
    }

    /* COMBO OPERATIONS */

    /// @notice Supply collateral and borrow in one transaction
    function supplyCollateralAndBorrow(
        MarketParams calldata marketParams,
        uint256 collateralAmount,
        uint256 borrowAmount,
        address receiver
    ) external returns (uint256 borrowed, uint256 borrowShares) {
        // Supply collateral
        IERC20(marketParams.collateralToken).safeTransferFrom(msg.sender, address(this), collateralAmount);
        IERC20(marketParams.collateralToken).approve(address(markets), collateralAmount);
        markets.supplyCollateral(marketParams, collateralAmount, msg.sender, "");

        // Borrow
        return markets.borrow(marketParams, borrowAmount, 0, msg.sender, receiver);
    }

    /// @notice Repay and withdraw collateral in one transaction
    function repayAndWithdrawCollateral(
        MarketParams calldata marketParams,
        uint256 repayAmount,
        uint256 withdrawAmount,
        address receiver
    ) external returns (uint256 repaid, uint256 repayShares) {
        // Repay
        IERC20(marketParams.loanToken).safeTransferFrom(msg.sender, address(this), repayAmount);
        IERC20(marketParams.loanToken).approve(address(markets), repayAmount);
        (repaid, repayShares) = markets.repay(marketParams, repayAmount, 0, msg.sender, "");

        // Withdraw collateral
        markets.withdrawCollateral(marketParams, withdrawAmount, msg.sender, receiver);
    }
}
