// SPDX-License-Identifier: BSD-3-Clause
// Copyright (c) 2025 Lux Industries Inc.
pragma solidity ^0.8.28;

import {IERC20} from "@luxfi/standard/lib/token/ERC20/IERC20.sol";
import {SafeERC20} from "@luxfi/standard/lib/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@luxfi/standard/lib/access/Ownable.sol";
import {ReentrancyGuard} from "@luxfi/standard/lib/utils/ReentrancyGuard.sol";
import {ILiquidityEngine} from "./interfaces/ILiquidityEngine.sol";

/// @title UniversalLiquidityRouter
/// @notice Aggregates liquidity from multiple protocols across chains
/// @dev Routes to best protocol based on price/liquidity
contract UniversalLiquidityRouter is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    /*//////////////////////////////////////////////////////////////
                                 TYPES
    //////////////////////////////////////////////////////////////*/

    /// @notice Registered adapter info
    struct AdapterInfo {
        address adapter;
        bytes32 protocolId;
        ILiquidityEngine.ProtocolType protocolType;
        ILiquidityEngine.Chain chain;
        bool enabled;
        uint256 priority;  // Lower = higher priority
    }

    /// @notice Multi-hop route step
    struct RouteStep {
        address adapter;
        address tokenIn;
        address tokenOut;
        uint256 amountIn;
        bytes extraData;
    }

    /// @notice Cross-chain route
    struct CrossChainRoute {
        ILiquidityEngine.Chain sourceChain;
        ILiquidityEngine.Chain destChain;
        RouteStep[] sourceSteps;
        bytes bridgeData;
        RouteStep[] destSteps;
    }

    /*//////////////////////////////////////////////////////////////
                                 STATE
    //////////////////////////////////////////////////////////////*/

    /// @notice All registered adapters
    AdapterInfo[] public adapters;

    /// @notice Adapter by protocol ID
    mapping(bytes32 => address) public adapterByProtocol;

    /// @notice Adapters by chain
    mapping(ILiquidityEngine.Chain => address[]) public adaptersByChain;

    /// @notice Adapters by type
    mapping(ILiquidityEngine.ProtocolType => address[]) public adaptersByType;

    /// @notice Fee recipient
    address public feeRecipient;

    /// @notice Fee in basis points (default 5 = 0.05%)
    uint256 public feeBps = 5;

    /// @notice Max fee cap
    uint256 public constant MAX_FEE_BPS = 100; // 1%

    /// @notice Pause state
    bool public paused;

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    event AdapterRegistered(bytes32 indexed protocolId, address adapter);
    event AdapterEnabled(bytes32 indexed protocolId, bool enabled);
    event RouteExecuted(
        address indexed user,
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 amountOut,
        bytes32[] protocols
    );
    event CrossChainRouteExecuted(
        address indexed user,
        ILiquidityEngine.Chain sourceChain,
        ILiquidityEngine.Chain destChain,
        uint256 amountIn,
        bytes32 messageId
    );
    event FeeCollected(address indexed token, uint256 amount);

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    error Paused();
    error InvalidAdapter();
    error AdapterExists();
    error AdapterNotFound();
    error InsufficientOutput();
    error DeadlineExpired();
    error InvalidRoute();
    error FeeTooHigh();

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    constructor(address _feeRecipient) Ownable(msg.sender) {
        feeRecipient = _feeRecipient;
    }

    /*//////////////////////////////////////////////////////////////
                          ADAPTER MANAGEMENT
    //////////////////////////////////////////////////////////////*/

    /// @notice Register a new adapter
    function registerAdapter(
        bytes32 protocolId,
        address adapter,
        uint256 priority
    ) external onlyOwner {
        if (adapter == address(0)) revert InvalidAdapter();
        if (adapterByProtocol[protocolId] != address(0)) revert AdapterExists();

        ILiquidityEngine engine = ILiquidityEngine(adapter);

        AdapterInfo memory info = AdapterInfo({
            adapter: adapter,
            protocolId: protocolId,
            protocolType: engine.protocolType(),
            chain: engine.chain(),
            enabled: true,
            priority: priority
        });

        adapters.push(info);
        adapterByProtocol[protocolId] = adapter;
        adaptersByChain[info.chain].push(adapter);
        adaptersByType[info.protocolType].push(adapter);

        emit AdapterRegistered(protocolId, adapter);
    }

    /// @notice Enable/disable adapter
    function setAdapterEnabled(bytes32 protocolId, bool enabled) external onlyOwner {
        address adapter = adapterByProtocol[protocolId];
        if (adapter == address(0)) revert AdapterNotFound();

        for (uint256 i = 0; i < adapters.length; i++) {
            if (adapters[i].protocolId == protocolId) {
                adapters[i].enabled = enabled;
                break;
            }
        }

        emit AdapterEnabled(protocolId, enabled);
    }

    /*//////////////////////////////////////////////////////////////
                            SWAP FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Get best quote across all adapters
    function getBestQuote(
        address tokenIn,
        address tokenOut,
        uint256 amountIn
    ) external returns (
        ILiquidityEngine.SwapQuote memory bestQuote,
        bytes32 bestProtocol
    ) {
        uint256 bestAmountOut = 0;

        for (uint256 i = 0; i < adapters.length; i++) {
            if (!adapters[i].enabled) continue;
            if (adapters[i].protocolType != ILiquidityEngine.ProtocolType.DEX_AMM &&
                adapters[i].protocolType != ILiquidityEngine.ProtocolType.DEX_AGGREGATOR) continue;

            try ILiquidityEngine(adapters[i].adapter).getSwapQuote(
                tokenIn, tokenOut, amountIn
            ) returns (ILiquidityEngine.SwapQuote memory quote) {
                if (quote.amountOut > bestAmountOut) {
                    bestAmountOut = quote.amountOut;
                    bestQuote = quote;
                    bestProtocol = adapters[i].protocolId;
                }
            } catch {}
        }
    }

    /// @notice Swap with automatic best route selection
    function swap(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 minAmountOut,
        address recipient,
        uint256 deadline
    ) external payable nonReentrant returns (uint256 amountOut) {
        if (paused) revert Paused();
        if (block.timestamp > deadline) revert DeadlineExpired();

        // Find best adapter
        (ILiquidityEngine.SwapQuote memory quote, bytes32 protocol) =
            this.getBestQuote(tokenIn, tokenOut, amountIn);

        if (quote.amountOut < minAmountOut) revert InsufficientOutput();

        address adapter = adapterByProtocol[protocol];

        // Transfer tokens from user
        if (tokenIn != address(0)) {
            IERC20(tokenIn).safeTransferFrom(msg.sender, address(this), amountIn);
            IERC20(tokenIn).forceApprove(adapter, amountIn);
        }

        // Execute swap
        amountOut = ILiquidityEngine(adapter).swap{value: msg.value}(
            tokenIn,
            tokenOut,
            amountIn,
            minAmountOut,
            address(this),
            deadline
        );

        // Collect fee
        uint256 fee = (amountOut * feeBps) / 10000;
        uint256 userAmount = amountOut - fee;

        // Transfer to recipient
        if (tokenOut == address(0)) {
            payable(recipient).transfer(userAmount);
            if (fee > 0) payable(feeRecipient).transfer(fee);
        } else {
            IERC20(tokenOut).safeTransfer(recipient, userAmount);
            if (fee > 0) {
                IERC20(tokenOut).safeTransfer(feeRecipient, fee);
                emit FeeCollected(tokenOut, fee);
            }
        }

        bytes32[] memory protocols = new bytes32[](1);
        protocols[0] = protocol;
        emit RouteExecuted(msg.sender, tokenIn, tokenOut, amountIn, userAmount, protocols);
    }

    /// @notice Execute multi-step swap route
    function swapMultiHop(
        RouteStep[] calldata steps,
        uint256 minAmountOut,
        address recipient,
        uint256 deadline
    ) external payable nonReentrant returns (uint256 amountOut) {
        if (paused) revert Paused();
        if (block.timestamp > deadline) revert DeadlineExpired();
        if (steps.length == 0) revert InvalidRoute();

        bytes32[] memory protocols = new bytes32[](steps.length);
        uint256 currentAmount = steps[0].amountIn;

        // Transfer initial tokens
        if (steps[0].tokenIn != address(0)) {
            IERC20(steps[0].tokenIn).safeTransferFrom(msg.sender, address(this), currentAmount);
        }

        // Execute each step
        for (uint256 i = 0; i < steps.length; i++) {
            RouteStep memory step = steps[i];

            if (step.tokenIn != address(0)) {
                IERC20(step.tokenIn).forceApprove(step.adapter, currentAmount);
            }

            currentAmount = ILiquidityEngine(step.adapter).swap{
                value: step.tokenIn == address(0) ? currentAmount : 0
            }(
                step.tokenIn,
                step.tokenOut,
                currentAmount,
                0, // Check at end
                address(this),
                deadline
            );

            // Track protocol
            for (uint256 j = 0; j < adapters.length; j++) {
                if (adapters[j].adapter == step.adapter) {
                    protocols[i] = adapters[j].protocolId;
                    break;
                }
            }
        }

        if (currentAmount < minAmountOut) revert InsufficientOutput();

        // Collect fee and transfer
        uint256 fee = (currentAmount * feeBps) / 10000;
        amountOut = currentAmount - fee;

        address tokenOut = steps[steps.length - 1].tokenOut;
        if (tokenOut == address(0)) {
            payable(recipient).transfer(amountOut);
            if (fee > 0) payable(feeRecipient).transfer(fee);
        } else {
            IERC20(tokenOut).safeTransfer(recipient, amountOut);
            if (fee > 0) IERC20(tokenOut).safeTransfer(feeRecipient, fee);
        }

        emit RouteExecuted(
            msg.sender,
            steps[0].tokenIn,
            tokenOut,
            steps[0].amountIn,
            amountOut,
            protocols
        );
    }

    /*//////////////////////////////////////////////////////////////
                          LENDING FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Get best lending rate across protocols
    function getBestLendingRate(
        address token,
        uint256 amount,
        bool isSupply
    ) external view returns (
        ILiquidityEngine.LendingQuote memory bestQuote,
        bytes32 bestProtocol
    ) {
        uint256 bestApy = isSupply ? 0 : type(uint256).max;

        for (uint256 i = 0; i < adapters.length; i++) {
            if (!adapters[i].enabled) continue;
            if (adapters[i].protocolType != ILiquidityEngine.ProtocolType.LENDING) continue;

            try ILiquidityEngine(adapters[i].adapter).getLendingQuote(
                token, amount, isSupply
            ) returns (ILiquidityEngine.LendingQuote memory quote) {
                if (isSupply && quote.apy > bestApy) {
                    bestApy = quote.apy;
                    bestQuote = quote;
                    bestProtocol = adapters[i].protocolId;
                } else if (!isSupply && quote.apy < bestApy) {
                    bestApy = quote.apy;
                    bestQuote = quote;
                    bestProtocol = adapters[i].protocolId;
                }
            } catch {}
        }
    }

    /// @notice Supply to best lending protocol
    function supplyBest(
        address token,
        uint256 amount
    ) external nonReentrant returns (uint256 shares, bytes32 protocol) {
        if (paused) revert Paused();

        (ILiquidityEngine.LendingQuote memory quote, bytes32 bestProtocol) =
            this.getBestLendingRate(token, amount, true);

        protocol = bestProtocol;
        address adapter = adapterByProtocol[protocol];

        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
        IERC20(token).forceApprove(adapter, amount);

        shares = ILiquidityEngine(adapter).supply(token, amount, msg.sender);
    }

    /*//////////////////////////////////////////////////////////////
                            ADMIN FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function setFee(uint256 _feeBps) external onlyOwner {
        if (_feeBps > MAX_FEE_BPS) revert FeeTooHigh();
        feeBps = _feeBps;
    }

    function setFeeRecipient(address _feeRecipient) external onlyOwner {
        feeRecipient = _feeRecipient;
    }

    function setPaused(bool _paused) external onlyOwner {
        paused = _paused;
    }

    function emergencyWithdraw(address token, uint256 amount) external onlyOwner {
        if (token == address(0)) {
            payable(owner()).transfer(amount);
        } else {
            IERC20(token).safeTransfer(owner(), amount);
        }
    }

    /*//////////////////////////////////////////////////////////////
                            VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Get all adapters
    function getAllAdapters() external view returns (AdapterInfo[] memory) {
        return adapters;
    }

    /// @notice Get adapters for a specific chain
    function getAdaptersForChain(ILiquidityEngine.Chain chain)
        external view returns (address[] memory)
    {
        return adaptersByChain[chain];
    }

    /// @notice Get adapters for a specific type
    function getAdaptersForType(ILiquidityEngine.ProtocolType protocolType)
        external view returns (address[] memory)
    {
        return adaptersByType[protocolType];
    }

    receive() external payable {}
}
