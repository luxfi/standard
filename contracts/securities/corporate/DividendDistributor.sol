// SPDX-License-Identifier: MIT
// Lux Standard Library — Securities Module
//
// Originally based on Arca Labs ST-Contracts (https://github.com/arcalabs/st-contracts)
// Updated to Solidity ^0.8.24 with OpenZeppelin v5 by the Hanzo AI team
//
// Copyright (c) 2026 Lux Partners Limited — https://lux.network
// Copyright (c) 2019 Arca Labs Inc — https://arca.digital
pragma solidity ^0.8.24;

import { AccessControl } from "@luxfi/oz/access/AccessControl.sol";
import { IERC20 } from "@luxfi/oz/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@luxfi/oz/token/ERC20/utils/SafeERC20.sol";

/**
 * @title DividendDistributor
 * @notice On-chain dividend payments for security token holders.
 *
 * Dividends can be paid in any ERC-20 (e.g., USDC, LUX) or native currency.
 * Uses a snapshot-based pull model: admin creates a dividend round, holders claim
 * their pro-rata share based on their balance at the snapshot block.
 */
contract DividendDistributor is AccessControl {
    using SafeERC20 for IERC20;

    bytes32 public constant DIVIDEND_ADMIN_ROLE = keccak256("DIVIDEND_ADMIN_ROLE");

    struct DividendRound {
        IERC20 paymentToken; // address(0) sentinel not used — always ERC-20
        uint256 totalAmount;
        uint256 totalSupplyAtSnapshot;
        uint256 snapshotBlock;
        uint256 claimedAmount;
        bool reclaimed;
    }

    /// @notice The security token whose holders receive dividends.
    IERC20 public immutable SECURITY_TOKEN;

    /// @notice All dividend rounds.
    DividendRound[] public rounds;

    /// @notice roundId => account => claimed
    mapping(uint256 => mapping(address => bool)) public hasClaimed;

    // ──────────────────────────────────────────────────────────────────────────
    // Events
    // ──────────────────────────────────────────────────────────────────────────

    event DividendCreated(uint256 indexed roundId, address paymentToken, uint256 totalAmount, uint256 snapshotBlock);
    event DividendClaimed(uint256 indexed roundId, address indexed account, uint256 amount);
    event DividendReclaimed(uint256 indexed roundId, uint256 unclaimedAmount);

    // ──────────────────────────────────────────────────────────────────────────
    // Errors
    // ──────────────────────────────────────────────────────────────────────────

    error ZeroAddress();
    error ZeroAmount();
    error RoundNotFound(uint256 roundId);
    error AlreadyClaimed(uint256 roundId, address account);
    error AlreadyReclaimed(uint256 roundId);
    error NothingToClaim();

    // ──────────────────────────────────────────────────────────────────────────
    // Constructor
    // ──────────────────────────────────────────────────────────────────────────

    constructor(address admin, IERC20 _securityToken) {
        if (admin == address(0)) revert ZeroAddress();
        if (address(_securityToken) == address(0)) revert ZeroAddress();
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(DIVIDEND_ADMIN_ROLE, admin);
        SECURITY_TOKEN = _securityToken;
    }

    // ──────────────────────────────────────────────────────────────────────────
    // Admin
    // ──────────────────────────────────────────────────────────────────────────

    /**
     * @notice Create a new dividend round. Caller must have approved `totalAmount` of `paymentToken`.
     * @param paymentToken ERC-20 used for payment (e.g., USDC)
     * @param totalAmount  Total dividend pool
     */
    function createDividend(IERC20 paymentToken, uint256 totalAmount) external onlyRole(DIVIDEND_ADMIN_ROLE) {
        if (address(paymentToken) == address(0)) revert ZeroAddress();
        if (totalAmount == 0) revert ZeroAmount();

        uint256 currentSupply = SECURITY_TOKEN.totalSupply();
        if (currentSupply == 0) revert ZeroAmount();

        paymentToken.safeTransferFrom(_msgSender(), address(this), totalAmount);

        uint256 roundId = rounds.length;
        rounds.push(
            DividendRound({
                paymentToken: paymentToken,
                totalAmount: totalAmount,
                totalSupplyAtSnapshot: currentSupply,
                snapshotBlock: block.number,
                claimedAmount: 0,
                reclaimed: false
            })
        );

        emit DividendCreated(roundId, address(paymentToken), totalAmount, block.number);
    }

    /**
     * @notice Reclaim unclaimed dividends from a round.
     */
    function reclaimDividend(uint256 roundId) external onlyRole(DIVIDEND_ADMIN_ROLE) {
        if (roundId >= rounds.length) revert RoundNotFound(roundId);
        DividendRound storage round = rounds[roundId];
        if (round.reclaimed) revert AlreadyReclaimed(roundId);

        round.reclaimed = true;
        uint256 unclaimed = round.totalAmount - round.claimedAmount;
        if (unclaimed > 0) {
            round.paymentToken.safeTransfer(_msgSender(), unclaimed);
        }

        emit DividendReclaimed(roundId, unclaimed);
    }

    // ──────────────────────────────────────────────────────────────────────────
    // Claim
    // ──────────────────────────────────────────────────────────────────────────

    /**
     * @notice Claim dividend for a specific round.
     * @dev Uses current balance as proxy for snapshot balance (simplified model).
     *      For production, integrate with ERC20Votes or an external snapshot mechanism.
     */
    function claim(uint256 roundId) external {
        if (roundId >= rounds.length) revert RoundNotFound(roundId);
        DividendRound storage round = rounds[roundId];

        address account = _msgSender();
        if (hasClaimed[roundId][account]) revert AlreadyClaimed(roundId, account);

        uint256 balance = SECURITY_TOKEN.balanceOf(account);
        if (balance == 0) revert NothingToClaim();

        uint256 amount = (round.totalAmount * balance) / round.totalSupplyAtSnapshot;
        if (amount == 0) revert NothingToClaim();

        hasClaimed[roundId][account] = true;
        round.claimedAmount += amount;
        round.paymentToken.safeTransfer(account, amount);

        emit DividendClaimed(roundId, account, amount);
    }

    // ──────────────────────────────────────────────────────────────────────────
    // Queries
    // ──────────────────────────────────────────────────────────────────────────

    function roundCount() external view returns (uint256) {
        return rounds.length;
    }

    function claimableAmount(uint256 roundId, address account) external view returns (uint256) {
        if (roundId >= rounds.length) return 0;
        DividendRound storage round = rounds[roundId];
        if (hasClaimed[roundId][account]) return 0;
        uint256 balance = SECURITY_TOKEN.balanceOf(account);
        return (round.totalAmount * balance) / round.totalSupplyAtSnapshot;
    }
}
