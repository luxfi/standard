// SPDX-License-Identifier: BSD-3-Clause
// Copyright (c) 2025 Lux Industries Inc.
// Copyright (C) 2019-2025, Lux Industries Inc. All rights reserved.
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

/**
 * @title ComputeMarket
 * @notice Decentralized marketplace for AI compute services
 * @dev Implements Hamiltonian-inspired market dynamics for price discovery.
 *
 * Market Architecture:
 * - Providers register with compute capacity and pricing
 * - Users request compute with payment escrow
 * - Providers submit results, payment released on verification
 * - Slashing for invalid or missing compute
 *
 * Hamiltonian Market Dynamics:
 * - Energy conservation: Total value in system conserved
 * - Phase space: Price oscillates around equilibrium based on supply/demand
 * - Action principle: Market seeks minimum-energy (efficient) configuration
 * - Potential wells: Price stabilizes in equilibrium regions
 *
 * Pricing Model:
 * - Per-token pricing (input/output tokens)
 * - Per-inference pricing (batch operations)
 * - Time-based pricing (session compute)
 * - Dynamic adjustment based on utilization
 */
contract ComputeMarket is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;
    using ECDSA for bytes32;

    // ============ Types ============

    /// @notice Pricing model for compute services
    enum PricingModel {
        PerToken,      // 0: Price per input/output token
        PerInference,  // 1: Fixed price per inference call
        PerMinute,     // 2: Time-based pricing
        Hybrid         // 3: Combination pricing
    }

    /// @notice Request status
    enum RequestStatus {
        Pending,    // 0: Awaiting provider
        Active,     // 1: Provider assigned, in progress
        Completed,  // 2: Result submitted
        Verified,   // 3: Result verified, payment released
        Disputed,   // 4: Under dispute
        Cancelled,  // 5: Cancelled by requester
        Slashed     // 6: Provider slashed for failure
    }

    /// @notice Provider information
    struct Provider {
        bool registered;
        bool active;
        uint256 stake;                    // Collateral stake
        uint256 totalEarnings;            // Lifetime earnings
        uint256 completedJobs;            // Successfully completed jobs
        uint256 slashedCount;             // Number of slashing events
        uint256 reputation;               // Reputation score (0-10000)
        PricingModel model;               // Primary pricing model
        uint256 pricePerToken;            // Price per token (in payment token)
        uint256 pricePerInference;        // Price per inference
        uint256 pricePerMinute;           // Price per minute
        uint256 maxConcurrentJobs;        // Maximum concurrent requests
        uint256 currentJobs;              // Current active jobs
        string modelId;                   // Supported model identifier
        bytes32 gpuId;                    // Attested GPU identifier
    }

    /// @notice Compute request
    struct ComputeRequest {
        bytes32 requestId;                // Unique request identifier
        address requester;                // User who made request
        address provider;                 // Assigned provider
        uint256 escrowAmount;             // Escrowed payment
        uint256 estimatedTokens;          // Estimated token count
        uint256 createdAt;                // Request creation time
        uint256 deadline;                 // Completion deadline
        RequestStatus status;             // Current status
        bytes32 inputHash;                // Hash of input data
        bytes32 resultHash;               // Hash of result (when completed)
        string modelId;                   // Requested model
    }

    /// @notice Market state for Hamiltonian dynamics
    struct MarketState {
        uint256 totalSupply;              // Total provider capacity
        uint256 totalDemand;              // Total pending requests
        uint256 equilibriumPrice;         // Current equilibrium price
        uint256 priceVelocity;            // Price change rate
        uint256 lastUpdateBlock;          // Last state update
        uint256 utilizationRate;          // Current utilization (bps)
    }

    // ============ Constants ============

    /// @notice Minimum stake for providers
    uint256 public constant MIN_STAKE = 1000 ether; // 1000 AI tokens

    /// @notice Slashing percentage (in basis points)
    uint256 public constant SLASH_BPS = 1000; // 10%

    /// @notice Market fee (in basis points)
    uint256 public constant MARKET_FEE_BPS = 100; // 1%

    /// @notice Maximum request duration (7 days)
    uint256 public constant MAX_DURATION = 7 days;

    /// @notice Dispute window after completion
    uint256 public constant DISPUTE_WINDOW = 1 hours;

    /// @notice Price update interval
    uint256 public constant PRICE_UPDATE_INTERVAL = 100; // blocks

    /// @notice Hamiltonian damping factor (prevents wild oscillations)
    uint256 public constant DAMPING_FACTOR = 9500; // 95%

    // ============ State ============

    /// @notice Payment token (AI token)
    IERC20 public immutable paymentToken;

    /// @notice Provider registry
    mapping(address => Provider) public providers;

    /// @notice Request registry
    mapping(bytes32 => ComputeRequest) public requests;

    /// @notice Provider list
    address[] public providerList;

    /// @notice Market state
    MarketState public marketState;

    /// @notice Total escrowed amount
    uint256 public totalEscrowed;

    /// @notice Treasury address for fees
    address public treasury;

    /// @notice Accumulated fees
    uint256 public accumulatedFees;

    /// @notice Request nonce per user
    mapping(address => uint256) public userNonce;

    // ============ Events ============

    event ProviderRegistered(address indexed provider, uint256 stake, string modelId);
    event ProviderUpdated(address indexed provider, PricingModel model, uint256 price);
    event ProviderDeactivated(address indexed provider);
    event RequestCreated(bytes32 indexed requestId, address indexed requester, string modelId, uint256 escrow);
    event RequestAssigned(bytes32 indexed requestId, address indexed provider);
    event ResultSubmitted(bytes32 indexed requestId, bytes32 resultHash);
    event RequestVerified(bytes32 indexed requestId, uint256 payment);
    event RequestDisputed(bytes32 indexed requestId, address indexed disputer);
    event ProviderSlashed(address indexed provider, uint256 amount, bytes32 indexed requestId);
    event MarketStateUpdated(uint256 equilibriumPrice, uint256 utilization);

    // ============ Errors ============

    error InsufficientStake(uint256 provided, uint256 required);
    error ProviderNotRegistered(address provider);
    error ProviderNotActive(address provider);
    error ProviderAtCapacity(address provider);
    error RequestNotFound(bytes32 requestId);
    error InvalidRequestStatus(bytes32 requestId, RequestStatus expected, RequestStatus actual);
    error NotRequester(bytes32 requestId, address caller);
    error NotProvider(bytes32 requestId, address caller);
    error DeadlineExpired(bytes32 requestId);
    error DeadlineNotExpired(bytes32 requestId);
    error DisputeWindowActive(bytes32 requestId);
    error DisputeWindowExpired(bytes32 requestId);
    error InsufficientEscrow(uint256 provided, uint256 required);
    error InvalidSignature();
    error ZeroAddress();

    // ============ Constructor ============

    /**
     * @notice Deploy ComputeMarket
     * @param _paymentToken AI token address
     * @param _treasury Treasury address for fees
     */
    constructor(address _paymentToken, address _treasury) Ownable(msg.sender) {
        if (_paymentToken == address(0)) revert ZeroAddress();
        if (_treasury == address(0)) revert ZeroAddress();

        paymentToken = IERC20(_paymentToken);
        treasury = _treasury;

        // Initialize market state
        marketState = MarketState({
            totalSupply: 0,
            totalDemand: 0,
            equilibriumPrice: 1e15, // 0.001 AI per token initial
            priceVelocity: 0,
            lastUpdateBlock: block.number,
            utilizationRate: 0
        });
    }

    // ============ Provider Functions ============

    /**
     * @notice Register as a compute provider
     * @param stake Collateral stake amount
     * @param modelId Supported model identifier
     * @param gpuId Attested GPU identifier
     * @param model Pricing model
     * @param pricePerToken Price per token
     * @param pricePerInference Price per inference
     * @param pricePerMinute Price per minute
     * @param maxConcurrent Maximum concurrent jobs
     */
    function registerProvider(
        uint256 stake,
        string calldata modelId,
        bytes32 gpuId,
        PricingModel model,
        uint256 pricePerToken,
        uint256 pricePerInference,
        uint256 pricePerMinute,
        uint256 maxConcurrent
    ) external nonReentrant {
        if (stake < MIN_STAKE) revert InsufficientStake(stake, MIN_STAKE);

        // Transfer stake
        paymentToken.safeTransferFrom(msg.sender, address(this), stake);

        // Register provider
        Provider storage provider = providers[msg.sender];
        if (!provider.registered) {
            providerList.push(msg.sender);
        }

        provider.registered = true;
        provider.active = true;
        provider.stake = stake;
        provider.modelId = modelId;
        provider.gpuId = gpuId;
        provider.model = model;
        provider.pricePerToken = pricePerToken;
        provider.pricePerInference = pricePerInference;
        provider.pricePerMinute = pricePerMinute;
        provider.maxConcurrentJobs = maxConcurrent;
        provider.reputation = 5000; // Start at 50%

        // Update market state
        marketState.totalSupply += maxConcurrent;
        _updateMarketPrice();

        emit ProviderRegistered(msg.sender, stake, modelId);
    }

    /**
     * @notice Update provider pricing and settings
     * @param model Pricing model
     * @param pricePerToken Price per token
     * @param pricePerInference Price per inference
     * @param pricePerMinute Price per minute
     */
    function updateProvider(
        PricingModel model,
        uint256 pricePerToken,
        uint256 pricePerInference,
        uint256 pricePerMinute
    ) external {
        Provider storage provider = providers[msg.sender];
        if (!provider.registered) revert ProviderNotRegistered(msg.sender);

        provider.model = model;
        provider.pricePerToken = pricePerToken;
        provider.pricePerInference = pricePerInference;
        provider.pricePerMinute = pricePerMinute;

        emit ProviderUpdated(msg.sender, model, pricePerToken);
    }

    /**
     * @notice Add more stake
     * @param amount Additional stake amount
     */
    function addStake(uint256 amount) external nonReentrant {
        Provider storage provider = providers[msg.sender];
        if (!provider.registered) revert ProviderNotRegistered(msg.sender);

        paymentToken.safeTransferFrom(msg.sender, address(this), amount);
        provider.stake += amount;
    }

    /**
     * @notice Withdraw stake (only if no active jobs)
     * @param amount Amount to withdraw
     */
    function withdrawStake(uint256 amount) external nonReentrant {
        Provider storage provider = providers[msg.sender];
        if (!provider.registered) revert ProviderNotRegistered(msg.sender);
        require(provider.currentJobs == 0, "Active jobs exist");
        require(provider.stake >= amount, "Insufficient stake");

        provider.stake -= amount;
        paymentToken.safeTransfer(msg.sender, amount);

        // Deactivate if below minimum
        if (provider.stake < MIN_STAKE) {
            provider.active = false;
            marketState.totalSupply -= provider.maxConcurrentJobs;
            emit ProviderDeactivated(msg.sender);
        }
    }

    // ============ Request Functions ============

    /**
     * @notice Create a compute request
     * @param modelId Requested model identifier
     * @param inputHash Hash of input data
     * @param estimatedTokens Estimated token count
     * @param maxPayment Maximum payment willing to pay
     * @param duration Maximum duration in seconds
     * @return requestId The created request ID
     */
    function createRequest(
        string calldata modelId,
        bytes32 inputHash,
        uint256 estimatedTokens,
        uint256 maxPayment,
        uint256 duration
    ) external nonReentrant returns (bytes32 requestId) {
        require(duration > 0 && duration <= MAX_DURATION, "Invalid duration");

        // Generate request ID
        requestId = keccak256(abi.encode(
            msg.sender,
            userNonce[msg.sender]++,
            block.timestamp,
            inputHash
        ));

        // Calculate escrow based on market price
        uint256 escrowAmount = _calculateEscrow(estimatedTokens, maxPayment);
        if (escrowAmount > maxPayment) revert InsufficientEscrow(maxPayment, escrowAmount);

        // Transfer escrow
        paymentToken.safeTransferFrom(msg.sender, address(this), escrowAmount);
        totalEscrowed += escrowAmount;

        // Create request
        requests[requestId] = ComputeRequest({
            requestId: requestId,
            requester: msg.sender,
            provider: address(0),
            escrowAmount: escrowAmount,
            estimatedTokens: estimatedTokens,
            createdAt: block.timestamp,
            deadline: block.timestamp + duration,
            status: RequestStatus.Pending,
            inputHash: inputHash,
            resultHash: bytes32(0),
            modelId: modelId
        });

        // Update market state
        marketState.totalDemand++;
        _updateMarketPrice();

        emit RequestCreated(requestId, msg.sender, modelId, escrowAmount);
        return requestId;
    }

    /**
     * @notice Accept and assign a request (provider)
     * @param requestId Request to accept
     */
    function acceptRequest(bytes32 requestId) external nonReentrant {
        ComputeRequest storage request = requests[requestId];
        if (request.requester == address(0)) revert RequestNotFound(requestId);
        if (request.status != RequestStatus.Pending) {
            revert InvalidRequestStatus(requestId, RequestStatus.Pending, request.status);
        }

        Provider storage provider = providers[msg.sender];
        if (!provider.registered) revert ProviderNotRegistered(msg.sender);
        if (!provider.active) revert ProviderNotActive(msg.sender);
        if (provider.currentJobs >= provider.maxConcurrentJobs) {
            revert ProviderAtCapacity(msg.sender);
        }

        // Assign request
        request.provider = msg.sender;
        request.status = RequestStatus.Active;
        provider.currentJobs++;

        emit RequestAssigned(requestId, msg.sender);
    }

    /**
     * @notice Submit result (provider)
     * @param requestId Request ID
     * @param resultHash Hash of result data
     */
    function submitResult(bytes32 requestId, bytes32 resultHash) external nonReentrant {
        ComputeRequest storage request = requests[requestId];
        if (request.requester == address(0)) revert RequestNotFound(requestId);
        if (request.provider != msg.sender) revert NotProvider(requestId, msg.sender);
        if (request.status != RequestStatus.Active) {
            revert InvalidRequestStatus(requestId, RequestStatus.Active, request.status);
        }
        if (block.timestamp > request.deadline) revert DeadlineExpired(requestId);

        request.resultHash = resultHash;
        request.status = RequestStatus.Completed;

        emit ResultSubmitted(requestId, resultHash);
    }

    /**
     * @notice Verify result and release payment (requester)
     * @param requestId Request ID
     */
    function verifyAndRelease(bytes32 requestId) external nonReentrant {
        ComputeRequest storage request = requests[requestId];
        if (request.requester == address(0)) revert RequestNotFound(requestId);
        if (request.requester != msg.sender) revert NotRequester(requestId, msg.sender);
        if (request.status != RequestStatus.Completed) {
            revert InvalidRequestStatus(requestId, RequestStatus.Completed, request.status);
        }

        request.status = RequestStatus.Verified;

        // Calculate payment and fee
        uint256 fee = (request.escrowAmount * MARKET_FEE_BPS) / 10000;
        uint256 providerPayment = request.escrowAmount - fee;

        // Update provider stats
        Provider storage provider = providers[request.provider];
        provider.totalEarnings += providerPayment;
        provider.completedJobs++;
        provider.currentJobs--;
        provider.reputation = _updateReputation(provider.reputation, true);

        // Transfer payment
        paymentToken.safeTransfer(request.provider, providerPayment);
        accumulatedFees += fee;
        totalEscrowed -= request.escrowAmount;

        // Update market state
        marketState.totalDemand--;
        _updateMarketPrice();

        emit RequestVerified(requestId, providerPayment);
    }

    /**
     * @notice Dispute a result (requester)
     * @param requestId Request ID
     */
    function dispute(bytes32 requestId) external {
        ComputeRequest storage request = requests[requestId];
        if (request.requester == address(0)) revert RequestNotFound(requestId);
        if (request.requester != msg.sender) revert NotRequester(requestId, msg.sender);
        if (request.status != RequestStatus.Completed) {
            revert InvalidRequestStatus(requestId, RequestStatus.Completed, request.status);
        }
        if (block.timestamp > request.deadline + DISPUTE_WINDOW) {
            revert DisputeWindowExpired(requestId);
        }

        request.status = RequestStatus.Disputed;

        emit RequestDisputed(requestId, msg.sender);
    }

    /**
     * @notice Slash provider for failed request
     * @param requestId Request ID where provider failed
     */
    function slashProvider(bytes32 requestId) external nonReentrant {
        ComputeRequest storage request = requests[requestId];
        if (request.requester == address(0)) revert RequestNotFound(requestId);
        if (request.status != RequestStatus.Active) {
            revert InvalidRequestStatus(requestId, RequestStatus.Active, request.status);
        }
        if (block.timestamp <= request.deadline) revert DeadlineNotExpired(requestId);

        // Provider failed to deliver
        Provider storage provider = providers[request.provider];

        // Calculate slash amount
        uint256 slashAmount = (provider.stake * SLASH_BPS) / 10000;
        provider.stake -= slashAmount;
        provider.slashedCount++;
        provider.currentJobs--;
        provider.reputation = _updateReputation(provider.reputation, false);

        // Refund requester from escrow + slash
        uint256 refund = request.escrowAmount + slashAmount;
        paymentToken.safeTransfer(request.requester, refund);
        totalEscrowed -= request.escrowAmount;

        request.status = RequestStatus.Slashed;

        // Deactivate if stake too low
        if (provider.stake < MIN_STAKE) {
            provider.active = false;
            marketState.totalSupply -= provider.maxConcurrentJobs;
        }

        // Update market state
        marketState.totalDemand--;
        _updateMarketPrice();

        emit ProviderSlashed(request.provider, slashAmount, requestId);
    }

    /**
     * @notice Cancel pending request (requester)
     * @param requestId Request ID
     */
    function cancelRequest(bytes32 requestId) external nonReentrant {
        ComputeRequest storage request = requests[requestId];
        if (request.requester == address(0)) revert RequestNotFound(requestId);
        if (request.requester != msg.sender) revert NotRequester(requestId, msg.sender);
        if (request.status != RequestStatus.Pending) {
            revert InvalidRequestStatus(requestId, RequestStatus.Pending, request.status);
        }

        request.status = RequestStatus.Cancelled;

        // Refund escrow
        paymentToken.safeTransfer(msg.sender, request.escrowAmount);
        totalEscrowed -= request.escrowAmount;

        // Update market state
        marketState.totalDemand--;
        _updateMarketPrice();
    }

    // ============ View Functions ============

    /**
     * @notice Get provider information
     * @param provider Provider address
     * @return info Provider struct
     */
    function getProvider(address provider) external view returns (Provider memory info) {
        return providers[provider];
    }

    /**
     * @notice Get request information
     * @param requestId Request ID
     * @return request Request struct
     */
    function getRequest(bytes32 requestId) external view returns (ComputeRequest memory request) {
        return requests[requestId];
    }

    /**
     * @notice Get current market price
     * @return price Current equilibrium price per token
     */
    function getMarketPrice() external view returns (uint256 price) {
        return marketState.equilibriumPrice;
    }

    /**
     * @notice Get market statistics
     * @return supply Total provider capacity
     * @return demand Total pending requests
     * @return price Current equilibrium price
     * @return utilization Current utilization rate (bps)
     */
    function getMarketStats() external view returns (
        uint256 supply,
        uint256 demand,
        uint256 price,
        uint256 utilization
    ) {
        return (
            marketState.totalSupply,
            marketState.totalDemand,
            marketState.equilibriumPrice,
            marketState.utilizationRate
        );
    }

    /**
     * @notice Estimate cost for a request
     * @param estimatedTokens Estimated token count
     * @return cost Estimated cost in payment tokens
     */
    function estimateCost(uint256 estimatedTokens) external view returns (uint256 cost) {
        return (marketState.equilibriumPrice * estimatedTokens) / 1e18;
    }

    /**
     * @notice Get number of registered providers
     * @return count Provider count
     */
    function getProviderCount() external view returns (uint256 count) {
        return providerList.length;
    }

    // ============ Admin Functions ============

    /**
     * @notice Withdraw accumulated fees to treasury
     */
    function withdrawFees() external onlyOwner {
        uint256 fees = accumulatedFees;
        accumulatedFees = 0;
        paymentToken.safeTransfer(treasury, fees);
    }

    /**
     * @notice Update treasury address
     * @param newTreasury New treasury address
     */
    function setTreasury(address newTreasury) external onlyOwner {
        if (newTreasury == address(0)) revert ZeroAddress();
        treasury = newTreasury;
    }

    /**
     * @notice Resolve dispute (owner only)
     * @param requestId Request ID
     * @param favorRequester True to refund requester, false to pay provider
     */
    function resolveDispute(bytes32 requestId, bool favorRequester) external onlyOwner {
        ComputeRequest storage request = requests[requestId];
        if (request.status != RequestStatus.Disputed) {
            revert InvalidRequestStatus(requestId, RequestStatus.Disputed, request.status);
        }

        Provider storage provider = providers[request.provider];

        if (favorRequester) {
            // Refund requester
            paymentToken.safeTransfer(request.requester, request.escrowAmount);
            provider.reputation = _updateReputation(provider.reputation, false);
            request.status = RequestStatus.Cancelled;
        } else {
            // Pay provider
            uint256 fee = (request.escrowAmount * MARKET_FEE_BPS) / 10000;
            uint256 payment = request.escrowAmount - fee;
            paymentToken.safeTransfer(request.provider, payment);
            provider.totalEarnings += payment;
            provider.completedJobs++;
            provider.reputation = _updateReputation(provider.reputation, true);
            accumulatedFees += fee;
            request.status = RequestStatus.Verified;
        }

        provider.currentJobs--;
        totalEscrowed -= request.escrowAmount;
        marketState.totalDemand--;
        _updateMarketPrice();
    }

    // ============ Internal Functions ============

    /**
     * @notice Calculate escrow amount based on market dynamics
     * @param estimatedTokens Estimated token count
     * @param maxPayment Maximum payment
     * @return escrow Required escrow amount
     */
    function _calculateEscrow(
        uint256 estimatedTokens,
        uint256 maxPayment
    ) internal view returns (uint256 escrow) {
        // Base cost from market price
        escrow = (marketState.equilibriumPrice * estimatedTokens) / 1e18;

        // Add 10% buffer for price volatility
        escrow = (escrow * 110) / 100;

        // Cap at max payment
        if (escrow > maxPayment) {
            escrow = maxPayment;
        }

        return escrow;
    }

    /**
     * @notice Update market price using Hamiltonian dynamics
     * @dev Implements energy-conserving price oscillation with damping
     *
     * Hamiltonian analogy:
     * - Position (q) = log(price)
     * - Momentum (p) = price velocity
     * - Potential V(q) = (utilization - 50%)^2 (equilibrium at 50%)
     * - Kinetic T(p) = p^2 / 2
     * - Total energy H = T + V conserved (with damping)
     */
    function _updateMarketPrice() internal {
        if (block.number < marketState.lastUpdateBlock + PRICE_UPDATE_INTERVAL) {
            return;
        }

        // Calculate utilization
        uint256 utilization = 0;
        if (marketState.totalSupply > 0) {
            utilization = (marketState.totalDemand * 10000) / marketState.totalSupply;
        }

        // Target utilization is 50% (5000 bps)
        // Price increases when utilization > 50%, decreases when < 50%
        int256 force;
        if (utilization > 5000) {
            // High demand: increase price
            force = int256((utilization - 5000) * marketState.equilibriumPrice / 10000);
        } else {
            // Low demand: decrease price
            force = -int256((5000 - utilization) * marketState.equilibriumPrice / 10000);
        }

        // Update velocity (momentum) with damping
        int256 newVelocity = (int256(marketState.priceVelocity) * int256(DAMPING_FACTOR) / 10000) + force;

        // Update price (position)
        int256 newPrice = int256(marketState.equilibriumPrice) + newVelocity;

        // Enforce bounds
        if (newPrice < 1e12) newPrice = 1e12; // Floor: 0.000001 AI
        if (newPrice > 1e21) newPrice = 1e21; // Cap: 1000 AI per token

        marketState.equilibriumPrice = uint256(newPrice);
        marketState.priceVelocity = newVelocity >= 0 ? uint256(newVelocity) : 0;
        marketState.utilizationRate = utilization;
        marketState.lastUpdateBlock = block.number;

        emit MarketStateUpdated(uint256(newPrice), utilization);
    }

    /**
     * @notice Update provider reputation
     * @param currentRep Current reputation
     * @param positive True for positive update, false for negative
     * @return newRep Updated reputation
     */
    function _updateReputation(
        uint256 currentRep,
        bool positive
    ) internal pure returns (uint256 newRep) {
        if (positive) {
            // Increase by 2%, cap at 10000
            newRep = currentRep + 200;
            if (newRep > 10000) newRep = 10000;
        } else {
            // Decrease by 5%, floor at 0
            if (currentRep >= 500) {
                newRep = currentRep - 500;
            } else {
                newRep = 0;
            }
        }
        return newRep;
    }
}
