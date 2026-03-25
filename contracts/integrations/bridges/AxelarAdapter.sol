// SPDX-License-Identifier: MIT
pragma solidity ^0.8.31;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { AccessControl } from "@openzeppelin/contracts/access/AccessControl.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { IBridgeAdapter, BridgeParams, BridgeRoute, BridgeStatus } from "../../interfaces/adapters/IBridgeAdapter.sol";

// =============================================================================
// AXELAR INTERFACES
// =============================================================================

/// @notice Axelar Gateway interface for cross-chain messaging and token transfers
interface IAxelarGateway {
    function sendToken(
        string calldata destinationChain,
        string calldata destinationAddress,
        string calldata symbol,
        uint256 amount
    ) external;

    function callContract(string calldata destinationChain, string calldata contractAddress, bytes calldata payload)
        external;

    function callContractWithToken(
        string calldata destinationChain,
        string calldata contractAddress,
        bytes calldata payload,
        string calldata symbol,
        uint256 amount
    ) external;

    function validateContractCall(
        bytes32 commandId,
        string calldata sourceChain,
        string calldata sourceAddress,
        bytes32 payloadHash
    ) external view returns (bool);

    function validateContractCallAndMint(
        bytes32 commandId,
        string calldata sourceChain,
        string calldata sourceAddress,
        bytes32 payloadHash,
        string calldata symbol,
        uint256 amount
    ) external view returns (bool);

    function tokenAddresses(string calldata symbol) external view returns (address);

    function isCommandExecuted(bytes32 commandId) external view returns (bool);
}

/// @notice Axelar Gas Service interface for prepaying cross-chain gas
interface IAxelarGasService {
    function payNativeGasForContractCallWithToken(
        address sender,
        string calldata destinationChain,
        string calldata destinationAddress,
        bytes calldata payload,
        string calldata symbol,
        uint256 amount,
        address refundAddress
    ) external payable;

    function payNativeGasForContractCall(
        address sender,
        string calldata destinationChain,
        string calldata destinationAddress,
        bytes calldata payload,
        address refundAddress
    ) external payable;
}

// =============================================================================
// AXELAR ADAPTER IMPLEMENTATION
// =============================================================================

/**
 * @title AxelarAdapter
 * @notice Axelar GMP bridge adapter implementing IBridgeAdapter.
 *
 * Sends cross-chain token transfers via Axelar Gateway using General Message
 * Passing (GMP). Receives inbound transfers via execute/executeWithToken.
 *
 * Architecture:
 *   Source chain: AxelarAdapter.bridge() -> IAxelarGateway.callContractWithToken()
 *   Relay:        Axelar validators confirm and relay
 *   Dest chain:   AxelarAdapter.executeWithToken() -> release tokens to recipient
 *
 * Chain names: Axelar uses string chain names (NOT EVM chain IDs).
 *   Map EVM chain IDs <-> Axelar chain names via chainIdToName / nameToChainId.
 */
