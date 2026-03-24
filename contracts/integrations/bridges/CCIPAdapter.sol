// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IRouterClient} from "@chainlink/contracts/src/v0.8/ccip/interfaces/IRouterClient.sol";
import {IAny2EVMMessageReceiver} from "@chainlink/contracts/src/v0.8/ccip/interfaces/IAny2EVMMessageReceiver.sol";
import {Client} from "@chainlink/contracts/src/v0.8/ccip/libraries/Client.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IBridgeAdapter, BridgeParams, BridgeRoute, BridgeStatus} from "../../interfaces/adapters/IBridgeAdapter.sol";

/**
 * @title CCIPAdapter
 * @notice Chainlink CCIP bridge adapter implementing IBridgeAdapter.
 *
 * Sends and receives cross-chain messages + token transfers via Chainlink CCIP.
 * Supports ERC-20 token bridging with programmable token transfers.
 *
 * Architecture:
 *   Source chain: CCIPAdapter.bridge() → IRouterClient.ccipSend()
 *   Dest chain:   CCIP Router → CCIPAdapter.ccipReceive() → mint/release tokens
 *
 * Chain selectors: CCIP uses uint64 chain selectors (NOT EVM chain IDs).
 * Map EVM chain IDs ↔ CCIP selectors via chainIdToSelector / selectorToChainId.
 */
