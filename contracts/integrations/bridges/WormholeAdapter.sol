// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.31;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title WormholeAdapter
 * @notice Complete adapter for Wormhole cross-chain messaging
 * @dev Implements both automatic relay (WormholeRelayer) and manual relay (CoreBridge) patterns
 *
 * Apache-2.0 licensed - Wormhole SDK is Apache-2.0
 *
 * Architecture:
 * ┌─────────────────────────────────────────────────────────────────────────────┐
 * │  SOURCE CHAIN                                                               │
 * │  ┌─────────────┐    ┌─────────────┐    ┌─────────────┐                     │
 * │  │ User/       │ -> │ Wormhole    │ -> │ Guardian    │                     │
 * │  │ Protocol    │    │ Adapter     │    │ Network     │                     │
 * │  └─────────────┘    └─────────────┘    └─────────────┘                     │
 * └──────────────────────────────────────────┼──────────────────────────────────┘
 *                                            │ VAA (Verifiable Action Approval)
 * ┌──────────────────────────────────────────┼──────────────────────────────────┐
 * │  DESTINATION CHAIN                       ▼                                  │
 * │  ┌─────────────┐    ┌─────────────┐    ┌─────────────┐                     │
 * │  │ Wormhole    │ <- │ Relayer     │ <- │ VAA         │                     │
 * │  │ Adapter     │    │ (Auto/Man)  │    │ Verification│                     │
 * │  └─────────────┘    └─────────────┘    └─────────────┘                     │
 * └─────────────────────────────────────────────────────────────────────────────┘
 */

// ═══════════════════════════════════════════════════════════════════════════════
// WORMHOLE INTERFACES
// ═══════════════════════════════════════════════════════════════════════════════

/// @notice Wormhole Core Bridge interface for publishing messages
interface IWormhole {
    /// @notice Publish a message to be picked up by Guardians
    /// @param nonce Unique nonce for deduplication
    /// @param payload Message payload
    /// @param consistencyLevel Finality requirement (1 = instant, 200+ = finalized)
    /// @return sequence Message sequence number
    function publishMessage(
        uint32 nonce,
        bytes memory payload,
        uint8 consistencyLevel
    ) external payable returns (uint64 sequence);

    /// @notice Parse and verify a VAA
    /// @param encodedVM The VAA bytes
    /// @return vm The parsed VM struct
    /// @return valid Whether the VAA is valid
    /// @return reason Failure reason if invalid
    function parseAndVerifyVM(bytes calldata encodedVM)
        external
        view
        returns (VM memory vm, bool valid, string memory reason);

    /// @notice Get the message fee
    function messageFee() external view returns (uint256);

    /// @notice Get the current guardian set index
    function getCurrentGuardianSetIndex() external view returns (uint32);

    /// @notice Check if a sequence has been consumed
    function isMessageConsumed(bytes32 hash) external view returns (bool);
}

/// @notice Parsed VAA structure
struct VM {
    uint8 version;
    uint32 timestamp;
    uint32 nonce;
    uint16 emitterChainId;
    bytes32 emitterAddress;
    uint64 sequence;
    uint8 consistencyLevel;
    bytes payload;
    uint32 guardianSetIndex;
    Signature[] signatures;
    bytes32 hash;
}

/// @notice Guardian signature
struct Signature {
    bytes32 r;
    bytes32 s;
    uint8 v;
    uint8 guardianIndex;
}

/// @notice Wormhole Automatic Relayer interface
interface IWormholeRelayer {
    /// @notice Send a message to another chain with automatic delivery
    /// @param targetChain Wormhole chain ID of destination
    /// @param targetAddress Contract address on destination (as bytes32)
    /// @param payload Message payload
    /// @param receiverValue Native tokens to send to receiver
    /// @param gasLimit Gas limit for execution on target chain
    /// @return sequence Message sequence number
    function sendPayloadToEvm(
        uint16 targetChain,
        address targetAddress,
        bytes memory payload,
        uint256 receiverValue,
        uint256 gasLimit
    ) external payable returns (uint64 sequence);

    /// @notice Send tokens with a message
    function sendVaasToEvm(
        uint16 targetChain,
        address targetAddress,
        bytes memory payload,
        uint256 receiverValue,
        uint256 gasLimit,
        VaaKey[] memory vaaKeys
    ) external payable returns (uint64 sequence);

