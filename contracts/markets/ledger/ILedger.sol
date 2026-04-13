// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title ILedger — generic append-only holder books & records.
/// @notice Implementations track token-ownership transfers as a signed
///         journal with balance + holder-count projections. Domain
///         wrappers (Transfer Agent, Cap Table, DAO Treasury) add their
///         own authorization models (registry, multisig, DAO governance).
interface ILedger {
    event Recorded(uint64 indexed recordId, address indexed from, address indexed to, address asset, uint256 amount);
    event Reversed(uint64 indexed recordId, uint8 reasonCode);

    function record(address from, address to, address asset, uint256 amount) external returns (uint64 recordId);
    function reverse(uint64 recordId, uint8 reasonCode) external returns (bool);

    function balanceOf(address holder, address asset) external view returns (uint256);
    function holderCount(address asset) external view returns (uint64);
}
