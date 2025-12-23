// SPDX-License-Identifier: BSD-3-Clause
// Copyright (c) 2025 Lux Industries Inc.

pragma solidity ^0.8.28;

/// @title Position Parameters
/// @notice Common position parameters for perpetual markets
struct OpenPositionParams {
    address market;           // Market/pair address or identifier
    address collateralToken;  // Collateral asset (USDC, USDT, ETH, etc.)
    uint256 collateralAmount; // Amount of collateral
    uint256 sizeDelta;        // Position size delta (notional)
    bool isLong;              // True for long, false for short
    uint256 acceptablePrice;  // Worst acceptable execution price (slippage protection)
    uint256 leverage;         // Leverage multiplier (1e18 = 1x)
    bytes referralCode;       // Optional referral/broker code
}

/// @title Close Position Parameters  
struct ClosePositionParams {
    bytes32 positionId;       // Position identifier
    uint256 sizeDelta;        // Size to close (0 = full close)
    uint256 acceptablePrice;  // Worst acceptable execution price
}

/// @title Modify Position Parameters
struct ModifyPositionParams {
    bytes32 positionId;       // Position identifier
    int256 collateralDelta;   // Change in collateral (positive = add, negative = remove)
    int256 sizeDelta;         // Change in size (positive = increase, negative = decrease)
    uint256 acceptablePrice;  // Worst acceptable execution price
}

/// @title Position Info
/// @notice Read-only position data returned by adapters
struct Position {
    bytes32 id;               // Position identifier
    address market;           // Market address
    address collateralToken;  // Collateral asset
    uint256 collateral;       // Current collateral amount
    uint256 size;             // Position size (notional)
    uint256 entryPrice;       // Average entry price
    uint256 leverage;         // Current leverage
    bool isLong;              // Direction
    int256 unrealizedPnL;     // Current unrealized P&L
    uint256 liquidationPrice; // Estimated liquidation price
    uint256 lastUpdated;      // Timestamp of last update
}

/// @title Market Info
/// @notice Market/pair metadata
struct MarketInfo {
    address market;           // Market address or identifier
    address indexToken;       // Index/underlying asset
    address longToken;        // Token for long positions
    address shortToken;       // Token for short positions
    uint256 maxLeverage;      // Maximum allowed leverage
    uint256 minCollateral;    // Minimum collateral requirement
    bool isActive;            // Whether market is accepting trades
    uint256 fundingRate;      // Current funding rate (1e18 = 100%)
    uint256 borrowRate;       // Current borrow rate (1e18 = 100%)
}

/// @title IMarketAdapter
/// @author Lux Industries Inc.
/// @notice Standard interface for perpetual futures market adapters
/// @dev Implement this interface to integrate with GMX, AsterDex, Hyperliquid, etc.
interface IMarketAdapter {
    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    event PositionOpened(
        bytes32 indexed positionId,
        address indexed account,
        address indexed market,
        bool isLong,
        uint256 size,
        uint256 collateral
    );

    event PositionClosed(
        bytes32 indexed positionId,
        address indexed account,
        int256 realizedPnL
    );

    event PositionModified(
        bytes32 indexed positionId,
        int256 collateralDelta,
        int256 sizeDelta
    );

    event PositionLiquidated(
        bytes32 indexed positionId,
        address indexed account,
        address liquidator
    );

    /*//////////////////////////////////////////////////////////////
                              METADATA
    //////////////////////////////////////////////////////////////*/

    /// @notice Returns the adapter version
    /// @return Semantic version string (e.g., "1.0.0")
    function version() external view returns (string memory);

    /// @notice Returns the name of the underlying protocol
    /// @return Protocol name (e.g., "GMX V2", "AsterDex", "Hyperliquid")
    function protocol() external view returns (string memory);

    /// @notice Returns the chain ID this adapter is deployed on
    /// @return Chain ID
    function chainId() external view returns (uint256);

    /// @notice Returns the core router/trading contract address
    /// @return Address of the underlying protocol's main contract
    function router() external view returns (address);

    /*//////////////////////////////////////////////////////////////
                            MARKET INFO
    //////////////////////////////////////////////////////////////*/

    /// @notice Returns list of supported markets
    /// @return Array of market addresses
    function supportedMarkets() external view returns (address[] memory);

    /// @notice Returns detailed market information
    /// @param market Market address
    /// @return MarketInfo struct with market details
    function getMarketInfo(address market) external view returns (MarketInfo memory);

    /// @notice Returns current price for a market
    /// @param market Market address
    /// @return price Current index price (1e30 precision for compatibility)
    function getPrice(address market) external view returns (uint256 price);

    /// @notice Check if a market is supported
    /// @param market Market address to check
    /// @return True if market is supported
    function isMarketSupported(address market) external view returns (bool);

    /*//////////////////////////////////////////////////////////////
                          POSITION MANAGEMENT
    //////////////////////////////////////////////////////////////*/

    /// @notice Open a new perpetual position
    /// @param params Position parameters
    /// @return positionId Unique identifier for the position
    function openPosition(OpenPositionParams calldata params) 
        external 
        payable 
        returns (bytes32 positionId);

    /// @notice Close an existing position
    /// @param params Close parameters
    /// @return realizedPnL Profit/loss from closing
    function closePosition(ClosePositionParams calldata params) 
        external 
        returns (int256 realizedPnL);

    /// @notice Modify an existing position (add/remove collateral or size)
    /// @param params Modification parameters
    function modifyPosition(ModifyPositionParams calldata params) external;

    /// @notice Get position details
    /// @param positionId Position identifier
    /// @return Position struct with current position data
    function getPosition(bytes32 positionId) external view returns (Position memory);

    /// @notice Get all positions for an account
    /// @param account Account address
    /// @return Array of position IDs
    function getPositions(address account) external view returns (bytes32[] memory);

    /// @notice Check if a position can be liquidated
    /// @param positionId Position identifier
    /// @return True if position is liquidatable
    function isLiquidatable(bytes32 positionId) external view returns (bool);

    /*//////////////////////////////////////////////////////////////
                             ESTIMATION
    //////////////////////////////////////////////////////////////*/

    /// @notice Estimate fees for opening a position
    /// @param params Position parameters
    /// @return positionFee Fee for opening (in collateral token)
    /// @return executionFee Network execution fee (in native token)
    function estimateOpenFees(OpenPositionParams calldata params)
        external
        view
        returns (uint256 positionFee, uint256 executionFee);

    /// @notice Estimate fees for closing a position
    /// @param params Close parameters
    /// @return positionFee Fee for closing
    /// @return executionFee Network execution fee
    function estimateCloseFees(ClosePositionParams calldata params)
        external
        view
        returns (uint256 positionFee, uint256 executionFee);

    /// @notice Estimate liquidation price for a potential position
    /// @param market Market address
    /// @param collateral Collateral amount
    /// @param size Position size
    /// @param isLong Position direction
    /// @return Estimated liquidation price
    function estimateLiquidationPrice(
        address market,
        uint256 collateral,
        uint256 size,
        bool isLong
    ) external view returns (uint256);
}
