// SPDX-License-Identifier: MIT
pragma solidity ^0.8.31;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IBridgeAdapter, BridgeParams, BridgeRoute, BridgeStatus} from "../../interfaces/adapters/IBridgeAdapter.sol";

// =============================================================================
// LAYERZERO V2 INTERFACES
// =============================================================================

/// @notice Messaging fee structure
struct MessagingFee {
    uint256 nativeFee;
    uint256 lzTokenFee;
}

/// @notice Messaging parameters for sending
struct MessagingParams {
    uint32 dstEid;
    bytes32 receiver;
    bytes message;
    bytes options;
    bool payInLzToken;
}

/// @notice Messaging receipt returned from send
struct MessagingReceipt {
    bytes32 guid;
    uint64 nonce;
    MessagingFee fee;
}

/// @notice Origin metadata for received messages
struct Origin {
    uint32 srcEid;
    bytes32 sender;
    uint64 nonce;
}

/// @notice LayerZero V2 endpoint interface
interface ILayerZeroEndpointV2 {
    function send(
        MessagingParams calldata _params,
        address _refundAddress
    ) external payable returns (MessagingReceipt memory);

    function quote(
        MessagingParams calldata _params,
        address _sender
    ) external view returns (MessagingFee memory);

    function setDelegate(address _delegate) external;
}

// =============================================================================
// LAYERZERO ADAPTER IMPLEMENTATION
// =============================================================================

/**
 * @title LayerZeroAdapter
 * @notice LayerZero V2 bridge adapter implementing IBridgeAdapter.
 *
 * Sends cross-chain messages and token transfers via LayerZero V2 endpoint.
 * Receives inbound messages via lzReceive callback from the endpoint.
 *
 * Architecture:
 *   Source chain: LayerZeroAdapter.bridge() -> ILayerZeroEndpointV2.send()
 *   Dest chain:   LZ Endpoint -> LayerZeroAdapter.lzReceive() -> release tokens
 *
 * Endpoint IDs: LayerZero uses uint32 endpoint IDs (NOT EVM chain IDs).
 *   Map EVM chain IDs <-> LZ endpoint IDs via chainIdToEid / eidToChainId.
 */
