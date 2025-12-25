// SPDX-License-Identifier: BSD-3-Clause
// Copyright (c) 2025 Lux Industries Inc.
// Copyright (C) 2019-2025, Lux Industries Inc. All rights reserved.
pragma solidity ^0.8.31;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
    ██╗     ██╗   ██╗██╗  ██╗     █████╗ ██╗    ████████╗ ██████╗ ██╗  ██╗███████╗███╗   ██╗
    ██║     ██║   ██║╚██╗██╔╝    ██╔══██╗██║    ╚══██╔══╝██╔═══██╗██║ ██╔╝██╔════╝████╗  ██║
    ██║     ██║   ██║ ╚███╔╝     ███████║██║       ██║   ██║   ██║█████╔╝ █████╗  ██╔██╗ ██║
    ██║     ██║   ██║ ██╔██╗     ██╔══██║██║       ██║   ██║   ██║██╔═██╗ ██╔══╝  ██║╚██╗██║
    ███████╗╚██████╔╝██╔╝ ██╗    ██║  ██║██║       ██║   ╚██████╔╝██║  ██╗███████╗██║ ╚████║
    ╚══════╝ ╚═════╝ ╚═╝  ╚═╝    ╚═╝  ╚═╝╚═╝       ╚═╝    ╚═════╝ ╚═╝  ╚═╝╚══════╝╚═╝  ╚═══╝

    AI Token - Hardware-attested GPU compute mining

    Architecture:
    ┌─────────────────────────────────────────────────────────────────────────────────────────┐
    │  Q-Chain (Quantum Finality) - Shared quantum safety via Quasar (BLS/Ringtail)          │
    │  ┌─────────────────────────────────────────────────────────────────────────────────┐   │
    │  │ Stores quantum-final block tips from: P-Chain | C-Chain | X-Chain | A-Chain    │   │
    │  │ | Hanzo | Zoo | All Subnets                                                     │   │
    │  └─────────────────────────────────────────────────────────────────────────────────┘   │
    └─────────────────────────────────────────────────────────────────────────────────────────┘
                                              │
    ┌─────────────────────────────────────────┼───────────────────────────────────────────────┐
    │  Source Chains: C-Chain, Hanzo EVM, Zoo EVM                                             │
    │  ┌─────────────┐    ┌─────────────┐    ┌─────────────┐    ┌─────────────┐             │
    │  │ Pay with    │ -> │ Swap to LUX │ -> │ Bridge to   │ -> │ Attestation │             │
    │  │ AI/ETH/BTC  │    │ (DEX pools) │    │ A-Chain     │    │ Stored      │             │
    │  │ ZOO/any     │    │             │    │ (Warp)      │    │             │             │
    │  └─────────────┘    └─────────────┘    └─────────────┘    └─────────────┘             │
    │                                                                                         │
    │  AI/LUX pool enables paying attestation fees with AI tokens                            │
    └─────────────────────────────────────────────────────────────────────────────────────────┘
                                              │ Warp
    ┌─────────────────────────────────────────┼───────────────────────────────────────────────┐
    │  A-Chain (Attestation Chain) - GPU compute attestation storage                         │
    │  ┌─────────────┐    ┌─────────────┐    ┌─────────────┐    ┌─────────────┐             │
    │  │ GPU Compute │ -> │ TEE Quote   │ -> │ Attestation │ -> │  AI Mint    │             │
    │  │ (NVIDIA)    │    │ Verified    │    │ Stored      │    │  (Native)   │             │
    │  └─────────────┘    └─────────────┘    └─────────────┘    └─────────────┘             │
    │                                                                  │                      │
    │  Payment: LUX required (from bridged assets or native AI→LUX)  │                      │
    │  Q-Chain provides quantum finality for attestation proofs       │                      │
    └─────────────────────────────────────────────────────────────────┼──────────────────────┘
                                                                       │ Teleport (Warp)
    ┌─────────────────────────────────────────────────────────────────┼──────────────────────┐
    │  Destination: C-Chain, Hanzo, Zoo (claim minted AI)             ▼                      │
    │  ┌─────────────┐    ┌─────────────┐    ┌─────────────┐                                 │
    │  │ Warp Proof  │ -> │  Verify &   │ -> │  AI Mint    │                                 │
    │  │ (from A)    │    │  Claim      │    │  (Remote)   │                                 │
    │  └─────────────┘    └─────────────┘    └─────────────┘                                 │
    └─────────────────────────────────────────────────────────────────────────────────────────┘

    References:
    - LP-2000: AI Mining Standard
    - HIP-006: Hanzo AI Mining Protocol
    - ZIP-005: Zoo AI Mining Integration
    - LP-1001: Q-Chain Quantum Finality
    - LP-1002: Quasar Consensus (BLS/Ringtail Hybrid)
 */

