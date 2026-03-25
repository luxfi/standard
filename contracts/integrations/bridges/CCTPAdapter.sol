// SPDX-License-Identifier: MIT
pragma solidity ^0.8.31;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { AccessControl } from "@openzeppelin/contracts/access/AccessControl.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { IBridgeAdapter, BridgeParams, BridgeRoute, BridgeStatus } from "../../interfaces/adapters/IBridgeAdapter.sol";

// ═══════════════════════════════════════════════════════════════════════════════
// CIRCLE CCTP INTERFACES
// ═══════════════════════════════════════════════════════════════════════════════

/// @notice Circle TokenMessenger interface for initiating USDC burns
interface ITokenMessenger {
    /// @notice Deposit USDC for burn on source chain and mint on destination
    /// @param amount Amount of USDC to burn
    /// @param destinationDomain CCTP destination domain
    /// @param mintRecipient Recipient address on destination (as bytes32)
    /// @param burnToken Address of the token to burn (USDC)
    /// @return nonce The nonce of the burn message
    function depositForBurn(uint256 amount, uint32 destinationDomain, bytes32 mintRecipient, address burnToken)
        external
        returns (uint64 nonce);

    /// @notice Deposit USDC for burn with a caller restriction on destination
    /// @param amount Amount of USDC to burn
    /// @param destinationDomain CCTP destination domain
    /// @param mintRecipient Recipient address on destination (as bytes32)
    /// @param burnToken Address of the token to burn (USDC)
    /// @param destinationCaller Authorized caller on destination (or bytes32(0) for any)
    /// @return nonce The nonce of the burn message
    function depositForBurnWithCaller(
        uint256 amount,
        uint32 destinationDomain,
        bytes32 mintRecipient,
        address burnToken,
        bytes32 destinationCaller
    ) external returns (uint64 nonce);

    /// @notice Get the local MessageTransmitter address
    function localMessageTransmitter() external view returns (address);
}

/// @notice Circle MessageTransmitter interface for receiving messages on destination
interface IMessageTransmitter {
    /// @notice Receive a message from another domain
    /// @param message The message bytes from the source domain
    /// @param attestation Circle attestation for the message
    /// @return success Whether the message was received successfully
    function receiveMessage(bytes calldata message, bytes calldata attestation) external returns (bool success);

    /// @notice Get the next available nonce for a domain
    function nextAvailableNonce() external view returns (uint64);
}

// ═══════════════════════════════════════════════════════════════════════════════
// CCTP ADAPTER IMPLEMENTATION
// ═══════════════════════════════════════════════════════════════════════════════

/**
 * @title CCTPAdapter
 * @notice Circle CCTP bridge adapter implementing IBridgeAdapter.
 *
 * Burns USDC on the source chain via TokenMessenger and mints native USDC
 * on the destination chain via MessageTransmitter attestation.
 *
 * Architecture:
 *   Source chain: CCTPAdapter.bridge() → ITokenMessenger.depositForBurn()
 *   Attestation:  Circle attestation service signs the burn message
 *   Dest chain:   IMessageTransmitter.receiveMessage() → USDC minted to recipient
 *
 * Domain IDs: CCTP uses uint32 domain IDs (NOT EVM chain IDs).
 *   Ethereum=0, Avalanche=1, Optimism=2, Arbitrum=3, Base=6, Polygon PoS=7
 *
 * USDC-only bridge: only supports USDC transfers, not arbitrary tokens.
 */
