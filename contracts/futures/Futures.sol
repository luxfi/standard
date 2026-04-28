// SPDX-License-Identifier: MIT
pragma solidity ^0.8.31;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { AccessControl } from "@openzeppelin/contracts/access/AccessControl.sol";
import { Pausable } from "@openzeppelin/contracts/utils/Pausable.sol";
import { IFutures } from "../interfaces/futures/IFutures.sol";

/**
 * @title Futures
 * @author Lux Industries
 * @notice Traditional dated futures contracts with daily mark-to-market settlement
 * @dev CME-style futures supporting cash and physical settlement. Positions are margined
 *      in the quote asset (e.g., USDL). A keeper calls dailySettlement() to sweep PnL
 *      between longs and shorts. Positions below maintenance margin are liquidatable.
 *
 * Key features:
 * - Admin-created contract specs (underlying, size, tick, margin, expiry)
 * - Long/short position opening with initial margin
 * - Partial and full closes with realised PnL
 * - Daily mark-to-market settlement (keeper-driven)
 * - Maintenance margin enforcement with liquidation
 * - Final settlement at expiry via oracle
 * - Open interest tracking per side
 */
contract Futures is IFutures, ReentrancyGuard, AccessControl, Pausable {
    using SafeERC20 for IERC20;

    // ═══════════════════════════════════════════════════════════════════════
    // CONSTANTS
    // ═══════════════════════════════════════════════════════════════════════

    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant KEEPER_ROLE = keccak256("KEEPER_ROLE");

    /// @notice 18-decimal precision for prices and PnL
    uint256 public constant PRECISION = 1e18;

    /// @notice Basis points denominator
    uint256 public constant BPS = 10000;

    /// @notice Minimum expiry duration from creation
    uint256 public constant MIN_EXPIRY_DURATION = 1 hours;

    /// @notice Maximum expiry duration from creation
    uint256 public constant MAX_EXPIRY_DURATION = 365 days;

    /// @notice Liquidation penalty in BPS paid to liquidator
    uint256 public constant LIQUIDATION_PENALTY_BPS = 250; // 2.5%

    // ═══════════════════════════════════════════════════════════════════════
    // STATE
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice Oracle for settlement prices
    address public oracle;

    /// @notice Fee receiver
    address public feeReceiver;

    /// @notice Trading fee in basis points
    uint256 public tradingFeeBps = 5; // 0.05%

    /// @notice Contract specs by ID
    mapping(uint256 => ContractSpec) private _contracts;

    /// @notice Positions by (contractId, trader)
    mapping(uint256 => mapping(address => Position)) private _positions;

    /// @notice Last daily settlement price per contract
    mapping(uint256 => uint256) public lastSettlementPrice;

    /// @notice Whether a contract has been finally settled
    mapping(uint256 => bool) public isFinallySettled;

    /// @notice Final settlement price per contract
    mapping(uint256 => uint256) public finalSettlementPrices;

    /// @notice Long open interest per contract (number of contracts)
    mapping(uint256 => uint256) public longOpenInterest;

    /// @notice Short open interest per contract (number of contracts)
    mapping(uint256 => uint256) public shortOpenInterest;

    /// @notice Traders with open positions per contract (for daily settlement iteration)
    mapping(uint256 => address[]) private _traders;

    /// @notice Trader index in _traders array (contractId => trader => index+1, 0 = not tracked)
    mapping(uint256 => mapping(address => uint256)) private _traderIndex;

    /// @notice Next contract ID
    uint256 public nextContractId = 1;

    // ═══════════════════════════════════════════════════════════════════════
    // CONSTRUCTOR
    // ═══════════════════════════════════════════════════════════════════════

    constructor(address _oracle, address _feeReceiver, address _admin) {
        if (_oracle == address(0)) revert InvalidOracle();
        if (_admin == address(0)) revert ZeroAddress();

        oracle = _oracle;
        feeReceiver = _feeReceiver;

        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        _grantRole(ADMIN_ROLE, _admin);
        _grantRole(KEEPER_ROLE, _admin);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // CONTRACT MANAGEMENT
    // ═══════════════════════════════════════════════════════════════════════

    /// @inheritdoc IFutures
    function createContract(
        address underlying,
        address quote,
        uint256 expiryDate,
        uint256 contractSize,
        uint256 tickSize,
        uint256 initialMarginBps,
        uint256 maintenanceMarginBps,
        SettlementType settlement
    ) external onlyRole(ADMIN_ROLE) returns (uint256 contractId) {
        if (underlying == address(0) || quote == address(0)) revert ZeroAddress();
        if (expiryDate <= block.timestamp + MIN_EXPIRY_DURATION) revert InvalidExpiry();
        if (expiryDate > block.timestamp + MAX_EXPIRY_DURATION) revert InvalidExpiry();
        if (contractSize == 0) revert InvalidContractSize();
        if (tickSize == 0) revert InvalidTickSize();
        if (initialMarginBps == 0 || maintenanceMarginBps == 0) revert InvalidMarginParams();
        if (maintenanceMarginBps >= initialMarginBps) revert InvalidMarginParams();
        if (initialMarginBps > BPS) revert InvalidMarginParams();

        contractId = nextContractId++;

        _contracts[contractId] = ContractSpec({
            underlying: underlying,
            quote: quote,
            expiryDate: expiryDate,
            contractSize: contractSize,
            tickSize: tickSize,
            initialMarginBps: initialMarginBps,
            maintenanceMarginBps: maintenanceMarginBps,
            settlement: settlement,
            exists: true
        });

        emit ContractCreated(contractId, underlying, quote, expiryDate, contractSize, settlement);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // TRADING
    // ═══════════════════════════════════════════════════════════════════════

    /// @inheritdoc IFutures
    function openPosition(uint256 contractId, Side side, uint256 size, uint256 price, uint256 marginAmount)
        external
        nonReentrant
        whenNotPaused
    {
        if (size == 0) revert ZeroAmount();

        ContractSpec storage spec = _contracts[contractId];
        if (!spec.exists) revert ContractNotFound();
        if (block.timestamp >= spec.expiryDate) revert ContractExpired();
        if (price % spec.tickSize != 0) revert PriceNotAlignedToTick();

        // Calculate required initial margin
        uint256 notional = _notionalValue(spec, size, price);
        uint256 requiredMargin = (notional * spec.initialMarginBps) / BPS;
        if (marginAmount < requiredMargin) revert InsufficientMargin();

        // Apply trading fee
        uint256 fee = (notional * tradingFeeBps) / BPS;
        uint256 totalDeposit = marginAmount + fee;

        // Transfer margin + fee from trader
        IERC20(spec.quote).safeTransferFrom(msg.sender, address(this), totalDeposit);
        if (fee > 0 && feeReceiver != address(0)) {
            IERC20(spec.quote).safeTransfer(feeReceiver, fee);
        }

        Position storage pos = _positions[contractId][msg.sender];

        if (pos.status == PositionStatus.OPEN && pos.size > 0) {
            // Existing open position — must be same side
            if (pos.side != side) revert InsufficientPosition(); // Cannot open opposite side; close first

            // Weighted average entry price
            uint256 oldNotional = pos.entryPrice * pos.size;
            uint256 newNotional = price * size;
            pos.entryPrice = (oldNotional + newNotional) / (pos.size + size);
            pos.size += size;
            pos.margin += marginAmount;

            if (pos.lastSettlementPrice == 0) {
                pos.lastSettlementPrice = price;
            }

            emit PositionIncreased(contractId, msg.sender, size, pos.entryPrice, marginAmount);
        } else {
            // New position
            _positions[contractId][msg.sender] = Position({
                contractId: contractId,
                trader: msg.sender,
                side: side,
                size: size,
                entryPrice: price,
                margin: marginAmount,
                realisedPnl: 0,
                lastSettlementPrice: price,
                status: PositionStatus.OPEN
            });

            _addTrader(contractId, msg.sender);

            emit PositionOpened(contractId, msg.sender, side, size, price, marginAmount);
        }

        // Update open interest
        if (side == Side.LONG) {
            longOpenInterest[contractId] += size;
        } else {
            shortOpenInterest[contractId] += size;
        }
    }

    /// @inheritdoc IFutures
    function closePosition(uint256 contractId, uint256 size, uint256 price) external nonReentrant returns (int256 pnl) {
        ContractSpec storage spec = _contracts[contractId];
        if (!spec.exists) revert ContractNotFound();
        if (price % spec.tickSize != 0) revert PriceNotAlignedToTick();

        Position storage pos = _positions[contractId][msg.sender];
        if (pos.status != PositionStatus.OPEN || pos.size == 0) revert PositionNotFound();
        if (size == 0) revert ZeroAmount();
        if (size > pos.size) revert InsufficientPosition();

        // Calculate PnL for closed portion
        pnl = _calculatePnl(pos.side, pos.entryPrice, price, spec.contractSize, size);

        // Apply trading fee on close
        uint256 notional = _notionalValue(spec, size, price);
        uint256 fee = (notional * tradingFeeBps) / BPS;

        // Update position
        uint256 marginRelease = (pos.margin * size) / pos.size;
        pos.size -= size;
        pos.margin -= marginRelease;
        pos.realisedPnl += pnl;

        // Update open interest
        if (pos.side == Side.LONG) {
            longOpenInterest[contractId] -= size;
        } else {
            shortOpenInterest[contractId] -= size;
        }

        // Calculate net transfer to/from trader
        // marginRelease + pnl - fee
        int256 netTransfer = int256(marginRelease) + pnl - int256(fee);

        if (pos.size == 0) {
            pos.status = PositionStatus.CLOSED;
            _removeTrader(contractId, msg.sender);
        }

        // Transfer funds
        if (netTransfer > 0) {
            IERC20(spec.quote).safeTransfer(msg.sender, uint256(netTransfer));
        } else if (netTransfer < 0) {
            // Trader owes — pull from their remaining margin or external
            uint256 owed = uint256(-netTransfer);
            if (owed <= pos.margin) {
                pos.margin -= owed;
            } else {
                // Clamp to zero — position is effectively bankrupt
                pos.margin = 0;
            }
        }

        if (fee > 0 && feeReceiver != address(0)) {
            IERC20(spec.quote).safeTransfer(feeReceiver, fee);
        }

        emit PositionClosed(contractId, msg.sender, size, price, pnl);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // MARGIN
    // ═══════════════════════════════════════════════════════════════════════

    /// @inheritdoc IFutures
    function depositMargin(uint256 contractId, uint256 amount) external nonReentrant {
        if (amount == 0) revert ZeroAmount();

        ContractSpec storage spec = _contracts[contractId];
        if (!spec.exists) revert ContractNotFound();

        Position storage pos = _positions[contractId][msg.sender];
        if (pos.status != PositionStatus.OPEN || pos.size == 0) revert PositionNotFound();

        IERC20(spec.quote).safeTransferFrom(msg.sender, address(this), amount);
        pos.margin += amount;

        emit MarginDeposited(contractId, msg.sender, amount);
    }

    /// @inheritdoc IFutures
    function withdrawMargin(uint256 contractId, uint256 amount) external nonReentrant {
        if (amount == 0) revert ZeroAmount();

        ContractSpec storage spec = _contracts[contractId];
        if (!spec.exists) revert ContractNotFound();

        Position storage pos = _positions[contractId][msg.sender];
        if (pos.status != PositionStatus.OPEN || pos.size == 0) revert PositionNotFound();

        // After withdrawal, margin must still meet initial margin requirement
        uint256 currentPrice = lastSettlementPrice[contractId];
        if (currentPrice == 0) currentPrice = pos.entryPrice;
        uint256 notional = _notionalValue(spec, pos.size, currentPrice);
        uint256 requiredMargin = (notional * spec.initialMarginBps) / BPS;

        // Account for unrealised PnL in effective margin
        int256 unrealised = _calculatePnl(pos.side, pos.lastSettlementPrice, currentPrice, spec.contractSize, pos.size);
        int256 effectiveMargin = int256(pos.margin) + unrealised;

        if (effectiveMargin - int256(amount) < int256(requiredMargin)) revert InsufficientMargin();

        pos.margin -= amount;
        IERC20(spec.quote).safeTransfer(msg.sender, amount);

        emit MarginWithdrawn(contractId, msg.sender, amount);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // SETTLEMENT
    // ═══════════════════════════════════════════════════════════════════════

    /**
     * @notice Perform daily mark-to-market settlement
     * @dev Iterates all open positions for this contract and settles PnL since
     *      last settlement price. Winners receive quote tokens, losers have margin
     *      deducted. Emits MarginCall for positions below maintenance margin.
     * @param contractId Futures contract ID
     */
    function dailySettlement(uint256 contractId) external onlyRole(KEEPER_ROLE) {
        ContractSpec storage spec = _contracts[contractId];
        if (!spec.exists) revert ContractNotFound();
        if (isFinallySettled[contractId]) revert ContractAlreadySettled();

        // Get current mark price from oracle
        uint256 markPrice = _getOraclePrice(spec.underlying);
        lastSettlementPrice[contractId] = markPrice;

        // Iterate all traders with open positions
        address[] storage traders = _traders[contractId];
        for (uint256 i; i < traders.length; ++i) {
            address trader = traders[i];
            Position storage pos = _positions[contractId][trader];

            if (pos.status != PositionStatus.OPEN || pos.size == 0) continue;

            // PnL since last settlement
            int256 pnlDelta = _calculatePnl(pos.side, pos.lastSettlementPrice, markPrice, spec.contractSize, pos.size);

            pos.lastSettlementPrice = markPrice;
            pos.realisedPnl += pnlDelta;

            // Settle PnL against margin
            if (pnlDelta > 0) {
                pos.margin += uint256(pnlDelta);
            } else if (pnlDelta < 0) {
                uint256 loss = uint256(-pnlDelta);
                if (loss >= pos.margin) {
                    pos.margin = 0;
                } else {
                    pos.margin -= loss;
                }
            }

            // Check maintenance margin
            uint256 notional = _notionalValue(spec, pos.size, markPrice);
            uint256 maintenanceReq = (notional * spec.maintenanceMarginBps) / BPS;
            if (pos.margin < maintenanceReq) {
                emit MarginCall(contractId, trader, pos.margin, maintenanceReq);
            }
        }

        emit DailySettlement(contractId, markPrice, block.timestamp);
    }

    /**
     * @notice Liquidate an under-margined position
     * @dev Anyone can call. Liquidator receives a penalty from the position's margin.
     *      The position is closed at the current mark price.
     * @param contractId Futures contract ID
     * @param trader Trader to liquidate
     */
    function liquidate(uint256 contractId, address trader) external nonReentrant {
        ContractSpec storage spec = _contracts[contractId];
        if (!spec.exists) revert ContractNotFound();

        Position storage pos = _positions[contractId][trader];
        if (pos.status != PositionStatus.OPEN || pos.size == 0) revert PositionNotFound();

        // Get current price
        uint256 markPrice = lastSettlementPrice[contractId];
        if (markPrice == 0) markPrice = _getOraclePrice(spec.underlying);

        // Verify position is below maintenance
        uint256 notional = _notionalValue(spec, pos.size, markPrice);
        uint256 maintenanceReq = (notional * spec.maintenanceMarginBps) / BPS;

        int256 unrealised = _calculatePnl(pos.side, pos.lastSettlementPrice, markPrice, spec.contractSize, pos.size);
        int256 effectiveMargin = int256(pos.margin) + unrealised;

        if (effectiveMargin >= int256(maintenanceReq)) revert NotLiquidatable();

        // Liquidation penalty to liquidator
        uint256 penalty = (pos.margin * LIQUIDATION_PENALTY_BPS) / BPS;
        uint256 remainingMargin = pos.margin > penalty ? pos.margin - penalty : 0;

        // Update open interest
        if (pos.side == Side.LONG) {
            longOpenInterest[contractId] -= pos.size;
        } else {
            shortOpenInterest[contractId] -= pos.size;
        }

        uint256 liquidatedSize = pos.size;

        // Close position
        pos.size = 0;
        pos.margin = 0;
        pos.status = PositionStatus.LIQUIDATED;

        _removeTrader(contractId, trader);

        // Transfer penalty to liquidator
        if (penalty > 0) {
            IERC20(spec.quote).safeTransfer(msg.sender, penalty);
        }

        // Return remaining margin to trader
        if (remainingMargin > 0) {
            IERC20(spec.quote).safeTransfer(trader, remainingMargin);
        }

        emit PositionLiquidated(contractId, trader, msg.sender, liquidatedSize, markPrice);
    }

    /**
     * @notice Final settlement at expiry — settles all remaining positions
     * @dev Gets final price from oracle and closes all open positions.
     *      After this, no new positions can be opened.
     * @param contractId Futures contract ID
     */
    function finalSettlement(uint256 contractId) external onlyRole(KEEPER_ROLE) {
        ContractSpec storage spec = _contracts[contractId];
        if (!spec.exists) revert ContractNotFound();
        if (block.timestamp < spec.expiryDate) revert ContractNotExpired();
        if (isFinallySettled[contractId]) revert ContractAlreadySettled();

        uint256 finalPrice = _getOraclePrice(spec.underlying);
        finalSettlementPrices[contractId] = finalPrice;
        isFinallySettled[contractId] = true;
        lastSettlementPrice[contractId] = finalPrice;

        // Settle all open positions
        address[] storage traders = _traders[contractId];
        for (uint256 i; i < traders.length; ++i) {
            address trader = traders[i];
            Position storage pos = _positions[contractId][trader];

            if (pos.status != PositionStatus.OPEN || pos.size == 0) continue;

            int256 pnl = _calculatePnl(pos.side, pos.lastSettlementPrice, finalPrice, spec.contractSize, pos.size);

            pos.realisedPnl += pnl;

            // Calculate net payout
            int256 netPayout = int256(pos.margin) + pnl;

            // Update open interest
            if (pos.side == Side.LONG) {
                longOpenInterest[contractId] -= pos.size;
            } else {
                shortOpenInterest[contractId] -= pos.size;
            }

            pos.size = 0;
            pos.margin = 0;
            pos.status = PositionStatus.CLOSED;
            pos.lastSettlementPrice = finalPrice;

            // Transfer net payout
            if (netPayout > 0) {
                IERC20(spec.quote).safeTransfer(trader, uint256(netPayout));
            }

            emit PositionClosed(contractId, trader, 0, finalPrice, pnl);
        }

        // Clear trader list
        delete _traders[contractId];

        emit FinalSettlement(contractId, finalPrice, block.timestamp);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // VIEW FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════

    /// @inheritdoc IFutures
    function getContract(uint256 contractId) external view returns (ContractSpec memory) {
        return _contracts[contractId];
    }

    /// @inheritdoc IFutures
    function getPosition(uint256 contractId, address trader) external view returns (Position memory) {
        return _positions[contractId][trader];
    }

    /// @inheritdoc IFutures
    function getUnrealisedPnl(uint256 contractId, address trader) external view returns (int256 pnl) {
        ContractSpec storage spec = _contracts[contractId];
        Position storage pos = _positions[contractId][trader];
        if (pos.status != PositionStatus.OPEN || pos.size == 0) return 0;

        uint256 markPrice = lastSettlementPrice[contractId];
        if (markPrice == 0) markPrice = pos.entryPrice;

        pnl = _calculatePnl(pos.side, pos.lastSettlementPrice, markPrice, spec.contractSize, pos.size);
    }

    /// @inheritdoc IFutures
    function getOpenInterest(uint256 contractId) external view returns (uint256 longOI, uint256 shortOI) {
        longOI = longOpenInterest[contractId];
        shortOI = shortOpenInterest[contractId];
    }

    /// @inheritdoc IFutures
    function isLiquidatable(uint256 contractId, address trader) external view returns (bool) {
        ContractSpec storage spec = _contracts[contractId];
        Position storage pos = _positions[contractId][trader];
        if (pos.status != PositionStatus.OPEN || pos.size == 0) return false;

        uint256 markPrice = lastSettlementPrice[contractId];
        if (markPrice == 0) return false;

        uint256 notional = _notionalValue(spec, pos.size, markPrice);
        uint256 maintenanceReq = (notional * spec.maintenanceMarginBps) / BPS;

        int256 unrealised = _calculatePnl(pos.side, pos.lastSettlementPrice, markPrice, spec.contractSize, pos.size);
        int256 effectiveMargin = int256(pos.margin) + unrealised;

        return effectiveMargin < int256(maintenanceReq);
    }

    /**
     * @notice Get the number of tracked traders for a contract
     * @param contractId Contract ID
     * @return count Number of traders with open positions
     */
    function getTraderCount(uint256 contractId) external view returns (uint256) {
        return _traders[contractId].length;
    }

    // ═══════════════════════════════════════════════════════════════════════
    // ADMIN FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════

    /**
     * @notice Update oracle address
     * @param _oracle New oracle address
     */
    function setOracle(address _oracle) external onlyRole(ADMIN_ROLE) {
        if (_oracle == address(0)) revert InvalidOracle();
        oracle = _oracle;
    }

    /**
     * @notice Update fee receiver
     * @param _feeReceiver New fee receiver address
     */
    function setFeeReceiver(address _feeReceiver) external onlyRole(ADMIN_ROLE) {
        feeReceiver = _feeReceiver;
    }

    /**
     * @notice Update trading fee
     * @param _tradingFeeBps New fee in basis points
     */
    function setTradingFeeBps(uint256 _tradingFeeBps) external onlyRole(ADMIN_ROLE) {
        tradingFeeBps = _tradingFeeBps;
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

    /**
     * @dev Calculate notional value of a position
     * @param spec Contract specification
     * @param size Number of contracts
     * @param price Price per unit (PRECISION-scaled)
     * @return Notional value in quote asset
     */
    function _notionalValue(ContractSpec storage spec, uint256 size, uint256 price) internal view returns (uint256) {
        return (size * spec.contractSize * price) / PRECISION;
    }

    /**
     * @dev Calculate PnL for a position move
     * @param side Position direction
     * @param fromPrice Starting price
     * @param toPrice Ending price
     * @param contractSize Units per contract
     * @param size Number of contracts
     * @return pnl Signed PnL (positive = profit)
     */
    function _calculatePnl(Side side, uint256 fromPrice, uint256 toPrice, uint256 contractSize, uint256 size)
        internal
        pure
        returns (int256 pnl)
    {
        if (fromPrice == toPrice) return 0;

        int256 priceDelta = int256(toPrice) - int256(fromPrice);

        // Long profits when price goes up, short profits when price goes down
        if (side == Side.SHORT) {
            priceDelta = -priceDelta;
        }

        pnl = (priceDelta * int256(size) * int256(contractSize)) / int256(PRECISION);
    }

    /**
     * @dev Get price from oracle
     * @param asset Asset address
     * @return price Current price (PRECISION-scaled)
     */
    function _getOraclePrice(address asset) internal view returns (uint256) {
        (bool success, bytes memory data) = oracle.staticcall(abi.encodeWithSignature("getPrice(address)", asset));
        require(success, "Oracle call failed");
        (uint256 price,) = abi.decode(data, (uint256, uint256));
        return price;
    }

    /**
     * @dev Add a trader to the tracking array for a contract
     */
    function _addTrader(uint256 contractId, address trader) internal {
        if (_traderIndex[contractId][trader] != 0) return; // Already tracked
        _traders[contractId].push(trader);
        _traderIndex[contractId][trader] = _traders[contractId].length; // 1-indexed
    }

    /**
     * @dev Remove a trader from the tracking array (swap-and-pop)
     */
    function _removeTrader(uint256 contractId, address trader) internal {
        uint256 idx = _traderIndex[contractId][trader];
        if (idx == 0) return; // Not tracked

        address[] storage arr = _traders[contractId];
        uint256 lastIdx = arr.length - 1;
        uint256 removeIdx = idx - 1; // Convert to 0-indexed

        _traderIndex[contractId][trader] = 0;

        if (removeIdx != lastIdx) {
            address lastTrader = arr[lastIdx];
            arr[removeIdx] = lastTrader;
            _traderIndex[contractId][lastTrader] = removeIdx + 1; // 1-indexed
        }

        arr.pop();
    }
}
