// SPDX-License-Identifier: BSD-3-Clause
// Copyright (c) 2025 Lux Industries Inc.
pragma solidity ^0.8.20;

import "@luxfi/standard/lib/token/ERC20/ERC20.sol";
import "@luxfi/standard/lib/access/Ownable.sol";

/**
 * @title LRC20Basic
 * @author Lux Network
 * @notice Minimal LRC20 implementation for simple tokens
 */
contract LRC20Basic is ERC20, Ownable {
    uint8 private immutable _decimals;

    constructor(
        string memory name_,
        string memory symbol_,
        uint8 decimals_,
        uint256 initialSupply
    ) ERC20(name_, symbol_) Ownable(msg.sender) {
        _decimals = decimals_;
        if (initialSupply > 0) {
            _mint(msg.sender, initialSupply);
        }
    }

    function decimals() public view virtual override returns (uint8) {
        return _decimals;
    }

    function mint(address to, uint256 amount) public onlyOwner {
        _mint(to, amount);
    }
}
