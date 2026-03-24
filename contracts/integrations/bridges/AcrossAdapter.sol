// SPDX-License-Identifier: MIT
pragma solidity ^0.8.31;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IBridgeAdapter, BridgeParams, BridgeRoute, BridgeStatus} from "../../interfaces/adapters/IBridgeAdapter.sol";

// =============================================================================
// ACROSS PROTOCOL INTERFACES
// =============================================================================

/// @notice Across V3 SpokePool interface for deposit and relay
interface ISpokePool {
    function depositV3(
        address depositor,
        address recipient,
        address inputToken,
        address outputToken,
        uint256 inputAmount,
        uint256 outputAmount,
        uint256 destinationChainId,
        address exclusiveRelayer,
        uint32 quoteTimestamp,
        uint32 fillDeadline,
        uint32 exclusivityDeadline,
        bytes calldata message
    ) external payable;

    function getCurrentTime() external view returns (uint256);
}

// =============================================================================
// ACROSS ADAPTER IMPLEMENTATION
// =============================================================================

/**
 * @title AcrossAdapter
 * @notice Across V3 bridge adapter implementing IBridgeAdapter.
 *
 * Deposits tokens into the Across SpokePool on the source chain. Across
 * relayers fill the order on the destination chain and are repaid from the
 * HubPool liquidity on L1.
 *
 * Architecture:
 *   Source chain: AcrossAdapter.bridge() -> ISpokePool.depositV3()
 *   Relay:        Across relayers fill on destination
 *   Settlement:   HubPool settles relayer repayments on L1
 *
 * Fees: Relayer fee is deducted from the output amount (configurable bps).
 */
