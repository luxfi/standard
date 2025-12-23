// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/// @title Perp
/// @notice Lux perpetual trading interface - simplified wrapper for perpetual trading
/// @dev Wraps GMX-style perpetuals with Lux-branded interface
contract Perp is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // ═══════════════════════════════════════════════════════════════════════
    // TYPES
    // ═══════════════════════════════════════════════════════════════════════

    struct Position {
        uint256 size;           // Position size in USD (30 decimals)
        uint256 collateral;     // Collateral amount in USD (30 decimals)
        uint256 averagePrice;   // Average entry price
        uint256 entryFunding;   // Funding rate at entry
        uint256 reserveAmount;  // Reserved collateral
        int256 realisedPnl;     // Realized PnL
        uint256 lastUpdated;    // Last update timestamp
    }

    struct Market {
        address indexToken;     // The token to trade (e.g., WBTC, WETH)
        address collateralToken; // Collateral token (e.g., USDC)
        bool isLong;            // Long or short
        uint256 maxLeverage;    // Maximum leverage (e.g., 50x = 50e30)
        uint256 fundingRate;    // Current funding rate
        bool isActive;          // Market active flag
    }

    // ═══════════════════════════════════════════════════════════════════════
    // CONSTANTS
    // ═══════════════════════════════════════════════════════════════════════

    uint256 public constant PRICE_PRECISION = 1e30;
    uint256 public constant BASIS_POINTS = 10000;
    uint256 public constant MAX_FEE_BASIS_POINTS = 500; // 5%
    
    // ═══════════════════════════════════════════════════════════════════════
    // STATE
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice Core vault for collateral management
    address public vault;

    /// @notice Price feed for market prices
    address public priceFeed;

    /// @notice Fee receiver
    address public feeReceiver;

    /// @notice Position fee in basis points (0.1% = 10)
    uint256 public positionFee = 10;

    /// @notice Liquidation fee in basis points
    uint256 public liquidationFee = 50;

    /// @notice Minimum collateral in USD
    uint256 public minCollateral = 10e30; // $10

    /// @notice Market configurations
    mapping(bytes32 => Market) public markets;

    /// @notice User positions: user => market key => position
    mapping(address => mapping(bytes32 => Position)) public positions;

    /// @notice Global long/short positions per market
    mapping(bytes32 => uint256) public globalLongSizes;
    mapping(bytes32 => uint256) public globalShortSizes;

    // ═══════════════════════════════════════════════════════════════════════
    // EVENTS
    // ═══════════════════════════════════════════════════════════════════════

    event MarketAdded(bytes32 indexed key, address indexToken, address collateralToken, bool isLong);
    event PositionOpened(address indexed user, bytes32 indexed market, uint256 size, uint256 collateral, bool isLong);
    event PositionClosed(address indexed user, bytes32 indexed market, uint256 size, int256 pnl);
    event PositionLiquidated(address indexed user, bytes32 indexed market, address liquidator, uint256 size);
    event CollateralAdded(address indexed user, bytes32 indexed market, uint256 amount);
    event CollateralRemoved(address indexed user, bytes32 indexed market, uint256 amount);

    // ═══════════════════════════════════════════════════════════════════════
    // ERRORS
    // ═══════════════════════════════════════════════════════════════════════

    error MarketNotActive();
    error InsufficientCollateral();
    error ExceedsMaxLeverage();
    error PositionNotFound();
    error NotLiquidatable();
    error ZeroAmount();
    error InvalidMarket();

    // ═══════════════════════════════════════════════════════════════════════
    // CONSTRUCTOR
    // ═══════════════════════════════════════════════════════════════════════

    constructor(
        address _vault,
        address _priceFeed,
        address _feeReceiver
    ) Ownable(msg.sender) {
        vault = _vault;
        priceFeed = _priceFeed;
        feeReceiver = _feeReceiver;
    }

    // ═══════════════════════════════════════════════════════════════════════
    // TRADING FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice Open a new perpetual position
    /// @param indexToken Token to trade
    /// @param collateralToken Collateral token
    /// @param collateralAmount Amount of collateral
    /// @param sizeDelta Position size increase
    /// @param isLong Long or short
    function open(
        address indexToken,
        address collateralToken,
        uint256 collateralAmount,
        uint256 sizeDelta,
        bool isLong
    ) external nonReentrant {
        bytes32 key = getMarketKey(indexToken, collateralToken, isLong);
        Market storage market = markets[key];
        
        if (!market.isActive) revert MarketNotActive();
        if (collateralAmount == 0 || sizeDelta == 0) revert ZeroAmount();

        // Transfer collateral
        IERC20(collateralToken).safeTransferFrom(msg.sender, address(this), collateralAmount);

        // Calculate collateral in USD
        uint256 collateralUsd = _tokenToUsd(collateralToken, collateralAmount);
        if (collateralUsd < minCollateral) revert InsufficientCollateral();

        // Check leverage
        uint256 leverage = sizeDelta * PRICE_PRECISION / collateralUsd;
        if (leverage > market.maxLeverage) revert ExceedsMaxLeverage();

        // Get or create position
        Position storage position = positions[msg.sender][key];
        
        // Calculate fees
        uint256 fee = sizeDelta * positionFee / BASIS_POINTS;

        // Update position
        uint256 price = _getPrice(indexToken, isLong);
        
        if (position.size == 0) {
            // New position
            position.averagePrice = price;
            position.entryFunding = market.fundingRate;
        } else {
            // Increase position - weighted average price
            position.averagePrice = (position.size * position.averagePrice + sizeDelta * price) / (position.size + sizeDelta);
        }

        position.size += sizeDelta;
        position.collateral += collateralUsd - fee;
        position.lastUpdated = block.timestamp;

        // Update global positions
        if (isLong) {
            globalLongSizes[key] += sizeDelta;
        } else {
            globalShortSizes[key] += sizeDelta;
        }

        emit PositionOpened(msg.sender, key, sizeDelta, collateralAmount, isLong);
    }

    /// @notice Close a perpetual position
    /// @param indexToken Token traded
    /// @param collateralToken Collateral token
    /// @param sizeDelta Position size to close
    /// @param isLong Long or short
    function close(
        address indexToken,
        address collateralToken,
        uint256 sizeDelta,
        bool isLong
    ) external nonReentrant {
        bytes32 key = getMarketKey(indexToken, collateralToken, isLong);
        Position storage position = positions[msg.sender][key];
        
        if (position.size == 0) revert PositionNotFound();
        if (sizeDelta > position.size) sizeDelta = position.size;

        // Calculate PnL
        uint256 currentPrice = _getPrice(indexToken, isLong);
        int256 pnl = _calculatePnL(position, currentPrice, sizeDelta, isLong);

        // Calculate proportional collateral
        uint256 collateralDelta = position.collateral * sizeDelta / position.size;

        // Calculate fees
        uint256 fee = sizeDelta * positionFee / BASIS_POINTS;

        // Update position
        position.size -= sizeDelta;
        position.collateral -= collateralDelta;
        position.realisedPnl += pnl;
        position.lastUpdated = block.timestamp;

        // Update global positions
        if (isLong) {
            globalLongSizes[key] -= sizeDelta;
        } else {
            globalShortSizes[key] -= sizeDelta;
        }

        // Calculate payout
        int256 payout = int256(collateralDelta) + pnl - int256(fee);
        
        if (payout > 0) {
            // Convert USD to tokens and transfer
            uint256 payoutTokens = _usdToToken(collateralToken, uint256(payout));
            IERC20(collateralToken).safeTransfer(msg.sender, payoutTokens);
        }

        emit PositionClosed(msg.sender, key, sizeDelta, pnl);
    }

    /// @notice Liquidate an underwater position
    /// @param user Position owner
    /// @param indexToken Token traded
    /// @param collateralToken Collateral token
    /// @param isLong Long or short
    function liquidate(
        address user,
        address indexToken,
        address collateralToken,
        bool isLong
    ) external nonReentrant {
        bytes32 key = getMarketKey(indexToken, collateralToken, isLong);
        Position storage position = positions[user][key];
        
        if (position.size == 0) revert PositionNotFound();

        // Check if liquidatable
        uint256 currentPrice = _getPrice(indexToken, isLong);
        int256 pnl = _calculatePnL(position, currentPrice, position.size, isLong);
        
        // Position is liquidatable if collateral + PnL < maintenance margin (5%)
        int256 remainingCollateral = int256(position.collateral) + pnl;
        uint256 maintenanceMargin = position.size * 500 / BASIS_POINTS; // 5%
        
        if (remainingCollateral >= int256(maintenanceMargin)) revert NotLiquidatable();

        // Calculate liquidation fee
        uint256 fee = position.size * liquidationFee / BASIS_POINTS;
        
        // Update global positions
        if (isLong) {
            globalLongSizes[key] -= position.size;
        } else {
            globalShortSizes[key] -= position.size;
        }

        uint256 positionSize = position.size;

        // Clear position
        delete positions[user][key];

        // Pay liquidator fee
        if (remainingCollateral > 0) {
            uint256 liquidatorReward = _usdToToken(collateralToken, fee);
            IERC20(collateralToken).safeTransfer(msg.sender, liquidatorReward);
        }

        emit PositionLiquidated(user, key, msg.sender, positionSize);
    }

    /// @notice Add collateral to existing position
    function addCollateral(
        address indexToken,
        address collateralToken,
        uint256 amount,
        bool isLong
    ) external nonReentrant {
        bytes32 key = getMarketKey(indexToken, collateralToken, isLong);
        Position storage position = positions[msg.sender][key];
        
        if (position.size == 0) revert PositionNotFound();
        if (amount == 0) revert ZeroAmount();

        IERC20(collateralToken).safeTransferFrom(msg.sender, address(this), amount);
        
        uint256 collateralUsd = _tokenToUsd(collateralToken, amount);
        position.collateral += collateralUsd;
        position.lastUpdated = block.timestamp;

        emit CollateralAdded(msg.sender, key, amount);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // VIEW FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice Get position details
    function getPosition(
        address user,
        address indexToken,
        address collateralToken,
        bool isLong
    ) external view returns (Position memory) {
        bytes32 key = getMarketKey(indexToken, collateralToken, isLong);
        return positions[user][key];
    }

    /// @notice Calculate current PnL for a position
    function getPositionPnL(
        address user,
        address indexToken,
        address collateralToken,
        bool isLong
    ) external view returns (int256 pnl, uint256 leverage) {
        bytes32 key = getMarketKey(indexToken, collateralToken, isLong);
        Position storage position = positions[user][key];
        
        if (position.size == 0) return (0, 0);

        uint256 currentPrice = _getPrice(indexToken, isLong);
        pnl = _calculatePnL(position, currentPrice, position.size, isLong);
        
        int256 effectiveCollateral = int256(position.collateral) + pnl;
        if (effectiveCollateral > 0) {
            leverage = position.size * PRICE_PRECISION / uint256(effectiveCollateral);
        }
    }

    /// @notice Get market key from parameters
    function getMarketKey(
        address indexToken,
        address collateralToken,
        bool isLong
    ) public pure returns (bytes32) {
        return keccak256(abi.encodePacked(indexToken, collateralToken, isLong));
    }

    // ═══════════════════════════════════════════════════════════════════════
    // ADMIN FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice Add a new trading market
    function addMarket(
        address indexToken,
        address collateralToken,
        bool isLong,
        uint256 maxLeverage
    ) external onlyOwner {
        bytes32 key = getMarketKey(indexToken, collateralToken, isLong);
        markets[key] = Market({
            indexToken: indexToken,
            collateralToken: collateralToken,
            isLong: isLong,
            maxLeverage: maxLeverage,
            fundingRate: 0,
            isActive: true
        });

        emit MarketAdded(key, indexToken, collateralToken, isLong);
    }

    /// @notice Set market active status
    function setMarketActive(bytes32 key, bool active) external onlyOwner {
        markets[key].isActive = active;
    }

    /// @notice Update fees
    function setFees(uint256 _positionFee, uint256 _liquidationFee) external onlyOwner {
        require(_positionFee <= MAX_FEE_BASIS_POINTS, "Fee too high");
        require(_liquidationFee <= MAX_FEE_BASIS_POINTS, "Fee too high");
        positionFee = _positionFee;
        liquidationFee = _liquidationFee;
    }

    // ═══════════════════════════════════════════════════════════════════════
    // INTERNAL FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════

    function _getPrice(address token, bool maximize) internal view returns (uint256) {
        // TODO: Integrate with price feed
        // For now, return mock price
        return 1e30; // $1 placeholder
    }

    function _tokenToUsd(address token, uint256 amount) internal view returns (uint256) {
        uint256 price = _getPrice(token, false);
        // Assume 18 decimals for simplicity
        return amount * price / 1e18;
    }

    function _usdToToken(address token, uint256 usdAmount) internal view returns (uint256) {
        uint256 price = _getPrice(token, true);
        return usdAmount * 1e18 / price;
    }

    function _calculatePnL(
        Position storage position,
        uint256 currentPrice,
        uint256 sizeDelta,
        bool isLong
    ) internal view returns (int256) {
        if (position.averagePrice == 0) return 0;

        int256 priceDelta = int256(currentPrice) - int256(position.averagePrice);
        
        if (!isLong) {
            priceDelta = -priceDelta;
        }

        return int256(sizeDelta) * priceDelta / int256(position.averagePrice);
    }
}
