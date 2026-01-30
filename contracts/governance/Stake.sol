// SPDX-License-Identifier: MIT
pragma solidity ^0.8.31;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import {ERC20Votes} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Votes.sol";
import {Nonces} from "@openzeppelin/contracts/utils/Nonces.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title Stake
 * @author Lux Industries Inc
 * @notice ERC20 governance token representing staked voting power in a DAO
 * @dev Implements ERC20Votes for on-chain governance with optional soulbound mode
 *
 * Represents staked voting power:
 * - Voting weight in DAO governance
 * - Can be transferable or soulbound (non-transferable)
 * - Links to DID for identity (did:lux:alice)
 *
 * Features:
 * - Checkpointing for historical vote lookups
 * - EIP-2612 permit for gasless approvals
 * - Delegation of voting power
 * - Optional minting cap
 * - Soulbound mode for citizenship-like tokens
 * - DID linkage (references did/Registry)
 */
contract Stake is ERC20, ERC20Permit, ERC20Votes, Ownable {
    /// @notice Maximum supply (0 = unlimited)
    uint256 public immutable maxSupply;

    /// @notice Whether token is soulbound (non-transferable)
    bool public soulbound;

    /// @notice DID document URI for each holder
    mapping(address => string) public did;

    /// @notice Error when max supply would be exceeded
    error MaxSupplyExceeded(uint256 requested, uint256 available);

    /// @notice Error when transfers are not allowed (soulbound)
    error SoulboundToken();

    /// @notice Error when DID is already linked
    error DIDAlreadyLinked();

    /// @notice Allocation struct for initial distribution
    struct Allocation {
        address recipient;
        uint256 amount;
    }

    /// @notice Emitted when a DID is linked to an address
    event DIDLinked(address indexed account, string didDocument);

    /// @notice Emitted when soulbound mode is changed
    event SoulboundModeChanged(bool enabled);

    /**
     * @notice Constructor
     * @param name_ Token name (e.g., "Security Committee")
     * @param symbol_ Token symbol (e.g., "SECURITY")
     * @param allocations Initial token allocations
     * @param owner_ Owner address (Council Safe)
     * @param maxSupply_ Maximum supply (0 = unlimited)
     * @param soulbound_ Whether token is non-transferable
     */
    constructor(
        string memory name_,
        string memory symbol_,
        Allocation[] memory allocations,
        address owner_,
        uint256 maxSupply_,
        bool soulbound_
    ) ERC20(name_, symbol_) ERC20Permit(name_) Ownable(owner_) {
        maxSupply = maxSupply_;
        soulbound = soulbound_;

        // Distribute initial allocations
        for (uint256 i = 0; i < allocations.length; i++) {
            _mint(allocations[i].recipient, allocations[i].amount);
        }
    }

    // ═══════════════════════════════════════════════════════════════════════
    // MINTING
    // ═══════════════════════════════════════════════════════════════════════

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

    // ═══════════════════════════════════════════════════════════════════════
    // SOULBOUND MODE
    // ═══════════════════════════════════════════════════════════════════════

    /**
     * @notice Toggle soulbound mode
     * @dev Only owner can change, affects all future transfers
     * @param enabled Whether transfers should be disabled
     */
    function setSoulbound(bool enabled) external onlyOwner {
        soulbound = enabled;
        emit SoulboundModeChanged(enabled);
    }

    /**
     * @notice Check if token is soulbound
     * @return True if non-transferable
     */
    function isSoulbound() external view returns (bool) {
        return soulbound;
    }

    // ═══════════════════════════════════════════════════════════════════════
    // DID INTEGRATION
    // ═══════════════════════════════════════════════════════════════════════

    /**
     * @notice Link a DID document to the caller's address
     * @param didDocument DID document URI (e.g., "did:lux:0x1234..." or IPFS hash)
     */
    function linkDID(string calldata didDocument) external {
        if (bytes(did[msg.sender]).length > 0) {
            revert DIDAlreadyLinked();
        }
        did[msg.sender] = didDocument;
        emit DIDLinked(msg.sender, didDocument);
    }

    /**
     * @notice Get DID for an account
     * @param account Address to query
     * @return DID document URI
     */
    function getDID(address account) external view returns (string memory) {
        return did[account];
    }

    // ═══════════════════════════════════════════════════════════════════════
    // OVERRIDES
    // ═══════════════════════════════════════════════════════════════════════

    function _update(address from, address to, uint256 value)
        internal
        override(ERC20, ERC20Votes)
    {
        // Soulbound check (mints and burns always allowed)
        if (soulbound && from != address(0) && to != address(0)) {
            revert SoulboundToken();
        }
        super._update(from, to, value);
    }

    function nonces(address owner_)
        public
        view
        override(ERC20Permit, Nonces)
        returns (uint256)
    {
        return super.nonces(owner_);
    }
}
