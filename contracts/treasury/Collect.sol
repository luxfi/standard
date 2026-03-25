// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.31;

import { IERC20, SafeERC20 } from "@luxfi/standard/tokens/ERC20.sol";
import { AccessControl } from "@openzeppelin/contracts/access/AccessControl.sol";

/**
 * @title Collect
 * @notice Fee collector deployed on each chain (P, X, A, B, D, T, G, Q, K, Z).
 * @dev Authorized relayers deliver settings and bridge fees until Warp precompile is active.
 *
 * First principles:
 * - Receives settings from C-Chain via authorized relayers (RELAYER_ROLE)
 * - Collects fees from local protocols
 * - Bridges fees to C-Chain Vault via authorized relayers
 * - No governance needed (inherits from FeeGov via relayer)
 * - Single-word naming: rate, total, pending
 */
contract Collect is AccessControl {
    using SafeERC20 for IERC20;

    // ============ Roles ============

    /// @notice Role for authorized relayers (delivers settings and bridges fees)
    bytes32 public constant RELAYER_ROLE = keccak256("RELAYER_ROLE");

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
    uint256 public total; // All-time collected
    uint256 public pending; // Awaiting bridge
    uint256 public bridged; // All-time bridged

    // ============ Events ============

    event Settings(uint16 rate, uint32 version);
    event Fee(address indexed from, uint256 amount);
    event Bridge(uint256 amount, bytes32 warpId);

    // ============ Errors ============

    error Zero();
    error Stale();
    error ZeroAddress();
    error ETHTransferFailed();

    // ============ Constructor ============

    constructor(address _token, bytes32 _cchain, address _vault, address _owner) {
        token = IERC20(_token);
        cchain = _cchain;
        vault = _vault;
        rate = 30; // Default 0.3%
        version = 1;
        _grantRole(DEFAULT_ADMIN_ROLE, _owner);
        _grantRole(RELAYER_ROLE, _owner);
    }

    // ============ Settings ============

    /// @notice Receive settings from FeeGov via authorized relayer
    /// @dev Restricted to RELAYER_ROLE. When Warp precompile is active, relayers
    ///      will verify Warp proofs off-chain before submitting; on-chain Warp
    ///      verification replaces this role entirely at that point.
    function sync(uint16 _rate, uint32 _version) external onlyRole(RELAYER_ROLE) {
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
    /// @dev Restricted to admin or relayer. Generates a deterministic receipt ID
    ///      from chain/block/amount. When Warp precompile is active, this will be
    ///      replaced by WarpLib.send() which returns a validator-signed message ID.
    /// @return warpId Deterministic receipt ID (placeholder until Warp precompile activation)
    function bridge() external onlyRole(RELAYER_ROLE) returns (bytes32 warpId) {
        uint256 amount = pending;
        if (amount == 0) revert Zero();

        pending = 0;
        bridged += amount;

        // Deterministic receipt — replaced by WarpLib.send(cchain, vault, ...) at Warp activation
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

    // ============ Emergency Withdrawal ============

    /**
     * @notice Withdraw locked ETH (emergency recovery)
     * @param to Recipient address
     * @param amount Amount to withdraw
     */
    function withdrawETH(address payable to, uint256 amount) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (to == address(0)) revert ZeroAddress();
        (bool success,) = to.call{ value: amount }("");
        if (!success) revert ETHTransferFailed();
    }

    /**
     * @notice Withdraw locked ERC20 tokens (emergency recovery)
     * @param tokenAddress Token to withdraw
     * @param to Recipient address
     * @param amount Amount to withdraw
     */
    function withdrawToken(address tokenAddress, address to, uint256 amount) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (to == address(0)) revert ZeroAddress();
        IERC20(tokenAddress).safeTransfer(to, amount);
    }
}
