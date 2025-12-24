// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.28;

import {IMarkets, MarketParams, Position, Market, Id} from "./interfaces/IMarkets.sol";
import {IMarketsCallbacks} from "./interfaces/IMarketsCallbacks.sol";
import {IOracle} from "./interfaces/IOracle.sol";
import {IRateModel} from "./interfaces/IRateModel.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import {MathLib} from "./libraries/MathLib.sol";
import {SharesMathLib} from "./libraries/SharesMathLib.sol";
import {MarketParamsLib} from "./libraries/MarketParamsLib.sol";

/// @title Lux Markets
/// @author Lux Industries
/// @notice Singleton lending primitive for Lux Network
/// @dev Inspired by Morpho Blue, optimized for Lux chain
contract Markets is IMarkets, ReentrancyGuard {
    using MathLib for uint256;
    using SharesMathLib for uint256;
    using SafeERC20 for IERC20;
    using MarketParamsLib for MarketParams;

    /* CONSTANTS */

    /// @notice Maximum liquidation incentive factor (15%)
    uint256 public constant MAX_LIQUIDATION_INCENTIVE_FACTOR = 1.15e18;

    /// @notice Oracle price scale
    uint256 public constant ORACLE_PRICE_SCALE = 1e36;

    /// @notice Maximum fee (25%)
    uint256 public constant MAX_FEE = 0.25e18;

    /* STORAGE */

    /// @notice Owner of the contract
    address public owner;

    /// @notice Fee recipient
    address public feeRecipient;

    /// @notice Market data by market ID
    mapping(Id => Market) public market;

    /// @notice User positions by market ID
    mapping(Id => mapping(address => Position)) public position;

    /// @notice Whether a market is created
    mapping(Id => bool) public isMarketCreated;

    /// @notice Whether a rate model is enabled
    mapping(address => bool) public isRateModelEnabled;

    /// @notice Whether an LLTV is enabled
    mapping(uint256 => bool) public isLltvEnabled;

    /// @notice Nonce for authorizations
    mapping(address => uint256) public nonce;

    /// @notice Authorization status
    mapping(address => mapping(address => bool)) public isAuthorized;

    /* EVENTS */

    event MarketCreated(Id indexed id, MarketParams marketParams);
    event Supply(Id indexed id, address indexed caller, address indexed onBehalf, uint256 assets, uint256 shares);
    event Withdraw(Id indexed id, address indexed caller, address indexed onBehalf, address receiver, uint256 assets, uint256 shares);
    event Borrow(Id indexed id, address indexed caller, address indexed onBehalf, address receiver, uint256 assets, uint256 shares);
    event Repay(Id indexed id, address indexed caller, address indexed onBehalf, uint256 assets, uint256 shares);
    event SupplyCollateral(Id indexed id, address indexed caller, address indexed onBehalf, uint256 assets);
    event WithdrawCollateral(Id indexed id, address indexed caller, address indexed onBehalf, address receiver, uint256 assets);
    event Liquidate(Id indexed id, address indexed caller, address indexed borrower, uint256 repaidAssets, uint256 repaidShares, uint256 seizedAssets, uint256 badDebtAssets, uint256 badDebtShares);
    event FlashLoan(address indexed caller, address indexed token, uint256 assets);
    event SetOwner(address indexed newOwner);
    event SetFee(Id indexed id, uint256 newFee);
    event SetFeeRecipient(address indexed newFeeRecipient);
    event EnableRateModel(address indexed rateModel);
    event EnableLltv(uint256 lltv);
    event AccrueInterest(Id indexed id, uint256 prevBorrowRate, uint256 interest, uint256 feeShares);

    /* ERRORS */

    error NotOwner();
    error MarketNotCreated();
    error MarketAlreadyCreated();
    error RateModelNotEnabled();
    error LltvNotEnabled();
    error ZeroAddress();
    error ZeroAssets();
    error ZeroShares();
    error InsufficientCollateral();
    error InsufficientLiquidity();
    error HealthyPosition();
    error NotAuthorized();
    error MaxFeeExceeded();

    /* MODIFIERS */

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    /* CONSTRUCTOR */

    constructor(address _owner) {
        owner = _owner;
        emit SetOwner(_owner);
    }

    /* ADMIN */

    function setOwner(address newOwner) external onlyOwner {
        if (newOwner == address(0)) revert ZeroAddress();
        owner = newOwner;
        emit SetOwner(newOwner);
    }

    function setFeeRecipient(address newFeeRecipient) external onlyOwner {
        feeRecipient = newFeeRecipient;
        emit SetFeeRecipient(newFeeRecipient);
    }

    function enableRateModel(address rateModel) external onlyOwner {
        isRateModelEnabled[rateModel] = true;
        emit EnableRateModel(rateModel);
    }

    function enableLltv(uint256 lltv) external onlyOwner {
        if (lltv >= 1e18) revert();
        isLltvEnabled[lltv] = true;
        emit EnableLltv(lltv);
    }

    function setFee(MarketParams memory marketParams, uint256 newFee) external onlyOwner {
        Id id = marketParams.id();
        if (!isMarketCreated[id]) revert MarketNotCreated();
        if (newFee > MAX_FEE) revert MaxFeeExceeded();
        
        _accrueInterest(marketParams, id);
        market[id].fee = uint128(newFee);
        emit SetFee(id, newFee);
    }

    /* MARKET CREATION */

    function createMarket(MarketParams memory marketParams) external {
        Id id = marketParams.id();
        if (isMarketCreated[id]) revert MarketAlreadyCreated();
        if (!isRateModelEnabled[marketParams.rateModel]) revert RateModelNotEnabled();
        if (!isLltvEnabled[marketParams.lltv]) revert LltvNotEnabled();

        isMarketCreated[id] = true;
        market[id].lastUpdate = uint128(block.timestamp);

        emit MarketCreated(id, marketParams);
    }

    /* SUPPLY */

    function supply(
        MarketParams memory marketParams,
        uint256 assets,
        uint256 shares,
        address onBehalf,
        bytes calldata data
    ) external nonReentrant returns (uint256, uint256) {
        Id id = marketParams.id();
        if (!isMarketCreated[id]) revert MarketNotCreated();
        if (onBehalf == address(0)) revert ZeroAddress();

        _accrueInterest(marketParams, id);

        if (assets > 0) {
            shares = assets.toSharesDown(market[id].totalSupplyAssets, market[id].totalSupplyShares);
        } else {
            assets = shares.toAssetsUp(market[id].totalSupplyAssets, market[id].totalSupplyShares);
        }

        if (assets == 0 || shares == 0) revert ZeroAssets();

        position[id][onBehalf].supplyShares += shares;
        market[id].totalSupplyShares += uint128(shares);
        market[id].totalSupplyAssets += uint128(assets);

        emit Supply(id, msg.sender, onBehalf, assets, shares);

        if (data.length > 0) {
            IMarketsCallbacks(msg.sender).onSupply(assets, data);
        }

        IERC20(marketParams.loanToken).safeTransferFrom(msg.sender, address(this), assets);

        return (assets, shares);
    }

    function withdraw(
        MarketParams memory marketParams,
        uint256 assets,
        uint256 shares,
        address onBehalf,
        address receiver
    ) external nonReentrant returns (uint256, uint256) {
        Id id = marketParams.id();
        if (!isMarketCreated[id]) revert MarketNotCreated();
        if (receiver == address(0)) revert ZeroAddress();
        
        _checkAuthorization(onBehalf);
        _accrueInterest(marketParams, id);

        if (assets > 0) {
            shares = assets.toSharesUp(market[id].totalSupplyAssets, market[id].totalSupplyShares);
        } else {
            assets = shares.toAssetsDown(market[id].totalSupplyAssets, market[id].totalSupplyShares);
        }

        if (assets == 0 || shares == 0) revert ZeroAssets();

        position[id][onBehalf].supplyShares -= shares;
        market[id].totalSupplyShares -= uint128(shares);
        market[id].totalSupplyAssets -= uint128(assets);

        if (market[id].totalBorrowAssets > market[id].totalSupplyAssets) revert InsufficientLiquidity();

        emit Withdraw(id, msg.sender, onBehalf, receiver, assets, shares);

        IERC20(marketParams.loanToken).safeTransfer(receiver, assets);

        return (assets, shares);
    }

    /* BORROW */

    function borrow(
        MarketParams memory marketParams,
        uint256 assets,
        uint256 shares,
        address onBehalf,
        address receiver
    ) external nonReentrant returns (uint256, uint256) {
        Id id = marketParams.id();
        if (!isMarketCreated[id]) revert MarketNotCreated();
        if (receiver == address(0)) revert ZeroAddress();

        _checkAuthorization(onBehalf);
        _accrueInterest(marketParams, id);

        if (assets > 0) {
            shares = assets.toSharesUp(market[id].totalBorrowAssets, market[id].totalBorrowShares);
        } else {
            assets = shares.toAssetsDown(market[id].totalBorrowAssets, market[id].totalBorrowShares);
        }

        if (assets == 0 || shares == 0) revert ZeroAssets();

        position[id][onBehalf].borrowShares += shares;
        market[id].totalBorrowShares += uint128(shares);
        market[id].totalBorrowAssets += uint128(assets);

        if (market[id].totalBorrowAssets > market[id].totalSupplyAssets) revert InsufficientLiquidity();
        if (!_isHealthy(marketParams, id, onBehalf)) revert InsufficientCollateral();

        emit Borrow(id, msg.sender, onBehalf, receiver, assets, shares);

        IERC20(marketParams.loanToken).safeTransfer(receiver, assets);

        return (assets, shares);
    }

    function repay(
        MarketParams memory marketParams,
        uint256 assets,
        uint256 shares,
        address onBehalf,
        bytes calldata data
    ) external nonReentrant returns (uint256, uint256) {
        Id id = marketParams.id();
        if (!isMarketCreated[id]) revert MarketNotCreated();
        if (onBehalf == address(0)) revert ZeroAddress();

        _accrueInterest(marketParams, id);

        if (assets > 0) {
            shares = assets.toSharesDown(market[id].totalBorrowAssets, market[id].totalBorrowShares);
        } else {
            assets = shares.toAssetsUp(market[id].totalBorrowAssets, market[id].totalBorrowShares);
        }

        if (assets == 0 || shares == 0) revert ZeroAssets();

        position[id][onBehalf].borrowShares -= shares;
        market[id].totalBorrowShares -= uint128(shares);
        market[id].totalBorrowAssets -= uint128(assets);

        emit Repay(id, msg.sender, onBehalf, assets, shares);

        if (data.length > 0) {
            IMarketsCallbacks(msg.sender).onRepay(assets, data);
        }

        IERC20(marketParams.loanToken).safeTransferFrom(msg.sender, address(this), assets);

        return (assets, shares);
    }

    /* COLLATERAL */

    function supplyCollateral(
        MarketParams memory marketParams,
        uint256 assets,
        address onBehalf,
        bytes calldata data
    ) external nonReentrant {
        Id id = marketParams.id();
        if (!isMarketCreated[id]) revert MarketNotCreated();
        if (onBehalf == address(0)) revert ZeroAddress();
        if (assets == 0) revert ZeroAssets();

        position[id][onBehalf].collateral += assets;

        emit SupplyCollateral(id, msg.sender, onBehalf, assets);

        if (data.length > 0) {
            IMarketsCallbacks(msg.sender).onSupplyCollateral(assets, data);
        }

        IERC20(marketParams.collateralToken).safeTransferFrom(msg.sender, address(this), assets);
    }

    function withdrawCollateral(
        MarketParams memory marketParams,
        uint256 assets,
        address onBehalf,
        address receiver
    ) external nonReentrant {
        Id id = marketParams.id();
        if (!isMarketCreated[id]) revert MarketNotCreated();
        if (receiver == address(0)) revert ZeroAddress();
        if (assets == 0) revert ZeroAssets();

        _checkAuthorization(onBehalf);
        _accrueInterest(marketParams, id);

        position[id][onBehalf].collateral -= assets;

        if (!_isHealthy(marketParams, id, onBehalf)) revert InsufficientCollateral();

        emit WithdrawCollateral(id, msg.sender, onBehalf, receiver, assets);

        IERC20(marketParams.collateralToken).safeTransfer(receiver, assets);
    }

    /* LIQUIDATION */

    function liquidate(
        MarketParams memory marketParams,
        address borrower,
        uint256 seizedAssets,
        uint256 repaidShares,
        bytes calldata data
    ) external nonReentrant returns (uint256, uint256) {
        Id id = marketParams.id();
        if (!isMarketCreated[id]) revert MarketNotCreated();

        _accrueInterest(marketParams, id);

        if (_isHealthy(marketParams, id, borrower)) revert HealthyPosition();

        uint256 repaidAssets;
        {
            uint256 collateralPrice = IOracle(marketParams.oracle).price();
            uint256 incentiveFactor = _liquidationIncentiveFactor(marketParams.lltv);

            if (seizedAssets > 0) {
                repaidAssets = seizedAssets.mulDivUp(collateralPrice, ORACLE_PRICE_SCALE).mulDivUp(1e18, incentiveFactor);
                repaidShares = repaidAssets.toSharesDown(market[id].totalBorrowAssets, market[id].totalBorrowShares);
            } else {
                repaidAssets = repaidShares.toAssetsUp(market[id].totalBorrowAssets, market[id].totalBorrowShares);
                seizedAssets = repaidAssets.mulDivDown(incentiveFactor, 1e18).mulDivDown(ORACLE_PRICE_SCALE, collateralPrice);
            }
        }

        uint256 badDebtAssets;
        uint256 badDebtShares;

        position[id][borrower].borrowShares -= repaidShares;
        market[id].totalBorrowShares -= uint128(repaidShares);
        market[id].totalBorrowAssets -= uint128(repaidAssets);

        position[id][borrower].collateral -= seizedAssets;

        // Handle bad debt if position is insolvent
        if (position[id][borrower].collateral == 0 && position[id][borrower].borrowShares > 0) {
            badDebtShares = position[id][borrower].borrowShares;
            badDebtAssets = badDebtShares.toAssetsUp(market[id].totalBorrowAssets, market[id].totalBorrowShares);

            market[id].totalBorrowAssets -= uint128(badDebtAssets);
            market[id].totalBorrowShares -= uint128(badDebtShares);
            market[id].totalSupplyAssets -= uint128(badDebtAssets);
            position[id][borrower].borrowShares = 0;
        }

        emit Liquidate(id, msg.sender, borrower, repaidAssets, repaidShares, seizedAssets, badDebtAssets, badDebtShares);

        if (data.length > 0) {
            IMarketsCallbacks(msg.sender).onLiquidate(repaidAssets, data);
        }

        IERC20(marketParams.loanToken).safeTransferFrom(msg.sender, address(this), repaidAssets);
        IERC20(marketParams.collateralToken).safeTransfer(msg.sender, seizedAssets);

        return (seizedAssets, repaidAssets);
    }

    /* FLASH LOANS */

    function flashLoan(address token, uint256 assets, bytes calldata data) external nonReentrant {
        if (assets == 0) revert ZeroAssets();

        emit FlashLoan(msg.sender, token, assets);

        IERC20(token).safeTransfer(msg.sender, assets);

        IMarketsCallbacks(msg.sender).onFlashLoan(assets, data);

        IERC20(token).safeTransferFrom(msg.sender, address(this), assets);
    }

    /* AUTHORIZATION */

    function setAuthorization(address authorized, bool newIsAuthorized) external {
        isAuthorized[msg.sender][authorized] = newIsAuthorized;
    }

    /* INTERNAL */

    function _checkAuthorization(address onBehalf) internal view {
        if (msg.sender != onBehalf && !isAuthorized[onBehalf][msg.sender]) {
            revert NotAuthorized();
        }
    }

    function _accrueInterest(MarketParams memory marketParams, Id id) internal {
        uint256 elapsed = block.timestamp - market[id].lastUpdate;
        if (elapsed == 0) return;

        market[id].lastUpdate = uint128(block.timestamp);

        if (market[id].totalBorrowAssets == 0) return;

        uint256 borrowRate = IRateModel(marketParams.rateModel).borrowRate(marketParams, market[id]);
        uint256 interest = uint256(market[id].totalBorrowAssets).mulDivDown(borrowRate * elapsed, 1e18 * 365 days);

        market[id].totalBorrowAssets += uint128(interest);
        market[id].totalSupplyAssets += uint128(interest);

        uint256 feeShares;
        if (market[id].fee > 0 && feeRecipient != address(0)) {
            uint256 feeAmount = interest.mulDivDown(market[id].fee, 1e18);
            feeShares = feeAmount.toSharesDown(market[id].totalSupplyAssets - feeAmount, market[id].totalSupplyShares);
            position[id][feeRecipient].supplyShares += feeShares;
            market[id].totalSupplyShares += uint128(feeShares);
        }

        emit AccrueInterest(id, borrowRate, interest, feeShares);
    }

    function _isHealthy(MarketParams memory marketParams, Id id, address borrower) internal view returns (bool) {
        if (position[id][borrower].borrowShares == 0) return true;

        uint256 collateralPrice = IOracle(marketParams.oracle).price();
        uint256 collateralValue = position[id][borrower].collateral.mulDivDown(collateralPrice, ORACLE_PRICE_SCALE);
        uint256 maxBorrow = collateralValue.mulDivDown(marketParams.lltv, 1e18);

        uint256 borrowed = position[id][borrower].borrowShares.toAssetsUp(
            market[id].totalBorrowAssets,
            market[id].totalBorrowShares
        );

        return borrowed <= maxBorrow;
    }

    function _liquidationIncentiveFactor(uint256 lltv) internal pure returns (uint256) {
        return MathLib.min(MAX_LIQUIDATION_INCENTIVE_FACTOR, 1e18 + (1e18 - lltv) / 2);
    }

    /* VIEW */

    function totalSupplyAssets(Id id) external view returns (uint256) {
        return market[id].totalSupplyAssets;
    }

    function totalBorrowAssets(Id id) external view returns (uint256) {
        return market[id].totalBorrowAssets;
    }

    function supplyShares(Id id, address user) external view returns (uint256) {
        return position[id][user].supplyShares;
    }

    function borrowShares(Id id, address user) external view returns (uint256) {
        return position[id][user].borrowShares;
    }

    function collateral(Id id, address user) external view returns (uint256) {
        return position[id][user].collateral;
    }
}
