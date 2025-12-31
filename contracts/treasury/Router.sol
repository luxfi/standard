// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.31;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

interface IVault {
    function flush(bytes32 chain) external returns (uint256);
    function flushAll(bytes32[] calldata chains) external returns (uint256[] memory);
}

/**
 * @title Router
 * @notice Fee distribution router on C-Chain. Pull pattern for recipients.
 * @dev Governance-controlled weights, permissionless claims.
 *
 * First principles:
 * - Fixed recipients with governance-set weights
 * - Pull pattern: recipients claim their share
 * - No unbounded loops in distribution
 * - Single-word naming: weight, owed, claimed
 */
contract Router is Ownable {
    using SafeERC20 for IERC20;

    // ============ Constants ============

    uint256 public constant BASE = 10000; // 100% in basis points

    // ============ State ============

    /// @notice Fee token (WLUX)
    IERC20 public immutable token;

    /// @notice Fee vault
    IVault public immutable vault;

    /// @notice Recipient weights (basis points, sum to 10000)
    mapping(address => uint256) public weight;

    /// @notice Owed to each recipient (accumulated)
    mapping(address => uint256) public owed;

    /// @notice Claimed by each recipient (all-time)
    mapping(address => uint256) public claimed;

    /// @notice Active recipients
    address[] public list;
    mapping(address => bool) public active;

    /// @notice Total distributed (all-time)
    uint256 public total;

    // ============ Events ============

    event Weight(address indexed recipient, uint256 weight);
    event Distribute(uint256 amount);
    event Claim(address indexed recipient, uint256 amount);

    // ============ Errors ============

    error Zero();
    error Invalid();
    error Overflow();

    // ============ Constructor ============

    constructor(address _token, address _vault, address _owner) Ownable(_owner) {
        token = IERC20(_token);
        vault = IVault(_vault);
    }

    // ============ Governance ============

    /// @notice Set recipient weight
    /// @param recipient Address to receive fees
    /// @param _weight Weight in basis points (0-10000)
    function set(address recipient, uint256 _weight) external onlyOwner {
        if (recipient == address(0)) revert Zero();
        if (_weight > BASE) revert Overflow();

        // Add to list if new
        if (!active[recipient] && _weight > 0) {
            active[recipient] = true;
            list.push(recipient);
        }

        weight[recipient] = _weight;
        emit Weight(recipient, _weight);
    }

    /// @notice Batch set weights
    /// @param recipients Array of addresses
    /// @param weights Array of weights (must sum to 10000)
    function setBatch(address[] calldata recipients, uint256[] calldata weights) external onlyOwner {
        if (recipients.length != weights.length) revert Invalid();

        uint256 sum;
        for (uint256 i = 0; i < recipients.length;) {
            if (recipients[i] == address(0)) revert Zero();
            if (weights[i] > BASE) revert Overflow();

            if (!active[recipients[i]] && weights[i] > 0) {
                active[recipients[i]] = true;
                list.push(recipients[i]);
            }

            weight[recipients[i]] = weights[i];
            sum += weights[i];
            emit Weight(recipients[i], weights[i]);
            unchecked { i++; }
        }

        if (sum != BASE) revert Invalid();
    }

    // ============ Distribution ============

    /// @notice Pull fees from vault and distribute to recipients
    /// @param chains Chain IDs to flush
    /// @return amount Total distributed
    function distribute(bytes32[] calldata chains) external returns (uint256 amount) {
        uint256[] memory amounts = vault.flushAll(chains);

        for (uint256 i = 0; i < amounts.length;) {
            amount += amounts[i];
            unchecked { i++; }
        }

        if (amount == 0) return 0;

        // Distribute to recipients by weight
        for (uint256 i = 0; i < list.length;) {
            address recipient = list[i];
            uint256 w = weight[recipient];
            if (w > 0) {
                uint256 share = (amount * w) / BASE;
                owed[recipient] += share;
            }
            unchecked { i++; }
        }

        total += amount;
        emit Distribute(amount);
    }

    // ============ Claims ============

    /// @notice Claim owed fees (pull pattern)
    /// @return amount Amount claimed
    function claim() external returns (uint256 amount) {
        amount = owed[msg.sender];
        if (amount == 0) return 0;

        owed[msg.sender] = 0;
        claimed[msg.sender] += amount;

        token.safeTransfer(msg.sender, amount);
        emit Claim(msg.sender, amount);
    }

    /// @notice Claim on behalf of recipient (permissionless)
    /// @param recipient Address to claim for
    /// @return amount Amount claimed
    function claimFor(address recipient) external returns (uint256 amount) {
        amount = owed[recipient];
        if (amount == 0) return 0;

        owed[recipient] = 0;
        claimed[recipient] += amount;

        token.safeTransfer(recipient, amount);
        emit Claim(recipient, amount);
    }

    // ============ View ============

    function count() external view returns (uint256) {
        return list.length;
    }

    function info(address recipient) external view returns (uint256, uint256, uint256) {
        return (weight[recipient], owed[recipient], claimed[recipient]);
    }

    function weights() external view returns (address[] memory, uint256[] memory) {
        uint256[] memory w = new uint256[](list.length);
        for (uint256 i = 0; i < list.length;) {
            w[i] = weight[list[i]];
            unchecked { i++; }
        }
        return (list, w);
    }
}
