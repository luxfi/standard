// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.28;

import {Enum} from "@safe-global/safe-smart-account/interfaces/Enum.sol";
import {IAvatar} from "../interfaces/dao/IAvatar.sol";
import {IGuard} from "../interfaces/dao/IGuard.sol";

/**
 * @title GuardableModule
 * @author Lux Industriesn Inc (adapted from Gnosis Guild Zodiac)
 * @notice Base contract for modules that can execute transactions through a Safe (avatar)
 * @dev This is a local implementation that removes dependency on gnosis.pm/safe-contracts
 * and gnosis-guild/zodiac packages while maintaining the same functionality.
 * 
 * The module pattern allows for flexible execution of transactions through a Safe,
 * with optional guard functionality for pre/post transaction checks.
 */
abstract contract GuardableModule {
    // ======================================================================
    // EVENTS
    // ======================================================================

    event AvatarSet(address indexed previousAvatar, address indexed newAvatar);
    event TargetSet(address indexed previousTarget, address indexed newTarget);
    event GuardSet(address indexed guard);

    // ======================================================================
    // STATE VARIABLES
    // ======================================================================

    /// @notice Address of the avatar (Safe) that this module is attached to
    address public avatar;
    
    /// @notice Address of the target that transactions will be executed on
    /// @dev In most cases, target == avatar, but they can be different for complex setups
    address public target;
    
    /// @notice Optional guard contract that can implement pre/post transaction checks
    address public guard;

    // ======================================================================
    // ERRORS
    // ======================================================================

    error GuardRejected();
    error ModuleTransactionFailed();

    // ======================================================================
    // MODIFIERS
    // ======================================================================

    modifier onlyAvatar() {
        require(msg.sender == avatar, "GuardableModule: caller is not the avatar");
        _;
    }

    // ======================================================================
    // EXTERNAL FUNCTIONS
    // ======================================================================

    /**
     * @notice Sets the avatar (Safe) address for this module
     * @param _avatar The address of the avatar/Safe
     * @dev Can only be called by the current avatar
     */
    function setAvatar(address _avatar) external onlyAvatar {
        address previousAvatar = avatar;
        avatar = _avatar;
        emit AvatarSet(previousAvatar, _avatar);
    }

    /**
     * @notice Sets the target address for transactions
     * @param _target The address that transactions will be executed on
     * @dev Can only be called by the avatar
     */
    function setTarget(address _target) external onlyAvatar {
        address previousTarget = target;
        target = _target;
        emit TargetSet(previousTarget, _target);
    }

    /**
     * @notice Sets an optional guard contract
     * @param _guard The address of the guard contract (or address(0) to disable)
     * @dev Can only be called by the avatar
     */
    function setGuard(address _guard) external onlyAvatar {
        guard = _guard;
        emit GuardSet(_guard);
    }

    /**
     * @notice Gets the current guard address
     * @return The address of the current guard (or address(0) if no guard is set)
     */
    function getGuard() external view returns (address) {
        return guard;
    }

    // ======================================================================
    // INTERNAL FUNCTIONS
    // ======================================================================

    /**
     * @notice Executes a transaction through the avatar
     * @param to Destination address
     * @param value Ether value
     * @param data Data payload
     * @param operation Operation type (0: Call, 1: DelegateCall)
     * @return success True if the transaction succeeded
     * @dev This function handles guard checks and transaction execution
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
                // Additional parameters for guard interface
                0, // safeTxGas
                0, // baseGas
                0, // gasPrice
                address(0), // gasToken
                payable(address(0)), // refundReceiver
                "", // signatures
                msg.sender
            );
        }

        // Execute transaction through avatar
        success = IAvatar(target).execTransactionFromModule(
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
     * @notice Alternative initialization function following Zodiac pattern
     * @param initializeParams ABI encoded initialization parameters
     * @dev Must be implemented by inheriting contracts
     */
    function setUp(bytes memory initializeParams) public virtual;
}