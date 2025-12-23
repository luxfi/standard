// SPDX-License-Identifier: BSD-3-Clause
// Copyright (c) 2025 Lux Industries Inc.
pragma solidity ^0.8.28;

/// @title IBridgeAggregator
/// @notice Unified interface for cross-chain bridge aggregation
/// @dev Supports Axelar GMP, LayerZero V2, Wormhole CCTP, and Lux Warp
interface IBridgeAggregator {
    /*//////////////////////////////////////////////////////////////
                                 TYPES
    //////////////////////////////////////////////////////////////*/

    /// @notice Supported bridge protocols
    enum BridgeProtocol {
        LUX_WARP,       // Native Lux Warp messaging (fastest for Lux ecosystem)
        AXELAR_GMP,     // Axelar General Message Passing
        LAYERZERO_V2,   // LayerZero V2 OFT/ONFT
        WORMHOLE_CCTP,  // Wormhole Circle CCTP
        HYPERLANE,      // Hyperlane messaging
        CCIP            // Chainlink CCIP
    }

    /// @notice Bridge route for cross-chain transfer
    struct BridgeRoute {
        BridgeProtocol protocol;
        uint256 srcChainId;
        uint256 dstChainId;
        address srcToken;
        address dstToken;
        uint256 estimatedTime;      // Seconds
        uint256 fee;                // Native token fee
        uint256 minAmount;          // Minimum transfer amount
        uint256 maxAmount;          // Maximum transfer amount
        bool isActive;
    }

    /// @notice Cross-chain message
    struct CrossChainMessage {
        uint256 srcChainId;
        uint256 dstChainId;
        address sender;
        address recipient;
        bytes payload;
        uint256 gasLimit;
        uint256 value;
        bytes32 messageId;
    }

    /// @notice Bridge transfer request
    struct TransferRequest {
        address token;
        uint256 amount;
        uint256 dstChainId;
        address recipient;
        uint256 minAmountOut;
        uint256 gasLimit;
        bytes extraData;            // Protocol-specific data
    }

    /// @notice Bridge transfer result
    struct TransferResult {
        bytes32 messageId;
        BridgeProtocol protocol;
        uint256 srcChainId;
        uint256 dstChainId;
        uint256 amount;
        uint256 fee;
        uint256 estimatedArrival;
    }

    /// @notice Bridge quote
    struct BridgeQuote {
        BridgeProtocol protocol;
        uint256 fee;
        uint256 estimatedTime;
        uint256 amountOut;
        bool available;
    }

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    event BridgeInitiated(
        bytes32 indexed messageId,
        BridgeProtocol indexed protocol,
        uint256 srcChainId,
        uint256 dstChainId,
        address indexed sender,
        address recipient,
        address token,
        uint256 amount
    );

    event BridgeCompleted(
        bytes32 indexed messageId,
        BridgeProtocol indexed protocol,
        address indexed recipient,
        address token,
        uint256 amount
    );

    event BridgeFailed(
        bytes32 indexed messageId,
        BridgeProtocol indexed protocol,
        string reason
    );

    event MessageReceived(
        bytes32 indexed messageId,
        uint256 srcChainId,
        address sender,
        bytes payload
    );

    /*//////////////////////////////////////////////////////////////
                          BRIDGE FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Bridge tokens to another chain
    /// @param request Transfer request details
    /// @return result Transfer result with message ID
    function bridge(
        TransferRequest calldata request
    ) external payable returns (TransferResult memory result);

    /// @notice Bridge with specific protocol
    /// @param protocol Bridge protocol to use
    /// @param request Transfer request details
    /// @return result Transfer result
    function bridgeVia(
        BridgeProtocol protocol,
        TransferRequest calldata request
    ) external payable returns (TransferResult memory result);

    /// @notice Get best route for transfer
    /// @param token Source token
    /// @param amount Amount to transfer
    /// @param dstChainId Destination chain
    /// @return route Best available route
    function getBestRoute(
        address token,
        uint256 amount,
        uint256 dstChainId
    ) external view returns (BridgeRoute memory route);

    /// @notice Get quotes from all available bridges
    /// @param token Source token
    /// @param amount Amount to transfer
    /// @param dstChainId Destination chain
    /// @return quotes Array of quotes from each protocol
    function getQuotes(
        address token,
        uint256 amount,
        uint256 dstChainId
    ) external view returns (BridgeQuote[] memory quotes);

    /// @notice Get available routes for a token pair
    /// @param srcToken Source token
    /// @param dstChainId Destination chain
    /// @return routes Array of available routes
    function getRoutes(
        address srcToken,
        uint256 dstChainId
    ) external view returns (BridgeRoute[] memory routes);

    /*//////////////////////////////////////////////////////////////
                       MESSAGE FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Send cross-chain message (no token transfer)
    /// @param dstChainId Destination chain
    /// @param recipient Recipient contract
    /// @param payload Message payload
    /// @param gasLimit Gas limit on destination
    /// @return messageId Unique message identifier
    function sendMessage(
        uint256 dstChainId,
        address recipient,
        bytes calldata payload,
        uint256 gasLimit
    ) external payable returns (bytes32 messageId);

