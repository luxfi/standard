// SPDX-License-Identifier: BSD-3-Clause
// Copyright (c) 2025 Lux Industries Inc.
pragma solidity ^0.8.20;

import "@luxfi/standard/lib/token/ERC20/ERC20.sol";
import "@luxfi/standard/lib/token/ERC20/extensions/ERC20Burnable.sol";
import "@luxfi/standard/lib/token/ERC20/extensions/ERC20Pausable.sol";
import "@luxfi/standard/lib/token/ERC20/extensions/ERC20Permit.sol";
import "@luxfi/standard/lib/token/ERC20/extensions/ERC20Votes.sol";
import "@luxfi/standard/lib/token/ERC20/extensions/ERC20FlashMint.sol";
import "@luxfi/standard/lib/access/AccessControl.sol";

/**
 * @title LRC20
 * @author Lux Network
 * @notice Lux Request for Comments 20 - Full-featured fungible token standard
 * @dev Extends OpenZeppelin ERC20 with all major extensions:
 * - Burnable: Token burning capability
 * - Pausable: Emergency pause functionality
 * - Permit: Gasless approvals (EIP-2612)
 * - Votes: On-chain governance voting power
 * - FlashMint: Flash loan capability
 * - AccessControl: Role-based permissions
 */
contract LRC20 is
    ERC20,
    ERC20Burnable,
    ERC20Pausable,
    ERC20Permit,
    ERC20Votes,
    ERC20FlashMint,
    AccessControl
{
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    uint8 private immutable _decimals;

    /**
     * @notice Constructor for LRC20 token
     * @param name_ Token name
     * @param symbol_ Token symbol
     * @param decimals_ Token decimals (default 18)
     * @param initialSupply Initial supply to mint to deployer
     */
    constructor(
        string memory name_,
        string memory symbol_,
        uint8 decimals_,
        uint256 initialSupply
    ) ERC20(name_, symbol_) ERC20Permit(name_) {
        _decimals = decimals_;

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(MINTER_ROLE, msg.sender);
        _grantRole(PAUSER_ROLE, msg.sender);

        if (initialSupply > 0) {
            _mint(msg.sender, initialSupply);
        }
    }

    /**
     * @notice Returns token decimals
     */
    function decimals() public view virtual override returns (uint8) {
        return _decimals;
    }

    /**
     * @notice Mint new tokens
     * @param to Recipient address
     * @param amount Amount to mint
     */
    function mint(address to, uint256 amount) public onlyRole(MINTER_ROLE) {
        _mint(to, amount);
    }

    /**
     * @notice Pause all token transfers
     */
    function pause() public onlyRole(PAUSER_ROLE) {
        _pause();
    }

    /**
     * @notice Unpause token transfers
     */
    function unpause() public onlyRole(PAUSER_ROLE) {
        _unpause();
    }

    // ============ Required Overrides ============

    function _update(address from, address to, uint256 value)
        internal
        override(ERC20, ERC20Pausable, ERC20Votes)
    {
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
