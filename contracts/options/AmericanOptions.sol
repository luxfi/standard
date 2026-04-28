// SPDX-License-Identifier: MIT
pragma solidity ^0.8.31;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { ERC1155 } from "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { AccessControl } from "@openzeppelin/contracts/access/AccessControl.sol";
import { Pausable } from "@openzeppelin/contracts/utils/Pausable.sol";
import { Options } from "./Options.sol";
import { IAmericanOptions } from "../interfaces/options/IAmericanOptions.sol";
import { IOracle } from "../interfaces/options/IOracle.sol";

/**
 * @title AmericanOptions
 * @author Lux Industries
 * @notice American-style options with early exercise and writer assignment
 * @dev Composes with an Options contract (does NOT inherit — Options functions are
 *      not virtual). This contract wraps the underlying Options contract and adds:
 *
 * - writeAmerican(): writes via the Options contract and tracks writers in a queue
 * - exerciseEarly(): exercise before expiry using current oracle price
 * - Assignment engine: FIFO or PRO_RATA writer selection on early exercise
 *
 * At-expiry exercise is handled by calling Options.exercise() directly.
 * The writer queue is maintained separately for early exercise assignment.
 *
 * Architecture:
 * - Users call writeAmerican() to write options AND register in the writer queue
 * - Users call exerciseEarly() to exercise before expiry
 * - Users call Options.exercise() directly for at-expiry exercise (European-style)
 * - Collateral flows through the underlying Options contract
 */
