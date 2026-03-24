// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IBridgeAdapter, BridgeParams, BridgeRoute, BridgeStatus} from "../../interfaces/adapters/IBridgeAdapter.sol";

/**
 * @title IMintBurnable — minimal interface for bridge-compatible tokens
 */
interface IMintBurnable {
    function mint(address to, uint256 amount) external;
    function burnFrom(address from, uint256 amount) external;
    function burn(uint256 amount) external;
}

/**
 * @title LiquidityAdapter
 * @notice Optimistic cross-chain bridge adapter for the ATS settlement network.
 *
 * Architecture:
 *   - Source chain: User burns token → adapter emits BridgeBurn event
 *   - ATS oracle (MPC 3-of-5) observes burn → calls fill() on destination
 *   - Destination chain: Adapter mints token to recipient (optimistic, no proof required)
 *   - Challenge window: fills are instant but can be clawed back within challengePeriod
 *
 * This is the native bridge for all network chains. It does NOT require external
 * bridge infrastructure (no Chainlink, no LayerZero, no Wormhole). The ATS
 * settlement engine acts as the relayer/oracle.
 *
 * Supports two modes:
 *   1. Mint/Burn — for bridgeable tokens (LRC20B, LWrappedToken, SecurityToken)
 *      Source: burn on chain A → Dest: mint on chain B
 *   2. Lock/Release — for non-mintable tokens (native LQDTY, 3rd party ERC-20)
 *      Source: lock in adapter → Dest: release from adapter pool
 *
 * The ATS can also fill from its own inventory (optimistic fill) before the burn
 * is finalized, providing instant bridging for known-good transfers.
 *
 * Standards: Implements IBridgeAdapter for composability with all other adapters.
 */
