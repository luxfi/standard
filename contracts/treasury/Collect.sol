// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.31;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title Collect
 * @notice Fee collector deployed on each chain (P, X, A, B, D, T, G, Q, K, Z).
 * @dev Permissionless: protocols push fees, anyone can bridge to C-Chain.
 *
 * First principles:
 * - Receives settings from C-Chain via Warp
 * - Collects fees from local protocols
 * - Bridges fees to C-Chain Vault via Warp
 * - No governance needed (inherits from FeeGov via Warp)
 * - Single-word naming: rate, total, pending
 */
contract Collect {
    using SafeERC20 for IERC20;

    // ============ Constants ============

    /// @notice C-Chain ID (destination for fees)
    bytes32 public immutable cchain;

    /// @notice C-Chain Vault address
    address public immutable vault;

    // ============ State ============

    /// @notice Fee token (WLUX or local equivalent)
    IERC20 public token;

    /// @notice Current fee rate (from FeeGov via Warp)
    uint16 public rate;

    /// @notice Settings version (staleness check)
    uint32 public version;

    /// @notice Accounting
    uint256 public total;    // All-time collected
    uint256 public pending;  // Awaiting bridge
    uint256 public bridged;  // All-time bridged

    // ============ Events ============

    event Settings(uint16 rate, uint32 version);
    event Fee(address indexed from, uint256 amount);
    event Bridge(uint256 amount, bytes32 warpId);

    // ============ Errors ============

    error Zero();
    error Stale();

    // ============ Constructor ============

    constructor(address _token, bytes32 _cchain, address _vault) {
        token = IERC20(_token);
        cchain = _cchain;
        vault = _vault;
        rate = 30; // Default 0.3%
        version = 1;
    }

    // ============ Settings ============

    /// @notice Receive settings from FeeGov via Warp
    /// @dev Permissionless - anyone can relay valid Warp proofs
    function sync(uint16 _rate, uint32 _version) external {
        // TODO: Verify Warp proof from C-Chain FeeGov
        // WarpLib.verifyFrom(cchain, abi.encode(_rate, _version));

        if (_version <= version) revert Stale();

        rate = _rate;
        version = _version;

        emit Settings(_rate, _version);
    }

    // ============ Collection ============

    /// @notice Protocols push fees here
    /// @param amount Fee amount
    function push(uint256 amount) external {
        if (amount == 0) revert Zero();

        token.safeTransferFrom(msg.sender, address(this), amount);
        total += amount;
        pending += amount;

        emit Fee(msg.sender, amount);
    }

    /// @notice Receive native token fees (payable)
    receive() external payable {
        // Wrap native token if needed
        // For now, just track as pending
        total += msg.value;
        pending += msg.value;
        emit Fee(msg.sender, msg.value);
    }

    // ============ Bridge ============

    /// @notice Bridge pending fees to C-Chain Vault
    /// @dev Permissionless - anyone can trigger
    /// @return warpId Warp message ID
    function bridge() external returns (bytes32 warpId) {
        uint256 amount = pending;
        if (amount == 0) revert Zero();

        pending = 0;
        bridged += amount;

        // TODO: Send via Warp to C-Chain Vault
        // warpId = WarpLib.send(cchain, vault, abi.encode(amount));
        warpId = keccak256(abi.encode(block.chainid, block.timestamp, amount));

        emit Bridge(amount, warpId);
    }

    // ============ View ============

    /// @notice Calculate fee for an amount
    /// @param amount Transaction amount
    /// @return fee Fee amount
    function fee(uint256 amount) external view returns (uint256) {
        return (amount * rate) / 10000;
    }

    function stats() external view returns (uint256, uint256, uint256, uint16, uint32) {
        return (total, pending, bridged, rate, version);
    }
}
