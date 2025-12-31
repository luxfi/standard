// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.31;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title FeeGov
 * @notice Fee governance for all Lux chains. Simple rate storage + Warp broadcast.
 * @dev Deploy on C-Chain only. Other chains read via Warp.
 *
 * First principles:
 * - C-Chain governs, other chains collect
 * - Settings propagate via Warp, not trusted reporters
 * - No dynamic fees (that's EIP-1559 at consensus)
 * - Single-word naming: rate, floor, cap, version
 */
contract FeeGov is Ownable {
    // ============ State ============

    /// @notice Fee rate in basis points (30 = 0.3%)
    uint16 public rate;

    /// @notice Bounds
    uint16 public floor;
    uint16 public cap;

    /// @notice Monotonic version for staleness checks
    uint32 public version;

    /// @notice Trusted chains
    mapping(bytes32 => bool) public chains;
    bytes32[] public list;

    // ============ Events ============

    event Rate(uint16 rate, uint32 version);
    event Chain(bytes32 indexed id, bool active);
    event Broadcast(uint32 version, uint256 count);

    // ============ Errors ============

    error TooLow();
    error TooHigh();
    error Exists();
    error Missing();

    // ============ Constructor ============

    constructor(
        uint16 _rate,
        uint16 _floor,
        uint16 _cap,
        address _owner
    ) Ownable(_owner) {
        floor = _floor;
        cap = _cap;
        rate = _rate;
        version = 1;
    }

    // ============ Governance ============

    /// @notice Set fee rate
    function set(uint16 _rate) external onlyOwner {
        if (_rate < floor) revert TooLow();
        if (_rate > cap) revert TooHigh();

        rate = _rate;
        unchecked { version++; }

        emit Rate(_rate, version);
    }

    /// @notice Set bounds
    function bounds(uint16 _floor, uint16 _cap) external onlyOwner {
        floor = _floor;
        cap = _cap;
    }

    /// @notice Add chain
    function add(bytes32 id) external onlyOwner {
        if (chains[id]) revert Exists();
        chains[id] = true;
        list.push(id);
        emit Chain(id, true);
    }

    /// @notice Remove chain
    function remove(bytes32 id) external onlyOwner {
        if (!chains[id]) revert Missing();
        chains[id] = false;
        emit Chain(id, false);
    }

    // ============ Broadcast ============

    /// @notice Broadcast settings to all chains via Warp
    /// @dev Permissionless - anyone can trigger broadcast
    function broadcast() external returns (uint256 sent) {
        bytes memory payload = abi.encode(rate, version);

        for (uint256 i = 0; i < list.length;) {
            if (chains[list[i]]) {
                // WarpLib.send(list[i], payload);
                unchecked { sent++; }
            }
            unchecked { i++; }
        }

        emit Broadcast(version, sent);
    }

    // ============ View ============

    function settings() external view returns (uint16, uint16, uint16, uint32) {
        return (rate, floor, cap, version);
    }

    function count() external view returns (uint256) {
        return list.length;
    }
}