    /// @notice Get delivery price quote
    /// @param targetChain Wormhole chain ID
    /// @param receiverValue Native tokens for receiver
    /// @param gasLimit Gas limit for execution
    /// @return nativePriceQuote Price in native tokens
    /// @return targetChainRefundPerGasUnused Refund rate
    function quoteEVMDeliveryPrice(
        uint16 targetChain,
        uint256 receiverValue,
        uint256 gasLimit
    ) external view returns (uint256 nativePriceQuote, uint256 targetChainRefundPerGasUnused);

    /// @notice Resend a failed delivery
    function resendToEvm(
        VaaKey memory deliveryVaaKey,
        uint16 targetChain,
        uint256 newReceiverValue,
        uint256 newGasLimit,
        address newDeliveryProviderAddress
    ) external payable returns (uint64 sequence);
}

/// @notice VAA key for referencing messages
struct VaaKey {
    uint16 chainId;
    bytes32 emitterAddress;
    uint64 sequence;
}

/// @notice Wormhole Token Bridge interface for token transfers
interface ITokenBridge {
    /// @notice Transfer tokens to another chain
    function transferTokens(
        address token,
        uint256 amount,
        uint16 recipientChain,
        bytes32 recipient,
        uint256 arbiterFee,
        uint32 nonce
    ) external payable returns (uint64 sequence);

    /// @notice Transfer native tokens
    function wrapAndTransferETH(
        uint16 recipientChain,
        bytes32 recipient,
        uint256 arbiterFee,
        uint32 nonce
    ) external payable returns (uint64 sequence);

    /// @notice Complete a token transfer
    function completeTransfer(bytes memory encodedVm) external;

    /// @notice Complete a native transfer
    function completeTransferAndUnwrapETH(bytes memory encodedVm) external;

    /// @notice Get wrapped asset address
    function wrappedAsset(uint16 tokenChainId, bytes32 tokenAddress) external view returns (address);

    /// @notice Check if asset is wrapped
    function isWrappedAsset(address token) external view returns (bool);

    /// @notice Get original asset info
    function bridgedTokens(address token) external view returns (uint16 chainId, bytes32 nativeContract);
}

// ═══════════════════════════════════════════════════════════════════════════════
// WORMHOLE ADAPTER IMPLEMENTATION
// ═══════════════════════════════════════════════════════════════════════════════

/**
 * @title WormholeAdapter
 * @notice Full-featured Wormhole adapter for cross-chain messaging and token transfers
 */