contract AcrossAdapter is IBridgeAdapter, AccessControl, ReentrancyGuard {
    using SafeERC20 for IERC20;

    bytes32 public constant BRIDGE_ADMIN_ROLE = keccak256("BRIDGE_ADMIN_ROLE");

    // -------------------------------------------------------------------------
    // State
    // -------------------------------------------------------------------------

    ISpokePool public immutable spokePool;
    uint256 public immutable srcChainId;

    /// @notice Set of supported destination chain IDs
    mapping(uint256 => bool) public isSupportedChain;

    /// @notice Supported destination chain IDs list
    uint256[] private _supportedChains;

    /// @notice Token mapping: local token -> (destChainId -> dest token)
    mapping(address => mapping(uint256 => address)) public tokenMapping;

    /// @notice Bridge tx tracking
    mapping(bytes32 => BridgeStatus) private _bridgeStatus;
    uint256 private _nonce;

    /// @notice Fill deadline offset from current time (seconds)
    uint32 public defaultFillDeadlineOffset = 7200; // 2 hours

    /// @notice Relayer fee in basis points (10 = 0.1%)
    uint256 public defaultRelayerFeeBps = 10;

    // -------------------------------------------------------------------------
    // Events
    // -------------------------------------------------------------------------

    event ChainAdded(uint256 indexed chainId);
    event ChainRemoved(uint256 indexed chainId);
    event TokenMapped(address indexed localToken, uint256 indexed destChainId, address destToken);

    // -------------------------------------------------------------------------
    // Errors
    // -------------------------------------------------------------------------

    error UnsupportedChain(uint256 chainId);
    error UnsupportedToken(address token, uint256 destChainId);
    error BelowMinOutput(uint256 output, uint256 minOutput);
    error ZeroAmount();
    error ZeroAddress();

    // -------------------------------------------------------------------------
    // Constructor
    // -------------------------------------------------------------------------

    constructor(address _spokePool, address admin) {
        if (_spokePool == address(0) || admin == address(0)) revert ZeroAddress();
        spokePool = ISpokePool(_spokePool);
        srcChainId = block.chainid;
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(BRIDGE_ADMIN_ROLE, admin);
    }

    // -------------------------------------------------------------------------
    // Admin: chain + token configuration
    // -------------------------------------------------------------------------

    function addChain(uint256 _chainId) external onlyRole(BRIDGE_ADMIN_ROLE) {
        isSupportedChain[_chainId] = true;
        _supportedChains.push(_chainId);
        emit ChainAdded(_chainId);
    }

    function removeChain(uint256 _chainId) external onlyRole(BRIDGE_ADMIN_ROLE) {
        isSupportedChain[_chainId] = false;
        emit ChainRemoved(_chainId);
    }

    function setTokenMapping(address localToken, uint256 destChainId, address destToken) external onlyRole(BRIDGE_ADMIN_ROLE) {
        tokenMapping[localToken][destChainId] = destToken;
        emit TokenMapped(localToken, destChainId, destToken);
    }

    function setFillDeadlineOffset(uint32 offset) external onlyRole(BRIDGE_ADMIN_ROLE) {
        defaultFillDeadlineOffset = offset;
    }

    function setRelayerFeeBps(uint256 bps) external onlyRole(BRIDGE_ADMIN_ROLE) {
        defaultRelayerFeeBps = bps;
    }

    // -------------------------------------------------------------------------
    // IBridgeAdapter: metadata
    // -------------------------------------------------------------------------

    function version() external pure override returns (string memory) { return "1.0.0"; }
    function protocol() external pure override returns (string memory) { return "Across V3"; }
    function chainId() external view override returns (uint256) { return srcChainId; }
    function endpoint() external view override returns (address) { return address(spokePool); }
    function supportedChains() external view override returns (uint256[] memory) { return _supportedChains; }

    function isRouteSupported(uint256 dstChainId, address token) external view override returns (bool) {
        return isSupportedChain[dstChainId] && tokenMapping[token][dstChainId] != address(0);
    }

    function getRoute(uint256 dstChainId, address token) external view override returns (BridgeRoute memory) {
        bool active = isSupportedChain[dstChainId] && tokenMapping[token][dstChainId] != address(0);
        return BridgeRoute({
            srcChainId: srcChainId,
            dstChainId: dstChainId,
            srcToken: token,
            dstToken: tokenMapping[token][dstChainId],
            minAmount: 0,
            maxAmount: type(uint256).max,
            estimatedTime: 120, // ~2 min Across relay
            isActive: active
        });
    }

    function getRoutes() external pure override returns (BridgeRoute[] memory) {
        return new BridgeRoute[](0);
    }

    // -------------------------------------------------------------------------
    // IBridgeAdapter: bridge
    // -------------------------------------------------------------------------

    function bridge(BridgeParams calldata params) external payable override nonReentrant returns (bytes32 bridgeId) {
        if (params.amount == 0) revert ZeroAmount();
        if (!isSupportedChain[params.dstChainId]) revert UnsupportedChain(params.dstChainId);

        address destToken = tokenMapping[params.token][params.dstChainId];
        if (destToken == address(0)) revert UnsupportedToken(params.token, params.dstChainId);

        // Calculate output amount after relayer fee
        uint256 outputAmount = params.amount - (params.amount * defaultRelayerFeeBps / 10_000);
        if (outputAmount < params.minAmountOut) revert BelowMinOutput(outputAmount, params.minAmountOut);

        // Transfer tokens from sender to this contract
        IERC20(params.token).safeTransferFrom(msg.sender, address(this), params.amount);

        // Approve SpokePool to spend tokens
        IERC20(params.token).forceApprove(address(spokePool), params.amount);

        // Calculate fill deadline
        uint32 fillDeadline = uint32(block.timestamp) + defaultFillDeadlineOffset;

        // Deposit via Across SpokePool
        spokePool.depositV3(
            msg.sender,                // depositor
            params.recipient,          // recipient
            params.token,              // inputToken
            destToken,                 // outputToken
            params.amount,             // inputAmount
            outputAmount,              // outputAmount
            params.dstChainId,         // destinationChainId
            address(0),                // exclusiveRelayer (none)
            uint32(block.timestamp),   // quoteTimestamp
            fillDeadline,              // fillDeadline
            0,                         // exclusivityDeadline
            params.extraData           // message
        );

        // Track bridge status
        bridgeId = keccak256(abi.encodePacked(block.timestamp, _nonce++, msg.sender));
        _bridgeStatus[bridgeId] = BridgeStatus({
            txHash: bridgeId,
            srcChainId: srcChainId,
            dstChainId: params.dstChainId,
            token: params.token,
            amount: params.amount,
            sender: msg.sender,
            recipient: params.recipient,
            status: 1, // confirmed (deposited to SpokePool)
            timestamp: block.timestamp
        });

        emit BridgeInitiated(bridgeId, msg.sender, srcChainId, params.dstChainId, params.token, params.amount);
    }

    function getStatus(bytes32 bridgeId) external view override returns (BridgeStatus memory) {
        return _bridgeStatus[bridgeId];
    }

    // -------------------------------------------------------------------------
    // IBridgeAdapter: estimation
    // -------------------------------------------------------------------------

    function estimateFees(uint256 dstChainId, address, uint256 amount)
        external view override returns (uint256 bridgeFee, uint256 protocolFee)
    {
        if (!isSupportedChain[dstChainId]) revert UnsupportedChain(dstChainId);
        bridgeFee = amount * defaultRelayerFeeBps / 10_000;
        protocolFee = 0;
    }

    function estimateOutput(uint256, address, uint256 amount) external view override returns (uint256) {
        return amount - (amount * defaultRelayerFeeBps / 10_000);
    }

    function estimateTime(uint256) external pure override returns (uint256) {
        return 120; // ~2 min Across relay
    }

    /// @notice Allow contract to receive native tokens
    receive() external payable {}
}
