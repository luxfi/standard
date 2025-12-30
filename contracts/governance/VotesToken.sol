// SPDX-License-Identifier: MIT
pragma solidity ^0.8.31;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import {ERC20Votes} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Votes.sol";
import {Nonces} from "@openzeppelin/contracts/utils/Nonces.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title VotesToken
 * @author Lux Industries Inc
 * @notice ERC20 governance token with voting power for DAOs
 * @dev Implements ERC20Votes for on-chain governance
 *
 * Features:
 * - Checkpointing for historical vote lookups
 * - EIP-2612 permit for gasless approvals
 * - Delegation of voting power
 * - Optional minting cap
 */
contract VotesToken is ERC20, ERC20Permit, ERC20Votes, Ownable {
    /// @notice Maximum supply (0 = unlimited)
    uint256 public immutable maxSupply;

    /// @notice Whether token is transferable (true = locked initially)
    bool public locked;

    /// @notice Error when max supply would be exceeded
    error MaxSupplyExceeded(uint256 requested, uint256 available);

    /// @notice Error when transfers are locked
    error TransfersLocked();

    /// @notice Allocation struct for initial distribution
    struct Allocation {
        address recipient;
        uint256 amount;
    }

    /**
     * @notice Constructor
     * @param name_ Token name
     * @param symbol_ Token symbol
     * @param allocations Initial token allocations
     * @param owner_ Owner address (can mint/burn)
     * @param maxSupply_ Maximum supply (0 = unlimited)
     * @param locked_ Whether transfers are initially locked
     */
    constructor(
        string memory name_,
        string memory symbol_,
        Allocation[] memory allocations,
        address owner_,
        uint256 maxSupply_,
        bool locked_
    ) ERC20(name_, symbol_) ERC20Permit(name_) Ownable(owner_) {
        maxSupply = maxSupply_;
        locked = locked_;

        // Distribute initial allocations
        for (uint256 i = 0; i < allocations.length; i++) {
            _mint(allocations[i].recipient, allocations[i].amount);
        }
    }

    /**
     * @notice Mint new tokens
     * @param to Recipient address
     * @param amount Amount to mint
     */
    function mint(address to, uint256 amount) external onlyOwner {
        if (maxSupply > 0 && totalSupply() + amount > maxSupply) {
            revert MaxSupplyExceeded(amount, maxSupply - totalSupply());
        }
        _mint(to, amount);
    }

    /**
     * @notice Burn tokens from sender
     * @param amount Amount to burn
     */
    function burn(uint256 amount) external {
        _burn(msg.sender, amount);
    }

    /**
     * @notice Unlock transfers
     * @dev Can only be called by owner, irreversible
     */
    function unlock() external onlyOwner {
        locked = false;
    }

    // ═══════════════════════════════════════════════════════════════════════
    // OVERRIDES
    // ═══════════════════════════════════════════════════════════════════════

    function _update(address from, address to, uint256 value)
        internal
        override(ERC20, ERC20Votes)
    {
        // Check if transfers are locked (mints and burns are always allowed)
        if (locked && from != address(0) && to != address(0)) {
            revert TransfersLocked();
        }
        super._update(from, to, value);
    }

    function nonces(address owner)
        public
        view
        override(ERC20Permit, Nonces)
        returns (uint256)
    {
        return super.nonces(owner);
    }
}
