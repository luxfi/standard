// SPDX-License-Identifier: MIT

pragma solidity ^0.8.31;

import { Token } from "../../mocks/PerpsTestToken.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IPancakeRouter } from "./interfaces/IPancakeRouter.sol";

contract PancakeRouter is IPancakeRouter {
    using SafeERC20 for IERC20;

    address public pair;

    constructor(address _pair) public {
        pair = _pair;
    }

    function addLiquidity(
        address tokenA,
        address tokenB,
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256,
        /*amountAMin*/
        uint256,
        /*amountBMin*/
        address to,
        uint256 deadline
    ) external override returns (uint256 amountA, uint256 amountB, uint256 liquidity) {
        require(deadline >= block.timestamp, "PancakeRouter: EXPIRED");

        Token(pair).mint(to, 1000);

        IERC20(tokenA).safeTransferFrom(msg.sender, pair, amountADesired);
        IERC20(tokenB).safeTransferFrom(msg.sender, pair, amountBDesired);

        amountA = amountADesired;
        amountB = amountBDesired;
        liquidity = 1000;
    }
}
