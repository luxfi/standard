// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.31;

import {Enum} from "./base/Enum.sol";
import {IVault} from "./interfaces/IVault.sol";
import {IGuard} from "./interfaces/IGuard.sol";

/**
 * @title Secretariat
 * @author Lux Industries Inc
 * @notice Base contract for governance modules that execute transactions through a Safe (vault)
 * @dev Renamed from GuardableModule (Zodiac) to align with UN terminology.
 *
 * The Secretariat pattern allows for flexible execution of transactions through a Safe,
 * with optional guard functionality for pre/post transaction checks.
 *
 * Key features:
 * - Execute transactions through a Safe vault
 * - Optional guard hooks for validation
 * - Support for both Call and DelegateCall operations
 * - Compatible with Gnosis Safe module system
 */
abstract contract Secretariat {
    // ======================================================================
    // EVENTS
    // ======================================================================

    event VaultSet(address indexed previousVault, address indexed newVault);
    event TargetSet(address indexed previousTarget, address indexed newTarget);
    event GuardSet(address indexed guard);

    // ======================================================================
    // STATE VARIABLES
    // ======================================================================

    /// @notice Address of the vault (Safe) that this secretariat manages
    address public vault;

    /// @notice Address of the target for transaction execution
    /// @dev In most cases, target == vault, but can differ for complex setups
    address public target;

    /// @notice Optional guard contract for pre/post transaction checks
    address public guard;

    /// @notice H-06 fix: Whether guard is immutable (cannot be changed)
    bool public guardImmutable;

    /// @notice H-06 fix: Parent DAO address that must approve guard changes
    address public parentDAO;

    // ======================================================================
    // ERRORS
    // ======================================================================

    error GuardRejected();
    error SecretariatTransactionFailed();
    error GuardIsImmutable();
    error ParentApprovalRequired();

    // ======================================================================
    // MODIFIERS
    // ======================================================================

    modifier onlyVault() {
        require(msg.sender == vault, "Secretariat: caller is not the vault");
        _;
    }

    // ======================================================================
    // EXTERNAL FUNCTIONS
    // ======================================================================

    /**
     * @notice Sets the vault (Safe) address for this secretariat
     * @param vault_ The address of the vault/Safe
     * @dev Can only be called by the current vault
     */
    function setVault(address vault_) external onlyVault {
        address previousVault = vault;
        vault = vault_;
        emit VaultSet(previousVault, vault_);
    }

    /**
     * @notice Sets the target address for transactions
     * @param target_ The target address
     * @dev Can only be called by the vault
     */
    function setTarget(address target_) external onlyVault {
        address previousTarget = target;
        target = target_;
        emit TargetSet(previousTarget, target_);
    }

    /**
     * @notice Sets an optional guard contract
     * @param guard_ The guard address (or address(0) to disable)
     * @dev H-06 fix: Can only be called by vault, respects immutability and parent approval
     */
    function setGuard(address guard_) external onlyVault {
        // H-06 fix: Check if guard is immutable
        if (guardImmutable) revert GuardIsImmutable();

        // H-06 fix: If parent DAO is set and trying to remove guard, require parent approval
        if (parentDAO != address(0) && guard_ == address(0) && guard != address(0)) {
            revert ParentApprovalRequired();
        }

        guard = guard_;
        emit GuardSet(guard_);
    }

    /**
     * @notice H-06 fix: Set the guard as immutable (cannot be changed after)
     * @dev Can only be called by the vault, one-way operation
     */
    function setGuardImmutable() external onlyVault {
        guardImmutable = true;
    }

    /**
     * @notice H-06 fix: Set the parent DAO that must approve guard removal
     * @param parentDAO_ The parent DAO address
     * @dev Can only be called by the vault
     */
    function setParentDAO(address parentDAO_) external onlyVault {
        parentDAO = parentDAO_;
    }

    /**
     * @notice H-06 fix: Remove guard with parent approval
     * @dev Can only be called by the parent DAO
     */
    function removeGuardWithParentApproval() external {
        if (msg.sender != parentDAO) revert ParentApprovalRequired();
        if (guardImmutable) revert GuardIsImmutable();
        guard = address(0);
        emit GuardSet(address(0));
    }

    /**
     * @notice Returns the current guard address
     * @return The guard address (or address(0) if none)
     */
    function getGuard() external view returns (address) {
        return guard;
    }

    // ======================================================================
    // INTERNAL FUNCTIONS
    // ======================================================================

    /**
     * @notice Executes a transaction through the vault
     * @param to Destination address
     * @param value Ether value
     * @param data Transaction data
     * @param operation Call or DelegateCall
     * @return success True if succeeded
     * @dev Handles guard checks and transaction execution
     */
    function exec(
        address to,
        uint256 value,
        bytes memory data,
        Enum.Operation operation
    ) internal virtual returns (bool success) {
        // Pre-transaction guard check
        if (guard != address(0)) {
            IGuard(guard).checkTransaction(
                to,
                value,
                data,
                operation,
                0, // safeTxGas
                0, // baseGas
                0, // gasPrice
                address(0), // gasToken
                payable(address(0)), // refundReceiver
                "", // signatures
                msg.sender
            );
        }

        // Execute transaction through vault
        success = IVault(target).execTransactionFromModule(
            to,
            value,
            data,
            operation
        );

        // Post-transaction guard check
        if (guard != address(0)) {
            IGuard(guard).checkAfterExecution(bytes32(0), success);
        }

        return success;
    }

    /**
     * @notice Alternative initialization following module pattern
     * @param initializeParams ABI encoded initialization parameters
     * @dev Must be implemented by inheriting contracts
     */
    function setUp(bytes memory initializeParams) public virtual;
}
