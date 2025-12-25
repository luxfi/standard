// SPDX-License-Identifier: MIT
pragma solidity ^0.8.31;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./AMMV2Factory.sol";
import "./AMMV2Pair.sol";
import "./interfaces/IWLUX.sol";

/// @title AMMV2Router - Uniswap V2 Compatible Router
/// @notice Routes trades and liquidity operations through LP pairs
/// @dev Supports native LUX through WLUX wrapping
contract AMMV2Router {
    using SafeERC20 for IERC20;

    address public immutable factory;
    address public immutable WLUX;

    modifier ensure(uint256 deadline) {
        require(deadline >= block.timestamp, "AMMV2Router: EXPIRED");
        _;
    }

    constructor(address _factory, address _wlux) {
        factory = _factory;
        WLUX = _wlux;
    }

    receive() external payable {
        require(msg.sender == WLUX, "AMMV2Router: NOT_WLUX");
    }

    // **** ADD LIQUIDITY ****
    function addLiquidity(
        address tokenA,
        address tokenB,
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    ) external ensure(deadline) returns (uint256 amountA, uint256 amountB, uint256 liquidity) {
        (amountA, amountB) = _addLiquidity(tokenA, tokenB, amountADesired, amountBDesired, amountAMin, amountBMin);
        address pair = AMMV2Factory(factory).getPair(tokenA, tokenB);
        IERC20(tokenA).safeTransferFrom(msg.sender, pair, amountA);
        IERC20(tokenB).safeTransferFrom(msg.sender, pair, amountB);
        liquidity = AMMV2Pair(pair).mint(to);
    }

    function addLiquidityLUX(
        address token,
        uint256 amountTokenDesired,
        uint256 amountTokenMin,
        uint256 amountLUXMin,
        address to,
        uint256 deadline
    ) external payable ensure(deadline) returns (uint256 amountToken, uint256 amountLUX, uint256 liquidity) {
        (amountToken, amountLUX) = _addLiquidity(token, WLUX, amountTokenDesired, msg.value, amountTokenMin, amountLUXMin);
        address pair = AMMV2Factory(factory).getPair(token, WLUX);
        IERC20(token).safeTransferFrom(msg.sender, pair, amountToken);
        IWLUX(WLUX).deposit{value: amountLUX}();
        IERC20(WLUX).safeTransfer(pair, amountLUX);
        liquidity = AMMV2Pair(pair).mint(to);
        // Refund excess LUX
        if (msg.value > amountLUX) {
            (bool success,) = msg.sender.call{value: msg.value - amountLUX}("");
            require(success, "AMMV2Router: LUX_REFUND_FAILED");
        }
    }

    // **** REMOVE LIQUIDITY ****
    function removeLiquidity(
        address tokenA,
        address tokenB,
        uint256 liquidity,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    ) public ensure(deadline) returns (uint256 amountA, uint256 amountB) {
        address pair = AMMV2Factory(factory).getPair(tokenA, tokenB);
        IERC20(pair).safeTransferFrom(msg.sender, pair, liquidity);
        (uint256 amount0, uint256 amount1) = AMMV2Pair(pair).burn(to);
        (address token0,) = _sortTokens(tokenA, tokenB);
        (amountA, amountB) = tokenA == token0 ? (amount0, amount1) : (amount1, amount0);
        require(amountA >= amountAMin, "AMMV2Router: INSUFFICIENT_A_AMOUNT");
        require(amountB >= amountBMin, "AMMV2Router: INSUFFICIENT_B_AMOUNT");
    }

    function removeLiquidityLUX(
        address token,
        uint256 liquidity,
        uint256 amountTokenMin,
        uint256 amountLUXMin,
        address to,
        uint256 deadline
    ) public ensure(deadline) returns (uint256 amountToken, uint256 amountLUX) {
        (amountToken, amountLUX) = removeLiquidity(token, WLUX, liquidity, amountTokenMin, amountLUXMin, address(this), deadline);
        IERC20(token).safeTransfer(to, amountToken);
        IWLUX(WLUX).withdraw(amountLUX);
        (bool success,) = to.call{value: amountLUX}("");
        require(success, "AMMV2Router: LUX_TRANSFER_FAILED");
    }

    // **** SWAP ****
    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external ensure(deadline) returns (uint256[] memory amounts) {
        amounts = getAmountsOut(amountIn, path);
        require(amounts[amounts.length - 1] >= amountOutMin, "AMMV2Router: INSUFFICIENT_OUTPUT_AMOUNT");
        IERC20(path[0]).safeTransferFrom(msg.sender, AMMV2Factory(factory).getPair(path[0], path[1]), amounts[0]);
        _swap(amounts, path, to);
    }

    function swapTokensForExactTokens(
        uint256 amountOut,
        uint256 amountInMax,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external ensure(deadline) returns (uint256[] memory amounts) {
        amounts = getAmountsIn(amountOut, path);
        require(amounts[0] <= amountInMax, "AMMV2Router: EXCESSIVE_INPUT_AMOUNT");
        IERC20(path[0]).safeTransferFrom(msg.sender, AMMV2Factory(factory).getPair(path[0], path[1]), amounts[0]);
        _swap(amounts, path, to);
    }

    function swapExactLUXForTokens(
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external payable ensure(deadline) returns (uint256[] memory amounts) {
        require(path[0] == WLUX, "AMMV2Router: INVALID_PATH");
        amounts = getAmountsOut(msg.value, path);
        require(amounts[amounts.length - 1] >= amountOutMin, "AMMV2Router: INSUFFICIENT_OUTPUT_AMOUNT");
        IWLUX(WLUX).deposit{value: amounts[0]}();
        IERC20(WLUX).safeTransfer(AMMV2Factory(factory).getPair(path[0], path[1]), amounts[0]);
        _swap(amounts, path, to);
    }

    function swapExactTokensForLUX(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external ensure(deadline) returns (uint256[] memory amounts) {
        require(path[path.length - 1] == WLUX, "AMMV2Router: INVALID_PATH");
        amounts = getAmountsOut(amountIn, path);
        require(amounts[amounts.length - 1] >= amountOutMin, "AMMV2Router: INSUFFICIENT_OUTPUT_AMOUNT");
        IERC20(path[0]).safeTransferFrom(msg.sender, AMMV2Factory(factory).getPair(path[0], path[1]), amounts[0]);
        _swap(amounts, path, address(this));
        IWLUX(WLUX).withdraw(amounts[amounts.length - 1]);
        (bool success,) = to.call{value: amounts[amounts.length - 1]}("");
        require(success, "AMMV2Router: LUX_TRANSFER_FAILED");
    }

    // **** LIBRARY FUNCTIONS ****
    function quote(uint256 amountA, uint256 reserveA, uint256 reserveB) public pure returns (uint256 amountB) {
        require(amountA > 0, "AMMV2Router: INSUFFICIENT_AMOUNT");
        require(reserveA > 0 && reserveB > 0, "AMMV2Router: INSUFFICIENT_LIQUIDITY");
        amountB = (amountA * reserveB) / reserveA;
    }

    function getAmountOut(uint256 amountIn, uint256 reserveIn, uint256 reserveOut) public pure returns (uint256 amountOut) {
        require(amountIn > 0, "AMMV2Router: INSUFFICIENT_INPUT_AMOUNT");
        require(reserveIn > 0 && reserveOut > 0, "AMMV2Router: INSUFFICIENT_LIQUIDITY");
        uint256 amountInWithFee = amountIn * 997;
        uint256 numerator = amountInWithFee * reserveOut;
        uint256 denominator = (reserveIn * 1000) + amountInWithFee;
        amountOut = numerator / denominator;
    }

    function getAmountIn(uint256 amountOut, uint256 reserveIn, uint256 reserveOut) public pure returns (uint256 amountIn) {
        require(amountOut > 0, "AMMV2Router: INSUFFICIENT_OUTPUT_AMOUNT");
        require(reserveIn > 0 && reserveOut > 0, "AMMV2Router: INSUFFICIENT_LIQUIDITY");
        uint256 numerator = reserveIn * amountOut * 1000;
        uint256 denominator = (reserveOut - amountOut) * 997;
        amountIn = (numerator / denominator) + 1;
    }

    function getAmountsOut(uint256 amountIn, address[] memory path) public view returns (uint256[] memory amounts) {
        require(path.length >= 2, "AMMV2Router: INVALID_PATH");
        amounts = new uint256[](path.length);
        amounts[0] = amountIn;
        for (uint256 i; i < path.length - 1; i++) {
            (uint256 reserveIn, uint256 reserveOut) = _getReserves(path[i], path[i + 1]);
            amounts[i + 1] = getAmountOut(amounts[i], reserveIn, reserveOut);
        }
    }

    function getAmountsIn(uint256 amountOut, address[] memory path) public view returns (uint256[] memory amounts) {
        require(path.length >= 2, "AMMV2Router: INVALID_PATH");
        amounts = new uint256[](path.length);
        amounts[amounts.length - 1] = amountOut;
        for (uint256 i = path.length - 1; i > 0; i--) {
            (uint256 reserveIn, uint256 reserveOut) = _getReserves(path[i - 1], path[i]);
            amounts[i - 1] = getAmountIn(amounts[i], reserveIn, reserveOut);
        }
    }

    // **** INTERNAL FUNCTIONS ****
    function _addLiquidity(
        address tokenA,
        address tokenB,
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256 amountAMin,
        uint256 amountBMin
    ) internal returns (uint256 amountA, uint256 amountB) {
        // Create the pair if it doesn't exist
        if (AMMV2Factory(factory).getPair(tokenA, tokenB) == address(0)) {
            AMMV2Factory(factory).createPair(tokenA, tokenB);
        }
        (uint256 reserveA, uint256 reserveB) = _getReserves(tokenA, tokenB);
        if (reserveA == 0 && reserveB == 0) {
            (amountA, amountB) = (amountADesired, amountBDesired);
        } else {
            uint256 amountBOptimal = quote(amountADesired, reserveA, reserveB);
            if (amountBOptimal <= amountBDesired) {
                require(amountBOptimal >= amountBMin, "AMMV2Router: INSUFFICIENT_B_AMOUNT");
                (amountA, amountB) = (amountADesired, amountBOptimal);
            } else {
                uint256 amountAOptimal = quote(amountBDesired, reserveB, reserveA);
                require(amountAOptimal <= amountADesired && amountAOptimal >= amountAMin, "AMMV2Router: INSUFFICIENT_A_AMOUNT");
                (amountA, amountB) = (amountAOptimal, amountBDesired);
            }
        }
    }

    function _swap(uint256[] memory amounts, address[] memory path, address _to) internal {
        for (uint256 i; i < path.length - 1; i++) {
            (address input, address output) = (path[i], path[i + 1]);
            (address token0,) = _sortTokens(input, output);
            uint256 amountOut = amounts[i + 1];
            (uint256 amount0Out, uint256 amount1Out) = input == token0 ? (uint256(0), amountOut) : (amountOut, uint256(0));
            address to = i < path.length - 2 ? AMMV2Factory(factory).getPair(output, path[i + 2]) : _to;
            AMMV2Pair(AMMV2Factory(factory).getPair(input, output)).swap(amount0Out, amount1Out, to, new bytes(0));
        }
    }

    function _getReserves(address tokenA, address tokenB) internal view returns (uint256 reserveA, uint256 reserveB) {
        (address token0,) = _sortTokens(tokenA, tokenB);
        address pair = AMMV2Factory(factory).getPair(tokenA, tokenB);
        if (pair == address(0)) return (0, 0);
        (uint112 reserve0, uint112 reserve1,) = AMMV2Pair(pair).getReserves();
        (reserveA, reserveB) = tokenA == token0 ? (reserve0, reserve1) : (reserve1, reserve0);
    }

    function _sortTokens(address tokenA, address tokenB) internal pure returns (address token0, address token1) {
        require(tokenA != tokenB, "AMMV2Router: IDENTICAL_ADDRESSES");
        (token0, token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        require(token0 != address(0), "AMMV2Router: ZERO_ADDRESS");
    }
}
