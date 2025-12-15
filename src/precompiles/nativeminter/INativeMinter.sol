// SPDX-License-Identifier: MIT
// Copyright (C) 2025, Lux Industries, Inc. All rights reserved.
pragma solidity ^0.8.0;

import "../IAllowList.sol";

/**
 * @title INativeMinter
 * @dev Interface for the Native Minter precompile
 *
 * This precompile allows permissioned addresses to mint native tokens directly.
 * Only addresses with Enabled, Admin, or Manager roles can mint tokens.
 *
 * Precompile Address: 0x0200000000000000000000000000000000000001
 *
 * Use Cases:
 * - Bridge contracts minting wrapped assets
 * - Faucet contracts for testnets
 * - Custom tokenomics with controlled inflation
 * - Cross-chain asset creation
 *
 * Gas Costs:
 * - mintNativeCoin: 30,000 gas
 * - readAllowList: 2,600 gas
 * - setAdmin/setEnabled/setManager/setNone: 20,000 gas
 *
 * Security:
 * - Only enabled addresses can mint
 * - No limit on mint amount (controlled by allow list permissions)
 * - Minting creates new tokens (increases total supply)
 */
interface INativeMinter is IAllowList {
    /**
     * @notice Emitted when native coins are minted
     * @param sender The address that initiated the mint
     * @param recipient The address receiving the minted coins
     * @param amount The amount of coins minted
     */
    event NativeCoinMinted(address indexed sender, address indexed recipient, uint256 amount);

    /**
     * @notice Mint native coins to an address
     * @dev Only callable by enabled addresses
     * @param addr The address to receive the minted coins
     * @param amount The amount of native coins to mint (in wei)
     */
    function mintNativeCoin(address addr, uint256 amount) external;
}

/**
 * @title NativeMinterLib
 * @dev Library for interacting with the Native Minter precompile
 */
library NativeMinterLib {
    /// @dev The address of the Native Minter precompile
    address constant PRECOMPILE_ADDRESS = 0x0200000000000000000000000000000000000001;

    /// @dev Gas cost for minting
    uint256 constant MINT_GAS = 30000;

    error NotMinterEnabled();
    error ZeroAmount();
    error ZeroAddress();

    /**
     * @notice Check if an address can mint native coins
     * @param addr The address to check
     * @return True if the address can mint
     */
    function canMint(address addr) internal view returns (bool) {
        return AllowListLib.isEnabled(PRECOMPILE_ADDRESS, addr);
    }

    /**
     * @notice Require caller to be able to mint
     */
    function requireCanMint() internal view {
        if (!canMint(msg.sender)) {
            revert NotMinterEnabled();
        }
    }

    /**
     * @notice Mint native coins to an address
     * @param to The recipient address
     * @param amount The amount to mint
     */
    function mint(address to, uint256 amount) internal {
        if (to == address(0)) revert ZeroAddress();
        if (amount == 0) revert ZeroAmount();
        INativeMinter(PRECOMPILE_ADDRESS).mintNativeCoin(to, amount);
    }

    /**
     * @notice Mint native coins to the caller
     * @param amount The amount to mint
     */
    function mintToSelf(uint256 amount) internal {
        mint(msg.sender, amount);
    }

    /**
     * @notice Get the role of an address
     * @param addr The address to check
     * @return role The role (0=None, 1=Enabled, 2=Admin, 3=Manager)
     */
    function getRole(address addr) internal view returns (uint256 role) {
        return INativeMinter(PRECOMPILE_ADDRESS).readAllowList(addr);
    }

    /**
     * @notice Set an address as minter admin
     * @param addr The address to set as admin
     */
    function setAdmin(address addr) internal {
        INativeMinter(PRECOMPILE_ADDRESS).setAdmin(addr);
    }

    /**
     * @notice Enable an address to mint
     * @param addr The address to enable
     */
    function setEnabled(address addr) internal {
        INativeMinter(PRECOMPILE_ADDRESS).setEnabled(addr);
    }

    /**
     * @notice Disable an address from minting
     * @param addr The address to disable
     */
    function setNone(address addr) internal {
        INativeMinter(PRECOMPILE_ADDRESS).setNone(addr);
    }
}

/**
 * @title NativeMinterVerifier
 * @dev Abstract contract for contracts that need native minting capability
 */
abstract contract NativeMinterVerifier {
    using NativeMinterLib for address;

    /// @dev Modifier to check if caller can mint
    modifier onlyMinter() {
        NativeMinterLib.requireCanMint();
        _;
    }

    /**
     * @notice Mint native coins to an address
     * @param to The recipient address
     * @param amount The amount to mint
     */
    function _mintNative(address to, uint256 amount) internal {
        NativeMinterLib.mint(to, amount);
    }
}
