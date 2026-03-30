// SPDX-License-Identifier: MIT
pragma solidity ^0.8.31;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { AccessControl } from "@openzeppelin/contracts/access/AccessControl.sol";
import { Pausable } from "@openzeppelin/contracts/utils/Pausable.sol";
import { IForexForward } from "../interfaces/forex/IForexForward.sol";
import { IForexPair } from "../interfaces/forex/IForexPair.sol";
import { IPriceOracle } from "../interfaces/oracle/IPriceOracle.sol";

/**
 * @title ForexForward
 * @author Lux Industries
 * @notice FX forward contracts — agree to exchange currencies at a future date/rate
 * @dev Buyer locks quote collateral, seller locks base collateral. At maturity,
 *      settlement pays the difference or exchanges actual tokens.
 *
 * Key features:
 * - Buyer creates forward, deposits quote collateral
 * - Seller accepts forward, deposits base collateral
 * - At maturity, keeper or either party calls settle
 * - Cash settlement: pays PnL diff in quote token
 * - Configurable collateral ratio for mark-to-market exposure
 */
contract ForexForward is IForexForward, ReentrancyGuard, AccessControl, Pausable {
    using SafeERC20 for IERC20;

    // ═══════════════════════════════════════════════════════════════════════
    // CONSTANTS
    // ═══════════════════════════════════════════════════════════════════════

    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant KEEPER_ROLE = keccak256("KEEPER_ROLE");

    uint256 public constant PRECISION = 1e18;
    uint256 public constant BPS = 10000;
    uint256 public constant MIN_MATURITY = 1 hours;
    uint256 public constant MAX_MATURITY = 365 days;

    // ═══════════════════════════════════════════════════════════════════════
    // STATE
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice ForexPair contract for pair data
    IForexPair public forexPair;

    /// @notice Price oracle
    IPriceOracle public oracle;

    /// @notice Collateral ratio in basis points (10000 = 100%)
    uint256 public collateralRatioBps = 10000;

    /// @notice Fee receiver
    address public feeReceiver;

    /// @notice Settlement fee in basis points
    uint256 public settlementFeeBps = 5; // 0.05%

    /// @notice Forwards by ID
    mapping(uint256 => Forward) public forwards;

    /// @notice Next forward ID
    uint256 public nextForwardId = 1;

    // ═══════════════════════════════════════════════════════════════════════
    // EVENTS (additional)
    // ═══════════════════════════════════════════════════════════════════════

    event OracleUpdated(address indexed oracle);

    // ═══════════════════════════════════════════════════════════════════════
    // ERRORS (additional)
    // ═══════════════════════════════════════════════════════════════════════

    error InvalidOracle();
    error InvalidForexPair();

    // ═══════════════════════════════════════════════════════════════════════
    // CONSTRUCTOR
    // ═══════════════════════════════════════════════════════════════════════

    constructor(address _forexPair, address _oracle, address _feeReceiver, address _admin) {
        if (_forexPair == address(0)) revert InvalidForexPair();
        if (_oracle == address(0)) revert InvalidOracle();
        if (_admin == address(0)) revert ZeroAddress();

        forexPair = IForexPair(_forexPair);
        oracle = IPriceOracle(_oracle);
        feeReceiver = _feeReceiver;

        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        _grantRole(ADMIN_ROLE, _admin);
        _grantRole(KEEPER_ROLE, _admin);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // FORWARD LIFECYCLE
    // ═══════════════════════════════════════════════════════════════════════

    /// @inheritdoc IForexForward
    function createForward(uint256 pairId, uint256 rate, uint256 baseAmount, uint256 maturityDate)
        external
        override
        nonReentrant
        whenNotPaused
        returns (uint256 forwardId)
    {
        if (rate == 0) revert InvalidRate();
        if (baseAmount == 0) revert ZeroAmount();
        if (maturityDate <= block.timestamp + MIN_MATURITY) revert InvalidMaturityDate();
        if (maturityDate > block.timestamp + MAX_MATURITY) revert InvalidMaturityDate();

        // Verify pair exists
        IForexPair.FXPair memory pair = forexPair.getPair(pairId);
        if (pair.base == address(0)) revert ForwardNotFound();

        // Buyer deposits collateral in quote: baseAmount * rate / PRECISION * collateralRatio / BPS
        uint256 quoteCollateral = (baseAmount * rate * collateralRatioBps) / (PRECISION * BPS);

        IERC20(pair.quote).safeTransferFrom(msg.sender, address(this), quoteCollateral);

        forwardId = nextForwardId++;

        forwards[forwardId] = Forward({
            pairId: pairId,
            buyer: msg.sender,
            seller: address(0),
            rate: rate,
            baseAmount: baseAmount,
            maturityDate: maturityDate,
            buyerCollateral: quoteCollateral,
            sellerCollateral: 0,
            status: ForwardStatus.OPEN
        });

        emit ForwardCreated(forwardId, pairId, msg.sender, rate, baseAmount, maturityDate);
    }

    /// @inheritdoc IForexForward
    function acceptForward(uint256 forwardId) external override nonReentrant whenNotPaused {
        Forward storage fwd = forwards[forwardId];
        if (fwd.buyer == address(0)) revert ForwardNotFound();
        if (fwd.status != ForwardStatus.OPEN) revert ForwardNotOpen();

        IForexPair.FXPair memory pair = forexPair.getPair(fwd.pairId);

        // Seller deposits collateral in base: baseAmount * collateralRatio / BPS
        uint256 baseCollateral = (fwd.baseAmount * collateralRatioBps) / BPS;

        IERC20(pair.base).safeTransferFrom(msg.sender, address(this), baseCollateral);

        fwd.seller = msg.sender;
        fwd.sellerCollateral = baseCollateral;
        fwd.status = ForwardStatus.ACTIVE;

        emit ForwardActivated(forwardId, msg.sender);
    }

    /// @inheritdoc IForexForward
    function settleForward(uint256 forwardId) external override nonReentrant {
        Forward storage fwd = forwards[forwardId];
        if (fwd.buyer == address(0)) revert ForwardNotFound();
        if (fwd.status != ForwardStatus.ACTIVE) revert ForwardNotActive();
        if (block.timestamp < fwd.maturityDate) {
            // Only keeper can settle early (auto-settlement)
            _checkRole(KEEPER_ROLE, msg.sender);
        }

        IForexPair.FXPair memory pair = forexPair.getPair(fwd.pairId);

        // Get current market rate
        (uint256 currentRate,) = oracle.getRate(pair.base, pair.quote);

        // Cash settlement: compute PnL
        // If currentRate > fwd.rate: buyer profits (they locked a cheaper rate)
        // PnL in quote = baseAmount * (currentRate - fwd.rate) / PRECISION
        uint256 pnlQuote;
        uint256 pnlBase;

        if (currentRate >= fwd.rate) {
            // Buyer profits
            pnlQuote = (fwd.baseAmount * (currentRate - fwd.rate)) / PRECISION;

            // Fee on profit
            uint256 fee = (pnlQuote * settlementFeeBps) / BPS;

            // Pay buyer from seller's collateral (converted)
            // Seller's base collateral converted to quote at current rate
            uint256 sellerCollateralInQuote = (fwd.sellerCollateral * currentRate) / PRECISION;

            uint256 buyerPayout = pnlQuote - fee;
            if (buyerPayout > sellerCollateralInQuote) {
                buyerPayout = sellerCollateralInQuote;
            }

            // Return buyer collateral + profit (in quote)
            IERC20(pair.quote).safeTransfer(fwd.buyer, fwd.buyerCollateral + buyerPayout);

            // Return remaining seller collateral (in base)
            uint256 sellerBaseUsed = (buyerPayout * PRECISION) / currentRate;
            if (fwd.sellerCollateral > sellerBaseUsed) {
                IERC20(pair.base).safeTransfer(fwd.seller, fwd.sellerCollateral - sellerBaseUsed);
            }

            // Fee
            if (fee > 0 && feeReceiver != address(0)) {
                IERC20(pair.quote).safeTransfer(feeReceiver, fee);
            }

            pnlBase = 0;
        } else {
            // Seller profits
            pnlQuote = (fwd.baseAmount * (fwd.rate - currentRate)) / PRECISION;

            uint256 fee = (pnlQuote * settlementFeeBps) / BPS;

            uint256 sellerPayout = pnlQuote - fee;
            if (sellerPayout > fwd.buyerCollateral) {
                sellerPayout = fwd.buyerCollateral;
            }

            // Return seller collateral (in base)
            IERC20(pair.base).safeTransfer(fwd.seller, fwd.sellerCollateral);

            // Pay seller from buyer's collateral + return remainder to buyer (in quote)
            IERC20(pair.quote).safeTransfer(fwd.seller, sellerPayout);
            uint256 buyerRemainder = fwd.buyerCollateral - sellerPayout;
            if (buyerRemainder > 0) {
                IERC20(pair.quote).safeTransfer(fwd.buyer, buyerRemainder);
            }

            // Fee
            if (fee > 0 && feeReceiver != address(0)) {
                IERC20(pair.quote).safeTransfer(feeReceiver, fee);
            }

            pnlBase = 0;
        }

        fwd.status = ForwardStatus.SETTLED;
        fwd.buyerCollateral = 0;
        fwd.sellerCollateral = 0;

        emit ForwardSettled(forwardId, currentRate, pnlBase, pnlQuote);
    }

    /// @inheritdoc IForexForward
    function cancelForward(uint256 forwardId) external override nonReentrant {
        Forward storage fwd = forwards[forwardId];
        if (fwd.buyer == address(0)) revert ForwardNotFound();
        if (fwd.status != ForwardStatus.OPEN) revert ForwardNotOpen();
        if (msg.sender != fwd.buyer) revert NotParty();

        IForexPair.FXPair memory pair = forexPair.getPair(fwd.pairId);

        // Return buyer collateral
        uint256 collateral = fwd.buyerCollateral;
        fwd.buyerCollateral = 0;
        fwd.status = ForwardStatus.CANCELLED;

        IERC20(pair.quote).safeTransfer(fwd.buyer, collateral);

        emit ForwardCancelled(forwardId);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // COLLATERAL MANAGEMENT
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice Top up collateral on an active forward
    /// @param forwardId The forward ID
    /// @param amount Additional collateral amount
    function topUpCollateral(uint256 forwardId, uint256 amount) external nonReentrant {
        if (amount == 0) revert ZeroAmount();

        Forward storage fwd = forwards[forwardId];
        if (fwd.buyer == address(0)) revert ForwardNotFound();
        if (fwd.status != ForwardStatus.ACTIVE) revert ForwardNotActive();

        IForexPair.FXPair memory pair = forexPair.getPair(fwd.pairId);

        if (msg.sender == fwd.buyer) {
            IERC20(pair.quote).safeTransferFrom(msg.sender, address(this), amount);
            fwd.buyerCollateral += amount;
        } else if (msg.sender == fwd.seller) {
            IERC20(pair.base).safeTransferFrom(msg.sender, address(this), amount);
            fwd.sellerCollateral += amount;
        } else {
            revert NotParty();
        }

        emit CollateralToppedUp(forwardId, msg.sender, amount);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // KEEPER FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice Batch settle mature forwards
    /// @param forwardIds Array of forward IDs to settle
    function batchSettle(uint256[] calldata forwardIds) external onlyRole(KEEPER_ROLE) {
        for (uint256 i = 0; i < forwardIds.length; i++) {
            Forward storage fwd = forwards[forwardIds[i]];
            if (fwd.status == ForwardStatus.ACTIVE && block.timestamp >= fwd.maturityDate) {
                // Re-enter settleForward logic inline to avoid external call
                _settleInternal(forwardIds[i]);
            }
        }
    }

    // ═══════════════════════════════════════════════════════════════════════
    // VIEW FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════

    /// @inheritdoc IForexForward
    function getForward(uint256 forwardId) external view override returns (Forward memory) {
        return forwards[forwardId];
    }

    /// @notice Calculate current mark-to-market PnL for a forward
    /// @param forwardId The forward ID
    /// @return buyerPnl Buyer's unrealized PnL in quote (negative if loss)
    /// @return sellerPnl Seller's unrealized PnL in quote (negative if loss)
    function getMarkToMarket(uint256 forwardId) external view returns (int256 buyerPnl, int256 sellerPnl) {
        Forward storage fwd = forwards[forwardId];
        if (fwd.status != ForwardStatus.ACTIVE) return (0, 0);

        IForexPair.FXPair memory pair = forexPair.getPair(fwd.pairId);
        (uint256 currentRate,) = oracle.getRate(pair.base, pair.quote);

        if (currentRate >= fwd.rate) {
            uint256 profit = (fwd.baseAmount * (currentRate - fwd.rate)) / PRECISION;
            buyerPnl = int256(profit);
            sellerPnl = -int256(profit);
        } else {
            uint256 loss = (fwd.baseAmount * (fwd.rate - currentRate)) / PRECISION;
            buyerPnl = -int256(loss);
            sellerPnl = int256(loss);
        }
    }

    // ═══════════════════════════════════════════════════════════════════════
    // ADMIN FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════

    function setOracle(address _oracle) external onlyRole(ADMIN_ROLE) {
        if (_oracle == address(0)) revert InvalidOracle();
        oracle = IPriceOracle(_oracle);
        emit OracleUpdated(_oracle);
    }

    function setCollateralRatio(uint256 _ratioBps) external onlyRole(ADMIN_ROLE) {
        collateralRatioBps = _ratioBps;
    }

    function setFeeReceiver(address _feeReceiver) external onlyRole(ADMIN_ROLE) {
        feeReceiver = _feeReceiver;
    }

    function setSettlementFeeBps(uint256 _feeBps) external onlyRole(ADMIN_ROLE) {
        settlementFeeBps = _feeBps;
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

    /// @dev Internal settlement logic (used by both settleForward and batchSettle)
    function _settleInternal(uint256 forwardId) internal {
        Forward storage fwd = forwards[forwardId];

        IForexPair.FXPair memory pair = forexPair.getPair(fwd.pairId);
        (uint256 currentRate,) = oracle.getRate(pair.base, pair.quote);

        if (currentRate >= fwd.rate) {
            uint256 pnlQuote = (fwd.baseAmount * (currentRate - fwd.rate)) / PRECISION;
            uint256 fee = (pnlQuote * settlementFeeBps) / BPS;

            uint256 sellerCollateralInQuote = (fwd.sellerCollateral * currentRate) / PRECISION;
            uint256 buyerPayout = pnlQuote - fee;
            if (buyerPayout > sellerCollateralInQuote) {
                buyerPayout = sellerCollateralInQuote;
            }

            IERC20(pair.quote).safeTransfer(fwd.buyer, fwd.buyerCollateral + buyerPayout);

            uint256 sellerBaseUsed = (buyerPayout * PRECISION) / currentRate;
            if (fwd.sellerCollateral > sellerBaseUsed) {
                IERC20(pair.base).safeTransfer(fwd.seller, fwd.sellerCollateral - sellerBaseUsed);
            }

            if (fee > 0 && feeReceiver != address(0)) {
                IERC20(pair.quote).safeTransfer(feeReceiver, fee);
            }
        } else {
            uint256 pnlQuote = (fwd.baseAmount * (fwd.rate - currentRate)) / PRECISION;
            uint256 fee = (pnlQuote * settlementFeeBps) / BPS;

            uint256 sellerPayout = pnlQuote - fee;
            if (sellerPayout > fwd.buyerCollateral) {
                sellerPayout = fwd.buyerCollateral;
            }

            IERC20(pair.base).safeTransfer(fwd.seller, fwd.sellerCollateral);
            IERC20(pair.quote).safeTransfer(fwd.seller, sellerPayout);

            uint256 buyerRemainder = fwd.buyerCollateral - sellerPayout;
            if (buyerRemainder > 0) {
                IERC20(pair.quote).safeTransfer(fwd.buyer, buyerRemainder);
            }

            if (fee > 0 && feeReceiver != address(0)) {
                IERC20(pair.quote).safeTransfer(feeReceiver, fee);
            }
        }

        fwd.status = ForwardStatus.SETTLED;
        fwd.buyerCollateral = 0;
        fwd.sellerCollateral = 0;

        emit ForwardSettled(forwardId, currentRate, 0, 0);
    }
}
