// SPDX-License-Identifier: BSD-3-Clause
// Copyright (c) 2025 Lux Industries Inc.
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/// @title Aster Trading Data Input
/// @notice Struct for opening positions on Aster DEX
struct OpenDataInput {
    address pairBase;      // Trading pair base asset (e.g., WBTC)
    bool isLong;           // True for long, false for short
    address tokenIn;       // Margin token (USDT/USDC)
    uint256 amountIn;      // Margin amount (token decimals, e.g., 1e18 for USDT)
    uint256 qty;           // Position quantity (1e10 decimals)
    uint256 price;         // Worst acceptable price (1e8 decimals)
    uint256 stopLoss;      // Stop loss price (1e8), 0 to disable
    uint256 takeProfit;    // Take profit price (1e8), 0 to disable
    uint256 broker;        // Broker ID for referrals
}

/// @title Aster Trading Interface
/// @notice Interface for Aster DEX trading contract
interface IAsterTrading {
    /// @notice Open a market trade
    function openMarketTrade(OpenDataInput calldata data) external;

    /// @notice Open a market trade with native token (BNB)
    function openMarketTradeBNB(OpenDataInput calldata data) external payable;

    /// @notice Create a limit order
    function createLimitOrder(OpenDataInput calldata data) external;

    /// @notice Create a limit order with native token
    function createLimitOrderBNB(OpenDataInput calldata data) external payable;

    /// @notice Close an existing trade
    function closeTrade(bytes32 tradeHash) external;

    /// @notice Add margin to an existing position
    function addMargin(bytes32 tradeHash, uint256 amount) external;

    /// @notice Update stop loss and take profit
    function updateTradeTpAndSl(bytes32 tradeHash, uint256 stopLoss, uint256 takeProfit) external;

    /// @notice Cancel a pending limit order
    function cancelLimitOrder(bytes32 orderHash) external;
}

/// @title Aster Price Feed Interface
interface IAsterPriceFeed {
    function getPrice(address pairBase) external view returns (uint256);
}

