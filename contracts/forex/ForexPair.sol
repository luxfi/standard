// SPDX-License-Identifier: MIT
pragma solidity ^0.8.31;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { AccessControl } from "@openzeppelin/contracts/access/AccessControl.sol";
import { Pausable } from "@openzeppelin/contracts/utils/Pausable.sol";
import { IForexPair } from "../interfaces/forex/IForexPair.sol";
import { IPriceOracle } from "../interfaces/oracle/IPriceOracle.sol";

/**
 * @title ForexPair
 * @author Lux Industries
 * @notice On-chain FX pair spot trading at oracle-determined rates
 * @dev Supports any ERC20 currency pair with oracle pricing
 *
 * Key features:
 * - Spot swaps base<->quote at real-time oracle rate
 * - Configurable tick size, min/max trade sizes per pair
 * - Jurisdiction-based compliance hooks (restrict/allow per pair)
 * - Slippage protection on all trades
 * - Trading fees in basis points
 */
contract ForexPair is IForexPair, ReentrancyGuard, AccessControl, Pausable {
    using SafeERC20 for IERC20;

    // ═══════════════════════════════════════════════════════════════════════
    // CONSTANTS
    // ═══════════════════════════════════════════════════════════════════════

    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant KEEPER_ROLE = keccak256("KEEPER_ROLE");
    bytes32 public constant COMPLIANCE_ROLE = keccak256("COMPLIANCE_ROLE");

    uint256 public constant PRECISION = 1e18;
    uint256 public constant BPS = 10000;

    // ═══════════════════════════════════════════════════════════════════════
    // STATE
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice Price oracle
    IPriceOracle public oracle;

    /// @notice Fee receiver
    address public feeReceiver;

    /// @notice Trading fee in basis points
    uint256 public tradeFeeBps = 10; // 0.1%

    /// @notice Maximum price staleness for trades
    uint256 public maxPriceAge = 5 minutes;

    /// @notice FX pairs by ID
    mapping(uint256 => FXPair) public pairs;

    /// @notice Pair ID lookup by (base, quote) hash
    mapping(bytes32 => uint256) public pairIndex;

    /// @notice Jurisdiction restrictions: keccak256(pairId, jurisdictionCode) => blocked
    mapping(bytes32 => bool) public jurisdictionBlocked;

    /// @notice Per-trader compliance check contract (0 = no check)
    address public complianceHook;

    /// @notice Next pair ID
    uint256 public nextPairId = 1;

    // ═══════════════════════════════════════════════════════════════════════
    // EVENTS (additional)
    // ═══════════════════════════════════════════════════════════════════════

    event OracleUpdated(address indexed oracle);
    event FeeUpdated(uint256 feeBps);
    event ComplianceHookUpdated(address indexed hook);
    event JurisdictionSet(uint256 indexed pairId, bytes32 indexed jurisdiction, bool blocked);

    // ═══════════════════════════════════════════════════════════════════════
    // ERRORS (additional)
    // ═══════════════════════════════════════════════════════════════════════

    error InvalidOracle();

    // ═══════════════════════════════════════════════════════════════════════
    // CONSTRUCTOR
    // ═══════════════════════════════════════════════════════════════════════

    constructor(address _oracle, address _feeReceiver, address _admin) {
        if (_oracle == address(0)) revert InvalidOracle();
        if (_admin == address(0)) revert ZeroAddress();

        oracle = IPriceOracle(_oracle);
        feeReceiver = _feeReceiver;

        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        _grantRole(ADMIN_ROLE, _admin);
        _grantRole(KEEPER_ROLE, _admin);
        _grantRole(COMPLIANCE_ROLE, _admin);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // PAIR MANAGEMENT
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice Create a new FX pair
    /// @param base Base currency token address
    /// @param quote Quote currency token address
    /// @param tickSize Minimum price increment (18 decimals)
    /// @param minSize Minimum trade size in base (18 decimals)
    /// @param maxSize Maximum trade size in base (18 decimals)
    /// @return pairId New pair ID
    function createPair(address base, address quote, uint256 tickSize, uint256 minSize, uint256 maxSize)
        external
        onlyRole(ADMIN_ROLE)
        returns (uint256 pairId)
    {
        if (base == address(0) || quote == address(0)) revert ZeroAddress();
        if (tickSize == 0) revert InvalidTickSize();

        bytes32 key = _pairKey(base, quote);
        if (pairIndex[key] != 0) revert PairAlreadyExists();

        pairId = nextPairId++;

        pairs[pairId] =
            FXPair({ base: base, quote: quote, tickSize: tickSize, minSize: minSize, maxSize: maxSize, active: true });

        pairIndex[key] = pairId;

        emit PairCreated(pairId, base, quote);
    }

    /// @notice Update pair parameters
    function updatePair(uint256 pairId, uint256 tickSize, uint256 minSize, uint256 maxSize, bool active)
        external
        onlyRole(ADMIN_ROLE)
    {
        FXPair storage pair = pairs[pairId];
        if (pair.base == address(0)) revert PairNotFound();
        if (tickSize == 0) revert InvalidTickSize();

        pair.tickSize = tickSize;
        pair.minSize = minSize;
        pair.maxSize = maxSize;
        pair.active = active;

        emit PairUpdated(pairId, tickSize, minSize, maxSize, active);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // SPOT TRADING
    // ═══════════════════════════════════════════════════════════════════════

    /// @inheritdoc IForexPair
    function sellBase(uint256 pairId, uint256 baseAmount, uint256 minQuoteAmount)
        external
        override
        nonReentrant
        whenNotPaused
        returns (uint256 quoteAmount)
    {
        if (baseAmount == 0) revert ZeroAmount();

        FXPair storage pair = pairs[pairId];
        if (pair.base == address(0)) revert PairNotFound();
        if (!pair.active) revert PairNotActive();

        _checkSize(pair, baseAmount);
        _checkCompliance(msg.sender, pairId);

        // Get rate: how much quote per 1 base
        uint256 rate = oracle.getRateIfFresh(pair.base, pair.quote, maxPriceAge);

        // quoteAmount = baseAmount * rate / PRECISION
        quoteAmount = (baseAmount * rate) / PRECISION;

        // Apply fee
        uint256 fee = (quoteAmount * tradeFeeBps) / BPS;
        quoteAmount -= fee;

        if (quoteAmount < minQuoteAmount) revert SlippageExceeded();

        // Transfer base from trader
        IERC20(pair.base).safeTransferFrom(msg.sender, address(this), baseAmount);

        // Transfer quote to trader (from contract reserves)
        IERC20(pair.quote).safeTransfer(msg.sender, quoteAmount);

        // Transfer fee
        if (fee > 0 && feeReceiver != address(0)) {
            IERC20(pair.quote).safeTransfer(feeReceiver, fee);
        }

        emit SpotTrade(pairId, msg.sender, false, baseAmount, quoteAmount, rate);
    }

    /// @inheritdoc IForexPair
    function buyBase(uint256 pairId, uint256 quoteAmount, uint256 minBaseAmount)
        external
        override
        nonReentrant
        whenNotPaused
        returns (uint256 baseAmount)
    {
        if (quoteAmount == 0) revert ZeroAmount();

        FXPair storage pair = pairs[pairId];
        if (pair.base == address(0)) revert PairNotFound();
        if (!pair.active) revert PairNotActive();

        _checkCompliance(msg.sender, pairId);

        // Get rate: how much quote per 1 base
        uint256 rate = oracle.getRateIfFresh(pair.base, pair.quote, maxPriceAge);

        // Apply fee to quote first
        uint256 fee = (quoteAmount * tradeFeeBps) / BPS;
        uint256 netQuote = quoteAmount - fee;

        // baseAmount = netQuote * PRECISION / rate
        baseAmount = (netQuote * PRECISION) / rate;

        _checkSize(pair, baseAmount);

        if (baseAmount < minBaseAmount) revert SlippageExceeded();

        // Transfer quote from trader
        IERC20(pair.quote).safeTransferFrom(msg.sender, address(this), quoteAmount);

        // Transfer base to trader (from contract reserves)
        IERC20(pair.base).safeTransfer(msg.sender, baseAmount);

        // Transfer fee
        if (fee > 0 && feeReceiver != address(0)) {
            IERC20(pair.quote).safeTransfer(feeReceiver, fee);
        }

        emit SpotTrade(pairId, msg.sender, true, baseAmount, quoteAmount, rate);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // VIEW FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════

    /// @inheritdoc IForexPair
    function getPair(uint256 pairId) external view override returns (FXPair memory) {
        return pairs[pairId];
    }

    /// @inheritdoc IForexPair
    function getRate(uint256 pairId) external view override returns (uint256 rate, uint256 timestamp) {
        FXPair storage pair = pairs[pairId];
        if (pair.base == address(0)) revert PairNotFound();
        return oracle.getRate(pair.base, pair.quote);
    }

    /// @inheritdoc IForexPair
    function getPairId(address base, address quote) external view override returns (uint256) {
        return pairIndex[_pairKey(base, quote)];
    }

    // ═══════════════════════════════════════════════════════════════════════
    // COMPLIANCE
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice Set jurisdiction restriction for a pair
    /// @param pairId Pair ID
    /// @param jurisdiction Jurisdiction code hash (keccak256 of ISO country code)
    /// @param blocked True to block, false to allow
    function setJurisdiction(uint256 pairId, bytes32 jurisdiction, bool blocked) external onlyRole(COMPLIANCE_ROLE) {
        FXPair storage pair = pairs[pairId];
        if (pair.base == address(0)) revert PairNotFound();

        jurisdictionBlocked[keccak256(abi.encodePacked(pairId, jurisdiction))] = blocked;
        emit JurisdictionSet(pairId, jurisdiction, blocked);
    }

    /// @notice Set compliance hook contract address
    /// @param _hook Address of IComplianceHook contract (0 = disabled)
    function setComplianceHook(address _hook) external onlyRole(COMPLIANCE_ROLE) {
        complianceHook = _hook;
        emit ComplianceHookUpdated(_hook);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // ADMIN FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════

    function setOracle(address _oracle) external onlyRole(ADMIN_ROLE) {
        if (_oracle == address(0)) revert InvalidOracle();
        oracle = IPriceOracle(_oracle);
        emit OracleUpdated(_oracle);
    }

    function setFeeReceiver(address _feeReceiver) external onlyRole(ADMIN_ROLE) {
        feeReceiver = _feeReceiver;
    }

    function setTradeFeeBps(uint256 _feeBps) external onlyRole(ADMIN_ROLE) {
        tradeFeeBps = _feeBps;
        emit FeeUpdated(_feeBps);
    }

    function setMaxPriceAge(uint256 _maxAge) external onlyRole(ADMIN_ROLE) {
        maxPriceAge = _maxAge;
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

    function _pairKey(address base, address quote) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(base, quote));
    }

    function _checkSize(FXPair storage pair, uint256 amount) internal view {
        if (pair.minSize > 0 && amount < pair.minSize) revert BelowMinSize();
        if (pair.maxSize > 0 && amount > pair.maxSize) revert AboveMaxSize();
    }

    function _checkCompliance(address trader, uint256 pairId) internal view {
        if (complianceHook == address(0)) return;

        // Call compliance hook: canTrade(trader, pairId) returns (bool)
        (bool success, bytes memory data) =
            complianceHook.staticcall(abi.encodeWithSignature("canTrade(address,uint256)", trader, pairId));

        if (success && data.length >= 32) {
            bool allowed = abi.decode(data, (bool));
            if (!allowed) revert JurisdictionRestricted();
        }
    }
}
