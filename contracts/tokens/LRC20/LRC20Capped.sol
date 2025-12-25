// SPDX-License-Identifier: BSD-3-Clause
// Copyright (c) 2025 Lux Industries Inc.
pragma solidity ^0.8.31;

import "@luxfi/standard/lib/token/ERC20/ERC20.sol";
import "@luxfi/standard/lib/token/ERC20/extensions/ERC20Capped.sol";
import "@luxfi/standard/lib/token/ERC20/extensions/ERC20Burnable.sol";
import "@luxfi/standard/lib/access/Ownable.sol";

/**
 * @title LRC20Capped
 * @author Lux Network
 * @notice LRC20 with maximum supply cap
 */
contract LRC20Capped is ERC20, ERC20Capped, ERC20Burnable, Ownable {
    uint8 private immutable _decimals;

    constructor(
        string memory name_,
        string memory symbol_,
        uint8 decimals_,
        uint256 cap_,
        uint256 initialSupply
    ) ERC20(name_, symbol_) ERC20Capped(cap_) Ownable(msg.sender) {
        _decimals = decimals_;
        require(initialSupply <= cap_, "Initial supply exceeds cap");
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

    function _update(address from, address to, uint256 value)
        internal
        override(ERC20, ERC20Capped)
    {
        super._update(from, to, value);
    }
}
