// SPDX-License-Identifier: BSD-3-Clause
// Copyright (c) 2025 Lux Industries Inc.
pragma solidity ^0.8.31;

import "../tokens/LRC20.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title ETHVault - ETH Vault with Share Tokens
 * @notice Vault for depositing ETH and receiving share tokens
 * @dev Built on LRC20 (Lux Request for Comments 20)
 *      H-03 fix: Added rate limiting and emergency pause
 */
contract ETHVault is LRC20, Pausable, Ownable {
    // ═══════════════════════════════════════════════════════════════════════
    // CONSTANTS (H-03 fix)
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice Maximum withdrawal per address per period
    uint256 public constant MAX_WITHDRAWAL_PER_PERIOD = 100 ether;

    /// @notice Withdrawal rate limit period
    uint256 public constant WITHDRAWAL_PERIOD = 1 hours;

    // ═══════════════════════════════════════════════════════════════════════
    // STATE (H-03 fix)
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice Withdrawal amount per recipient in current period
    mapping(address => uint256) public withdrawalAmount;

    /// @notice Last withdrawal timestamp per recipient
    mapping(address => uint256) public lastWithdrawalTime;

    // ═══════════════════════════════════════════════════════════════════════
    // EVENTS
    // ═══════════════════════════════════════════════════════════════════════

    event Deposit(address indexed user, uint256 amount);

    event Withdraw(
        address indexed caller,
        address indexed receiver,
        address indexed owner,
        uint256 amount
    );

    // ═══════════════════════════════════════════════════════════════════════
    // ERRORS (H-03 fix)
    // ═══════════════════════════════════════════════════════════════════════

    error ExceedsWithdrawalLimit();
    error InsufficientBalance();
    error InsufficientAllowance();
    error SendFailed();
    error ZeroValue();

    // ═══════════════════════════════════════════════════════════════════════
    // CONSTRUCTOR
    // ═══════════════════════════════════════════════════════════════════════

    constructor(string memory name, string memory symbol) LRC20(name, symbol) Ownable(msg.sender) {}

    // Function to receive ETH and mint shares
    receive() external payable {}

    /**
     * @dev deposit ETH
     * @param amount_ eth amount
     * @param receiver_ receiver's address
     */
    function deposit(uint256 amount_, address receiver_) external payable {
        if (msg.value == 0 || amount_ != msg.value) revert ZeroValue();
        // Calculate the number of shares to mint
        uint256 shares = msg.value; // For simplicity, 1 ETH = 1 share
        // Mint the shares to the sender
        _mint(receiver_, shares);
        emit Deposit(msg.sender, msg.value);
    }

    /**
     * @dev withdraw eth
     * @param amount_ eth amount
     * @param receiver_ receiver's address
     * @param owner_ owner's share address
     * @dev H-03 fix: Added rate limiting and pause capability
     */
    function withdraw(
        uint256 amount_,
        address receiver_,
        address owner_
    ) external whenNotPaused {
        if (amount_ > address(this).balance) revert InsufficientBalance();
        if (msg.sender != owner_) {
            uint256 allowed = allowance(owner_, msg.sender);
            if (allowed < amount_) revert InsufficientAllowance();
        }

        // H-03 fix: Validate withdrawal rate limit
        _validateWithdrawal(receiver_, amount_);

        _burn(owner_, amount_);
        (bool success, ) = payable(receiver_).call{value: amount_}("");
        if (!success) revert SendFailed();
        emit Withdraw(msg.sender, receiver_, owner_, amount_);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // ADMIN FUNCTIONS (H-03 fix)
    // ═══════════════════════════════════════════════════════════════════════

    /**
     * @notice Pause all withdrawals (emergency)
     */
    function pause() external onlyOwner {
        _pause();
    }

    /**
     * @notice Unpause withdrawals
     */
    function unpause() external onlyOwner {
        _unpause();
    }

    // ═══════════════════════════════════════════════════════════════════════
    // INTERNAL FUNCTIONS (H-03 fix)
    // ═══════════════════════════════════════════════════════════════════════

    /**
     * @notice Validate withdrawal against rate limits
     * @param recipient Address receiving the withdrawal
     * @param amount Amount being withdrawn
     */
    function _validateWithdrawal(address recipient, uint256 amount) internal {
        // Reset period if enough time has passed
        if (block.timestamp > lastWithdrawalTime[recipient] + WITHDRAWAL_PERIOD) {
            withdrawalAmount[recipient] = 0;
            lastWithdrawalTime[recipient] = block.timestamp;
        }

        // Check rate limit
        if (withdrawalAmount[recipient] + amount > MAX_WITHDRAWAL_PER_PERIOD) {
            revert ExceedsWithdrawalLimit();
        }

        withdrawalAmount[recipient] += amount;
    }
}
