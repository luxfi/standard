// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import { OmnichainLP } from "./OmnichainLP.sol";
import { OmnichainLPFactory } from "./OmnichainLPFactory.sol";
import { Bridge } from "./Bridge.sol";

/**
 * @title OmnichainLPRouter
 * @dev Router contract for interacting with OmnichainLP pairs and facilitating cross-chain operations
 */
contract OmnichainLPRouter is ReentrancyGuard {
    using SafeERC20 for IERC20;
    
    OmnichainLPFactory public immutable factory;
    Bridge public immutable bridge;
    address public immutable WLUX; // Wrapped LUX token
    
    // Cross-chain routing information
    struct Route {
        address[] path;
        uint256[] chainIds;
        address[] bridges;
    }
    
    // Events
    event LiquidityAdded(
        address indexed pair,
        address indexed provider,
        uint256 amount0,
        uint256 amount1,
        uint256 liquidity
    );
    
    event LiquidityRemoved(
        address indexed pair,
        address indexed provider,
        uint256 amount0,
        uint256 amount1,
        uint256 liquidity
    );
    
    event CrossChainSwap(
        address indexed user,
        uint256 fromChain,
        uint256 toChain,
        address[] path,
        uint256 amountIn,
        uint256 amountOut
    );
    
    modifier ensure(uint256 deadline) {
        require(deadline >= block.timestamp, "OmnichainLPRouter: Expired");
        _;
    }
    
    constructor(address _factory, address _bridge, address _WLUX) {
        require(_factory != address(0), "OmnichainLPRouter: Invalid factory");
        require(_bridge != address(0), "OmnichainLPRouter: Invalid bridge");
        require(_WLUX != address(0), "OmnichainLPRouter: Invalid WLUX");
        
        factory = OmnichainLPFactory(_factory);
        bridge = Bridge(_bridge);
        WLUX = _WLUX;
    }
    
    /**
     * @dev Add liquidity to an OmnichainLP pair
     */
    function addLiquidity(
        address tokenA,
        address tokenB,
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    ) external nonReentrant ensure(deadline) returns (
        uint256 amountA,
        uint256 amountB,
        uint256 liquidity
    ) {
        address pair = _getPairOrCreate(tokenA, tokenB);
        
        (amountA, amountB) = _calculateOptimalAmounts(
            tokenA,
            tokenB,
            amountADesired,
            amountBDesired,
            amountAMin,
            amountBMin
        );
        
        // Transfer tokens to pair
        IERC20(tokenA).safeTransferFrom(msg.sender, pair, amountA);
        IERC20(tokenB).safeTransferFrom(msg.sender, pair, amountB);
        
        // Mint liquidity tokens
        liquidity = OmnichainLP(pair).mint(to);
        
        emit LiquidityAdded(pair, to, amountA, amountB, liquidity);
    }
    
    /**
     * @dev Add liquidity with native LUX
     */
    function addLiquidityLUX(
        address token,
        uint256 amountTokenDesired,
        uint256 amountTokenMin,
        uint256 amountLUXMin,
        address to,
        uint256 deadline
    ) external payable nonReentrant ensure(deadline) returns (
        uint256 amountToken,
        uint256 amountLUX,
        uint256 liquidity
    ) {
        address pair = _getPairOrCreate(token, WLUX);
        
        (amountToken, amountLUX) = _calculateOptimalAmounts(
            token,
            WLUX,
            amountTokenDesired,
            msg.value,
            amountTokenMin,
            amountLUXMin
        );
        
        // Transfer token to pair
        IERC20(token).safeTransferFrom(msg.sender, pair, amountToken);
        
        // Wrap LUX and transfer to pair
        IWLUX(WLUX).deposit{value: amountLUX}();
        IERC20(WLUX).safeTransfer(pair, amountLUX);
        
        // Mint liquidity tokens
        liquidity = OmnichainLP(pair).mint(to);
        
        // Refund excess LUX
        if (msg.value > amountLUX) {
            payable(msg.sender).transfer(msg.value - amountLUX);
        }
        
        emit LiquidityAdded(pair, to, amountToken, amountLUX, liquidity);
    }
    
    /**
     * @dev Remove liquidity from an OmnichainLP pair
     */
    function removeLiquidity(
        address tokenA,
        address tokenB,
        uint256 liquidity,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    ) external nonReentrant ensure(deadline) returns (uint256 amountA, uint256 amountB) {
        address pair = factory.getPair(tokenA, tokenB);
        require(pair != address(0), "OmnichainLPRouter: Pair does not exist");
        
        // Transfer LP tokens to pair
        IERC20(pair).safeTransferFrom(msg.sender, pair, liquidity);
        
        // Burn liquidity and receive tokens
        (uint256 amount0, uint256 amount1) = OmnichainLP(pair).burn(to);
        
        // Sort amounts
        (address token0,) = _sortTokens(tokenA, tokenB);
        (amountA, amountB) = tokenA == token0 ? (amount0, amount1) : (amount1, amount0);
        
        require(amountA >= amountAMin, "OmnichainLPRouter: Insufficient A amount");
        require(amountB >= amountBMin, "OmnichainLPRouter: Insufficient B amount");
        
        emit LiquidityRemoved(pair, msg.sender, amountA, amountB, liquidity);
    }
    
    /**
     * @dev Swap exact tokens for tokens
     */
    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external nonReentrant ensure(deadline) returns (uint256[] memory amounts) {
        require(path.length >= 2, "OmnichainLPRouter: Invalid path");
        amounts = _getAmountsOut(amountIn, path);
        require(amounts[amounts.length - 1] >= amountOutMin, "OmnichainLPRouter: Insufficient output");
        
        // Transfer first token to first pair
        address firstPair = factory.getPair(path[0], path[1]);
        IERC20(path[0]).safeTransferFrom(msg.sender, firstPair, amounts[0]);
        
        // Execute swaps
        _swap(amounts, path, to);
    }
    
    /**
     * @dev Cross-chain swap with bridge integration
     */
    function crossChainSwap(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        uint256[] calldata chainIds,
        address to,
        uint256 deadline
    ) external nonReentrant ensure(deadline) returns (uint256 amountOut) {
        require(path.length >= 2, "OmnichainLPRouter: Invalid path");
        require(path.length == chainIds.length, "OmnichainLPRouter: Mismatched arrays");
        
        uint256 currentChain = block.chainid;
        uint256 targetChain = chainIds[chainIds.length - 1];
        
        if (currentChain == targetChain) {
            // Same chain swap
            uint256[] memory amounts = swapExactTokensForTokens(
                amountIn,
                amountOutMin,
                path,
                to,
                deadline
            );
            amountOut = amounts[amounts.length - 1];
        } else {
            // Cross-chain swap
            // First swap on source chain if needed
            if (chainIds[0] == currentChain && path.length > 2) {
                address[] memory sourcePath = new address[](2);
                sourcePath[0] = path[0];
                sourcePath[1] = path[1];
                
                uint256[] memory amounts = _getAmountsOut(amountIn, sourcePath);
                IERC20(path[0]).safeTransferFrom(msg.sender, factory.getPair(path[0], path[1]), amounts[0]);
                _swap(amounts, sourcePath, address(this));
                amountIn = amounts[1];
            }
            
            // Bridge to target chain
            _bridgeTokens(path[1], amountIn, targetChain, to);
            
            // Note: Actual swap on target chain would be handled by a relayer or the user
            amountOut = amountIn; // Simplified - actual amount would depend on target chain execution
        }
        
        emit CrossChainSwap(msg.sender, currentChain, targetChain, path, amountIn, amountOut);
    }
    
    /**
     * @dev Bridge LP tokens to another chain
     */
    function bridgeLPTokens(
        address tokenA,
        address tokenB,
        uint256 amount,
        uint256 targetChain,
        address recipient,
        uint256 deadline
    ) external nonReentrant ensure(deadline) {
        address pair = factory.getPair(tokenA, tokenB);
        require(pair != address(0), "OmnichainLPRouter: Pair does not exist");
        
        // Transfer LP tokens from user
        IERC20(pair).safeTransferFrom(msg.sender, address(this), amount);
        
        // Approve bridge to spend LP tokens
        IERC20(pair).approve(address(bridge), amount);
        
        // Initiate bridge transfer
        OmnichainLP(pair).bridgeLPTokens(amount, targetChain, recipient);
    }
    
    /**
     * @dev Get optimal swap amounts for a path
     */
    function getAmountsOut(uint256 amountIn, address[] calldata path) 
        external 
        view 
        returns (uint256[] memory amounts) 
    {
        return _getAmountsOut(amountIn, path);
    }
    
    /**
     * @dev Get required input amount for desired output
     */
    function getAmountsIn(uint256 amountOut, address[] calldata path)
        external
        view
        returns (uint256[] memory amounts)
    {
        return _getAmountsIn(amountOut, path);
    }
    
    // Internal functions
    
    function _getPairOrCreate(address tokenA, address tokenB) internal returns (address pair) {
        pair = factory.getPair(tokenA, tokenB);
        if (pair == address(0)) {
            pair = factory.createPair(tokenA, tokenB);
        }
    }
    
    function _sortTokens(address tokenA, address tokenB) internal pure returns (address token0, address token1) {
        require(tokenA != tokenB, "OmnichainLPRouter: Identical addresses");
        (token0, token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        require(token0 != address(0), "OmnichainLPRouter: Zero address");
    }
    
    function _calculateOptimalAmounts(
        address tokenA,
        address tokenB,
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256 amountAMin,
        uint256 amountBMin
    ) internal view returns (uint256 amountA, uint256 amountB) {
        address pair = factory.getPair(tokenA, tokenB);
        if (pair == address(0)) {
            (amountA, amountB) = (amountADesired, amountBDesired);
        } else {
            (uint112 reserveA, uint112 reserveB,) = OmnichainLP(pair).getReserves();
            if (reserveA == 0 && reserveB == 0) {
                (amountA, amountB) = (amountADesired, amountBDesired);
            } else {
                uint256 amountBOptimal = _quote(amountADesired, reserveA, reserveB);
                if (amountBOptimal <= amountBDesired) {
                    require(amountBOptimal >= amountBMin, "OmnichainLPRouter: Insufficient B amount");
                    (amountA, amountB) = (amountADesired, amountBOptimal);
                } else {
                    uint256 amountAOptimal = _quote(amountBDesired, reserveB, reserveA);
                    assert(amountAOptimal <= amountADesired);
                    require(amountAOptimal >= amountAMin, "OmnichainLPRouter: Insufficient A amount");
                    (amountA, amountB) = (amountAOptimal, amountBDesired);
                }
            }
        }
    }
    
    function _quote(uint256 amountA, uint256 reserveA, uint256 reserveB) internal pure returns (uint256 amountB) {
        require(amountA > 0, "OmnichainLPRouter: Insufficient amount");
        require(reserveA > 0 && reserveB > 0, "OmnichainLPRouter: Insufficient liquidity");
        amountB = (amountA * reserveB) / reserveA;
    }
    
    function _getAmountsOut(uint256 amountIn, address[] memory path) internal view returns (uint256[] memory amounts) {
        require(path.length >= 2, "OmnichainLPRouter: Invalid path");
        amounts = new uint256[](path.length);
        amounts[0] = amountIn;
        
        for (uint256 i = 0; i < path.length - 1; i++) {
            address pair = factory.getPair(path[i], path[i + 1]);
            require(pair != address(0), "OmnichainLPRouter: Pair does not exist");
            (uint112 reserveIn, uint112 reserveOut,) = _getReserves(pair, path[i], path[i + 1]);
            amounts[i + 1] = _getAmountOut(amounts[i], reserveIn, reserveOut);
        }
    }
    
    function _getAmountsIn(uint256 amountOut, address[] memory path) internal view returns (uint256[] memory amounts) {
        require(path.length >= 2, "OmnichainLPRouter: Invalid path");
        amounts = new uint256[](path.length);
        amounts[amounts.length - 1] = amountOut;
        
        for (uint256 i = path.length - 1; i > 0; i--) {
            address pair = factory.getPair(path[i - 1], path[i]);
            require(pair != address(0), "OmnichainLPRouter: Pair does not exist");
            (uint112 reserveIn, uint112 reserveOut,) = _getReserves(pair, path[i - 1], path[i]);
            amounts[i - 1] = _getAmountIn(amounts[i], reserveIn, reserveOut);
        }
    }
    
    function _getReserves(address pair, address tokenA, address tokenB) 
        internal 
        view 
        returns (uint112 reserveA, uint112 reserveB, uint32 blockTimestampLast) 
    {
        (address token0,) = _sortTokens(tokenA, tokenB);
        (uint112 reserve0, uint112 reserve1, uint32 timestamp) = OmnichainLP(pair).getReserves();
        (reserveA, reserveB, blockTimestampLast) = tokenA == token0 ? 
            (reserve0, reserve1, timestamp) : (reserve1, reserve0, timestamp);
    }
    
    function _getAmountOut(uint256 amountIn, uint256 reserveIn, uint256 reserveOut) 
        internal 
        pure 
        returns (uint256 amountOut) 
    {
        require(amountIn > 0, "OmnichainLPRouter: Insufficient input");
        require(reserveIn > 0 && reserveOut > 0, "OmnichainLPRouter: Insufficient liquidity");
        uint256 amountInWithFee = amountIn * 997;
        uint256 numerator = amountInWithFee * reserveOut;
        uint256 denominator = (reserveIn * 1000) + amountInWithFee;
        amountOut = numerator / denominator;
    }
    
    function _getAmountIn(uint256 amountOut, uint256 reserveIn, uint256 reserveOut)
        internal
        pure
        returns (uint256 amountIn)
    {
        require(amountOut > 0, "OmnichainLPRouter: Insufficient output");
        require(reserveIn > 0 && reserveOut > 0, "OmnichainLPRouter: Insufficient liquidity");
        uint256 numerator = (reserveIn * amountOut * 1000);
        uint256 denominator = (reserveOut - amountOut) * 997;
        amountIn = (numerator / denominator) + 1;
    }
    
    function _swap(uint256[] memory amounts, address[] memory path, address to) internal {
        for (uint256 i = 0; i < path.length - 1; i++) {
            (address input, address output) = (path[i], path[i + 1]);
            (address token0,) = _sortTokens(input, output);
            uint256 amountOut = amounts[i + 1];
            
            (uint256 amount0Out, uint256 amount1Out) = input == token0 ? 
                (uint256(0), amountOut) : (amountOut, uint256(0));
                
            address _to = i < path.length - 2 ? factory.getPair(output, path[i + 2]) : to;
            address pair = factory.getPair(input, output);
            
            OmnichainLP(pair).swap(amount0Out, amount1Out, _to, new bytes(0));
        }
    }
    
    function _bridgeTokens(address token, uint256 amount, uint256 targetChain, address recipient) internal {
        // Prepare bridge tokens
        Bridge.Token memory fromToken = Bridge.Token({
            kind: Bridge.Type.ERC20,
            id: 0,
            chainId: block.chainid,
            tokenAddress: token,
            enabled: true
        });
        
        Bridge.Token memory toToken = Bridge.Token({
            kind: Bridge.Type.ERC20,
            id: 0,
            chainId: targetChain,
            tokenAddress: token,
            enabled: true
        });
        
        // Approve bridge
        IERC20(token).approve(address(bridge), amount);
        
        // Execute bridge
        bridge.swap(fromToken, toToken, recipient, amount, block.timestamp);
    }
}

interface IWLUX {
    function deposit() external payable;
    function withdraw(uint256) external;
}