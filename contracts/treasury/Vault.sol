// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.31;

import {IERC20, SafeERC20} from "@luxfi/standard/tokens/ERC20.sol";

/**
 * @title Vault
 * @notice Fee vault on C-Chain. Receives fees via Warp from all chains.
 * @dev Permissionless: anyone can relay valid Warp proofs.
 *
 * First principles:
 * - Warp proofs are validator-signed, no trusted reporters
 * - Per-chain accounting for transparency
 * - Pull pattern for claims (no unbounded loops)
 * - Single-word naming: total, pending, claimed
 */
contract Vault {
    using SafeERC20 for IERC20;

    // ============ State ============

    /// @notice Fee token (WLUX)
    IERC20 public immutable token;

    /// @notice Deployer address (for init access control)
    address public immutable deployer;

    /// @notice Router that distributes fees
    address public router;

    /// @notice Per-chain accounting
    mapping(bytes32 => uint256) public total;    // All-time received
    mapping(bytes32 => uint256) public pending;  // Awaiting distribution

    /// @notice Processed Warp message IDs (replay protection)
    mapping(bytes32 => bool) public processed;

    /// @notice Global totals
    uint256 public sum;      // All-time total
    uint256 public balance;  // Current pending

    // ============ Events ============

    event Receive(bytes32 indexed chain, uint256 amount, bytes32 warpId);
    event Flush(bytes32 indexed chain, uint256 amount);
    event Router(address indexed router);

    // ============ Errors ============

    error Zero();
    error Replay();
    error Invalid();
    error OnlyRouter();
    error OnlyDeployer();

    // ============ Constructor ============

    constructor(address _token) {
        token = IERC20(_token);
        deployer = msg.sender;
    }

    // ============ Receive ============

    /// @notice Receive fees from a chain via Warp proof
    /// @dev Permissionless - anyone can relay valid proofs
    /// @param chain Source chain ID
    /// @param amount Fee amount
    /// @param warpId Unique Warp message ID
    function receive_(bytes32 chain, uint256 amount, bytes32 warpId) external {
        if (amount == 0) revert Zero();
        if (processed[warpId]) revert Replay();

        // TODO: Verify Warp proof via precompile
        // WarpLib.verify(chain, amount, warpId);

        processed[warpId] = true;
        total[chain] += amount;
        pending[chain] += amount;
        sum += amount;
        balance += amount;

        // Transfer from relayer (they bridged the tokens)
        token.safeTransferFrom(msg.sender, address(this), amount);

        emit Receive(chain, amount, warpId);
    }

    // ============ Router ============

    /// @notice Set router address (one-time setup, deployer only)
    /// @dev C-02 fix: Restrict to deployer to prevent front-run attacks
    function init(address _router) external {
        if (msg.sender != deployer) revert OnlyDeployer();
        if (router != address(0)) revert Invalid();
        if (_router == address(0)) revert Zero();
        router = _router;
        emit Router(_router);
    }

    /// @notice Flush pending fees to router for distribution
    /// @param chain Chain to flush
    /// @return amount Amount flushed
    function flush(bytes32 chain) external returns (uint256 amount) {
        if (msg.sender != router) revert OnlyRouter();

        amount = pending[chain];
        if (amount == 0) return 0;

        pending[chain] = 0;
        balance -= amount;

        token.safeTransfer(router, amount);
        emit Flush(chain, amount);
    }

    /// @notice Flush all chains to router
    /// @param chains Array of chain IDs to flush
    /// @return amounts Array of amounts flushed
    function flushAll(bytes32[] calldata chains) external returns (uint256[] memory amounts) {
        if (msg.sender != router) revert OnlyRouter();

        amounts = new uint256[](chains.length);
        uint256 totalFlushed;

        for (uint256 i = 0; i < chains.length;) {
            uint256 amount = pending[chains[i]];
            if (amount > 0) {
                pending[chains[i]] = 0;
                amounts[i] = amount;
                totalFlushed += amount;
                emit Flush(chains[i], amount);
            }
            unchecked { i++; }
        }

        if (totalFlushed > 0) {
            balance -= totalFlushed;
            token.safeTransfer(router, totalFlushed);
        }
    }

    // ============ View ============

    function stats(bytes32 chain) external view returns (uint256, uint256) {
        return (total[chain], pending[chain]);
    }
}