import "./LRC20B.sol";
// IERC20 is already defined in ERC20B.sol (flattened)

// ============ Precompile Interfaces ============

/**
 * @dev Warp Messaging precompile interface (0x0200...0005)
 */
interface IWarp {
    struct WarpMessage {
        bytes32 sourceChainID;
        address originSenderAddress;
        bytes payload;
    }

    function getBlockchainID() external view returns (bytes32 blockchainID);
    function getVerifiedWarpMessage(uint32 index) external view returns (WarpMessage memory message, bool valid);
    function sendWarpMessage(bytes calldata payload) external returns (bytes32 messageID);
}

/**
 * @dev AI Attestation precompile interface (0x0300) - A-Chain only
 */
interface IAttestation {
    function submitAttestation(bytes calldata attestation) external returns (bytes32 attestationId, uint256 reward);
    function getSession(bytes32 sessionId) external view returns (address miner, uint64 startTime, uint8 privacy);
    function verifyTEEQuote(bytes calldata quote) external view returns (bool valid, bytes32 gpuId, uint8 privacyLevel);
}

/**
 * @dev DEX Router interface for swaps (Uniswap V2 compatible)
 */
interface IDEXRouter {
    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts);

    function swapExactETHForTokens(
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external payable returns (uint256[] memory amounts);

    function getAmountsOut(uint256 amountIn, address[] calldata path) external view returns (uint256[] memory amounts);
    function getAmountsIn(uint256 amountOut, address[] calldata path) external view returns (uint256[] memory amounts);
}

// Using IERC20 from OpenZeppelin via ERC20B import

// ============ Shared Types ============

/**
 * @notice Privacy level enum matching TEE hardware capability
 */
enum PrivacyLevel {
    Unknown,      // 0: Not attested
    Public,       // 1: Consumer GPU (stake-based soft attestation)
    Private,      // 2: Intel SGX or NVIDIA A100
    Confidential, // 3: NVIDIA H100 with TDX/SEV
    Sovereign     // 4: NVIDIA Blackwell full TEE
}

/**
 * @notice Attestation types for compute sessions
 */
enum AttestationType {
    Start,      // 0: Compute session started
    Heartbeat,  // 1: Per-minute heartbeat
    Complete    // 2: Compute session completed
}

/**
 * @notice Attestation data structure (ABI-encoded for Warp messages)
 */
struct Attestation {
    bytes32 sessionId;      // Unique session identifier
    bytes32 gpuId;          // GPU device identifier (hash of TEE quote)
    address miner;          // Miner address to receive credits
    AttestationType aType;  // Type of attestation
    PrivacyLevel privacy;   // Privacy/trust level
    uint64 timestamp;       // Unix timestamp
    uint64 computeMinutes;  // Minutes of compute (for Complete type)
    bytes32 prevHash;       // Hash chain link (for integrity)
}

// ============================================================================
// AIPaymentRouter - Multi-token payment for attestation (Source Chains)
// Deployed on: C-Chain, Hanzo EVM, Zoo EVM
// ============================================================================

