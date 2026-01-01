//SPDX-License-Identifier: MIT

pragma solidity ^0.8.31;

interface IPancakeFactory {
    function getPair(address tokenA, address tokenB) external view returns (address pair);
}