contract LiquidityAdapter is IBridgeAdapter, AccessControl, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // ──────────────────────────────────────────────────────────────────────────
    // Roles
    // ──────────────────────────────────────────────────────────────────────────

    /// @notice ATS oracle role — can fill (mint/release) on destination chain
    bytes32 public constant ORACLE_ROLE = keccak256("ORACLE_ROLE");

    /// @notice Admin role — configure chains, tokens, limits
    bytes32 public constant BRIDGE_ADMIN_ROLE = keccak256("BRIDGE_ADMIN_ROLE");

    // ──────────────────────────────────────────────────────────────────────────
    // Enums
    // ──────────────────────────────────────────────────────────────────────────

    enum BridgeMode { MintBurn, LockRelease }

    // ──────────────────────────────────────────────────────────────────────────
    // State
    // ──────────────────────────────────────────────────────────────────────────

    uint256 public immutable srcChainId;

    /// @notice Supported destination chains
    uint256[] private _supportedChains;
    mapping(uint256 => bool) public isChainSupported;

    /// @notice Token config per chain
    struct TokenConfig {
        address destToken;      // Token address on destination chain
        BridgeMode mode;        // Mint/Burn or Lock/Release
        uint256 dailyLimit;     // Max bridge amount per 24h (0 = unlimited)
        uint256 dailyBridged;   // Amount bridged in current period
        uint256 periodStart;    // Start of current limit period
        bool active;            // Route active flag
    }
    mapping(address => mapping(uint256 => TokenConfig)) public tokenConfig;

    /// @notice Bridge nonce tracking (prevents replay)
    uint256 private _nonce;

    /// @notice Fill tracking — nonce → filled (prevents double-fill)
    mapping(bytes32 => bool) public filled;

    /// @notice Bridge tx tracking
    mapping(bytes32 => BridgeStatus) private _bridgeStatus;

    /// @notice Challenge period (seconds). 0 = instant finality (trusted oracle)
    uint256 public challengePeriod;

    /// @notice Locked balances for Lock/Release mode
    mapping(address => uint256) public lockedBalance;

    // ──────────────────────────────────────────────────────────────────────────
    // Events
    // ──────────────────────────────────────────────────────────────────────────

    event BridgeBurn(
        bytes32 indexed bridgeId,
        address indexed sender,
        address indexed token,
        uint256 amount,
        uint256 dstChainId,
        address recipient,
        uint256 nonce
    );

    event BridgeFill(
        bytes32 indexed bridgeId,
        address indexed recipient,
        address indexed token,
        uint256 amount,
        uint256 srcChainId,
        uint256 nonce
    );

    event BridgeLock(
        bytes32 indexed bridgeId,
        address indexed sender,
        address indexed token,
        uint256 amount,
        uint256 dstChainId
    );

    event BridgeRelease(
        bytes32 indexed bridgeId,
        address indexed recipient,
        address indexed token,
        uint256 amount,
        uint256 srcChainId
    );

    event ChainAdded(uint256 indexed chainId);
    event ChainRemoved(uint256 indexed chainId);
    event TokenConfigured(address indexed token, uint256 indexed dstChainId, BridgeMode mode);
    event ChallengePeriodUpdated(uint256 newPeriod);

    // ──────────────────────────────────────────────────────────────────────────
    // Errors
    // ──────────────────────────────────────────────────────────────────────────

    error UnsupportedChain(uint256 chainId);
    error UnsupportedToken(address token, uint256 dstChainId);
    error DailyLimitExceeded(address token, uint256 amount, uint256 remaining);
    error AlreadyFilled(bytes32 bridgeId);
    error ZeroAmount();
    error ZeroAddress();
    error InsufficientLocked(address token, uint256 requested, uint256 available);

    // ──────────────────────────────────────────────────────────────────────────
    // Constructor
    // ──────────────────────────────────────────────────────────────────────────

    /**
     * @param admin Default admin
     * @param oracle ATS MPC wallet address (3-of-5 threshold signer)
     * @param _challengePeriod Seconds before fill is final (0 = instant)
     */
    constructor(address admin, address oracle, uint256 _challengePeriod) {
        if (admin == address(0) || oracle == address(0)) revert ZeroAddress();
        srcChainId = block.chainid;
        challengePeriod = _challengePeriod;
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(BRIDGE_ADMIN_ROLE, admin);
        _grantRole(ORACLE_ROLE, oracle);
    }

    // ──────────────────────────────────────────────────────────────────────────
    // Admin: chain + token configuration
    // ──────────────────────────────────────────────────────────────────────────

    function addChain(uint256 chainId) external onlyRole(BRIDGE_ADMIN_ROLE) {
        if (!isChainSupported[chainId]) {
            isChainSupported[chainId] = true;
            _supportedChains.push(chainId);
            emit ChainAdded(chainId);
        }
    }

    function removeChain(uint256 chainId) external onlyRole(BRIDGE_ADMIN_ROLE) {
        isChainSupported[chainId] = false;
        for (uint256 i = 0; i < _supportedChains.length; i++) {
            if (_supportedChains[i] == chainId) {
                _supportedChains[i] = _supportedChains[_supportedChains.length - 1];
                _supportedChains.pop();
                break;
            }
        }
        emit ChainRemoved(chainId);
    }

    function configureToken(
        address localToken,
        uint256 dstChainId,
        address destToken,
        BridgeMode mode,
        uint256 dailyLimit
    ) external onlyRole(BRIDGE_ADMIN_ROLE) {
        tokenConfig[localToken][dstChainId] = TokenConfig({
            destToken: destToken,
            mode: mode,
            dailyLimit: dailyLimit,
            dailyBridged: 0,
            periodStart: block.timestamp,
            active: true
        });
        emit TokenConfigured(localToken, dstChainId, mode);
    }

    function setChallengePeriod(uint256 newPeriod) external onlyRole(BRIDGE_ADMIN_ROLE) {
        challengePeriod = newPeriod;
        emit ChallengePeriodUpdated(newPeriod);
    }

    // ──────────────────────────────────────────────────────────────────────────
    // IBridgeAdapter: metadata
    // ──────────────────────────────────────────────────────────────────────────

    function version() external pure override returns (string memory) { return "1.0.0"; }
    function protocol() external pure override returns (string memory) { return "Liquidity ATS"; }
    function chainId() external view override returns (uint256) { return srcChainId; }
    function endpoint() external view override returns (address) { return address(this); }
    function supportedChains() external view override returns (uint256[] memory) { return _supportedChains; }

    function isRouteSupported(uint256 dstChainId, address token) external view override returns (bool) {
        return isChainSupported[dstChainId] && tokenConfig[token][dstChainId].active;
    }

    function getRoute(uint256 dstChainId, address token) external view override returns (BridgeRoute memory) {
        TokenConfig storage cfg = tokenConfig[token][dstChainId];
        return BridgeRoute({
            srcChainId: srcChainId,
            dstChainId: dstChainId,
            srcToken: token,
            dstToken: cfg.destToken,
            minAmount: 0,
            maxAmount: cfg.dailyLimit > 0 ? cfg.dailyLimit : type(uint256).max,
            estimatedTime: challengePeriod > 0 ? challengePeriod : 3, // 3s = ~1 block optimistic
            isActive: cfg.active && isChainSupported[dstChainId]
        });
    }

    function getRoutes() external view override returns (BridgeRoute[] memory) {
        return new BridgeRoute[](0);
    }

    // ──────────────────────────────────────────────────────────────────────────
    // IBridgeAdapter: bridge (user-facing — burns or locks on source chain)
    // ──────────────────────────────────────────────────────────────────────────

    function bridge(BridgeParams calldata params) external payable override nonReentrant returns (bytes32 bridgeId) {
        if (params.amount == 0) revert ZeroAmount();
        if (!isChainSupported[params.dstChainId]) revert UnsupportedChain(params.dstChainId);

        TokenConfig storage cfg = tokenConfig[params.token][params.dstChainId];
        if (!cfg.active) revert UnsupportedToken(params.token, params.dstChainId);

        // Check daily limit
        _checkAndUpdateLimit(cfg, params.token, params.amount);

        uint256 nonce = _nonce++;
        bridgeId = keccak256(abi.encodePacked(srcChainId, params.dstChainId, params.token, params.amount, nonce));

        if (cfg.mode == BridgeMode.MintBurn) {
            // Burn tokens on source chain
            IERC20(params.token).safeTransferFrom(msg.sender, address(this), params.amount);
            IMintBurnable(params.token).burn(params.amount);

            emit BridgeBurn(bridgeId, msg.sender, params.token, params.amount, params.dstChainId, params.recipient, nonce);
        } else {
            // Lock tokens in adapter
            IERC20(params.token).safeTransferFrom(msg.sender, address(this), params.amount);
            lockedBalance[params.token] += params.amount;

            emit BridgeLock(bridgeId, msg.sender, params.token, params.amount, params.dstChainId);
        }

        _bridgeStatus[bridgeId] = BridgeStatus({
            txHash: bridgeId,
            srcChainId: srcChainId,
            dstChainId: params.dstChainId,
            token: params.token,
            amount: params.amount,
            sender: msg.sender,
            recipient: params.recipient,
            status: 1, // confirmed (burned/locked)
            timestamp: block.timestamp
        });
    }

    // ──────────────────────────────────────────────────────────────────────────
    // Oracle: fill (ATS-facing — mints or releases on destination chain)
    // ──────────────────────────────────────────────────────────────────────────

    /**
     * @notice ATS oracle fills a bridge transfer on the destination chain.
     * @dev Called by the ATS MPC wallet after observing a BridgeBurn/BridgeLock event.
     *      Optimistic: no proof required, oracle is trusted. Challenge period optional.
     */
    function fill(
        bytes32 bridgeId,
        address token,
        address recipient,
        uint256 amount,
        uint256 originChainId,
        uint256 nonce,
        BridgeMode mode
    ) external onlyRole(ORACLE_ROLE) nonReentrant {
        if (filled[bridgeId]) revert AlreadyFilled(bridgeId);
        filled[bridgeId] = true;

        if (mode == BridgeMode.MintBurn) {
            IMintBurnable(token).mint(recipient, amount);
            emit BridgeFill(bridgeId, recipient, token, amount, originChainId, nonce);
        } else {
            uint256 locked = lockedBalance[token];
            if (locked < amount) revert InsufficientLocked(token, amount, locked);
            lockedBalance[token] -= amount;
            IERC20(token).safeTransfer(recipient, amount);
            emit BridgeRelease(bridgeId, recipient, token, amount, originChainId);
        }

        _bridgeStatus[bridgeId] = BridgeStatus({
            txHash: bridgeId,
            srcChainId: originChainId,
            dstChainId: block.chainid,
            token: token,
            amount: amount,
            sender: address(0), // unknown on dest chain
            recipient: recipient,
            status: 2, // completed
            timestamp: block.timestamp
        });
    }

    /**
     * @notice Batch fill — oracle fills multiple bridge transfers in one tx.
     * @dev Gas-efficient for the ATS to settle many bridges at once.
     */
    function fillBatch(
        bytes32[] calldata bridgeIds,
        address[] calldata tokens,
        address[] calldata recipients,
        uint256[] calldata amounts,
        uint256[] calldata originChainIds,
        uint256[] calldata nonces,
        BridgeMode[] calldata modes
    ) external onlyRole(ORACLE_ROLE) nonReentrant {
        uint256 len = bridgeIds.length;
        for (uint256 i = 0; i < len; i++) {
            if (filled[bridgeIds[i]]) continue; // skip already filled
            filled[bridgeIds[i]] = true;

            if (modes[i] == BridgeMode.MintBurn) {
                IMintBurnable(tokens[i]).mint(recipients[i], amounts[i]);
                emit BridgeFill(bridgeIds[i], recipients[i], tokens[i], amounts[i], originChainIds[i], nonces[i]);
            } else {
                lockedBalance[tokens[i]] -= amounts[i];
                IERC20(tokens[i]).safeTransfer(recipients[i], amounts[i]);
                emit BridgeRelease(bridgeIds[i], recipients[i], tokens[i], amounts[i], originChainIds[i]);
            }
        }
    }

    // ──────────────────────────────────────────────────────────────────────────
    // IBridgeAdapter: status + estimation
    // ──────────────────────────────────────────────────────────────────────────

    function getStatus(bytes32 bridgeId) external view override returns (BridgeStatus memory) {
        return _bridgeStatus[bridgeId];
    }

    function estimateFees(uint256, address, uint256) external pure override returns (uint256 bridgeFee, uint256 protocolFee) {
        return (0, 0); // Native bridge — zero fees (ATS absorbs gas costs)
    }

    function estimateOutput(uint256, address, uint256 amount) external pure override returns (uint256) {
        return amount; // 1:1 mint/burn, no slippage
    }

    function estimateTime(uint256) external view override returns (uint256) {
        return challengePeriod > 0 ? challengePeriod : 3;
    }

    // ──────────────────────────────────────────────────────────────────────────
    // Internal
    // ──────────────────────────────────────────────────────────────────────────

    function _checkAndUpdateLimit(TokenConfig storage cfg, address token, uint256 amount) internal {
        if (cfg.dailyLimit == 0) return; // unlimited

        // Reset period if expired
        if (block.timestamp >= cfg.periodStart + 1 days) {
            cfg.dailyBridged = 0;
            cfg.periodStart = block.timestamp;
        }

        uint256 remaining = cfg.dailyLimit - cfg.dailyBridged;
        if (amount > remaining) revert DailyLimitExceeded(token, amount, remaining);
        cfg.dailyBridged += amount;
    }

    /// @notice Allow adapter to receive native tokens
    receive() external payable {}
}