/**
 * @title AIPaymentRouter
 * @notice Accepts any supported token, swaps to LUX, bridges to A-Chain for attestation storage
 * @dev Uses native DEX pools (AI/LUX, ETH/LUX, BTC/LUX, ZOO/LUX, etc.)
 *
 * Payment Flow:
 * 1. User pays with AI/ETH/BTC/ZOO/any supported token
 * 2. Token swapped to LUX via DEX
 * 3. LUX bridged to A-Chain via Warp
 * 4. Attestation stored on A-Chain (paid in LUX)
 * 5. AI minted to user on A-Chain
 * 6. User can teleport AI back to source chain
 */
contract AIPaymentRouter {
    // ============ Constants ============

    address public constant WARP_PRECOMPILE = 0x0200000000000000000000000000000000000005;

    // ============ Immutables ============

    /// @notice Wrapped LUX token address
    address public immutable WLUX;

    /// @notice DEX router for token swaps
    address public immutable DEX_ROUTER;

    /// @notice A-Chain blockchain ID
    bytes32 public immutable A_CHAIN_ID;

    /// @notice AI token on this chain
    address public immutable AI_TOKEN;

    /// @notice WETH/native wrapper on this chain
    address public immutable WETH;

    // ============ State ============

    /// @notice Admin address
    address public admin;

    /// @notice Attestation cost in LUX
    uint256 public attestationCostLUX;

    /// @notice Supported payment tokens
    mapping(address => bool) public supportedTokens;

    /// @notice Pending attestation requests
    mapping(bytes32 => AttestationRequest) public requests;

    struct AttestationRequest {
        address requester;
        bytes32 sessionId;
        uint256 luxPaid;
        uint64 timestamp;
        bool bridged;
    }

    // ============ Events ============

    event PaymentReceived(address indexed payer, address indexed token, uint256 amountIn, uint256 luxOut, bytes32 indexed requestId);
    event AttestationBridged(bytes32 indexed requestId, bytes32 indexed warpMessageId, uint256 luxAmount);
    event TokenAdded(address indexed token);
    event TokenRemoved(address indexed token);
    event CostUpdated(uint256 newCost);

    // ============ Errors ============

    error UnsupportedToken();
    error InsufficientPayment();
    error SlippageExceeded();
    error OnlyAdmin();
    error TransferFailed();

    // ============ Constructor ============

    constructor(
        address _wlux,
        address _weth,
        address _dexRouter,
        bytes32 _aChainId,
        address _aiToken,
        uint256 _attestationCost
    ) {
        WLUX = _wlux;
        WETH = _weth;
        DEX_ROUTER = _dexRouter;
        A_CHAIN_ID = _aChainId;
        AI_TOKEN = _aiToken;
        attestationCostLUX = _attestationCost;
        admin = msg.sender;

        // Default supported tokens
        supportedTokens[_wlux] = true;      // LUX (direct)
        supportedTokens[_aiToken] = true;   // AI (via AI/LUX pool)
        supportedTokens[address(0)] = true; // Native ETH
    }

    // ============ Payment Functions ============

    /**
     * @notice Pay for attestation with any supported token
     * @param token Payment token (address(0) for native ETH)
     * @param amount Amount of payment token
     * @param minLuxOut Minimum LUX to receive (slippage protection)
     * @param sessionId Compute session ID
     * @return requestId The attestation request ID
     */
    function payForAttestation(
        address token,
        uint256 amount,
        uint256 minLuxOut,
        bytes32 sessionId
    ) external payable returns (bytes32 requestId) {
        if (!supportedTokens[token]) revert UnsupportedToken();

        uint256 luxReceived;

        if (token == address(0)) {
            // Native ETH payment
            luxReceived = _swapETHForLUX(msg.value, minLuxOut);
        } else if (token == WLUX) {
            // Direct LUX payment
            if (!IERC20(WLUX).transferFrom(msg.sender, address(this), amount)) revert TransferFailed();
            luxReceived = amount;
        } else {
            // ERC20 payment (AI, BTC, ZOO, etc.) - swap to LUX
            if (!IERC20(token).transferFrom(msg.sender, address(this), amount)) revert TransferFailed();
            luxReceived = _swapTokenForLUX(token, amount, minLuxOut);
        }

        if (luxReceived < attestationCostLUX) revert InsufficientPayment();

        // Generate request ID
        requestId = keccak256(abi.encode(msg.sender, sessionId, block.timestamp, block.chainid));

        // Store request
        requests[requestId] = AttestationRequest({
            requester: msg.sender,
            sessionId: sessionId,
            luxPaid: luxReceived,
            timestamp: uint64(block.timestamp),
            bridged: false
        });

        // Bridge LUX to A-Chain
        bytes32 warpId = _bridgeToAChain(requestId, msg.sender, luxReceived);
        requests[requestId].bridged = true;

        emit PaymentReceived(msg.sender, token, amount, luxReceived, requestId);
        emit AttestationBridged(requestId, warpId, luxReceived);

        return requestId;
    }

    /**
     * @notice Pay with AI tokens specifically (convenience function)
     */
    function payWithAI(uint256 aiAmount, uint256 minLuxOut, bytes32 sessionId) external returns (bytes32) {
        return this.payForAttestation(AI_TOKEN, aiAmount, minLuxOut, sessionId);
    }

    /**
     * @notice Pay with native ETH (convenience function)
     */
    function payWithETH(uint256 minLuxOut, bytes32 sessionId) external payable returns (bytes32) {
        return this.payForAttestation{value: msg.value}(address(0), msg.value, minLuxOut, sessionId);
    }

    /**
     * @notice Get quote: how much of a token is needed for one attestation
     * @param token The payment token
     * @return amountNeeded Amount of token needed
     */
    function getPaymentQuote(address token) external view returns (uint256 amountNeeded) {
        if (token == WLUX) {
            return attestationCostLUX;
        }

        address[] memory path = new address[](2);
        path[0] = token == address(0) ? WETH : token;
        path[1] = WLUX;

        uint256[] memory amounts = IDEXRouter(DEX_ROUTER).getAmountsIn(attestationCostLUX, path);
        return amounts[0];
    }

    // ============ Internal Functions ============

    function _swapETHForLUX(uint256 ethAmount, uint256 minLuxOut) internal returns (uint256) {
        address[] memory path = new address[](2);
        path[0] = WETH;
        path[1] = WLUX;

        uint256[] memory amounts = IDEXRouter(DEX_ROUTER).swapExactETHForTokens{value: ethAmount}(
            minLuxOut,
            path,
            address(this),
            block.timestamp + 300
        );

        return amounts[1];
    }

    function _swapTokenForLUX(address token, uint256 amountIn, uint256 minLuxOut) internal returns (uint256) {
        IERC20(token).approve(DEX_ROUTER, amountIn);

        address[] memory path = new address[](2);
        path[0] = token;
        path[1] = WLUX;

        uint256[] memory amounts = IDEXRouter(DEX_ROUTER).swapExactTokensForTokens(
            amountIn,
            minLuxOut,
            path,
            address(this),
            block.timestamp + 300
        );

        return amounts[1];
    }

    function _bridgeToAChain(bytes32 requestId, address requester, uint256 luxAmount) internal returns (bytes32) {
        // Encode attestation request for A-Chain
        bytes memory payload = abi.encode(requestId, requester, luxAmount);

        // Send via Warp to A-Chain
        return IWarp(WARP_PRECOMPILE).sendWarpMessage(payload);
    }

    // ============ Admin Functions ============

    function setAttestationCost(uint256 newCost) external {
        if (msg.sender != admin) revert OnlyAdmin();
        attestationCostLUX = newCost;
        emit CostUpdated(newCost);
    }

    function addToken(address token) external {
        if (msg.sender != admin) revert OnlyAdmin();
        supportedTokens[token] = true;
        emit TokenAdded(token);
    }

    function removeToken(address token) external {
        if (msg.sender != admin) revert OnlyAdmin();
        supportedTokens[token] = false;
        emit TokenRemoved(token);
    }

    function setAdmin(address newAdmin) external {
        if (msg.sender != admin) revert OnlyAdmin();
        admin = newAdmin;
    }

    receive() external payable {}
}

