// SPDX-License-Identifier: BSD-3-Clause
// Copyright (c) 2025 Lux Industries Inc.
pragma solidity ^0.8.31;

import "@luxfi/standard/lib/token/ERC20/extensions/ERC4626.sol";
import "@luxfi/standard/lib/token/ERC20/extensions/ERC20Permit.sol";
import "@luxfi/standard/lib/access/Ownable.sol";

/**
 * @title LRC4626
 * @author Lux Network
 * @notice Lux Request for Comments 4626 - Tokenized Vault Standard
 * @dev Extends OpenZeppelin ERC4626 with:
 * - Permit: Gasless approvals (EIP-2612)
 * - Ownable: Admin controls
 */
contract LRC4626 is ERC4626, ERC20Permit, Ownable {
    /**
     * @notice Constructor for LRC4626 vault
     * @param asset_ Underlying asset token
     * @param name_ Vault token name
     * @param symbol_ Vault token symbol
     */
    constructor(
        IERC20 asset_,
        string memory name_,
        string memory symbol_
    )
        ERC4626(asset_)
        ERC20(name_, symbol_)
        ERC20Permit(name_)
        Ownable(msg.sender)
    {}

    /**
     * @notice Returns the total assets managed by the vault
     */
    function totalAssets() public view virtual override returns (uint256) {
        return IERC20(asset()).balanceOf(address(this));
    }

    /**
     * @notice Maximum deposit allowed
     */
    function maxDeposit(address) public view virtual override returns (uint256) {
        return type(uint256).max;
    }

    /**
     * @notice Maximum mint allowed
     */
    function maxMint(address) public view virtual override returns (uint256) {
        return type(uint256).max;
    }

    /**
     * @notice Maximum withdraw allowed
     */
    function maxWithdraw(address owner) public view virtual override returns (uint256) {
        return convertToAssets(balanceOf(owner));
    }

    /**
     * @notice Maximum redeem allowed
     */
    function maxRedeem(address owner) public view virtual override returns (uint256) {
        return balanceOf(owner);
    }

    // ============ Required Overrides ============

    function decimals() public view override(ERC20, ERC4626) returns (uint8) {
        return super.decimals();
    }

    function nonces(address owner)
        public
        view
        override(ERC20Permit)
        returns (uint256)
    {
        return super.nonces(owner);
    }
}
