// SPDX-License-Identifier: MIT
pragma solidity ^0.8.31;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import {ERC20Votes} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Votes.sol";
import {Nonces} from "@openzeppelin/contracts/utils/Nonces.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title VotesToken
 * @notice ERC20 token with voting capabilities
 */
contract VotesToken is ERC20, ERC20Permit, ERC20Votes, Ownable {
    struct Allocation {
        address recipient;
        uint256 amount;
    }

    bool public transferable;

    constructor(
        string memory name,
        string memory symbol,
        Allocation[] memory allocations,
        address owner_,
        uint256, // totalSupply (unused, calculated from allocations)
        bool transferable_
    )
        ERC20(name, symbol)
        ERC20Permit(name)
        Ownable(owner_)
    {
        transferable = transferable_;
        for (uint256 i = 0; i < allocations.length; i++) {
            _mint(allocations[i].recipient, allocations[i].amount);
        }
    }

    function mint(address to, uint256 amount) external onlyOwner {
        _mint(to, amount);
    }

    function _update(address from, address to, uint256 value) internal override(ERC20, ERC20Votes) {
        if (!transferable && from != address(0) && to != address(0)) {
            revert("VotesToken: non-transferable");
        }
        super._update(from, to, value);
    }

    function nonces(address owner) public view override(ERC20Permit, Nonces) returns (uint256) {
        return super.nonces(owner);
    }
}