// ============================================================================
// AINative - Deployed on A-Chain (Attestation Chain)
// ============================================================================

/**
 * @title AINative
 * @notice AI Token on A-Chain with attestation-based minting
 * @dev Miners store attestations paid in LUX, receive AI rewards
 *
 * Flow:
 * 1. LUX payment received via Warp from source chain
 * 2. GPU compute session started with TEE quote
 * 3. Attestation stored on A-Chain (quantum-finalized via Q-Chain)
 * 4. AI tokens minted to miner
 * 5. Miner can teleport AI to destination chains
 */
contract AINative is LRC20B {
    // ============ Constants ============

    /// @notice Attestation precompile address
    address public constant ATTESTATION_PRECOMPILE = address(0x0300);

    /// @notice Warp precompile address
    address public constant WARP_PRECOMPILE = 0x0200000000000000000000000000000000000005;

    /// @notice Credits per minute of GPU compute (1 AI per minute base rate)
    uint256 public constant CREDITS_PER_MINUTE = 1e18;

    // ============ State ============

    /// @notice GPU tier to credit multiplier (basis points: 10000 = 1x)
    mapping(PrivacyLevel => uint256) public tierMultiplier;

    /// @notice Active sessions (sessionId => last heartbeat timestamp)
    mapping(bytes32 => uint64) public activeSessions;

    /// @notice Session miner (sessionId => miner address)
    mapping(bytes32 => address) public sessionMiner;

    /// @notice Session privacy level (sessionId => privacy)
    mapping(bytes32 => PrivacyLevel) public sessionPrivacy;

    /// @notice Trusted source chains for payments
    mapping(bytes32 => bool) public trustedChains;

    /// @notice Trusted payment routers per chain
    mapping(bytes32 => mapping(address => bool)) public trustedRouters;

    /// @notice Total LUX collected for attestations
    uint256 public totalLuxCollected;

    // ============ Events ============

    event SessionStarted(bytes32 indexed sessionId, address indexed miner, bytes32 gpuId, PrivacyLevel privacy);
    event HeartbeatReceived(bytes32 indexed sessionId, address indexed miner, uint64 timestamp, uint256 reward);
    event SessionCompleted(bytes32 indexed sessionId, address indexed miner, uint64 totalMinutes, uint256 totalReward);
    event Teleported(bytes32 indexed teleportId, bytes32 indexed destChainId, address indexed recipient, uint256 amount);
    event PaymentReceived(bytes32 indexed requestId, address indexed payer, uint256 luxAmount);

    // ============ Errors ============

    error InvalidAttestation();
    error InvalidPrivacyLevel();
    error SessionNotActive(bytes32 sessionId);
    error SessionAlreadyActive(bytes32 sessionId);
    error HeartbeatTooEarly(bytes32 sessionId);
    error InvalidTEEQuote();
    error InsufficientBalance();
    error UntrustedSource();

    // ============ Constructor ============

    constructor() LRC20B("AI", "AI") {
        // Set tier multipliers (basis points: 10000 = 1x)
        tierMultiplier[PrivacyLevel.Public] = 2500;       // 0.25x (stake-required)
        tierMultiplier[PrivacyLevel.Private] = 5000;      // 0.5x (SGX/A100)
        tierMultiplier[PrivacyLevel.Confidential] = 10000; // 1.0x (H100/TDX)
        tierMultiplier[PrivacyLevel.Sovereign] = 15000;   // 1.5x (Blackwell)
    }

    // ============ Payment Reception ============

    /**
     * @notice Receive payment from source chain via Warp
     * @param warpIndex Index of the Warp message
     */
    function receivePayment(uint32 warpIndex) external {
        (IWarp.WarpMessage memory message, bool valid) = IWarp(WARP_PRECOMPILE).getVerifiedWarpMessage(warpIndex);

        if (!valid) revert UntrustedSource();
        if (!trustedChains[message.sourceChainID]) revert UntrustedSource();
        if (!trustedRouters[message.sourceChainID][message.originSenderAddress]) revert UntrustedSource();

        (bytes32 requestId, address payer, uint256 luxAmount) = abi.decode(message.payload, (bytes32, address, uint256));

        totalLuxCollected += luxAmount;
        emit PaymentReceived(requestId, payer, luxAmount);
    }

    // ============ Mining Functions ============

    /**
     * @notice Start a new compute session with TEE quote
     * @param sessionId Unique session identifier
     * @param teeQuote The TEE attestation quote from GPU
     */
    function startSession(bytes32 sessionId, bytes calldata teeQuote) external {
        if (activeSessions[sessionId] != 0) {
            revert SessionAlreadyActive(sessionId);
        }

        // Verify TEE quote via precompile
        (bool success, bytes memory result) = ATTESTATION_PRECOMPILE.staticcall(
            abi.encodeWithSelector(IAttestation.verifyTEEQuote.selector, teeQuote)
        );
        require(success, "TEE verification failed");

        (bool teeValid, bytes32 gpuId, uint8 privacyLevel) = abi.decode(result, (bool, bytes32, uint8));
        if (!teeValid) revert InvalidTEEQuote();

        PrivacyLevel privacy = PrivacyLevel(privacyLevel);
        if (privacy == PrivacyLevel.Unknown) revert InvalidPrivacyLevel();

        // Record session
        activeSessions[sessionId] = uint64(block.timestamp);
        sessionMiner[sessionId] = msg.sender;
        sessionPrivacy[sessionId] = privacy;

        emit SessionStarted(sessionId, msg.sender, gpuId, privacy);
    }

    /**
     * @notice Submit a heartbeat attestation (per-minute proof)
     * @param sessionId The session identifier
     * @return reward The AI reward minted
     */
    function heartbeat(bytes32 sessionId) external returns (uint256 reward) {
        uint64 lastTimestamp = activeSessions[sessionId];
        if (lastTimestamp == 0) revert SessionNotActive(sessionId);

        address miner = sessionMiner[sessionId];
        require(msg.sender == miner, "Not session owner");

        // Validate timing (must be >= 60 seconds since last)
        if (block.timestamp < lastTimestamp + 60) {
            revert HeartbeatTooEarly(sessionId);
        }

        // Update session timestamp
        activeSessions[sessionId] = uint64(block.timestamp);

        // Calculate reward for 1 minute
        PrivacyLevel privacy = sessionPrivacy[sessionId];
        uint256 multiplier = tierMultiplier[privacy];
        reward = (CREDITS_PER_MINUTE * multiplier) / 10000;

        // Mint reward
        _mint(miner, reward);

        emit HeartbeatReceived(sessionId, miner, uint64(block.timestamp), reward);
        return reward;
    }

    /**
     * @notice Complete a compute session and claim final reward
     * @param sessionId The session identifier
     * @return totalReward The total AI reward for remaining minutes
     */
    function completeSession(bytes32 sessionId) external returns (uint256 totalReward) {
        uint64 startTime = activeSessions[sessionId];
        if (startTime == 0) revert SessionNotActive(sessionId);

        address miner = sessionMiner[sessionId];
        require(msg.sender == miner, "Not session owner");

        // Calculate remaining minutes since last heartbeat
        uint64 elapsedMinutes = uint64((block.timestamp - startTime) / 60);

        // Calculate final reward
        PrivacyLevel privacy = sessionPrivacy[sessionId];
        uint256 multiplier = tierMultiplier[privacy];
        totalReward = (CREDITS_PER_MINUTE * elapsedMinutes * multiplier) / 10000;

        // Clear session
        delete activeSessions[sessionId];
        delete sessionMiner[sessionId];
        delete sessionPrivacy[sessionId];

        // Mint final reward
        if (totalReward > 0) {
            _mint(miner, totalReward);
        }

        emit SessionCompleted(sessionId, miner, elapsedMinutes, totalReward);
        return totalReward;
    }

    // ============ Teleport Functions ============

    /**
     * @notice Teleport AI tokens to another chain
     * @param destChainId Destination chain ID (C-Chain, Hanzo, Zoo)
     * @param recipient Recipient address on destination chain
     * @param amount Amount of AI to teleport
     * @return teleportId The teleport transfer ID
     */
    function teleport(bytes32 destChainId, address recipient, uint256 amount) external returns (bytes32 teleportId) {
        if (balanceOf(msg.sender) < amount) revert InsufficientBalance();

        // Burn tokens on A-Chain
        _burn(msg.sender, amount);

        // Send Warp message with teleport data
        bytes memory payload = abi.encode(recipient, amount);
        teleportId = IWarp(WARP_PRECOMPILE).sendWarpMessage(payload);

        emit Teleported(teleportId, destChainId, recipient, amount);
        return teleportId;
    }

    // ============ Admin Functions ============

    function setTierMultiplier(PrivacyLevel level, uint256 multiplier) external onlyAdmin {
        if (level == PrivacyLevel.Unknown) revert InvalidPrivacyLevel();
        tierMultiplier[level] = multiplier;
    }

    function addTrustedChain(bytes32 chainId) external onlyAdmin {
        trustedChains[chainId] = true;
    }

    function removeTrustedChain(bytes32 chainId) external onlyAdmin {
        trustedChains[chainId] = false;
    }

    function addTrustedRouter(bytes32 chainId, address router) external onlyAdmin {
        trustedRouters[chainId][router] = true;
    }

    function removeTrustedRouter(bytes32 chainId, address router) external onlyAdmin {
        trustedRouters[chainId][router] = false;
    }

    function getBlockchainID() external view returns (bytes32) {
        return IWarp(WARP_PRECOMPILE).getBlockchainID();
    }
}

