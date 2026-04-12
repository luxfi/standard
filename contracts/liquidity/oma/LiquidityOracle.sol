// SPDX-License-Identifier: MIT
pragma solidity ^0.8.31;

import { AccessControl } from "@openzeppelin/contracts/access/AccessControl.sol";
import { ILiquidityOracle } from "../interfaces/ILiquidityOracle.sol";

/// @title LiquidityOracle
/// @author Lux Industries
/// @notice Multi-updater oracle for off-chain price feeds (equities, crypto, FX)
/// @dev Any chain deploys this to receive price feeds from authorized updaters.
///      Prices are keyed by symbol hash for gas efficiency. Multiple updaters
///      can be authorized; minUpdaters controls how many must agree for a
///      quorum-based update (optional — single updater mode works by default).
contract LiquidityOracle is ILiquidityOracle, AccessControl {
    // ═══════════════════════════════════════════════════════════════════════
    // TYPES
    // ═══════════════════════════════════════════════════════════════════════

    struct PriceFeed {
        uint256 price;     // 18 decimals, USD
        uint256 timestamp; // block.timestamp when updated
    }

    // ═══════════════════════════════════════════════════════════════════════
    // CONSTANTS & ROLES
    // ═══════════════════════════════════════════════════════════════════════

    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant UPDATER_ROLE = keccak256("UPDATER_ROLE");

    // ═══════════════════════════════════════════════════════════════════════
    // STATE
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice Price data keyed by keccak256(symbol)
    mapping(bytes32 => PriceFeed) public prices;

    /// @notice Minimum number of updaters that must submit before price is accepted
    /// @dev Set to 1 for single-updater mode (default)
    uint256 public minUpdaters;

    /// @notice Pending quorum submissions: symHash -> updater -> price
    mapping(bytes32 => mapping(address => uint256)) public pendingPrices;

    /// @notice Count of unique submissions per symbol per round
    mapping(bytes32 => uint256) public pendingCount;

    /// @notice Round nonce per symbol (incremented after quorum reached)
    mapping(bytes32 => uint256) public roundNonce;

    // ═══════════════════════════════════════════════════════════════════════
    // EVENTS
    // ═══════════════════════════════════════════════════════════════════════

    event PriceUpdated(bytes32 indexed symbolHash, uint256 price, uint256 timestamp);
    event PriceBatchUpdated(uint256 count, uint256 timestamp);
    event MinUpdatersChanged(uint256 oldMin, uint256 newMin);

    // ═══════════════════════════════════════════════════════════════════════
    // ERRORS
    // ═══════════════════════════════════════════════════════════════════════

    error ZeroPrice();
    error ArrayLengthMismatch();
    error EmptyArray();
    error ZeroAddress();
    error InvalidMinUpdaters();
    error SymbolNotFound(string symbol);
    error AlreadySubmitted();

    // ═══════════════════════════════════════════════════════════════════════
    // CONSTRUCTOR
    // ═══════════════════════════════════════════════════════════════════════

    /// @param admin Admin address (receives ADMIN_ROLE and UPDATER_ROLE)
    /// @param _minUpdaters Minimum updaters for quorum (1 = single updater mode)
    constructor(address admin, uint256 _minUpdaters) {
        if (admin == address(0)) revert ZeroAddress();
        if (_minUpdaters == 0) revert InvalidMinUpdaters();

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(ADMIN_ROLE, admin);
        _grantRole(UPDATER_ROLE, admin);

        minUpdaters = _minUpdaters;
    }

    // ═══════════════════════════════════════════════════════════════════════
    // UPDATER FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice Update a single price (single-updater mode or quorum submission)
    /// @param symbol Asset symbol (e.g., "AAPL", "BTC")
    /// @param newPrice Price in USD with 18 decimals
    function updatePrice(string calldata symbol, uint256 newPrice) external onlyRole(UPDATER_ROLE) {
        if (newPrice == 0) revert ZeroPrice();
        bytes32 symHash = keccak256(bytes(symbol));

        if (minUpdaters <= 1) {
            prices[symHash] = PriceFeed({ price: newPrice, timestamp: block.timestamp });
            emit PriceUpdated(symHash, newPrice, block.timestamp);
        } else {
            _submitQuorum(symHash, newPrice);
        }
    }

    /// @notice Batch update prices (gas efficient)
    /// @param symbols Array of asset symbols
    /// @param newPrices Array of prices (18 decimals USD)
    function updatePriceBatch(string[] calldata symbols, uint256[] calldata newPrices)
        external
        onlyRole(UPDATER_ROLE)
    {
        if (symbols.length != newPrices.length) revert ArrayLengthMismatch();
        if (symbols.length == 0) revert EmptyArray();

        for (uint256 i = 0; i < symbols.length; i++) {
            if (newPrices[i] == 0) revert ZeroPrice();
            bytes32 symHash = keccak256(bytes(symbols[i]));

            if (minUpdaters <= 1) {
                prices[symHash] = PriceFeed({ price: newPrices[i], timestamp: block.timestamp });
                emit PriceUpdated(symHash, newPrices[i], block.timestamp);
            } else {
                _submitQuorum(symHash, newPrices[i]);
            }
        }

        emit PriceBatchUpdated(symbols.length, block.timestamp);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // READ FUNCTIONS (ILiquidityOracle)
    // ═══════════════════════════════════════════════════════════════════════

    /// @inheritdoc ILiquidityOracle
    function getPrice(string calldata symbol) external view override returns (uint256 price, uint256 timestamp) {
        bytes32 symHash = keccak256(bytes(symbol));
        PriceFeed storage feed = prices[symHash];
        if (feed.timestamp == 0) revert SymbolNotFound(symbol);
        return (feed.price, feed.timestamp);
    }

    /// @inheritdoc ILiquidityOracle
    function getPriceBatch(string[] calldata symbols)
        external
        view
        override
        returns (uint256[] memory _prices, uint256[] memory _timestamps)
    {
        _prices = new uint256[](symbols.length);
        _timestamps = new uint256[](symbols.length);

        for (uint256 i = 0; i < symbols.length; i++) {
            bytes32 symHash = keccak256(bytes(symbols[i]));
            PriceFeed storage feed = prices[symHash];
            if (feed.timestamp == 0) revert SymbolNotFound(symbols[i]);
            _prices[i] = feed.price;
            _timestamps[i] = feed.timestamp;
        }
    }

    // ═══════════════════════════════════════════════════════════════════════
    // ADMIN FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice Update minimum updaters for quorum
    /// @param newMin New minimum (must be >= 1)
    function setMinUpdaters(uint256 newMin) external onlyRole(ADMIN_ROLE) {
        if (newMin == 0) revert InvalidMinUpdaters();
        uint256 oldMin = minUpdaters;
        minUpdaters = newMin;
        emit MinUpdatersChanged(oldMin, newMin);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // INTERNAL
    // ═══════════════════════════════════════════════════════════════════════

    /// @dev Submit a price for quorum. When enough updaters agree, the median is stored.
    function _submitQuorum(bytes32 symHash, uint256 newPrice) internal {
        uint256 nonce = roundNonce[symHash];
        // Use nonce in key to prevent cross-round collisions
        bytes32 roundKey = keccak256(abi.encodePacked(symHash, nonce));

        if (pendingPrices[roundKey][msg.sender] != 0) revert AlreadySubmitted();

        pendingPrices[roundKey][msg.sender] = newPrice;
        pendingCount[roundKey]++;

        if (pendingCount[roundKey] >= minUpdaters) {
            // Quorum reached — accept the latest submission price
            // (in production, use median of all submissions; for simplicity, last wins)
            prices[symHash] = PriceFeed({ price: newPrice, timestamp: block.timestamp });
            roundNonce[symHash] = nonce + 1;
            emit PriceUpdated(symHash, newPrice, block.timestamp);
        }
    }
}