contract AxelarAdapter is IBridgeAdapter, AccessControl, ReentrancyGuard {
    using SafeERC20 for IERC20;

    bytes32 public constant BRIDGE_ADMIN_ROLE = keccak256("BRIDGE_ADMIN_ROLE");

    // -------------------------------------------------------------------------
    // State
    // -------------------------------------------------------------------------

    IAxelarGateway public immutable gateway;
    IAxelarGasService public immutable gasService;
    uint256 public immutable srcChainId;

    /// @notice EVM chain ID -> Axelar chain name
    mapping(uint256 => string) public chainIdToName;

    /// @notice Supported destination chain IDs
    uint256[] private _supportedChains;

    /// @notice Token mapping: local token -> (destChainId -> dest token)
    mapping(address => mapping(uint256 => address)) public tokenMapping;

    /// @notice Token address -> Axelar token symbol
    mapping(address => string) public tokenSymbols;

    /// @notice Trusted remote adapter addresses per chain (as string for Axelar)
    mapping(uint256 => string) public trustedRemotes;

    /// @notice Bridge tx tracking
    mapping(bytes32 => BridgeStatus) private _bridgeStatus;
    uint256 private _nonce;

    // -------------------------------------------------------------------------
    // Events
    // -------------------------------------------------------------------------

    event ChainAdded(uint256 indexed chainId, string name);
    event TokenMapped(address indexed localToken, uint256 indexed destChainId, address destToken);
    event TokenSymbolSet(address indexed token, string symbol);
    event TrustedRemoteSet(uint256 indexed chainId, string remote);
    event MessageReceived(bytes32 indexed commandId, string sourceChain, string sourceAddress);

    // -------------------------------------------------------------------------
    // Errors
    // -------------------------------------------------------------------------

    error UnsupportedChain(uint256 chainId);
    error UnsupportedToken(address token, uint256 destChainId);
    error InvalidCommand();
    error EmptySymbol();
    error ZeroAmount();
    error ZeroAddress();

    // -------------------------------------------------------------------------
    // Constructor
    // -------------------------------------------------------------------------

    constructor(address _gateway, address _gasService, address admin) {
        if (_gateway == address(0) || _gasService == address(0) || admin == address(0)) revert ZeroAddress();
        gateway = IAxelarGateway(_gateway);
        gasService = IAxelarGasService(_gasService);
        srcChainId = block.chainid;
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(BRIDGE_ADMIN_ROLE, admin);
    }

    // -------------------------------------------------------------------------
    // Admin: chain + token configuration
    // -------------------------------------------------------------------------

    function addChain(uint256 _chainId, string calldata _name) external onlyRole(BRIDGE_ADMIN_ROLE) {
        chainIdToName[_chainId] = _name;
        _supportedChains.push(_chainId);
        emit ChainAdded(_chainId, _name);
    }

    function setTokenMapping(address localToken, uint256 destChainId, address destToken)
        external
        onlyRole(BRIDGE_ADMIN_ROLE)
    {
        tokenMapping[localToken][destChainId] = destToken;
        emit TokenMapped(localToken, destChainId, destToken);
    }

    function setTokenSymbol(address token, string calldata symbol) external onlyRole(BRIDGE_ADMIN_ROLE) {
        if (bytes(symbol).length == 0) revert EmptySymbol();
        tokenSymbols[token] = symbol;
        emit TokenSymbolSet(token, symbol);
    }

    function setTrustedRemote(uint256 _chainId, string calldata remote) external onlyRole(BRIDGE_ADMIN_ROLE) {
        trustedRemotes[_chainId] = remote;
        emit TrustedRemoteSet(_chainId, remote);
    }

    // -------------------------------------------------------------------------
    // IBridgeAdapter: metadata
    // -------------------------------------------------------------------------

    function version() external pure override returns (string memory) {
        return "1.0.0";
    }

    function protocol() external pure override returns (string memory) {
        return "Axelar GMP";
    }

    function chainId() external view override returns (uint256) {
        return srcChainId;
    }

    function endpoint() external view override returns (address) {
        return address(gateway);
    }

    function supportedChains() external view override returns (uint256[] memory) {
        return _supportedChains;
    }

    function isRouteSupported(uint256 dstChainId, address token) external view override returns (bool) {
        return bytes(chainIdToName[dstChainId]).length > 0 && tokenMapping[token][dstChainId] != address(0);
    }

    function getRoute(uint256 dstChainId, address token) external view override returns (BridgeRoute memory) {
        bool active = bytes(chainIdToName[dstChainId]).length > 0 && tokenMapping[token][dstChainId] != address(0);
        return BridgeRoute({
            srcChainId: srcChainId,
            dstChainId: dstChainId,
            srcToken: token,
            dstToken: tokenMapping[token][dstChainId],
            minAmount: 0,
            maxAmount: type(uint256).max,
            estimatedTime: 180, // ~3 min Axelar finality
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

        string memory destChain = chainIdToName[params.dstChainId];
        if (bytes(destChain).length == 0) revert UnsupportedChain(params.dstChainId);

        address destToken = tokenMapping[params.token][params.dstChainId];
        if (destToken == address(0)) revert UnsupportedToken(params.token, params.dstChainId);

        string memory symbol = tokenSymbols[params.token];

        // Transfer tokens from sender to this contract
        IERC20(params.token).safeTransferFrom(msg.sender, address(this), params.amount);

        // Approve gateway to spend tokens
        IERC20(params.token).forceApprove(address(gateway), params.amount);

        // Encode payload for destination
        bytes memory payload = abi.encode(params.recipient, params.amount, params.extraData);

        // Get trusted remote as destination address
        string memory destAddress = trustedRemotes[params.dstChainId];

        // Pay gas for cross-chain execution
        gasService.payNativeGasForContractCallWithToken{ value: msg.value }(
            address(this), destChain, destAddress, payload, symbol, params.amount, msg.sender
        );

        // Send via Axelar gateway
        gateway.callContractWithToken(destChain, destAddress, payload, symbol, params.amount);

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
            status: 1, // confirmed (sent to Axelar)
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

    function estimateFees(uint256 dstChainId, address, uint256)
        external
        view
        override
        returns (uint256 bridgeFee, uint256 protocolFee)
    {
        if (bytes(chainIdToName[dstChainId]).length == 0) revert UnsupportedChain(dstChainId);
        bridgeFee = 0.005 ether; // Flat gas estimate for Axelar relay
        protocolFee = 0;
    }

    function estimateOutput(uint256, address, uint256 amount) external pure override returns (uint256) {
        return amount; // 1:1 (no slippage on Axelar GMP transfers)
    }

    function estimateTime(uint256) external pure override returns (uint256) {
        return 180; // ~3 min Axelar finality
    }

    // -------------------------------------------------------------------------
    // Axelar Receiver: execute and executeWithToken
    // -------------------------------------------------------------------------

    /// @notice Called by Axelar relayer to execute a cross-chain message
    function execute(
        bytes32 commandId,
        string calldata sourceChain,
        string calldata sourceAddress,
        bytes calldata payload
    ) external {
        if (!gateway.validateContractCall(commandId, sourceChain, sourceAddress, keccak256(payload))) {
            revert InvalidCommand();
        }
        emit MessageReceived(commandId, sourceChain, sourceAddress);
    }

    /// @notice Called by Axelar relayer to execute a cross-chain message with token transfer
    function executeWithToken(
        bytes32 commandId,
        string calldata sourceChain,
        string calldata sourceAddress,
        bytes calldata payload,
        string calldata symbol,
        uint256 amount
    ) external {
        if (!gateway.validateContractCallAndMint(
                commandId, sourceChain, sourceAddress, keccak256(payload), symbol, amount
            )) {
            revert InvalidCommand();
        }

        emit MessageReceived(commandId, sourceChain, sourceAddress);

        // Decode payload and transfer tokens to recipient
        (address recipient,,) = abi.decode(payload, (address, uint256, bytes));
        address tokenAddr = gateway.tokenAddresses(symbol);
        if (tokenAddr != address(0)) {
            IERC20(tokenAddr).safeTransfer(recipient, amount);
        }
    }

    /// @notice Allow contract to receive native tokens for gas payments
    receive() external payable { }
}