// ============================================================================
// AIRemote - Deployed on destination chains (C-Chain, Hanzo, Zoo)
// ============================================================================

/**
 * @title AIRemote
 * @notice AI Token on destination chains, minted via Warp teleport from A-Chain
 */
contract AIRemote is LRC20B {
    // ============ Constants ============

    bytes32 public immutable A_CHAIN_ID;
    address public immutable A_CHAIN_TOKEN;
    address public constant WARP_PRECOMPILE = 0x0200000000000000000000000000000000000005;

    // ============ State ============

    mapping(bytes32 => bool) public claimed;
    mapping(address => bool) public trustedSources;

    // ============ Events ============

    event TeleportClaimed(bytes32 indexed teleportId, address indexed recipient, uint256 amount);
    event TrustedSourceAdded(address indexed source);
    event TrustedSourceRemoved(address indexed source);

    // ============ Errors ============

    error TeleportAlreadyClaimed(bytes32 teleportId);
    error WarpMessageNotVerified();
    error UntrustedSource(bytes32 chainId, address sender);
    error InvalidPayload();

    // ============ Constructor ============

    constructor(bytes32 _aChainId, address _aChainToken) LRC20B("AI", "AI") {
        A_CHAIN_ID = _aChainId;
        A_CHAIN_TOKEN = _aChainToken;
    }

    // ============ Claim Functions ============

    /**
     * @notice Claim teleported AI tokens via Warp proof
     */
    function claimTeleport(uint32 warpIndex) external returns (uint256 amount) {
        (IWarp.WarpMessage memory message, bool valid) = IWarp(WARP_PRECOMPILE).getVerifiedWarpMessage(warpIndex);

        if (!valid) revert WarpMessageNotVerified();
        if (message.sourceChainID != A_CHAIN_ID) {
            revert UntrustedSource(message.sourceChainID, message.originSenderAddress);
        }
        if (message.originSenderAddress != A_CHAIN_TOKEN && !trustedSources[message.originSenderAddress]) {
            revert UntrustedSource(message.sourceChainID, message.originSenderAddress);
        }

        bytes32 teleportId = keccak256(abi.encode(message.sourceChainID, message.originSenderAddress, message.payload));
        if (claimed[teleportId]) revert TeleportAlreadyClaimed(teleportId);
        claimed[teleportId] = true;

        (address recipient, uint256 teleportAmount) = abi.decode(message.payload, (address, uint256));
        if (recipient == address(0) || teleportAmount == 0) revert InvalidPayload();

        _mint(recipient, teleportAmount);

        emit TeleportClaimed(teleportId, recipient, teleportAmount);
        return teleportAmount;
    }

    /**
     * @notice Batch claim multiple teleports in one tx
     */
    function batchClaimTeleports(uint32[] calldata warpIndices) external returns (uint256 totalAmount) {
        for (uint256 i = 0; i < warpIndices.length; i++) {
            (IWarp.WarpMessage memory message, bool valid) = IWarp(WARP_PRECOMPILE).getVerifiedWarpMessage(warpIndices[i]);

            if (!valid) continue;
            if (message.sourceChainID != A_CHAIN_ID) continue;
            if (message.originSenderAddress != A_CHAIN_TOKEN && !trustedSources[message.originSenderAddress]) continue;

            bytes32 teleportId = keccak256(abi.encode(message.sourceChainID, message.originSenderAddress, message.payload));
            if (claimed[teleportId]) continue;

            claimed[teleportId] = true;

            (address recipient, uint256 amount) = abi.decode(message.payload, (address, uint256));
            if (recipient != address(0) && amount > 0) {
                _mint(recipient, amount);
                totalAmount += amount;
                emit TeleportClaimed(teleportId, recipient, amount);
            }
        }
        return totalAmount;
    }

    // ============ Admin Functions ============

    function addTrustedSource(address source) external onlyAdmin {
        trustedSources[source] = true;
        emit TrustedSourceAdded(source);
    }

    function removeTrustedSource(address source) external onlyAdmin {
        trustedSources[source] = false;
        emit TrustedSourceRemoved(source);
    }

    function getBlockchainID() external view returns (bytes32) {
        return IWarp(WARP_PRECOMPILE).getBlockchainID();
    }
}

// ============================================================================
// Factory Contracts
// ============================================================================

contract AINativeFactory {
    event AINativeDeployed(address indexed token, uint256 chainId);

    function deploy() external returns (address token) {
        token = address(new AINative());
        emit AINativeDeployed(token, block.chainid);
        return token;
    }
}

contract AIRemoteFactory {
    event AIRemoteDeployed(address indexed token, bytes32 indexed aChainId, address indexed aChainToken, uint256 chainId);

    function deploy(bytes32 aChainId, address aChainToken) external returns (address token) {
        token = address(new AIRemote(aChainId, aChainToken));
        emit AIRemoteDeployed(token, aChainId, aChainToken, block.chainid);
        return token;
    }
}

contract AIPaymentRouterFactory {
    event RouterDeployed(address indexed router, uint256 chainId, bytes32 indexed aChainId);

    function deploy(
        address wlux,
        address weth,
        address dexRouter,
        bytes32 aChainId,
        address aiToken,
        uint256 attestationCost
    ) external returns (address router) {
        router = address(new AIPaymentRouter(wlux, weth, dexRouter, aChainId, aiToken, attestationCost));
        emit RouterDeployed(router, block.chainid, aChainId);
        return router;
    }
}
