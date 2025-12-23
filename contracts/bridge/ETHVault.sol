// SPDX-License-Identifier: BSD-3-Clause
// Copyright (c) 2025 Lux Industries Inc.
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract ETHVault is ERC20 {
    // Event to emit when ETH is deposited
    event Deposit(address indexed user, uint256 amount);

    event Withdraw(
        address indexed caller,
        address indexed receiver,
        address indexed owner,
        uint256 amount
    );

    constructor(string memory name, string memory symbol) ERC20(name, symbol) {}
    // Function to receive ETH and mint shares
    receive() external payable {}

    /**
     * @dev deposit ETH
     * @param amount_ eth amount
     * @param receiver_ receiver's address
     */
    function deposit(uint256 amount_, address receiver_) external payable {
        require(msg.value > 0 && amount_ == msg.value, "Must send ETH");
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
     */
    function withdraw(
        uint256 amount_,
        address receiver_,
        address owner_
    ) external {
        require(amount_ <= address(this).balance, "Insufficient balance");
        if (msg.sender != owner_) {
            uint256 allowed = allowance(owner_, msg.sender);
            require(allowed >= amount_, "Invalid alowance");
        }
        _burn(owner_, amount_);
        (bool success, ) = payable(receiver_).call{value: amount_}("");
        require(success, "sending failed");
        emit Withdraw(msg.sender, receiver_, owner_, amount_);
    }
}
