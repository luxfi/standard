// SPDX-License-Identifier: MIT
pragma solidity ^0.8.31;

import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { SafeERC20, IERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { AccessControl } from "@openzeppelin/contracts/access/AccessControl.sol";
import { Pausable } from "@openzeppelin/contracts/utils/Pausable.sol";
import { ILiquidityOracle } from "../interfaces/ILiquidityOracle.sol";
import { ISecurityToken } from "../interfaces/ISecurityToken.sol";
import { IOracleMirroredAMM } from "../interfaces/IOracleMirroredAMM.sol";

/// @title OracleMirroredAMM
/// @author Lux Industries
/// @notice Oracle-priced AMM that mirrors real-world asset prices for on-chain trading.
///         Any chain deploys this to get instant access to oracle-backed markets.
///
/// @dev Architecture:
///      - Oracle provides real-time prices for symbols (equities, crypto, FX)
///      - Settlement account holds base token reserves (USDL or stablecoin)
///      - Buy: user sends base token -> settlement, AMM mints security token to user
///      - Sell: AMM burns security token from user, settlement sends base token to user
///      - Margin (spread) is applied on top of oracle price as protocol revenue
///      - Circuit breaker rejects price updates deviating >X% from previous
///
///      This is NOT a constant-product AMM. There is no liquidity pool or impermanent
///      loss. The oracle IS the price. The settlement account IS the counterparty.
contract OracleMirroredAMM is IOracleMirroredAMM, ReentrancyGuard, AccessControl, Pausable {
    using SafeERC20 for IERC20;

    // ═══════════════════════════════════════════════════════════════════════
    // CONSTANTS
    // ═══════════════════════════════════════════════════════════════════════

    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");

    uint256 public constant BPS = 10_000;
    uint256 public constant MAX_MARGIN_BPS = 500; // 5% cap
    uint256 public constant MAX_DEVIATION_CAP = 5000; // 50% cap on circuit breaker
    uint256 public constant MAX_STALENESS_CAP = 1 hours; // staleness cap

    // ═══════════════════════════════════════════════════════════════════════
    // IMMUTABLES
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice Oracle providing real-time prices
    ILiquidityOracle public immutable oracle;

    /// @notice Settlement account (ATS treasury) — receives base on buys, sends base on sells
    address public immutable settlementAccount;

    /// @notice Base token (USDL, USDC, or any stablecoin)
    IERC20 public immutable baseToken;

    // ═══════════════════════════════════════════════════════════════════════
    // STATE
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice Margin in basis points applied to oracle price (default 100 = 1%)
    uint256 public marginBps;

    /// @notice Maximum oracle staleness in seconds (default 10 for crypto)
    uint256 public maxStalenessSeconds;

    /// @notice Circuit breaker: reject price deviating >X% from last known (default 1000 = 10%)
    uint256 public maxDeviationBps;

    /// @notice Symbol hash -> SecurityToken address
    mapping(bytes32 => address) public tokens;

    /// @notice Last accepted price per symbol (for circuit breaker)
    mapping(bytes32 => uint256) public lastPrice;

    // ═══════════════════════════════════════════════════════════════════════
    // ERRORS
    // ═══════════════════════════════════════════════════════════════════════

    error ZeroAddress();
    error ZeroAmount();
    error SymbolNotRegistered(bytes32 symbolHash);
    error StaleOracle(uint256 age, uint256 maxAge);
    error PriceDeviationTooLarge(uint256 deviationBps, uint256 maxBps);
    error SlippageExceeded(uint256 amountOut, uint256 minAmountOut);
    error MarginTooHigh(uint256 marginBps, uint256 maxBps);
    error DeviationTooHigh(uint256 deviationBps, uint256 maxBps);
    error StalenessOutOfRange(uint256 staleness, uint256 maxCap);
    error SymbolAlreadyRegistered(bytes32 symbolHash);

    // ═══════════════════════════════════════════════════════════════════════
    // CONSTRUCTOR
    // ═══════════════════════════════════════════════════════════════════════

    /// @param _oracle Oracle contract providing price feeds
    /// @param _settlementAccount ATS treasury account
    /// @param _baseToken Base token for trading (USDL)
    /// @param _marginBps Initial margin in basis points (e.g., 100 = 1%)
    /// @param _maxStalenessSeconds Max oracle staleness (e.g., 10 for crypto)
    /// @param _maxDeviationBps Circuit breaker deviation (e.g., 1000 = 10%)
    /// @param admin Admin address
    constructor(
        address _oracle,
        address _settlementAccount,
        address _baseToken,
        uint256 _marginBps,
        uint256 _maxStalenessSeconds,
        uint256 _maxDeviationBps,
        address admin
    ) {
        if (_oracle == address(0)) revert ZeroAddress();
        if (_settlementAccount == address(0)) revert ZeroAddress();
        if (_baseToken == address(0)) revert ZeroAddress();
        if (admin == address(0)) revert ZeroAddress();
        if (_marginBps > MAX_MARGIN_BPS) revert MarginTooHigh(_marginBps, MAX_MARGIN_BPS);
        if (_maxDeviationBps > MAX_DEVIATION_CAP) revert DeviationTooHigh(_maxDeviationBps, MAX_DEVIATION_CAP);
        if (_maxStalenessSeconds > MAX_STALENESS_CAP) {
            revert StalenessOutOfRange(_maxStalenessSeconds, MAX_STALENESS_CAP);
        }

        oracle = ILiquidityOracle(_oracle);
        settlementAccount = _settlementAccount;
        baseToken = IERC20(_baseToken);
        marginBps = _marginBps;
        maxStalenessSeconds = _maxStalenessSeconds;
        maxDeviationBps = _maxDeviationBps;

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(ADMIN_ROLE, admin);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // SWAP
    // ═══════════════════════════════════════════════════════════════════════

    /// @inheritdoc IOracleMirroredAMM
    function swap(string calldata symbol, bool isBuy, uint256 amountIn, uint256 minAmountOut)
        external
        override
        nonReentrant
        whenNotPaused
        returns (uint256 amountOut)
    {
        if (amountIn == 0) revert ZeroAmount();

        bytes32 symHash = keccak256(bytes(symbol));
        address token = tokens[symHash];
        if (token == address(0)) revert SymbolNotRegistered(symHash);

        // Fetch and validate oracle price
        (uint256 oraclePrice, uint256 timestamp) = oracle.getPrice(symbol);
        uint256 age = block.timestamp - timestamp;
        if (age > maxStalenessSeconds) revert StaleOracle(age, maxStalenessSeconds);

        // Circuit breaker
        uint256 prev = lastPrice[symHash];
        if (prev > 0) {
            uint256 deviation =
                oraclePrice > prev ? ((oraclePrice - prev) * BPS / prev) : ((prev - oraclePrice) * BPS / prev);
            if (deviation > maxDeviationBps) revert PriceDeviationTooLarge(deviation, maxDeviationBps);
        }
        lastPrice[symHash] = oraclePrice;

        // Calculate execution price with margin
        uint256 execPrice;
        if (isBuy) {
            // Buy: user pays base token, receives security token
            // Higher price = user gets less token per dollar (margin is revenue)
            execPrice = oraclePrice * (BPS + marginBps) / BPS;
            // amountOut = amountIn / execPrice (base token in, security token out)
            amountOut = amountIn * 1e18 / execPrice;

            if (amountOut < minAmountOut) revert SlippageExceeded(amountOut, minAmountOut);

            baseToken.safeTransferFrom(msg.sender, settlementAccount, amountIn);
            ISecurityToken(token).mint(msg.sender, amountOut);
        } else {
            // Sell: user sends security token, receives base token
            // Lower price = user gets less base per token (margin is revenue)
            execPrice = oraclePrice * (BPS - marginBps) / BPS;
            // amountOut = amountIn * execPrice (security token in, base token out)
            amountOut = amountIn * execPrice / 1e18;

            if (amountOut < minAmountOut) revert SlippageExceeded(amountOut, minAmountOut);

            ISecurityToken(token).burnFrom(msg.sender, amountIn);
            baseToken.safeTransferFrom(settlementAccount, msg.sender, amountOut);
        }

        emit Swap(msg.sender, symHash, isBuy, amountIn, amountOut, execPrice);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // VIEW
    // ═══════════════════════════════════════════════════════════════════════

    /// @inheritdoc IOracleMirroredAMM
    function getExecutionPrice(string calldata symbol, bool isBuy)
        external
        view
        override
        returns (uint256 execPrice, uint256 oraclePrice)
    {
        (oraclePrice,) = oracle.getPrice(symbol);
        if (isBuy) {
            execPrice = oraclePrice * (BPS + marginBps) / BPS;
        } else {
            execPrice = oraclePrice * (BPS - marginBps) / BPS;
        }
    }

    /// @notice Get the token address for a registered symbol
    /// @param symbol The asset symbol
    /// @return token The SecurityToken address (address(0) if not registered)
    function getToken(string calldata symbol) external view returns (address token) {
        return tokens[keccak256(bytes(symbol))];
    }

    // ═══════════════════════════════════════════════════════════════════════
    // ADMIN
    // ═══════════════════════════════════════════════════════════════════════

    /// @inheritdoc IOracleMirroredAMM
    function registerSymbol(string calldata symbol, address token) external override onlyRole(ADMIN_ROLE) {
        if (token == address(0)) revert ZeroAddress();
        bytes32 symHash = keccak256(bytes(symbol));
        if (tokens[symHash] != address(0)) revert SymbolAlreadyRegistered(symHash);

        tokens[symHash] = token;
        emit SymbolRegistered(symHash, symbol, token);
    }

    /// @inheritdoc IOracleMirroredAMM
    function setMargin(uint256 newMarginBps) external override onlyRole(ADMIN_ROLE) {
        if (newMarginBps > MAX_MARGIN_BPS) revert MarginTooHigh(newMarginBps, MAX_MARGIN_BPS);
        uint256 oldMargin = marginBps;
        marginBps = newMarginBps;
        emit MarginUpdated(oldMargin, newMarginBps);
    }

    /// @notice Update the circuit breaker deviation threshold
    /// @param newDeviationBps New deviation in basis points
    function setMaxDeviation(uint256 newDeviationBps) external onlyRole(ADMIN_ROLE) {
        if (newDeviationBps > MAX_DEVIATION_CAP) revert DeviationTooHigh(newDeviationBps, MAX_DEVIATION_CAP);
        uint256 oldDeviation = maxDeviationBps;
        maxDeviationBps = newDeviationBps;
        emit MaxDeviationUpdated(oldDeviation, newDeviationBps);
    }

    /// @notice Update the oracle staleness threshold
    /// @param newStaleness New staleness in seconds
    function setMaxStaleness(uint256 newStaleness) external onlyRole(ADMIN_ROLE) {
        if (newStaleness > MAX_STALENESS_CAP) revert StalenessOutOfRange(newStaleness, MAX_STALENESS_CAP);
        uint256 oldStaleness = maxStalenessSeconds;
        maxStalenessSeconds = newStaleness;
        emit MaxStalenessUpdated(oldStaleness, newStaleness);
    }

    /// @notice Pause all swaps (emergency)
    function pause() external onlyRole(ADMIN_ROLE) {
        _pause();
    }

    /// @notice Unpause swaps
    function unpause() external onlyRole(ADMIN_ROLE) {
        _unpause();
    }
}