contract LayerZeroAdapter is IBridgeAdapter, AccessControl, ReentrancyGuard {
    using SafeERC20 for IERC20;

    bytes32 public constant BRIDGE_ADMIN_ROLE = keccak256("BRIDGE_ADMIN_ROLE");

    // -------------------------------------------------------------------------
    // State
    // -------------------------------------------------------------------------

    ILayerZeroEndpointV2 public immutable lzEndpoint;
    uint256 public immutable srcChainId;

    /// @notice EVM chain ID -> LayerZero V2 endpoint ID
    mapping(uint256 => uint32) public chainIdToEid;
    /// @notice LayerZero V2 endpoint ID -> EVM chain ID
    mapping(uint32 => uint256) public eidToChainId;

    /// @notice Supported destination chain IDs
    uint256[] private _supportedChains;

    /// @notice Token mapping: local token -> (destChainId -> dest token)
    mapping(address => mapping(uint256 => address)) public tokenMapping;

    /// @notice Trusted remote adapters: destChainId -> remote adapter (as bytes32)
    mapping(uint256 => bytes32) public trustedRemotes;

    /// @notice Bridge tx tracking
    mapping(bytes32 => BridgeStatus) private _bridgeStatus;
    uint256 private _nonce;

    /// @notice Gas limit for destination execution
    uint256 public defaultGasLimit = 200_000;

    // -------------------------------------------------------------------------
    // Events
    // -------------------------------------------------------------------------

    event ChainAdded(uint256 indexed chainId, uint32 eid);
    event TokenMapped(address indexed localToken, uint256 indexed destChainId, address destToken);
    event TrustedRemoteSet(uint256 indexed chainId, bytes32 remote);
    event MessageReceived(bytes32 indexed guid, uint32 srcEid, bytes32 sender);

    // -------------------------------------------------------------------------
    // Errors
    // -------------------------------------------------------------------------

    error UnsupportedChain(uint256 chainId);
    error UnsupportedToken(address token, uint256 destChainId);
    error UntrustedSender(uint32 srcEid, bytes32 sender);
    error OnlyEndpoint();
    error ZeroAmount();
    error ZeroAddress();

    // -------------------------------------------------------------------------
    // Constructor
    // -------------------------------------------------------------------------

    constructor(address _lzEndpoint, address admin) {
        if (_lzEndpoint == address(0) || admin == address(0)) revert ZeroAddress();
        lzEndpoint = ILayerZeroEndpointV2(_lzEndpoint);
        srcChainId = block.chainid;
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(BRIDGE_ADMIN_ROLE, admin);
    }

    // -------------------------------------------------------------------------
    // Admin: chain + token configuration
    // -------------------------------------------------------------------------

    function addChain(uint256 _chainId, uint32 _eid) external onlyRole(BRIDGE_ADMIN_ROLE) {
        chainIdToEid[_chainId] = _eid;
        eidToChainId[_eid] = _chainId;
        _supportedChains.push(_chainId);
        emit ChainAdded(_chainId, _eid);
    }

    function setTokenMapping(address localToken, uint256 destChainId, address destToken) external onlyRole(BRIDGE_ADMIN_ROLE) {
        tokenMapping[localToken][destChainId] = destToken;
        emit TokenMapped(localToken, destChainId, destToken);
    }

    function setTrustedRemote(uint256 _chainId, address remote) external onlyRole(BRIDGE_ADMIN_ROLE) {
        bytes32 remoteBytes = bytes32(uint256(uint160(remote)));
        trustedRemotes[_chainId] = remoteBytes;
        emit TrustedRemoteSet(_chainId, remoteBytes);
    }

    function setDefaultGasLimit(uint256 gasLimit) external onlyRole(BRIDGE_ADMIN_ROLE) {
        defaultGasLimit = gasLimit;
    }

    // -------------------------------------------------------------------------
    // IBridgeAdapter: metadata
    // -------------------------------------------------------------------------

    function version() external pure override returns (string memory) { return "1.0.0"; }
    function protocol() external pure override returns (string memory) { return "LayerZero V2"; }
    function chainId() external view override returns (uint256) { return srcChainId; }
    function endpoint() external view override returns (address) { return address(lzEndpoint); }
    function supportedChains() external view override returns (uint256[] memory) { return _supportedChains; }

    function isRouteSupported(uint256 dstChainId, address token) external view override returns (bool) {
        return chainIdToEid[dstChainId] != 0 && tokenMapping[token][dstChainId] != address(0);
    }

    function getRoute(uint256 dstChainId, address token) external view override returns (BridgeRoute memory) {
        return BridgeRoute({
            srcChainId: srcChainId,
            dstChainId: dstChainId,
            srcToken: token,
            dstToken: tokenMapping[token][dstChainId],
            minAmount: 0,
            maxAmount: type(uint256).max,
            estimatedTime: 60, // ~1 min LayerZero finality
            isActive: chainIdToEid[dstChainId] != 0 && tokenMapping[token][dstChainId] != address(0)
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

        uint32 destEid = chainIdToEid[params.dstChainId];
        if (destEid == 0) revert UnsupportedChain(params.dstChainId);

        address destToken = tokenMapping[params.token][params.dstChainId];
        if (destToken == address(0)) revert UnsupportedToken(params.token, params.dstChainId);

        // Transfer tokens from sender to this contract (lock on source)
        IERC20(params.token).safeTransferFrom(msg.sender, address(this), params.amount);

        // Encode payload: recipient, token, amount, extraData
        bytes memory payload = abi.encode(params.recipient, params.token, params.amount, params.extraData);

        // Build LZ messaging params
        MessagingParams memory msgParams = MessagingParams({
            dstEid: destEid,
            receiver: trustedRemotes[params.dstChainId],
            message: payload,
            options: "",
            payInLzToken: false
        });

        // Send via LayerZero endpoint
        MessagingReceipt memory receipt = lzEndpoint.send{value: msg.value}(msgParams, msg.sender);

        // Track bridge status
        bridgeId = keccak256(abi.encodePacked(receipt.guid, _nonce++));
        _bridgeStatus[bridgeId] = BridgeStatus({
            txHash: receipt.guid,
            srcChainId: srcChainId,
            dstChainId: params.dstChainId,
            token: params.token,
            amount: params.amount,
            sender: msg.sender,
            recipient: params.recipient,
            status: 1, // confirmed (sent to LZ)
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

    function estimateFees(uint256 dstChainId, address token, uint256 amount)
        external view override returns (uint256 bridgeFee, uint256 protocolFee)
    {
        uint32 destEid = chainIdToEid[dstChainId];
        if (destEid == 0) revert UnsupportedChain(dstChainId);

        bytes memory payload = abi.encode(address(0), token, amount, bytes(""));
        MessagingParams memory msgParams = MessagingParams({
            dstEid: destEid,
            receiver: trustedRemotes[dstChainId],
            message: payload,
            options: "",
            payInLzToken: false
        });

        MessagingFee memory fee = lzEndpoint.quote(msgParams, address(this));
        bridgeFee = fee.nativeFee;
        protocolFee = 0;
    }

    function estimateOutput(uint256, address, uint256 amount) external pure override returns (uint256) {
        return amount; // 1:1 (no slippage on token transfers)
    }

    function estimateTime(uint256) external pure override returns (uint256) {
        return 60; // ~1 min LayerZero finality
    }

    // -------------------------------------------------------------------------
    // LayerZero Receiver
    // -------------------------------------------------------------------------

    /// @notice Called by the LayerZero endpoint when a message arrives
    function lzReceive(
        Origin calldata _origin,
        bytes32 _guid,
        bytes calldata _message,
        address,
        bytes calldata
    ) external {
        if (msg.sender != address(lzEndpoint)) revert OnlyEndpoint();

        // Verify trusted remote
        uint256 sourceChainId = eidToChainId[_origin.srcEid];
        bytes32 trustedRemote = trustedRemotes[sourceChainId];
        if (trustedRemote != bytes32(0) && trustedRemote != _origin.sender) {
            revert UntrustedSender(_origin.srcEid, _origin.sender);
        }

        emit MessageReceived(_guid, _origin.srcEid, _origin.sender);

        // Decode and release tokens to recipient
        if (_message.length > 0) {
            (address recipient, address token, uint256 amount,) = abi.decode(_message, (address, address, uint256, bytes));
            IERC20(token).safeTransfer(recipient, amount);
        }
    }

    /// @notice Allow contract to receive native tokens for LZ fees
    receive() external payable {}
}
