// SPDX-License-Identifier: MIT
pragma solidity ^0.8.31;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ERC1155} from "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";

/**
 * @title Options
 * @author Lux Industries
 * @notice European-style options protocol with ERC1155 option tokens
 * @dev Supports calls and puts with cash-settled or physical delivery
 *
 * Key features:
 * - European-style options (exercise at expiry only)
 * - ERC1155 option positions (fungible within same strike/expiry)
 * - Collateralized writing with dynamic margin
 * - Cash settlement via oracle price or physical delivery
 * - Support for any ERC20 underlying
 */
contract Options is ERC1155, ReentrancyGuard, AccessControl, Pausable {
    using SafeERC20 for IERC20;

    // ═══════════════════════════════════════════════════════════════════════
    // TYPES
    // ═══════════════════════════════════════════════════════════════════════

    enum OptionType { CALL, PUT }
    enum SettlementType { CASH, PHYSICAL }

    struct OptionSeries {
        address underlying;        // Underlying asset
        address quote;             // Quote asset (collateral for puts, payment for calls)
        uint256 strikePrice;       // Strike price in quote decimals
        uint256 expiry;            // Expiration timestamp
        OptionType optionType;     // CALL or PUT
        SettlementType settlement; // CASH or PHYSICAL
        bool exists;
    }

    struct Position {
        uint256 written;           // Options written (short)
        uint256 collateral;        // Collateral deposited
    }

    // ═══════════════════════════════════════════════════════════════════════
    // CONSTANTS
    // ═══════════════════════════════════════════════════════════════════════

    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant KEEPER_ROLE = keccak256("KEEPER_ROLE");

    uint256 public constant PRECISION = 1e18;
    uint256 public constant BPS = 10000;
    uint256 public constant MIN_EXPIRY_DURATION = 1 hours;
    uint256 public constant MAX_EXPIRY_DURATION = 365 days;

    // ═══════════════════════════════════════════════════════════════════════
    // STATE
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice Oracle for settlement prices
    address public oracle;

    /// @notice Fee receiver
    address public feeReceiver;

    /// @notice Exercise fee in basis points
    uint256 public exerciseFeeBps = 30; // 0.3%

    /// @notice Writing fee in basis points
    uint256 public writeFeeBps = 10; // 0.1%

    /// @notice Collateral ratio for writes (e.g., 10000 = 100%)
    uint256 public collateralRatio = 10000;

    /// @notice Option series by ID
    mapping(uint256 => OptionSeries) public optionSeries;

    /// @notice Writer positions by (seriesId, writer)
    mapping(uint256 => mapping(address => Position)) public positions;

    /// @notice Settlement prices by series ID
    mapping(uint256 => uint256) public settlementPrices;

    /// @notice Whether series is settled
    mapping(uint256 => bool) public isSettled;

    /// @notice Total open interest per series
    mapping(uint256 => uint256) public openInterest;

    /// @notice Next series ID
    uint256 public nextSeriesId = 1;

    /// @notice Underlying token decimals cache
    mapping(address => uint8) public tokenDecimals;

    // ═══════════════════════════════════════════════════════════════════════
    // EVENTS
    // ═══════════════════════════════════════════════════════════════════════

    event SeriesCreated(
        uint256 indexed seriesId,
        address indexed underlying,
        address indexed quote,
        uint256 strikePrice,
        uint256 expiry,
        OptionType optionType,
        SettlementType settlement
    );

    event OptionsWritten(
        uint256 indexed seriesId,
        address indexed writer,
        uint256 amount,
        uint256 collateral
    );

    event OptionsBurned(
        uint256 indexed seriesId,
        address indexed writer,
        uint256 amount,
        uint256 collateralReturned
    );

    event OptionsExercised(
        uint256 indexed seriesId,
        address indexed holder,
        uint256 amount,
        uint256 payout
    );

    event SeriesSettled(
        uint256 indexed seriesId,
        uint256 settlementPrice,
        uint256 timestamp
    );

    event CollateralClaimed(
        uint256 indexed seriesId,
        address indexed writer,
        uint256 amount
    );

    // ═══════════════════════════════════════════════════════════════════════
    // ERRORS
    // ═══════════════════════════════════════════════════════════════════════

    error SeriesNotFound();
    error SeriesExpired();
    error SeriesNotExpired();
    error SeriesAlreadySettled();
    error SeriesNotSettled();
    error InvalidExpiry();
    error InvalidStrike();
    error InsufficientCollateral();
    error InsufficientOptions();
    error ZeroAmount();
    error InvalidOracle();
    error OutOfTheMoney();
    error NoPosition();

    // ═══════════════════════════════════════════════════════════════════════
    // CONSTRUCTOR
    // ═══════════════════════════════════════════════════════════════════════

    constructor(
        address _oracle,
        address _feeReceiver,
        address _admin
    ) ERC1155("") {
        if (_oracle == address(0)) revert InvalidOracle();

        oracle = _oracle;
        feeReceiver = _feeReceiver;

        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        _grantRole(ADMIN_ROLE, _admin);
        _grantRole(KEEPER_ROLE, _admin);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // SERIES MANAGEMENT
    // ═══════════════════════════════════════════════════════════════════════

    /**
     * @notice Create a new option series
     * @param underlying Underlying asset address
     * @param quote Quote asset address (LUSD for most)
     * @param strikePrice Strike price in quote decimals
     * @param expiry Expiration timestamp
     * @param optionType CALL or PUT
     * @param settlement CASH or PHYSICAL
     * @return seriesId New series ID
     */
    function createSeries(
        address underlying,
        address quote,
        uint256 strikePrice,
        uint256 expiry,
        OptionType optionType,
        SettlementType settlement
    ) external onlyRole(ADMIN_ROLE) returns (uint256 seriesId) {
        if (expiry <= block.timestamp + MIN_EXPIRY_DURATION) revert InvalidExpiry();
        if (expiry > block.timestamp + MAX_EXPIRY_DURATION) revert InvalidExpiry();
        if (strikePrice == 0) revert InvalidStrike();

        seriesId = nextSeriesId++;

        optionSeries[seriesId] = OptionSeries({
            underlying: underlying,
            quote: quote,
            strikePrice: strikePrice,
            expiry: expiry,
            optionType: optionType,
            settlement: settlement,
            exists: true
        });

        // Cache decimals
        if (tokenDecimals[underlying] == 0) {
            tokenDecimals[underlying] = _getDecimals(underlying);
        }
        if (tokenDecimals[quote] == 0) {
            tokenDecimals[quote] = _getDecimals(quote);
        }

        emit SeriesCreated(
            seriesId,
            underlying,
            quote,
            strikePrice,
            expiry,
            optionType,
            settlement
        );
    }

    // ═══════════════════════════════════════════════════════════════════════
    // WRITING OPTIONS
    // ═══════════════════════════════════════════════════════════════════════

    /**
     * @notice Write (sell) options with collateral
     * @param seriesId Option series ID
     * @param amount Number of options to write
     * @param recipient Recipient of option tokens
     * @return collateralRequired Collateral locked
     */
    function write(
        uint256 seriesId,
        uint256 amount,
        address recipient
    ) external nonReentrant whenNotPaused returns (uint256 collateralRequired) {
        if (amount == 0) revert ZeroAmount();

        OptionSeries storage series = optionSeries[seriesId];
        if (!series.exists) revert SeriesNotFound();
        if (block.timestamp >= series.expiry) revert SeriesExpired();

        // Calculate collateral requirement
        collateralRequired = _calculateCollateral(seriesId, amount);

        // Transfer collateral
        address collateralToken = series.optionType == OptionType.CALL
            ? series.underlying
            : series.quote;

        IERC20(collateralToken).safeTransferFrom(msg.sender, address(this), collateralRequired);

        // Apply writing fee
        uint256 fee = (collateralRequired * writeFeeBps) / BPS;
        if (fee > 0) {
            IERC20(collateralToken).safeTransfer(feeReceiver, fee);
            collateralRequired -= fee;
        }

        // Update position
        Position storage pos = positions[seriesId][msg.sender];
        pos.written += amount;
        pos.collateral += collateralRequired;

        openInterest[seriesId] += amount;

        // Mint option tokens to recipient
        _mint(recipient, seriesId, amount, "");

        emit OptionsWritten(seriesId, msg.sender, amount, collateralRequired);
    }

    /**
     * @notice Burn options to reduce position
     * @param seriesId Option series ID
     * @param amount Number of options to burn
     */
    function burn(
        uint256 seriesId,
        uint256 amount
    ) external nonReentrant returns (uint256 collateralReturned) {
        if (amount == 0) revert ZeroAmount();

        OptionSeries storage series = optionSeries[seriesId];
        if (!series.exists) revert SeriesNotFound();

        Position storage pos = positions[seriesId][msg.sender];
        if (pos.written < amount) revert InsufficientOptions();

        // Burn option tokens from sender
        _burn(msg.sender, seriesId, amount);

        // Calculate collateral to return (proportional)
        collateralReturned = (pos.collateral * amount) / pos.written;

        pos.written -= amount;
        pos.collateral -= collateralReturned;
        openInterest[seriesId] -= amount;

        // Return collateral
        address collateralToken = series.optionType == OptionType.CALL
            ? series.underlying
            : series.quote;

        IERC20(collateralToken).safeTransfer(msg.sender, collateralReturned);

        emit OptionsBurned(seriesId, msg.sender, amount, collateralReturned);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // SETTLEMENT & EXERCISE
    // ═══════════════════════════════════════════════════════════════════════

    /**
     * @notice Settle an expired series with oracle price
     * @param seriesId Option series ID
     */
    function settle(uint256 seriesId) external onlyRole(KEEPER_ROLE) {
        OptionSeries storage series = optionSeries[seriesId];
        if (!series.exists) revert SeriesNotFound();
        if (block.timestamp < series.expiry) revert SeriesNotExpired();
        if (isSettled[seriesId]) revert SeriesAlreadySettled();

        // Get settlement price from oracle
        uint256 price = _getSettlementPrice(series.underlying);
        settlementPrices[seriesId] = price;
        isSettled[seriesId] = true;

        emit SeriesSettled(seriesId, price, block.timestamp);
    }

    /**
     * @notice Exercise options at settlement
     * @param seriesId Option series ID
     * @param amount Number of options to exercise
     */
    function exercise(
        uint256 seriesId,
        uint256 amount
    ) external nonReentrant returns (uint256 payout) {
        if (amount == 0) revert ZeroAmount();

        OptionSeries storage series = optionSeries[seriesId];
        if (!series.exists) revert SeriesNotFound();
        if (!isSettled[seriesId]) revert SeriesNotSettled();

        uint256 balance = balanceOf(msg.sender, seriesId);
        if (balance < amount) revert InsufficientOptions();

        // Calculate payout
        payout = _calculatePayout(seriesId, amount);
        if (payout == 0) revert OutOfTheMoney();

        // Burn option tokens
        _burn(msg.sender, seriesId, amount);

        // Apply exercise fee
        uint256 fee = (payout * exerciseFeeBps) / BPS;
        payout -= fee;

        // Transfer payout
        address payoutToken = series.settlement == SettlementType.CASH
            ? series.quote
            : (series.optionType == OptionType.CALL ? series.underlying : series.quote);

        if (fee > 0) {
            IERC20(payoutToken).safeTransfer(feeReceiver, fee);
        }
        IERC20(payoutToken).safeTransfer(msg.sender, payout);

        emit OptionsExercised(seriesId, msg.sender, amount, payout);
    }

    /**
     * @notice Claim remaining collateral after settlement
     * @param seriesId Option series ID
     */
    function claimCollateral(uint256 seriesId) external nonReentrant returns (uint256 amount) {
        OptionSeries storage series = optionSeries[seriesId];
        if (!series.exists) revert SeriesNotFound();
        if (!isSettled[seriesId]) revert SeriesNotSettled();

        Position storage pos = positions[seriesId][msg.sender];
        if (pos.collateral == 0) revert NoPosition();

        // Calculate remaining collateral after exercises
        uint256 payoutPerOption = _calculatePayoutPerOption(seriesId);
        uint256 totalPayoutObligation = (payoutPerOption * pos.written) / PRECISION;

        if (totalPayoutObligation >= pos.collateral) {
            amount = 0;
        } else {
            amount = pos.collateral - totalPayoutObligation;
        }

        pos.collateral = 0;
        pos.written = 0;

        if (amount > 0) {
            address collateralToken = series.optionType == OptionType.CALL
                ? series.underlying
                : series.quote;
            IERC20(collateralToken).safeTransfer(msg.sender, amount);
        }

        emit CollateralClaimed(seriesId, msg.sender, amount);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // VIEW FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice Get series details
    function getSeries(uint256 seriesId) external view returns (OptionSeries memory) {
        return optionSeries[seriesId];
    }

    /// @notice Get writer position
    function getPosition(
        uint256 seriesId,
        address writer
    ) external view returns (Position memory) {
        return positions[seriesId][writer];
    }

    /// @notice Calculate collateral required for writing
    function calculateCollateral(
        uint256 seriesId,
        uint256 amount
    ) external view returns (uint256) {
        return _calculateCollateral(seriesId, amount);
    }

    /// @notice Calculate exercise payout
    function calculatePayout(
        uint256 seriesId,
        uint256 amount
    ) external view returns (uint256) {
        if (!isSettled[seriesId]) return 0;
        return _calculatePayout(seriesId, amount);
    }

    /// @notice Check if option is in the money
    function isInTheMoney(uint256 seriesId) external view returns (bool) {
        if (!isSettled[seriesId]) return false;
        return _calculatePayoutPerOption(seriesId) > 0;
    }

    // ═══════════════════════════════════════════════════════════════════════
    // ADMIN FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════

    function setOracle(address _oracle) external onlyRole(ADMIN_ROLE) {
        if (_oracle == address(0)) revert InvalidOracle();
        oracle = _oracle;
    }

    function setFeeReceiver(address _feeReceiver) external onlyRole(ADMIN_ROLE) {
        feeReceiver = _feeReceiver;
    }

    function setFees(
        uint256 _exerciseFeeBps,
        uint256 _writeFeeBps
    ) external onlyRole(ADMIN_ROLE) {
        exerciseFeeBps = _exerciseFeeBps;
        writeFeeBps = _writeFeeBps;
    }

    function setCollateralRatio(uint256 _ratio) external onlyRole(ADMIN_ROLE) {
        collateralRatio = _ratio;
    }

    function pause() external onlyRole(ADMIN_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(ADMIN_ROLE) {
        _unpause();
    }

    // ═══════════════════════════════════════════════════════════════════════
    // INTERNAL FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════

    function _calculateCollateral(
        uint256 seriesId,
        uint256 amount
    ) internal view returns (uint256) {
        OptionSeries storage series = optionSeries[seriesId];

        if (series.optionType == OptionType.CALL) {
            // For calls: collateral = amount of underlying (1:1)
            return (amount * collateralRatio) / BPS;
        } else {
            // For puts: collateral = strike * amount in quote
            uint8 underlyingDec = tokenDecimals[series.underlying];
            uint8 quoteDec = tokenDecimals[series.quote];

            uint256 collateral = (amount * series.strikePrice) / (10 ** underlyingDec);
            return (collateral * collateralRatio) / BPS;
        }
    }

    function _calculatePayout(
        uint256 seriesId,
        uint256 amount
    ) internal view returns (uint256) {
        uint256 payoutPerOption = _calculatePayoutPerOption(seriesId);
        return (payoutPerOption * amount) / PRECISION;
    }

    function _calculatePayoutPerOption(uint256 seriesId) internal view returns (uint256) {
        OptionSeries storage series = optionSeries[seriesId];
        uint256 price = settlementPrices[seriesId];

        if (series.optionType == OptionType.CALL) {
            // Call payout = max(0, spot - strike)
            if (price <= series.strikePrice) return 0;
            return ((price - series.strikePrice) * PRECISION) / series.strikePrice;
        } else {
            // Put payout = max(0, strike - spot)
            if (price >= series.strikePrice) return 0;
            return ((series.strikePrice - price) * PRECISION) / series.strikePrice;
        }
    }

    function _getSettlementPrice(address asset) internal view returns (uint256) {
        // Interface with oracle - simplified for now
        // In production, use IOracle(oracle).getPrice(asset)
        (bool success, bytes memory data) = oracle.staticcall(
            abi.encodeWithSignature("getPrice(address)", asset)
        );
        require(success, "Oracle call failed");
        (uint256 price,) = abi.decode(data, (uint256, uint256));
        return price;
    }

    function _getDecimals(address token) internal view returns (uint8) {
        (bool success, bytes memory data) = token.staticcall(
            abi.encodeWithSignature("decimals()")
        );
        if (success && data.length >= 32) {
            return uint8(abi.decode(data, (uint256)));
        }
        return 18;
    }

    // ERC1155 required overrides
    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC1155, AccessControl)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }
}
