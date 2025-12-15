// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts v4.x compatibility shim
// ReentrancyGuard moved from security/ to utils/ in OZ 5.x
pragma solidity ^0.8.0;

// Re-export from new location
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