    /// @notice Send message via specific protocol
    /// @param protocol Bridge protocol
    /// @param dstChainId Destination chain
    /// @param recipient Recipient contract
    /// @param payload Message payload
    /// @param gasLimit Gas limit on destination
    /// @return messageId Unique message identifier
    function sendMessageVia(
        BridgeProtocol protocol,
        uint256 dstChainId,
        address recipient,
        bytes calldata payload,
        uint256 gasLimit
    ) external payable returns (bytes32 messageId);

    /// @notice Estimate message fee
    /// @param protocol Bridge protocol
    /// @param dstChainId Destination chain
    /// @param payload Message payload
    /// @param gasLimit Gas limit on destination
    /// @return fee Estimated fee in native token
    function estimateMessageFee(
        BridgeProtocol protocol,
        uint256 dstChainId,
        bytes calldata payload,
        uint256 gasLimit
    ) external view returns (uint256 fee);

    /*//////////////////////////////////////////////////////////////
                        STATUS FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Check if message was delivered
    /// @param messageId Message identifier
    /// @return delivered True if delivered
    function isDelivered(bytes32 messageId) external view returns (bool delivered);

    /// @notice Get message status
    /// @param messageId Message identifier
    /// @return status 0=pending, 1=delivered, 2=failed
    function getMessageStatus(bytes32 messageId) external view returns (uint8 status);

    /// @notice Check if chain is supported by protocol
    /// @param protocol Bridge protocol
    /// @param chainId Chain ID to check
    /// @return supported True if chain is supported
    function isChainSupported(
        BridgeProtocol protocol,
        uint256 chainId
    ) external view returns (bool supported);

    /// @notice Get supported chains for protocol
    /// @param protocol Bridge protocol
    /// @return chainIds Array of supported chain IDs
    function getSupportedChains(
        BridgeProtocol protocol
    ) external view returns (uint256[] memory chainIds);
}

/// @title IAxelarGateway
/// @notice Axelar Gateway interface for GMP
interface IAxelarGateway {
    function callContract(
        string calldata destinationChain,
        string calldata contractAddress,
        bytes calldata payload
    ) external;

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
    ) external returns (bool);

    function validateContractCallAndMint(
        bytes32 commandId,
        string calldata sourceChain,
        string calldata sourceAddress,
        bytes32 payloadHash,
        string calldata symbol,
        uint256 amount
    ) external returns (bool);
}

/// @title IAxelarGasService
/// @notice Axelar Gas Service for prepaying destination gas
interface IAxelarGasService {
    function payNativeGasForContractCall(
        address sender,
        string calldata destinationChain,
        string calldata destinationAddress,
        bytes calldata payload,
        address refundAddress
    ) external payable;

    function payNativeGasForContractCallWithToken(
        address sender,
        string calldata destinationChain,
        string calldata destinationAddress,
        bytes calldata payload,
        string calldata symbol,
        uint256 amount,
        address refundAddress
    ) external payable;
}

/// @title ILayerZeroEndpointV2
/// @notice LayerZero V2 Endpoint interface
interface ILayerZeroEndpointV2 {
    struct MessagingParams {
        uint32 dstEid;
        bytes32 receiver;
        bytes message;
        bytes options;
        bool payInLzToken;
    }

    struct MessagingFee {
        uint256 nativeFee;
        uint256 lzTokenFee;
    }

    struct MessagingReceipt {
        bytes32 guid;
        uint64 nonce;
        MessagingFee fee;
    }

    function send(
        MessagingParams calldata _params,
        address _refundAddress
    ) external payable returns (MessagingReceipt memory);

    function quote(
        MessagingParams calldata _params,
        address _sender
    ) external view returns (MessagingFee memory);

    function eid() external view returns (uint32);
}

/// @title IWormholeRelayer
/// @notice Wormhole Relayer interface
interface IWormholeRelayer {
    function sendPayloadToEvm(
        uint16 targetChain,
        address targetAddress,
        bytes memory payload,
        uint256 receiverValue,
        uint256 gasLimit
    ) external payable returns (uint64 sequence);

    function quoteEVMDeliveryPrice(
        uint16 targetChain,
        uint256 receiverValue,
        uint256 gasLimit
    ) external view returns (
        uint256 nativePriceQuote,
        uint256 targetChainRefundPerGasUnused
    );
}

/// @title IWarp
/// @notice Lux Warp native cross-chain messaging
interface IWarp {
    function sendWarpMessage(bytes calldata payload) external returns (bytes32 messageId);

    function getVerifiedWarpMessage(uint32 index) external view returns (
        bytes32 sourceChainId,
        address originSenderAddress,
        bytes memory payload
    );

    function getVerifiedWarpBlockHash(uint32 index) external view returns (
        bytes32 sourceChainId,
        bytes32 blockHash
    );
}

/// @title BridgeLib
/// @notice Library for bridge aggregation utilities
library BridgeLib {
    /// @notice Lux Warp precompile address
    IWarp internal constant WARP = IWarp(0x0200000000000000000000000000000000000005);

    /// @notice Axelar Gateway (Ethereum)
    IAxelarGateway internal constant AXELAR_GATEWAY_ETH =
        IAxelarGateway(0x4F4495243837681061C4743b74B3eEdf548D56A5);

    /// @notice Axelar Gas Service (Ethereum)
    IAxelarGasService internal constant AXELAR_GAS_ETH =
        IAxelarGasService(0x2d5d7d31F671F86C782533cc367F14109a082712);

    /// @notice LayerZero V2 Endpoint (Ethereum)
    ILayerZeroEndpointV2 internal constant LZ_ENDPOINT_ETH =
        ILayerZeroEndpointV2(0x1a44076050125825900e736c501f859c50fE728c);

    /// @notice Wormhole Relayer (Ethereum)
    IWormholeRelayer internal constant WORMHOLE_RELAYER_ETH =
        IWormholeRelayer(0x27428DD2d3DD32A4D7f7C497eAaa23130d894911);

    /// @notice Chain ID to Axelar chain name mapping
    function getAxelarChainName(uint256 chainId) internal pure returns (string memory) {
        if (chainId == 1) return "ethereum";
        if (chainId == 56) return "binance";
        if (chainId == 137) return "polygon";
        if (chainId == 43114) return "avalanche";
        if (chainId == 42161) return "arbitrum";
        if (chainId == 10) return "optimism";
        if (chainId == 8453) return "base";
        if (chainId == 96369) return "lux";
        revert("BridgeLib: unsupported chain");
    }

    /// @notice Chain ID to LayerZero V2 EID mapping
    function getLzEndpointId(uint256 chainId) internal pure returns (uint32) {
        if (chainId == 1) return 30101;         // Ethereum
        if (chainId == 56) return 30102;        // BSC
        if (chainId == 137) return 30109;       // Polygon
        if (chainId == 43114) return 30106;     // Avalanche
        if (chainId == 42161) return 30110;     // Arbitrum
        if (chainId == 10) return 30111;        // Optimism
        if (chainId == 8453) return 30184;      // Base
        if (chainId == 96369) return 30369;     // Lux (custom EID)
        revert("BridgeLib: unsupported LZ chain");
    }

    /// @notice Chain ID to Wormhole chain ID mapping
    function getWormholeChainId(uint256 chainId) internal pure returns (uint16) {
        if (chainId == 1) return 2;             // Ethereum
        if (chainId == 56) return 4;            // BSC
        if (chainId == 137) return 5;           // Polygon
        if (chainId == 43114) return 6;         // Avalanche
        if (chainId == 42161) return 23;        // Arbitrum
        if (chainId == 10) return 24;           // Optimism
        if (chainId == 8453) return 30;         // Base
        if (chainId == 96369) return 36;        // Lux (reserved)
        revert("BridgeLib: unsupported Wormhole chain");
    }

    /// @notice Convert address to bytes32 for LayerZero
    function addressToBytes32(address addr) internal pure returns (bytes32) {
        return bytes32(uint256(uint160(addr)));
    }

    /// @notice Convert bytes32 to address
    function bytes32ToAddress(bytes32 b) internal pure returns (address) {
        return address(uint160(uint256(b)));
    }

    /// @notice Encode LayerZero options for gas limit
    function encodeLzOptions(uint128 gasLimit) internal pure returns (bytes memory) {
        // Type 3 options with executor gas
        return abi.encodePacked(
            uint16(3),          // Options type
            uint8(1),           // Worker options
            uint16(17),         // Length of gas option
            uint8(1),           // Gas option type
            uint128(gasLimit),  // Gas limit
            uint128(0)          // Native drop (0)
        );
    }
}

/// @title AxelarExecutable
/// @notice Base contract for Axelar GMP receivers
abstract contract AxelarExecutable {
    IAxelarGateway public immutable gateway;

    constructor(address _gateway) {
        gateway = IAxelarGateway(_gateway);
    }

    function execute(
        bytes32 commandId,
        string calldata sourceChain,
        string calldata sourceAddress,
        bytes calldata payload
    ) external {
        require(
            gateway.validateContractCall(commandId, sourceChain, sourceAddress, keccak256(payload)),
            "Invalid command"
        );
        _execute(sourceChain, sourceAddress, payload);
    }

    function executeWithToken(
        bytes32 commandId,
        string calldata sourceChain,
        string calldata sourceAddress,
        bytes calldata payload,
        string calldata tokenSymbol,
        uint256 amount
    ) external {
        require(
            gateway.validateContractCallAndMint(
                commandId,
                sourceChain,
                sourceAddress,
                keccak256(payload),
                tokenSymbol,
                amount
            ),
            "Invalid command"
        );
        _executeWithToken(sourceChain, sourceAddress, payload, tokenSymbol, amount);
    }

    function _execute(
        string calldata sourceChain,
        string calldata sourceAddress,
        bytes calldata payload
    ) internal virtual;

    function _executeWithToken(
        string calldata sourceChain,
        string calldata sourceAddress,
        bytes calldata payload,
        string calldata tokenSymbol,
        uint256 amount
    ) internal virtual {}
}

/// @title LayerZeroReceiver
/// @notice Base contract for LayerZero V2 receivers (OApp pattern)
abstract contract LayerZeroReceiver {
    ILayerZeroEndpointV2 public immutable endpoint;
    mapping(uint32 => bytes32) public peers;

    constructor(address _endpoint) {
        endpoint = ILayerZeroEndpointV2(_endpoint);
    }

    function setPeer(uint32 _eid, bytes32 _peer) external virtual {
        peers[_eid] = _peer;
    }

    function lzReceive(
        uint32 _srcEid,
        bytes32 _sender,
        uint64 _nonce,
        bytes calldata _message
    ) external {
        require(msg.sender == address(endpoint), "Not endpoint");
        require(_sender == peers[_srcEid], "Unknown peer");
        _lzReceive(_srcEid, _sender, _nonce, _message);
    }

    function _lzReceive(
        uint32 _srcEid,
        bytes32 _sender,
        uint64 _nonce,
        bytes calldata _message
    ) internal virtual;
}

/// @title WormholeReceiver
/// @notice Base contract for Wormhole receivers
abstract contract WormholeReceiver {
    IWormholeRelayer public immutable wormholeRelayer;
    mapping(uint16 => bytes32) public registeredSenders;

    constructor(address _relayer) {
        wormholeRelayer = IWormholeRelayer(_relayer);
    }

    function receiveWormholeMessages(
        bytes memory payload,
        bytes[] memory,
        bytes32 sourceAddress,
        uint16 sourceChain,
        bytes32
    ) public payable {
        require(msg.sender == address(wormholeRelayer), "Not relayer");
        require(sourceAddress == registeredSenders[sourceChain], "Unknown sender");
        _receiveWormholeMessage(payload, sourceChain, sourceAddress);
    }

    function _receiveWormholeMessage(
        bytes memory payload,
        uint16 sourceChain,
        bytes32 sourceAddress
    ) internal virtual;
}

/// @title WarpReceiver
/// @notice Base contract for Lux Warp message receivers
abstract contract WarpReceiver {
    IWarp internal constant WARP = IWarp(0x0200000000000000000000000000000000000005);

    mapping(bytes32 => bool) public trustedChains;
    mapping(bytes32 => mapping(address => bool)) public trustedSenders;

    function receiveWarpMessage(uint32 warpIndex) external {
        (bytes32 sourceChainId, address sender, bytes memory payload) =
            WARP.getVerifiedWarpMessage(warpIndex);

        require(trustedChains[sourceChainId], "Untrusted chain");
        require(trustedSenders[sourceChainId][sender], "Untrusted sender");

        _receiveWarpMessage(sourceChainId, sender, payload);
    }

    function _receiveWarpMessage(
        bytes32 sourceChainId,
        address sender,
        bytes memory payload
    ) internal virtual;
}