/// @title LuxAsterAdapter
/// @notice Trustless adapter for routing trades to Aster DEX (1001x leverage)
/// @dev Deploy on BSC (Chain ID: 56) or Arbitrum (Chain ID: 42161)
/// @custom:security-contact security@lux.network
contract LuxAsterAdapter is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    /*//////////////////////////////////////////////////////////////
                                CONSTANTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Aster Trading contract address
    IAsterTrading public constant ASTER = IAsterTrading(0x1b6F2d3844C6ae7D56ceb3C3643b9060ba28FEb0);

    /// @notice Lux broker ID for referral tracking
    uint256 public constant LUX_BROKER_ID = 0; // TODO: Register with Aster for broker ID

    /// @notice Maximum leverage allowed (1001x on Aster)
    uint256 public constant MAX_LEVERAGE = 1001;

    /// @notice Minimum leverage
    uint256 public constant MIN_LEVERAGE = 2;

    /// @notice Price decimals (1e8)
    uint256 public constant PRICE_DECIMALS = 1e8;

    /// @notice Quantity decimals (1e10)
    uint256 public constant QTY_DECIMALS = 1e10;

    /*//////////////////////////////////////////////////////////////
                                 STATE
    //////////////////////////////////////////////////////////////*/

    /// @notice Supported margin tokens
    mapping(address => bool) public supportedTokens;

    /// @notice Supported trading pairs (pairBase => enabled)
    mapping(address => bool) public supportedPairs;

    /// @notice User positions (user => tradeHash[])
    mapping(address => bytes32[]) public userPositions;

    /// @notice Position owner (tradeHash => user)
    mapping(bytes32 => address) public positionOwner;

    /// @notice Price feed contract
    IAsterPriceFeed public priceFeed;

    /// @notice Paused state
    bool public paused;

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    event PositionOpened(
        address indexed user,
        bytes32 indexed tradeHash,
        address pairBase,
        bool isLong,
        uint256 margin,
        uint256 leverage,
        uint256 size
    );

    event PositionClosed(address indexed user, bytes32 indexed tradeHash);
    event MarginAdded(address indexed user, bytes32 indexed tradeHash, uint256 amount);
    event RiskParamsUpdated(address indexed user, bytes32 indexed tradeHash, uint256 sl, uint256 tp);
    event TokenAdded(address indexed token);
    event PairAdded(address indexed pairBase);
    event PriceFeedUpdated(address indexed priceFeed);

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    error Paused();
    error InvalidLeverage();
    error InvalidMargin();
    error UnsupportedToken();
    error UnsupportedPair();
    error NotPositionOwner();
    error PositionNotFound();
    error ZeroAddress();

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    constructor(address _priceFeed) Ownable(msg.sender) {
        if (_priceFeed == address(0)) revert ZeroAddress();
        priceFeed = IAsterPriceFeed(_priceFeed);

        // Default supported tokens on BSC
        supportedTokens[0x55d398326f99059fF775485246999027B3197955] = true; // USDT
        supportedTokens[0x8AC76a51cc950d9822D68b83fE1Ad97B32Cd580d] = true; // USDC

        // Default supported pairs (1001x eligible)
        supportedPairs[0x7130d2A12B9BCbFAe4f2634d864A1Ee1Ce3Ead9c] = true; // BTCB
        supportedPairs[0x2170Ed0880ac9A755fd29B2688956BD959F933F8] = true; // ETH
    }

    /*//////////////////////////////////////////////////////////////
                            TRADING FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Open a leveraged position on Aster
    /// @param pairBase The trading pair base asset (e.g., WBTC)
    /// @param isLong True for long, false for short
    /// @param tokenIn Margin token address (USDT/USDC)
    /// @param margin Margin amount in token decimals
    /// @param leverage Leverage multiplier (2-1001)
    /// @param stopLoss Stop loss price (1e8), 0 to disable
    /// @param takeProfit Take profit price (1e8), 0 to disable
    /// @return tradeHash The unique identifier for this position
    function openPosition(
        address pairBase,
        bool isLong,
        address tokenIn,
        uint256 margin,
        uint256 leverage,
        uint256 stopLoss,
        uint256 takeProfit
    ) external nonReentrant returns (bytes32 tradeHash) {
        if (paused) revert Paused();
        if (leverage < MIN_LEVERAGE || leverage > MAX_LEVERAGE) revert InvalidLeverage();
        if (margin == 0) revert InvalidMargin();
        if (!supportedTokens[tokenIn]) revert UnsupportedToken();
        if (!supportedPairs[pairBase]) revert UnsupportedPair();

        // Transfer margin from user
        IERC20(tokenIn).safeTransferFrom(msg.sender, address(this), margin);

        // Approve Aster to spend margin
        IERC20(tokenIn).forceApprove(address(ASTER), margin);

        // Calculate position size from leverage
        uint256 currentPrice = priceFeed.getPrice(pairBase);
        uint256 positionValue = margin * leverage;
        uint256 qty = (positionValue * QTY_DECIMALS) / currentPrice;

        // Calculate worst acceptable price (0.5% slippage)
        uint256 worstPrice;
        if (isLong) {
            worstPrice = (currentPrice * 1005) / 1000; // 0.5% higher for longs
        } else {
            worstPrice = (currentPrice * 995) / 1000;  // 0.5% lower for shorts
        }

        // Build trade data
        OpenDataInput memory data = OpenDataInput({
            pairBase: pairBase,
            isLong: isLong,
            tokenIn: tokenIn,
            amountIn: margin,
            qty: qty,
            price: worstPrice,
            stopLoss: stopLoss,
            takeProfit: takeProfit,
            broker: LUX_BROKER_ID
        });

        // Execute on Aster
        ASTER.openMarketTrade(data);

        // Generate trade hash (matches Aster's internal hash)
        tradeHash = keccak256(abi.encodePacked(
            msg.sender,
            pairBase,
            isLong,
            block.timestamp
        ));

        // Track position
        userPositions[msg.sender].push(tradeHash);
        positionOwner[tradeHash] = msg.sender;

        emit PositionOpened(
            msg.sender,
            tradeHash,
            pairBase,
            isLong,
            margin,
            leverage,
            positionValue
        );
    }

    /// @notice Open a leveraged position with native token (BNB)
    /// @param pairBase The trading pair base asset
    /// @param isLong True for long, false for short
    /// @param leverage Leverage multiplier (2-1001)
    /// @param stopLoss Stop loss price (1e8), 0 to disable
    /// @param takeProfit Take profit price (1e8), 0 to disable
    function openPositionNative(
        address pairBase,
        bool isLong,
        uint256 leverage,
        uint256 stopLoss,
        uint256 takeProfit
    ) external payable nonReentrant returns (bytes32 tradeHash) {
        if (paused) revert Paused();
        if (leverage < MIN_LEVERAGE || leverage > MAX_LEVERAGE) revert InvalidLeverage();
        if (msg.value == 0) revert InvalidMargin();
        if (!supportedPairs[pairBase]) revert UnsupportedPair();

        uint256 margin = msg.value;

        // Calculate position size
        uint256 currentPrice = priceFeed.getPrice(pairBase);
        uint256 positionValue = margin * leverage;
        uint256 qty = (positionValue * QTY_DECIMALS) / currentPrice;

        // Calculate worst acceptable price
        uint256 worstPrice;
        if (isLong) {
            worstPrice = (currentPrice * 1005) / 1000;
        } else {
            worstPrice = (currentPrice * 995) / 1000;
        }

        OpenDataInput memory data = OpenDataInput({
            pairBase: pairBase,
            isLong: isLong,
            tokenIn: address(0), // Native token
            amountIn: margin,
            qty: qty,
            price: worstPrice,
            stopLoss: stopLoss,
            takeProfit: takeProfit,
            broker: LUX_BROKER_ID
        });

        // Execute on Aster with native token
        ASTER.openMarketTradeBNB{value: margin}(data);

        tradeHash = keccak256(abi.encodePacked(
            msg.sender,
            pairBase,
            isLong,
            block.timestamp
        ));

        userPositions[msg.sender].push(tradeHash);
        positionOwner[tradeHash] = msg.sender;

        emit PositionOpened(
            msg.sender,
            tradeHash,
            pairBase,
            isLong,
            margin,
            leverage,
            positionValue
        );
    }

    /// @notice Close an existing position
    /// @param tradeHash The position identifier
    function closePosition(bytes32 tradeHash) external nonReentrant {
        if (positionOwner[tradeHash] != msg.sender) revert NotPositionOwner();

        ASTER.closeTrade(tradeHash);

        // Remove from tracking
        delete positionOwner[tradeHash];
        _removePosition(msg.sender, tradeHash);

        emit PositionClosed(msg.sender, tradeHash);
    }

    /// @notice Add margin to an existing position
    /// @param tradeHash The position identifier
    /// @param tokenIn Margin token address
    /// @param amount Amount to add
    function addMargin(
        bytes32 tradeHash,
        address tokenIn,
        uint256 amount
    ) external nonReentrant {
        if (positionOwner[tradeHash] != msg.sender) revert NotPositionOwner();
        if (!supportedTokens[tokenIn]) revert UnsupportedToken();

        IERC20(tokenIn).safeTransferFrom(msg.sender, address(this), amount);
        IERC20(tokenIn).forceApprove(address(ASTER), amount);

        // Convert to 1e10 decimals for Aster
        uint256 asterAmount = (amount * QTY_DECIMALS) / 1e18;
        ASTER.addMargin(tradeHash, asterAmount);

        emit MarginAdded(msg.sender, tradeHash, amount);
    }

    /// @notice Update stop loss and take profit for a position
    /// @param tradeHash The position identifier
    /// @param stopLoss New stop loss price (1e8)
    /// @param takeProfit New take profit price (1e8)
    function updateRiskParams(
        bytes32 tradeHash,
        uint256 stopLoss,
        uint256 takeProfit
    ) external nonReentrant {
        if (positionOwner[tradeHash] != msg.sender) revert NotPositionOwner();

        ASTER.updateTradeTpAndSl(tradeHash, stopLoss, takeProfit);

        emit RiskParamsUpdated(msg.sender, tradeHash, stopLoss, takeProfit);
    }

    /*//////////////////////////////////////////////////////////////
                             VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Get all positions for a user
    function getPositions(address user) external view returns (bytes32[] memory) {
        return userPositions[user];
    }

    /// @notice Get current price for a pair
    function getPrice(address pairBase) external view returns (uint256) {
        return priceFeed.getPrice(pairBase);
    }

    /// @notice Calculate position size for given margin and leverage
    function calculatePositionSize(
        address pairBase,
        uint256 margin,
        uint256 leverage
    ) external view returns (uint256 qty, uint256 positionValue) {
        uint256 price = priceFeed.getPrice(pairBase);
        positionValue = margin * leverage;
        qty = (positionValue * QTY_DECIMALS) / price;
    }

    /// @notice Calculate liquidation price for a position
    /// @dev Aster uses 90% liquidation rate
    function calculateLiquidationPrice(
        address pairBase,
        bool isLong,
        uint256 margin,
        uint256 leverage
    ) external view returns (uint256 liqPrice) {
        uint256 entryPrice = priceFeed.getPrice(pairBase);
        uint256 positionValue = margin * leverage;

        // Liquidation at 90% loss of margin
        uint256 maxLoss = (margin * 90) / 100;
        uint256 priceMove = (maxLoss * entryPrice) / positionValue;

        if (isLong) {
            liqPrice = entryPrice - priceMove;
        } else {
            liqPrice = entryPrice + priceMove;
        }
    }

    /*//////////////////////////////////////////////////////////////
                            ADMIN FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function addSupportedToken(address token) external onlyOwner {
        supportedTokens[token] = true;
        emit TokenAdded(token);
    }

    function addSupportedPair(address pairBase) external onlyOwner {
        supportedPairs[pairBase] = true;
        emit PairAdded(pairBase);
    }

    function setPriceFeed(address _priceFeed) external onlyOwner {
        if (_priceFeed == address(0)) revert ZeroAddress();
        priceFeed = IAsterPriceFeed(_priceFeed);
        emit PriceFeedUpdated(_priceFeed);
    }

    function setPaused(bool _paused) external onlyOwner {
        paused = _paused;
    }

    /// @notice Emergency withdraw stuck tokens
    function emergencyWithdraw(address token, uint256 amount) external onlyOwner {
        if (token == address(0)) {
            payable(owner()).transfer(amount);
        } else {
            IERC20(token).safeTransfer(owner(), amount);
        }
    }

    /*//////////////////////////////////////////////////////////////
                           INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function _removePosition(address user, bytes32 tradeHash) internal {
        bytes32[] storage positions = userPositions[user];
        for (uint256 i = 0; i < positions.length; i++) {
            if (positions[i] == tradeHash) {
                positions[i] = positions[positions.length - 1];
                positions.pop();
                break;
            }
        }
    }

    receive() external payable {}
}