contract AmericanOptions is IAmericanOptions, ReentrancyGuard, AccessControl, Pausable {
    using SafeERC20 for IERC20;

    // ═══════════════════════════════════════════════════════════════════════
    // CONSTANTS
    // ═══════════════════════════════════════════════════════════════════════

    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant KEEPER_ROLE = keccak256("KEEPER_ROLE");

    uint256 public constant PRECISION = 1e18;
    uint256 public constant BPS = 10000;
    uint256 public constant MAX_EARLY_EXERCISE_FEE_BPS = 500; // 5% max

    // ═══════════════════════════════════════════════════════════════════════
    // STATE
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice Underlying Options contract
    Options public immutable options;

    /// @notice Oracle for current prices (same oracle as Options contract)
    address public oracle;

    /// @notice Fee receiver
    address public feeReceiver;

    /// @notice Early exercise fee in basis points (default 50 = 0.5%)
    uint256 public override earlyExerciseFeeBps = 50;

    /// @notice Assignment mode per series (default FIFO)
    mapping(uint256 => AssignmentMode) private _assignmentModes;

    /// @notice Writer queue per series (ordered by write time for FIFO)
    mapping(uint256 => WriterEntry[]) private _writerQueues;

    /// @notice Index of writer in queue (seriesId => writer => index+1, 0 means not in queue)
    mapping(uint256 => mapping(address => uint256)) private _writerIndex;

    // ═══════════════════════════════════════════════════════════════════════
    // ERRORS (ADDITIONAL)
    // ═══════════════════════════════════════════════════════════════════════

    error ZeroAmount();
    error ZeroAddress();
    error SeriesNotFound();
    error SeriesExpired();
    error InsufficientOptions();

    // ═══════════════════════════════════════════════════════════════════════
    // EVENTS (ADDITIONAL)
    // ═══════════════════════════════════════════════════════════════════════

    event AmericanOptionsWritten(uint256 indexed seriesId, address indexed writer, uint256 amount, uint256 collateral);

    // ═══════════════════════════════════════════════════════════════════════
    // CONSTRUCTOR
    // ═══════════════════════════════════════════════════════════════════════

    constructor(address _options, address _feeReceiver, address _admin) {
        if (_options == address(0)) revert ZeroAddress();
        if (_admin == address(0)) revert ZeroAddress();

        options = Options(_options);
        oracle = options.oracle();
        feeReceiver = _feeReceiver;

        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        _grantRole(ADMIN_ROLE, _admin);
        _grantRole(KEEPER_ROLE, _admin);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // WRITING WITH QUEUE TRACKING
    // ═══════════════════════════════════════════════════════════════════════

    /**
     * @notice Write options through the Options contract and register in the writer queue
     * @dev Caller must approve collateral to THIS contract. This contract forwards
     *      collateral to the Options contract via Options.write().
     * @param seriesId Option series ID
     * @param amount Number of options to write
     * @param recipient Recipient of option tokens
     * @return collateralRequired Collateral locked in Options contract
     */
    function writeAmerican(uint256 seriesId, uint256 amount, address recipient)
        external
        nonReentrant
        whenNotPaused
        returns (uint256 collateralRequired)
    {
        if (amount == 0) revert ZeroAmount();

        Options.OptionSeries memory series = options.getSeries(seriesId);
        if (!series.exists) revert SeriesNotFound();
        if (block.timestamp >= series.expiry) revert SeriesExpired();

        // Determine collateral token and required amount
        address collateralToken = series.optionType == Options.OptionType.CALL ? series.underlying : series.quote;

        uint256 calcCollateral = options.calculateCollateral(seriesId, amount);

        // Account for writing fee: Options.write deducts writeFeeBps from collateral
        // We need to transfer enough to cover collateral + fee
        uint256 writeFeeBps = options.writeFeeBps();
        uint256 feeBuffer = (calcCollateral * writeFeeBps) / BPS;
        uint256 totalNeeded = calcCollateral + feeBuffer;

        // Pull collateral from caller
        IERC20(collateralToken).safeTransferFrom(msg.sender, address(this), totalNeeded);

        // Approve Options contract to pull from us
        IERC20(collateralToken).approve(address(options), totalNeeded);

        // Write options — tokens go to recipient
        collateralRequired = options.write(seriesId, amount, recipient);

        // Track writer in queue for early exercise assignment
        _addToWriterQueue(seriesId, msg.sender, amount);

        // Return any excess collateral to caller
        uint256 remaining = IERC20(collateralToken).balanceOf(address(this));
        if (remaining > 0) {
            IERC20(collateralToken).safeTransfer(msg.sender, remaining);
        }

        emit AmericanOptionsWritten(seriesId, msg.sender, amount, collateralRequired);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // EARLY EXERCISE
    // ═══════════════════════════════════════════════════════════════════════

    /// @inheritdoc IAmericanOptions
    function exerciseEarly(uint256 seriesId, uint256 amount) external override nonReentrant returns (uint256 payout) {
        if (amount == 0) revert ZeroAmount();

        Options.OptionSeries memory series = options.getSeries(seriesId);
        if (!series.exists) revert SeriesNotFound();
        if (block.timestamp >= series.expiry) revert AlreadyExpired();

        uint256 balance = options.balanceOf(msg.sender, seriesId);
        if (balance < amount) revert InsufficientOptions();

        // Get current price from oracle
        uint256 currentPrice = _getOraclePrice(series.underlying);

        // Calculate payout using current price
        uint256 payoutPerOption = _calculateEarlyPayout(series, currentPrice);
        if (payoutPerOption == 0) revert NotInTheMoney();

        payout = (payoutPerOption * amount) / PRECISION;

        // Transfer option tokens from holder to this contract then burn
        // Holder must have approved this contract as ERC1155 operator
        options.safeTransferFrom(msg.sender, address(this), seriesId, amount, "");

        // Apply early exercise fee (higher than at-expiry fee)
        uint256 fee = (payout * earlyExerciseFeeBps) / BPS;
        payout -= fee;

        // Payout token is always the collateral token (underlying for calls, quote for puts)
        address payoutToken = series.optionType == Options.OptionType.CALL ? series.underlying : series.quote;

        // Assign writers — this deducts from writer collateral in the Options contract
        // The assigned collateral is already held by the Options contract
        _assignWriters(seriesId, amount, payoutPerOption, payoutToken);

        // Transfer fee
        if (fee > 0) {
            IERC20(payoutToken).safeTransfer(feeReceiver, fee);
        }

        // Transfer payout to exerciser
        IERC20(payoutToken).safeTransfer(msg.sender, payout);

        emit EarlyExercise(seriesId, msg.sender, amount, payout, fee);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // ADMIN FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════

    /// @inheritdoc IAmericanOptions
    function setAssignmentMode(uint256 seriesId, AssignmentMode mode) external onlyRole(ADMIN_ROLE) {
        _assignmentModes[seriesId] = mode;
        emit AssignmentModeChanged(seriesId, mode);
    }

    /// @inheritdoc IAmericanOptions
    function setEarlyExerciseFeeBps(uint256 feeBps) external onlyRole(ADMIN_ROLE) {
        if (feeBps > MAX_EARLY_EXERCISE_FEE_BPS) revert FeeTooHigh();
        uint256 old = earlyExerciseFeeBps;
        earlyExerciseFeeBps = feeBps;
        emit EarlyExerciseFeeChanged(old, feeBps);
    }

    /**
     * @notice Update the oracle address
     * @param _oracle New oracle address
     */
    function setOracle(address _oracle) external onlyRole(ADMIN_ROLE) {
        if (_oracle == address(0)) revert ZeroAddress();
        oracle = _oracle;
    }

    /**
     * @notice Update the fee receiver
     * @param _feeReceiver New fee receiver address
     */
    function setFeeReceiver(address _feeReceiver) external onlyRole(ADMIN_ROLE) {
        feeReceiver = _feeReceiver;
    }

    function pause() external onlyRole(ADMIN_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(ADMIN_ROLE) {
        _unpause();
    }

    // ═══════════════════════════════════════════════════════════════════════
    // VIEW FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════

    /// @inheritdoc IAmericanOptions
    function getAssignmentMode(uint256 seriesId) external view returns (AssignmentMode) {
        return _assignmentModes[seriesId];
    }

    /// @inheritdoc IAmericanOptions
    function getWriterQueueLength(uint256 seriesId) external view returns (uint256) {
        return _writerQueues[seriesId].length;
    }

    /// @inheritdoc IAmericanOptions
    function getWriterEntry(uint256 seriesId, uint256 index) external view returns (WriterEntry memory) {
        return _writerQueues[seriesId][index];
    }

    // ═══════════════════════════════════════════════════════════════════════
    // ERC1155 RECEIVER
    // ═══════════════════════════════════════════════════════════════════════

    function onERC1155Received(address, address, uint256, uint256, bytes calldata) external pure returns (bytes4) {
        return this.onERC1155Received.selector;
    }

    function onERC1155BatchReceived(address, address, uint256[] calldata, uint256[] calldata, bytes calldata)
        external
        pure
        returns (bytes4)
    {
        return this.onERC1155BatchReceived.selector;
    }

    // ═══════════════════════════════════════════════════════════════════════
    // INTERNAL: WRITER QUEUE MANAGEMENT
    // ═══════════════════════════════════════════════════════════════════════

    function _addToWriterQueue(uint256 seriesId, address writer, uint256 amount) internal {
        uint256 idx = _writerIndex[seriesId][writer];
        if (idx > 0) {
            // Writer already in queue — increase their amount
            _writerQueues[seriesId][idx - 1].amount += amount;
        } else {
            // New writer — append to queue
            _writerQueues[seriesId].push(WriterEntry({ writer: writer, amount: amount }));
            _writerIndex[seriesId][writer] = _writerQueues[seriesId].length; // 1-indexed
        }
    }

    function _removeFromWriterQueue(uint256 seriesId, uint256 index) internal {
        WriterEntry[] storage queue = _writerQueues[seriesId];
        uint256 lastIndex = queue.length - 1;

        // Clear index for the entry being removed
        _writerIndex[seriesId][queue[index].writer] = 0;

        if (index != lastIndex) {
            // Move last entry to the removed slot
            WriterEntry storage lastEntry = queue[lastIndex];
            queue[index] = lastEntry;
            _writerIndex[seriesId][lastEntry.writer] = index + 1; // 1-indexed
        }

        queue.pop();
    }

    // ═══════════════════════════════════════════════════════════════════════
    // INTERNAL: ASSIGNMENT ENGINE
    // ═══════════════════════════════════════════════════════════════════════

    function _assignWriters(uint256 seriesId, uint256 amount, uint256 payoutPerOption, address payoutToken) internal {
        AssignmentMode mode = _assignmentModes[seriesId];

        if (mode == AssignmentMode.FIFO) {
            _assignFIFO(seriesId, amount, payoutPerOption, payoutToken);
        } else {
            _assignProRata(seriesId, amount, payoutPerOption, payoutToken);
        }
    }

    function _assignFIFO(uint256 seriesId, uint256 amount, uint256 payoutPerOption, address payoutToken) internal {
        WriterEntry[] storage queue = _writerQueues[seriesId];
        uint256 remaining = amount;
        uint256 totalCollateralToRelease;
        uint256 i;

        while (remaining > 0 && i < queue.length) {
            WriterEntry storage entry = queue[i];
            uint256 assignable = entry.amount > remaining ? remaining : entry.amount;
            uint256 collateralDeducted = (payoutPerOption * assignable) / PRECISION;

            entry.amount -= assignable;
            remaining -= assignable;
            totalCollateralToRelease += collateralDeducted;

            emit WriterAssigned(seriesId, entry.writer, assignable, collateralDeducted);

            if (entry.amount == 0) {
                _removeFromWriterQueue(seriesId, i);
                // Don't increment i — swap-and-pop means new entry is at index i
            } else {
                ++i;
            }
        }

        if (remaining > 0) revert NoWritersAvailable();

        // Release collateral from Options in one call (position is under this contract's address)
        if (totalCollateralToRelease > 0) {
            options.releaseWriterCollateral(seriesId, address(this), totalCollateralToRelease);
        }
    }

    function _assignProRata(uint256 seriesId, uint256 amount, uint256 payoutPerOption, address payoutToken) internal {
        WriterEntry[] storage queue = _writerQueues[seriesId];

        // Calculate total written in queue
        uint256 totalWritten;
        for (uint256 i; i < queue.length; ++i) {
            totalWritten += queue[i].amount;
        }
        if (totalWritten == 0) revert NoWritersAvailable();

        // Assign proportionally
        uint256 assigned;
        uint256 totalCollateralToRelease;
        for (uint256 i; i < queue.length; ++i) {
            WriterEntry storage entry = queue[i];

            uint256 share = (amount * entry.amount) / totalWritten;
            if (share == 0) continue;
            if (share > entry.amount) share = entry.amount;

            uint256 collateralDeducted = (payoutPerOption * share) / PRECISION;
            entry.amount -= share;
            assigned += share;
            totalCollateralToRelease += collateralDeducted;

            emit WriterAssigned(seriesId, entry.writer, share, collateralDeducted);
        }

        // Handle rounding remainder — assign to first writer with capacity
        if (assigned < amount) {
            uint256 remainder = amount - assigned;
            for (uint256 i; i < queue.length; ++i) {
                WriterEntry storage entry = queue[i];
                if (entry.amount >= remainder) {
                    uint256 collateralDeducted = (payoutPerOption * remainder) / PRECISION;
                    entry.amount -= remainder;
                    totalCollateralToRelease += collateralDeducted;

                    emit WriterAssigned(seriesId, entry.writer, remainder, collateralDeducted);
                    break;
                }
            }
        }

        // Clean up exhausted entries (iterate backwards to avoid index shifting)
        for (uint256 i = queue.length; i > 0; --i) {
            if (queue[i - 1].amount == 0) {
                _removeFromWriterQueue(seriesId, i - 1);
            }
        }

        // Release collateral from Options in one call (position is under this contract's address)
        if (totalCollateralToRelease > 0) {
            options.releaseWriterCollateral(seriesId, address(this), totalCollateralToRelease);
        }
    }

    // ═══════════════════════════════════════════════════════════════════════
    // INTERNAL: ORACLE & PAYOUT
    // ═══════════════════════════════════════════════════════════════════════

    function _getOraclePrice(address asset) internal view returns (uint256) {
        (uint256 price,) = IOracle(oracle).getPrice(asset);
        return price;
    }

    function _calculateEarlyPayout(Options.OptionSeries memory series, uint256 currentPrice)
        internal
        view
        returns (uint256)
    {
        if (series.optionType == Options.OptionType.CALL) {
            // Call: collateral is in underlying. Payout in underlying fraction.
            if (currentPrice <= series.strikePrice) return 0;
            return ((currentPrice - series.strikePrice) * PRECISION) / currentPrice;
        } else {
            // Put: collateral is in quote. Payout in quote.
            if (currentPrice >= series.strikePrice) return 0;
            uint8 underlyingDec = options.tokenDecimals(series.underlying);
            return ((series.strikePrice - currentPrice) * PRECISION) / (10 ** underlyingDec);
        }
    }
}