contract CCIPAdapter is IBridgeAdapter, IAny2EVMMessageReceiver, AccessControl, ReentrancyGuard {
    using SafeERC20 for IERC20;

    bytes32 public constant BRIDGE_ADMIN_ROLE = keccak256("BRIDGE_ADMIN_ROLE");

    // ──────────────────────────────────────────────────────────────────────────
    // State
    // ──────────────────────────────────────────────────────────────────────────

    IRouterClient public immutable ccipRouter;
    uint256 public immutable srcChainId;

    /// @notice EVM chain ID → CCIP chain selector
    mapping(uint256 => uint64) public chainIdToSelector;
    /// @notice CCIP chain selector → EVM chain ID
    mapping(uint64 => uint256) public selectorToChainId;

    /// @notice Supported destination chain IDs
    uint256[] private _supportedChains;

    /// @notice Token mapping: local token → (destChainId → dest token)
    mapping(address => mapping(uint256 => address)) public tokenMapping;

    /// @notice Trusted remote adapters: destChainId → remote adapter address
    mapping(uint256 => address) public trustedRemotes;

    /// @notice Bridge tx tracking
    mapping(bytes32 => BridgeStatus) private _bridgeStatus;
    uint256 private _nonce;

    /// @notice Gas limit for destination execution
    uint256 public defaultGasLimit = 200_000;

    // ──────────────────────────────────────────────────────────────────────────
    // Events
    // ──────────────────────────────────────────────────────────────────────────

    event ChainAdded(uint256 indexed chainId, uint64 selector);
    event ChainRemoved(uint256 indexed chainId);
    event TokenMapped(address indexed localToken, uint256 indexed destChainId, address destToken);
    event TrustedRemoteSet(uint256 indexed chainId, address remote);
    event MessageReceived(bytes32 indexed messageId, uint64 sourceChainSelector, address sender);

    // ──────────────────────────────────────────────────────────────────────────
    // Errors
    // ──────────────────────────────────────────────────────────────────────────

    error UnsupportedChain(uint256 chainId);
    error UnsupportedToken(address token, uint256 destChainId);
    error UntrustedSender(uint64 sourceChainSelector, address sender);
    error OnlyRouter();
    error ZeroAmount();
    error ZeroAddress();

    // ──────────────────────────────────────────────────────────────────────────
    // Constructor
    // ──────────────────────────────────────────────────────────────────────────

    constructor(address _ccipRouter, address admin) {
        if (_ccipRouter == address(0) || admin == address(0)) revert ZeroAddress();
        ccipRouter = IRouterClient(_ccipRouter);
        srcChainId = block.chainid;
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(BRIDGE_ADMIN_ROLE, admin);
    }

    // ──────────────────────────────────────────────────────────────────────────
    // Admin: chain + token configuration
    // ──────────────────────────────────────────────────────────────────────────

    function addChain(uint256 _chainId, uint64 _selector) external onlyRole(BRIDGE_ADMIN_ROLE) {
        chainIdToSelector[_chainId] = _selector;
        selectorToChainId[_selector] = _chainId;
        _supportedChains.push(_chainId);
        emit ChainAdded(_chainId, _selector);
    }

    function setTokenMapping(address localToken, uint256 destChainId, address destToken) external onlyRole(BRIDGE_ADMIN_ROLE) {
        tokenMapping[localToken][destChainId] = destToken;
        emit TokenMapped(localToken, destChainId, destToken);
    }

    function setTrustedRemote(uint256 _chainId, address remote) external onlyRole(BRIDGE_ADMIN_ROLE) {
        trustedRemotes[_chainId] = remote;
        emit TrustedRemoteSet(_chainId, remote);
    }

    function setDefaultGasLimit(uint256 gasLimit) external onlyRole(BRIDGE_ADMIN_ROLE) {
        defaultGasLimit = gasLimit;
    }

    // ──────────────────────────────────────────────────────────────────────────
    // IBridgeAdapter: metadata
    // ──────────────────────────────────────────────────────────────────────────

    function version() external pure override returns (string memory) { return "1.0.0"; }
    function protocol() external pure override returns (string memory) { return "Chainlink CCIP"; }
    function chainId() external view override returns (uint256) { return srcChainId; }
    function endpoint() external view override returns (address) { return address(ccipRouter); }
    function supportedChains() external view override returns (uint256[] memory) { return _supportedChains; }

    function isRouteSupported(uint256 dstChainId, address token) external view override returns (bool) {
        return chainIdToSelector[dstChainId] != 0 && tokenMapping[token][dstChainId] != address(0);
    }

    function getRoute(uint256 dstChainId, address token) external view override returns (BridgeRoute memory) {
        return BridgeRoute({
            srcChainId: srcChainId,
            dstChainId: dstChainId,
            srcToken: token,
            dstToken: tokenMapping[token][dstChainId],
            minAmount: 0,
            maxAmount: type(uint256).max,
            estimatedTime: 900, // ~15 min CCIP finality
            isActive: chainIdToSelector[dstChainId] != 0 && tokenMapping[token][dstChainId] != address(0)
        });
    }

    function getRoutes() external view override returns (BridgeRoute[] memory) {
        // Simplified — returns empty, use getRoute() for specific queries
        return new BridgeRoute[](0);
    }

    // ──────────────────────────────────────────────────────────────────────────
    // IBridgeAdapter: bridge
    // ──────────────────────────────────────────────────────────────────────────

    function bridge(BridgeParams calldata params) external payable override nonReentrant returns (bytes32 bridgeId) {
        if (params.amount == 0) revert ZeroAmount();

        uint64 destSelector = chainIdToSelector[params.dstChainId];
        if (destSelector == 0) revert UnsupportedChain(params.dstChainId);

        address destToken = tokenMapping[params.token][params.dstChainId];
        if (destToken == address(0)) revert UnsupportedToken(params.token, params.dstChainId);

        // Transfer tokens from sender to this contract
        IERC20(params.token).safeTransferFrom(msg.sender, address(this), params.amount);

        // Approve CCIP router to spend tokens
        IERC20(params.token).forceApprove(address(ccipRouter), params.amount);

        // Build CCIP message
        Client.EVMTokenAmount[] memory tokenAmounts = new Client.EVMTokenAmount[](1);
        tokenAmounts[0] = Client.EVMTokenAmount({
            token: params.token,
            amount: params.amount
        });

        Client.EVM2AnyMessage memory message = Client.EVM2AnyMessage({
            receiver: abi.encode(params.recipient),
            data: params.extraData,
            tokenAmounts: tokenAmounts,
            feeToken: address(0), // pay in native
            extraArgs: Client._argsToBytes(Client.EVMExtraArgsV2({
                gasLimit: defaultGasLimit,
                allowOutOfOrderExecution: true
            }))
        });

        // Send via CCIP
        bytes32 messageId = ccipRouter.ccipSend{value: msg.value}(destSelector, message);

        // Track bridge status
        bridgeId = keccak256(abi.encodePacked(messageId, _nonce++));
        _bridgeStatus[bridgeId] = BridgeStatus({
            txHash: messageId,
            srcChainId: srcChainId,
            dstChainId: params.dstChainId,
            token: params.token,
            amount: params.amount,
            sender: msg.sender,
            recipient: params.recipient,
            status: 1, // confirmed (sent to CCIP)
            timestamp: block.timestamp
        });

        emit BridgeInitiated(bridgeId, msg.sender, srcChainId, params.dstChainId, params.token, params.amount);
    }

    function getStatus(bytes32 bridgeId) external view override returns (BridgeStatus memory) {
        return _bridgeStatus[bridgeId];
    }

    // ──────────────────────────────────────────────────────────────────────────
    // IBridgeAdapter: estimation
    // ──────────────────────────────────────────────────────────────────────────

    function estimateFees(uint256 dstChainId, address token, uint256 amount)
        external view override returns (uint256 bridgeFee, uint256 protocolFee)
    {
        uint64 destSelector = chainIdToSelector[dstChainId];
        if (destSelector == 0) revert UnsupportedChain(dstChainId);

        Client.EVMTokenAmount[] memory tokenAmounts = new Client.EVMTokenAmount[](1);
        tokenAmounts[0] = Client.EVMTokenAmount({ token: token, amount: amount });

        Client.EVM2AnyMessage memory message = Client.EVM2AnyMessage({
            receiver: abi.encode(address(0)),
            data: "",
            tokenAmounts: tokenAmounts,
            feeToken: address(0),
            extraArgs: Client._argsToBytes(Client.EVMExtraArgsV2({
                gasLimit: defaultGasLimit,
                allowOutOfOrderExecution: true
            }))
        });

        bridgeFee = ccipRouter.getFee(destSelector, message);
        protocolFee = 0;
    }

    function estimateOutput(uint256, address, uint256 amount) external pure override returns (uint256) {
        return amount; // CCIP is 1:1 (no slippage on token transfers)
    }

    function estimateTime(uint256) external pure override returns (uint256) {
        return 900; // ~15 min CCIP finality
    }

    // ──────────────────────────────────────────────────────────────────────────
    // CCIP Receiver
    // ──────────────────────────────────────────────────────────────────────────

    function ccipReceive(Client.Any2EVMMessage calldata message) external override {
        if (msg.sender != address(ccipRouter)) revert OnlyRouter();

        uint256 sourceChainId = selectorToChainId[message.sourceChainSelector];
        address sender = abi.decode(message.sender, (address));

        // Verify trusted remote
        if (trustedRemotes[sourceChainId] != address(0) && trustedRemotes[sourceChainId] != sender) {
            revert UntrustedSender(message.sourceChainSelector, sender);
        }

        emit MessageReceived(message.messageId, message.sourceChainSelector, sender);

        // Tokens are auto-released by CCIP to this contract
        // Forward to recipient encoded in message.data if present
        if (message.data.length > 0 && message.destTokenAmounts.length > 0) {
            address recipient = abi.decode(message.data, (address));
            for (uint256 i = 0; i < message.destTokenAmounts.length; i++) {
                IERC20(message.destTokenAmounts[i].token).safeTransfer(
                    recipient,
                    message.destTokenAmounts[i].amount
                );
            }
        }
    }

    /// @notice ERC-165 support
    function supportsInterface(bytes4 interfaceId) public view override returns (bool) {
        return interfaceId == type(IAny2EVMMessageReceiver).interfaceId || super.supportsInterface(interfaceId);
    }

    /// @notice Allow contract to receive native tokens for CCIP fees
    receive() external payable {}
}
