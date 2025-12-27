// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "./IBridgeToken.sol";

/**
 * @title ERC20B
 * @notice Bridgeable ERC20 token with role-based access control
 * @dev Only authorized bridges can mint/burn tokens
 */
contract ERC20B is ERC20, AccessControl, Pausable, IBridgeToken {
    bytes32 public constant BRIDGE_ROLE = keccak256("BRIDGE_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    // ============ Events ============
    event BridgeMint(address indexed account, uint256 amount);
    event BridgeBurn(address indexed account, uint256 amount);
    event BridgeAdded(address indexed bridge);
    event BridgeRemoved(address indexed bridge);

    // ============ Errors ============
    error InvalidAddress();
    error InsufficientBalance();

    // ============ Constructor ============
    constructor(
        string memory name,
        string memory symbol,
        address admin
    ) ERC20(name, symbol) {
        if (admin == address(0)) revert InvalidAddress();
        
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(PAUSER_ROLE, admin);
    }

    // ============ Bridge Functions ============

    /**
     * @notice Mint tokens to an account
     * @dev Only callable by addresses with BRIDGE_ROLE
     * @param account Account to mint to
     * @param amount Amount to mint
     */
    function bridgeMint(
        address account,
        uint256 amount
    ) external override onlyRole(BRIDGE_ROLE) whenNotPaused returns (bool) {
        if (account == address(0)) revert InvalidAddress();
        _mint(account, amount);
        emit BridgeMint(account, amount);
        return true;
    }

    /**
     * @notice Burn tokens from an account
     * @dev Only callable by addresses with BRIDGE_ROLE
     * @param account Account to burn from
     * @param amount Amount to burn
     */
    function bridgeBurn(
        address account,
        uint256 amount
    ) external override onlyRole(BRIDGE_ROLE) whenNotPaused returns (bool) {
        if (account == address(0)) revert InvalidAddress();
        if (balanceOf(account) < amount) revert InsufficientBalance();
        _burn(account, amount);
        emit BridgeBurn(account, amount);
        return true;
    }

    // ============ Admin Functions ============

    /**
     * @notice Add a bridge address
     */
    function addBridge(address bridge) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (bridge == address(0)) revert InvalidAddress();
        _grantRole(BRIDGE_ROLE, bridge);
        emit BridgeAdded(bridge);
    }

    /**
     * @notice Remove a bridge address
     */
    function removeBridge(address bridge) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _revokeRole(BRIDGE_ROLE, bridge);
        emit BridgeRemoved(bridge);
    }

    /**
     * @notice Pause token transfers
     */
    function pause() external onlyRole(PAUSER_ROLE) {
        _pause();
    }

    /**
     * @notice Unpause token transfers
     */
    function unpause() external onlyRole(PAUSER_ROLE) {
        _unpause();
    }

    // ============ Internal Functions ============

    /**
     * @dev Override to add pause check
     */
    function _update(
        address from,
        address to,
        uint256 value
    ) internal virtual override whenNotPaused {
        super._update(from, to, value);
    }
}
