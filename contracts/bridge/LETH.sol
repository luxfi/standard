// SPDX-License-Identifier: BSD-3-Clause
// Copyright (c) 2025 Lux Industries Inc.
pragma solidity ^0.8.31;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @title LETH - Bridged Ether on Lux Network
/// @notice ERC20 representation of ETH bridged to Lux
contract LETH is ERC20 {
    event Deposit(address indexed dst, uint256 wad);
    event Withdrawal(address indexed src, uint256 wad);

    constructor() ERC20("Lux Ether", "LETH") {
        // Pre-mint for testing/deployment
        _mint(msg.sender, 10000000 * 10 ** decimals());
    }

    receive() external payable {
        deposit();
    }

    function deposit() public payable {
        _mint(msg.sender, msg.value);
        emit Deposit(msg.sender, msg.value);
    }

    function withdraw(uint256 wad) public {
        require(balanceOf(msg.sender) >= wad, "LETH: insufficient balance");
        _burn(msg.sender, wad);
        payable(msg.sender).transfer(wad);
        emit Withdrawal(msg.sender, wad);
    }
}