contract WormholeAdapter is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // ═══════════════════════════════════════════════════════════════════════
    // CONSTANTS
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice Default gas limit for cross-chain execution
    uint256 public constant DEFAULT_GAS_LIMIT = 250_000;

    /// @notice Consistency level for finalized messages
    uint8 public constant CONSISTENCY_LEVEL_FINALIZED = 200;

    /// @notice Consistency level for instant messages (less secure)
    uint8 public constant CONSISTENCY_LEVEL_INSTANT = 1;

    // ═══════════════════════════════════════════════════════════════════════
    // WORMHOLE CHAIN IDS
    // ═══════════════════════════════════════════════════════════════════════

    uint16 public constant CHAIN_ID_SOLANA = 1;
    uint16 public constant CHAIN_ID_ETHEREUM = 2;
    uint16 public constant CHAIN_ID_BSC = 4;
    uint16 public constant CHAIN_ID_POLYGON = 5;
    uint16 public constant CHAIN_ID_AVALANCHE = 6;
    uint16 public constant CHAIN_ID_ARBITRUM = 23;
    uint16 public constant CHAIN_ID_OPTIMISM = 24;
    uint16 public constant CHAIN_ID_BASE = 30;
    uint16 public constant CHAIN_ID_LUX = 36; // Reserved for Lux

    // ═══════════════════════════════════════════════════════════════════════
    // STATE VARIABLES
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice Wormhole Core Bridge
    IWormhole public immutable wormhole;

    /// @notice Wormhole Automatic Relayer
    IWormholeRelayer public immutable relayer;

    /// @notice Wormhole Token Bridge
    ITokenBridge public immutable tokenBridge;

    /// @notice Registered senders by chain ID
    mapping(uint16 => bytes32) public registeredSenders;

    /// @notice Processed message hashes (replay protection)
    mapping(bytes32 => bool) public processedMessages;

    /// @notice Custom gas limits per chain
    mapping(uint16 => uint256) public chainGasLimits;

    /// @notice Message nonce counter
    uint32 public nonce;

    // ═══════════════════════════════════════════════════════════════════════
    // EVENTS
    // ═══════════════════════════════════════════════════════════════════════

    event MessageSent(
        uint16 indexed targetChain,
        bytes32 indexed targetAddress,
        uint64 sequence,
        bytes payload
    );

    event MessageReceived(
        uint16 indexed sourceChain,
        bytes32 indexed sourceAddress,
        bytes payload
    );

    event TokensSent(
        uint16 indexed targetChain,
        address indexed token,
        uint256 amount,
        bytes32 recipient,
        uint64 sequence
    );

    event TokensReceived(
        uint16 indexed sourceChain,
        address indexed token,
        uint256 amount,
        address recipient
    );

    event SenderRegistered(uint16 indexed chainId, bytes32 sender);
    event GasLimitUpdated(uint16 indexed chainId, uint256 gasLimit);

    // ═══════════════════════════════════════════════════════════════════════
    // ERRORS
    // ═══════════════════════════════════════════════════════════════════════

    error InvalidVAA();
    error UnregisteredSender();
    error AlreadyProcessed();
    error InsufficientFee();
    error InvalidChain();
    error TransferFailed();

    // ═══════════════════════════════════════════════════════════════════════
    // CONSTRUCTOR
    // ═══════════════════════════════════════════════════════════════════════

    constructor(
        address _wormhole,
        address _relayer,
        address _tokenBridge
    ) Ownable(msg.sender) {
        wormhole = IWormhole(_wormhole);
        relayer = IWormholeRelayer(_relayer);
        tokenBridge = ITokenBridge(_tokenBridge);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // ADMIN FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice Register a trusted sender from another chain
    /// @param chainId Wormhole chain ID
    /// @param sender Sender address as bytes32 (left-padded for EVM addresses)
    function registerSender(uint16 chainId, bytes32 sender) external onlyOwner {
        registeredSenders[chainId] = sender;
        emit SenderRegistered(chainId, sender);
    }

    /// @notice Set custom gas limit for a chain
    /// @param chainId Wormhole chain ID
    /// @param gasLimit Gas limit for execution
    function setGasLimit(uint16 chainId, uint256 gasLimit) external onlyOwner {
        chainGasLimits[chainId] = gasLimit;
        emit GasLimitUpdated(chainId, gasLimit);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // MESSAGING - AUTOMATIC RELAY
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice Send a message using automatic relay
    /// @param targetChain Wormhole chain ID of destination
    /// @param targetAddress Contract address on destination
    /// @param payload Message payload
    /// @param receiverValue Native tokens to send to receiver
    /// @return sequence Message sequence number
    function sendMessageAutoRelay(
        uint16 targetChain,
        address targetAddress,
        bytes memory payload,
        uint256 receiverValue
    ) external payable nonReentrant returns (uint64 sequence) {
        uint256 gasLimit = _getGasLimit(targetChain);

        (uint256 fee,) = relayer.quoteEVMDeliveryPrice(targetChain, receiverValue, gasLimit);
        if (msg.value < fee) revert InsufficientFee();

        sequence = relayer.sendPayloadToEvm{value: fee}(
            targetChain,
            targetAddress,
            payload,
            receiverValue,
            gasLimit
        );

        emit MessageSent(targetChain, bytes32(uint256(uint160(targetAddress))), sequence, payload);

        // Refund excess
        if (msg.value > fee) {
            (bool success,) = msg.sender.call{value: msg.value - fee}("");
            if (!success) revert TransferFailed();
        }
    }

    /// @notice Receive a message from automatic relay (called by relayer)
    /// @param payload Message payload
    /// @param sourceChain Source chain ID
    /// @param sourceAddress Source contract address
    function receiveWormholeMessages(
        bytes memory payload,
        bytes[] memory,
        bytes32 sourceAddress,
        uint16 sourceChain,
        bytes32
    ) external payable {
        require(msg.sender == address(relayer), "Only relayer");
        if (registeredSenders[sourceChain] != sourceAddress) revert UnregisteredSender();

        emit MessageReceived(sourceChain, sourceAddress, payload);

        // Override this function to handle the message
        _handleMessage(sourceChain, sourceAddress, payload);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // MESSAGING - MANUAL RELAY (Core Bridge)
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice Send a message using core bridge (requires manual relay)
    /// @param payload Message payload
    /// @param consistencyLevel Finality requirement
    /// @return sequence Message sequence number
    function sendMessageManual(
        bytes memory payload,
        uint8 consistencyLevel
    ) external payable nonReentrant returns (uint64 sequence) {
        uint256 fee = wormhole.messageFee();
        if (msg.value < fee) revert InsufficientFee();

        sequence = wormhole.publishMessage{value: fee}(
            nonce++,
            payload,
            consistencyLevel
        );

        emit MessageSent(0, bytes32(0), sequence, payload);

        if (msg.value > fee) {
            (bool success,) = msg.sender.call{value: msg.value - fee}("");
            if (!success) revert TransferFailed();
        }
    }

    /// @notice Receive and verify a VAA manually
    /// @param encodedVAA The VAA bytes
    /// @return payload The decoded payload
    function receiveMessageManual(bytes calldata encodedVAA)
        external
        nonReentrant
        returns (bytes memory payload)
    {
        (VM memory vm, bool valid, string memory reason) = wormhole.parseAndVerifyVM(encodedVAA);
        if (!valid) revert InvalidVAA();
        if (registeredSenders[vm.emitterChainId] != vm.emitterAddress) revert UnregisteredSender();
        if (processedMessages[vm.hash]) revert AlreadyProcessed();

        processedMessages[vm.hash] = true;
        payload = vm.payload;

        emit MessageReceived(vm.emitterChainId, vm.emitterAddress, payload);

        _handleMessage(vm.emitterChainId, vm.emitterAddress, payload);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // TOKEN TRANSFERS
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice Transfer ERC20 tokens to another chain
    /// @param token Token address
    /// @param amount Amount to transfer
    /// @param targetChain Destination chain ID
    /// @param recipient Recipient address as bytes32
    /// @return sequence Message sequence number
    function transferTokens(
        address token,
        uint256 amount,
        uint16 targetChain,
        bytes32 recipient
    ) external payable nonReentrant returns (uint64 sequence) {
        uint256 fee = wormhole.messageFee();
        if (msg.value < fee) revert InsufficientFee();

        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
        IERC20(token).forceApprove(address(tokenBridge), amount);

        sequence = tokenBridge.transferTokens{value: fee}(
            token,
            amount,
            targetChain,
            recipient,
            0, // No arbiter fee
            nonce++
        );

        emit TokensSent(targetChain, token, amount, recipient, sequence);

        if (msg.value > fee) {
            (bool success,) = msg.sender.call{value: msg.value - fee}("");
            if (!success) revert TransferFailed();
        }
    }

    /// @notice Transfer native tokens to another chain
    /// @param targetChain Destination chain ID
    /// @param recipient Recipient address as bytes32
    /// @return sequence Message sequence number
    function transferNative(
        uint16 targetChain,
        bytes32 recipient
    ) external payable nonReentrant returns (uint64 sequence) {
        uint256 fee = wormhole.messageFee();
        if (msg.value <= fee) revert InsufficientFee();

        uint256 amount = msg.value - fee;

        sequence = tokenBridge.wrapAndTransferETH{value: msg.value}(
            targetChain,
            recipient,
            0, // No arbiter fee
            nonce++
        );

        emit TokensSent(targetChain, address(0), amount, recipient, sequence);
    }

    /// @notice Complete a token transfer from another chain
    /// @param encodedVAA The VAA bytes
    function completeTokenTransfer(bytes memory encodedVAA) external nonReentrant {
        tokenBridge.completeTransfer(encodedVAA);
    }

    /// @notice Complete a native token transfer
    /// @param encodedVAA The VAA bytes
    function completeNativeTransfer(bytes memory encodedVAA) external nonReentrant {
        tokenBridge.completeTransferAndUnwrapETH(encodedVAA);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // VIEW FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice Get quote for automatic relay
    /// @param targetChain Destination chain ID
    /// @param receiverValue Native tokens for receiver
    /// @return fee Required fee in native tokens
    function quoteDelivery(
        uint16 targetChain,
        uint256 receiverValue
    ) external view returns (uint256 fee) {
        uint256 gasLimit = _getGasLimit(targetChain);
        (fee,) = relayer.quoteEVMDeliveryPrice(targetChain, receiverValue, gasLimit);
    }

    /// @notice Get message fee for core bridge
    /// @return fee Required fee in native tokens
    function getMessageFee() external view returns (uint256 fee) {
        return wormhole.messageFee();
    }

    /// @notice Get wrapped asset address for a foreign token
    /// @param tokenChainId Source chain ID
    /// @param tokenAddress Token address as bytes32
    /// @return wrapped Wrapped token address on this chain
    function getWrappedAsset(uint16 tokenChainId, bytes32 tokenAddress)
        external
        view
        returns (address wrapped)
    {
        return tokenBridge.wrappedAsset(tokenChainId, tokenAddress);
    }

    /// @notice Convert EVM address to bytes32
    /// @param addr EVM address
    /// @return Address as bytes32 (left-padded)
    function addressToBytes32(address addr) external pure returns (bytes32) {
        return bytes32(uint256(uint160(addr)));
    }

    /// @notice Convert bytes32 to EVM address
    /// @param b Bytes32 value
    /// @return addr EVM address
    function bytes32ToAddress(bytes32 b) external pure returns (address addr) {
        return address(uint160(uint256(b)));
    }

    /// @notice Get Wormhole chain ID for EVM chain ID
    /// @param evmChainId EVM chain ID
    /// @return Wormhole chain ID
    function getWormholeChainId(uint256 evmChainId) external pure returns (uint16) {
        if (evmChainId == 1) return CHAIN_ID_ETHEREUM;
        if (evmChainId == 56) return CHAIN_ID_BSC;
        if (evmChainId == 137) return CHAIN_ID_POLYGON;
        if (evmChainId == 43114) return CHAIN_ID_AVALANCHE;
        if (evmChainId == 42161) return CHAIN_ID_ARBITRUM;
        if (evmChainId == 10) return CHAIN_ID_OPTIMISM;
        if (evmChainId == 8453) return CHAIN_ID_BASE;
        if (evmChainId == 96369) return CHAIN_ID_LUX;
        revert InvalidChain();
    }

    // ═══════════════════════════════════════════════════════════════════════
    // INTERNAL FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice Get gas limit for a chain
    function _getGasLimit(uint16 chainId) internal view returns (uint256) {
        uint256 limit = chainGasLimits[chainId];
        return limit > 0 ? limit : DEFAULT_GAS_LIMIT;
    }

    /// @notice Handle received message - override in derived contracts
    function _handleMessage(
        uint16 sourceChain,
        bytes32 sourceAddress,
        bytes memory payload
    ) internal virtual {
        // Override to implement custom message handling
    }

    /// @notice Receive native tokens
    receive() external payable {}
}

// ═══════════════════════════════════════════════════════════════════════════════
// WORMHOLE RECEIVER BASE
// ═══════════════════════════════════════════════════════════════════════════════

/**
 * @title WormholeReceiverBase
 * @notice Abstract base for contracts that receive Wormhole messages
 */
abstract contract WormholeReceiverBase {
    /// @notice Wormhole relayer address
    address public immutable wormholeRelayer;

    /// @notice Registered senders by chain ID
    mapping(uint16 => bytes32) public registeredSenders;

    error NotRelayer();
    error UnknownSender();

    constructor(address _relayer) {
        wormholeRelayer = _relayer;
    }

    /// @notice Register a trusted sender
    function _registerSender(uint16 chainId, bytes32 sender) internal {
        registeredSenders[chainId] = sender;
    }

    /// @notice Receive messages from Wormhole relayer
    function receiveWormholeMessages(
        bytes memory payload,
        bytes[] memory,
        bytes32 sourceAddress,
        uint16 sourceChain,
        bytes32
    ) external payable {
        if (msg.sender != wormholeRelayer) revert NotRelayer();
        if (sourceAddress != registeredSenders[sourceChain]) revert UnknownSender();

        _receiveWormholeMessage(payload, sourceChain, sourceAddress);
    }

    /// @notice Handle the received message
    function _receiveWormholeMessage(
        bytes memory payload,
        uint16 sourceChain,
        bytes32 sourceAddress
    ) internal virtual;
}
