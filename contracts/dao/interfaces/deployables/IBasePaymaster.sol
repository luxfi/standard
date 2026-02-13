// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.30;

import {
    IEntryPoint
} from "@account-abstraction/interfaces/IEntryPoint.sol";

/**
 * @title IBasePaymaster
 * @notice Interface for base paymaster functionality in ERC-4337
 * @dev Extends the standard paymaster with deposit and staking management.
 * This interface defines functions that are common to paymaster implementations
 * but not part of the core IPaymaster interface from the account-abstraction package.
 *
 * Key features:
 * - Deposit management for gas fee sponsorship
 * - Staking functionality for EntryPoint requirements
 * - Withdrawal mechanisms for both deposits and stakes
 *
 * Security model:
 * - Only the paymaster owner can withdraw funds or manage stakes
 * - The EntryPoint validates all operations before execution
 * - Deposits are held by the EntryPoint, not the paymaster
 */
interface IBasePaymaster {
    // --- Errors ---

    /** @notice Thrown when the provided address does not implement IEntryPoint interface */
    error InvalidEntryPointInterface();

    /** @notice Thrown when caller is not the configured EntryPoint */
    error CallerNotEntryPoint();

    /** @notice Thrown when _postOp is called but not overridden by the inheriting contract */
    error PostOpNotImplemented();

    // --- View Functions ---

    /**
     * @notice Returns the EntryPoint contract address
     * @dev The EntryPoint is the core ERC-4337 contract that handles user operations
     * @return entryPoint The EntryPoint contract instance
     */
    function entryPoint() external view returns (IEntryPoint entryPoint);

    /**
     * @notice Returns the current deposit balance for this paymaster
     * @dev Queries the EntryPoint for the paymaster's deposit balance.
     * This balance is used to pay for sponsored transactions.
     * @return depositBalance The amount of ETH deposited for gas payments
     */
    function getDeposit() external view returns (uint256 depositBalance);

    // --- State-Changing Functions ---

    /**
     * @notice Adds to the deposit balance for paying gas fees
     * @dev Deposits ETH to the EntryPoint for this paymaster to use when sponsoring operations.
     * Anyone can deposit funds, but only the owner can withdraw.
     * The deposited ETH is held by the EntryPoint contract.
     * @custom:emits No events emitted directly, but EntryPoint may emit deposit events
     */
    function deposit() external payable;

    /**
     * @notice Withdraws ETH from the deposit balance
     * @dev Only callable by the paymaster owner. Withdraws funds that were previously
     * deposited to the EntryPoint for gas sponsorship.
     * @param withdrawAddress_ The address to receive the withdrawn funds
     * @param amount_ The amount of ETH to withdraw in wei
     * @custom:access Restricted to owner
     * @custom:throws May revert if insufficient balance in EntryPoint
     */
    function withdrawTo(
        address payable withdrawAddress_,
        uint256 amount_
    ) external;

    /**
     * @notice Stakes ETH with the EntryPoint
     * @dev Only callable by the paymaster owner. Some EntryPoint implementations
     * may require paymasters to stake ETH as a security measure.
     * The stake can only be withdrawn after the unstake delay period.
     * @param unstakeDelaySec_ The minimum delay in seconds before the stake can be withdrawn
     * @custom:access Restricted to owner
     */
    function addStake(uint32 unstakeDelaySec_) external payable;

    /**
     * @notice Unlocks the stake for withdrawal
     * @dev Only callable by the paymaster owner. Initiates the unstaking process.
     * Must wait for the unstake delay period before calling withdrawStake.
     * The paymaster cannot sponsor operations while stake is unlocked.
     * @custom:access Restricted to owner
     */
    function unlockStake() external;

    /**
     * @notice Withdraws the unlocked stake
     * @dev Only callable by the paymaster owner. Can only be called after unlockStake
     * and waiting for the unstake delay period to pass.
     * @param withdrawAddress_ The address to receive the withdrawn stake
     * @custom:access Restricted to owner
     * @custom:throws May revert if stake is not unlocked or delay period hasn't passed
     */
    function withdrawStake(address payable withdrawAddress_) external;
}