contract CCTPAdapter is IBridgeAdapter, AccessControl, ReentrancyGuard {
    using SafeERC20 for IERC20;

    bytes32 public constant BRIDGE_ADMIN_ROLE = keccak256("BRIDGE_ADMIN_ROLE");

    // ──────────────────────────────────────────────────────────────────────────
    // State
    // ──────────────────────────────────────────────────────────────────────────

    ITokenMessenger public immutable tokenMessenger;
    IMessageTransmitter public immutable messageTransmitter;
    uint256 public immutable srcChainId;

    /// @notice USDC token address on this chain
    address public immutable usdc;

    /// @notice EVM chain ID -> CCTP domain ID
    mapping(uint256 => uint32) public chainIdToDomain;
    /// @notice CCTP domain ID -> EVM chain ID
    mapping(uint32 => uint256) public domainToChainId;

    /// @notice Supported destination chain IDs
    uint256[] private _supportedChains;

    /// @notice USDC address on destination chains (for route info)
    mapping(uint256 => address) public destUsdc;

    /// @notice Bridge tx tracking
    mapping(bytes32 => BridgeStatus) private _bridgeStatus;
    uint256 private _nonce;

    // ──────────────────────────────────────────────────────────────────────────
    // Events
    // ──────────────────────────────────────────────────────────────────────────

    event ChainAdded(uint256 indexed chainId, uint32 domain);
    event DestUsdcSet(uint256 indexed chainId, address usdcAddr);
    event MessageReceived(bytes32 indexed messageHash);

    // ──────────────────────────────────────────────────────────────────────────
    // Errors
    // ──────────────────────────────────────────────────────────────────────────

    error UnsupportedChain(uint256 chainId);
    error UnsupportedToken(address token);
    error ZeroAmount();
    error ZeroAddress();
    error ReceiveFailed();

    // ──────────────────────────────────────────────────────────────────────────
    // Constructor
    // ──────────────────────────────────────────────────────────────────────────

    constructor(address _tokenMessenger, address _messageTransmitter, address _usdc, address admin) {
        if (
            _tokenMessenger == address(0) || _messageTransmitter == address(0) || _usdc == address(0)
                || admin == address(0)
        ) {
            revert ZeroAddress();
        }
        tokenMessenger = ITokenMessenger(_tokenMessenger);
        messageTransmitter = IMessageTransmitter(_messageTransmitter);
        usdc = _usdc;
        srcChainId = block.chainid;
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(BRIDGE_ADMIN_ROLE, admin);
    }

    // ──────────────────────────────────────────────────────────────────────────
    // Admin: chain configuration
    // ──────────────────────────────────────────────────────────────────────────

    function addChain(uint256 _chainId, uint32 _domain) external onlyRole(BRIDGE_ADMIN_ROLE) {
        chainIdToDomain[_chainId] = _domain;
        domainToChainId[_domain] = _chainId;
        _supportedChains.push(_chainId);
        emit ChainAdded(_chainId, _domain);
    }

    function setDestUsdc(uint256 _chainId, address _destUsdc) external onlyRole(BRIDGE_ADMIN_ROLE) {
        destUsdc[_chainId] = _destUsdc;
        emit DestUsdcSet(_chainId, _destUsdc);
    }

    // ──────────────────────────────────────────────────────────────────────────
    // IBridgeAdapter: metadata
    // ──────────────────────────────────────────────────────────────────────────

    function version() external pure override returns (string memory) {
        return "1.0.0";
    }

    function protocol() external pure override returns (string memory) {
        return "Circle CCTP";
    }

    function chainId() external view override returns (uint256) {
        return srcChainId;
    }

    function endpoint() external view override returns (address) {
        return address(tokenMessenger);
    }

    function supportedChains() external view override returns (uint256[] memory) {
        return _supportedChains;
    }

    function isRouteSupported(uint256 dstChainId, address token) external view override returns (bool) {
        // CCTP only supports USDC
        return token == usdc && chainIdToDomain[dstChainId] != 0;
    }

    function getRoute(uint256 dstChainId, address token) external view override returns (BridgeRoute memory) {
        bool active = token == usdc && chainIdToDomain[dstChainId] != 0;
        return BridgeRoute({
            srcChainId: srcChainId,
            dstChainId: dstChainId,
            srcToken: token,
            dstToken: destUsdc[dstChainId],
            minAmount: 0,
            maxAmount: type(uint256).max,
            estimatedTime: 780, // ~13 min CCTP attestation
            isActive: active
        });
    }

    function getRoutes() external pure override returns (BridgeRoute[] memory) {
        return new BridgeRoute[](0);
    }

    // ──────────────────────────────────────────────────────────────────────────
    // IBridgeAdapter: bridge
    // ──────────────────────────────────────────────────────────────────────────

    function bridge(BridgeParams calldata params) external payable override nonReentrant returns (bytes32 bridgeId) {
        if (params.amount == 0) revert ZeroAmount();
        if (params.token != usdc) revert UnsupportedToken(params.token);

        uint32 destDomain = chainIdToDomain[params.dstChainId];
        if (destDomain == 0) revert UnsupportedChain(params.dstChainId);

        // Transfer USDC from sender to this contract
        IERC20(usdc).safeTransferFrom(msg.sender, address(this), params.amount);

        // Approve TokenMessenger to burn USDC
        IERC20(usdc).forceApprove(address(tokenMessenger), params.amount);

        // Convert recipient to bytes32 for CCTP
        bytes32 mintRecipient = bytes32(uint256(uint160(params.recipient)));

        // Burn USDC via TokenMessenger
        uint64 burnNonce = tokenMessenger.depositForBurn(params.amount, destDomain, mintRecipient, usdc);

        // Track bridge status
        bridgeId = keccak256(abi.encodePacked(burnNonce, _nonce++, block.timestamp));
        _bridgeStatus[bridgeId] = BridgeStatus({
            txHash: bytes32(uint256(burnNonce)),
            srcChainId: srcChainId,
            dstChainId: params.dstChainId,
            token: usdc,
            amount: params.amount,
            sender: msg.sender,
            recipient: params.recipient,
            status: 1, // confirmed (burn initiated)
            timestamp: block.timestamp
        });

        emit BridgeInitiated(bridgeId, msg.sender, srcChainId, params.dstChainId, usdc, params.amount);
    }

    function getStatus(bytes32 bridgeId) external view override returns (BridgeStatus memory) {
        return _bridgeStatus[bridgeId];
    }

    // ──────────────────────────────────────────────────────────────────────────
    // IBridgeAdapter: estimation
    // ──────────────────────────────────────────────────────────────────────────

    function estimateFees(uint256 dstChainId, address token, uint256)
        external
        view
        override
        returns (uint256 bridgeFee, uint256 protocolFee)
    {
        if (token != usdc) revert UnsupportedToken(token);
        if (chainIdToDomain[dstChainId] == 0) revert UnsupportedChain(dstChainId);
        // CCTP has no bridge fee — USDC is burned 1:1 and minted 1:1
        bridgeFee = 0;
        protocolFee = 0;
    }

    function estimateOutput(uint256, address, uint256 amount) external pure override returns (uint256) {
        return amount; // CCTP is 1:1 burn/mint (no slippage, no fees)
    }

    function estimateTime(uint256) external pure override returns (uint256) {
        return 780; // ~13 min for Circle attestation
    }

    // ──────────────────────────────────────────────────────────────────────────
    // CCTP Receiver: complete transfers on destination
    // ──────────────────────────────────────────────────────────────────────────

    /// @notice Complete a CCTP transfer on the destination chain
    /// @param message The burn message from the source chain
    /// @param attestation Circle attestation for the burn message
    /// @return success Whether the message was received successfully
    function receiveMessage(bytes calldata message, bytes calldata attestation)
        external
        nonReentrant
        returns (bool success)
    {
        success = messageTransmitter.receiveMessage(message, attestation);
        if (!success) revert ReceiveFailed();
        emit MessageReceived(keccak256(message));
    }

    /// @notice Allow contract to receive native tokens (for gas refunds)
    receive() external payable { }
}
