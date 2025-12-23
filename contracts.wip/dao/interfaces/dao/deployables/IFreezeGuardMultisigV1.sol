// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.28;

import {Enum} from "@safe-global/safe-smart-account/interfaces/Enum.sol";
import {IFreezeGuardBaseV1} from "./IFreezeGuardBaseV1.sol";

/**
 * @title IFreezeGuardMultisigV1
 * @notice Freeze guard implementation for standard multisig Safe child DAOs with timelock functionality
 * @dev This guard variant is designed for child DAOs that operate as standard multisig Safes
 * without Azorius governance. It attaches directly to the Safe as a transaction guard.
 * In addition to freeze checking, it implements a timelock mechanism where transactions must
 * be timelocked before execution, providing a window for freeze votes to occur.
 *
 * Key features:
 * - Enforces timelock period before transaction execution
 * - Provides execution window after timelock expires
 * - Integrates with parent's freeze voting mechanism
 * - Prevents execution if DAO becomes frozen during timelock
 *
 * Transaction flow:
 * 1. Signers create and sign a transaction
 * 2. Transaction must be timelocked (registered) before execution
 * 3. After timelock period, transaction can execute within execution window
 * 4. Parent can freeze during timelock to prevent execution
 *
 * Security benefits:
 * - Gives parent DAO time to review and potentially freeze
 * - Prevents rushed or malicious transactions
 * - Maintains multisig autonomy while enabling parent oversight
 */
interface IFreezeGuardMultisigV1 is IFreezeGuardBaseV1 {
    // --- Errors ---

    /** @notice Thrown when attempting to timelock a transaction that's already timelocked */
    error AlreadyTimelocked();

    /** @notice Thrown when attempting to execute a transaction that hasn't been timelocked */
    error NotTimelocked();

    /** @notice Thrown when attempting to execute a transaction still in timelock period */
    error Timelocked();

    /** @notice Thrown when attempting to execute a transaction after execution period expired */
    error Expired();

    /** @notice Thrown when attempting to execute a transaction that was timelocked before the most recent freeze */
    error TimelockedBeforeFreeze();

    // --- Events ---

    /**
     * @notice Emitted when a transaction is successfully timelocked
     * @param timelocker The address that initiated the timelock
     * @param transactionHash The hash of the timelocked transaction
     * @param signatures The signatures authorizing the transaction
     */
    event TransactionTimelocked(
        address indexed timelocker,
        bytes32 indexed transactionHash,
        bytes indexed signatures
    );

    /**
     * @notice Emitted when the timelock period is updated
     * @param timelockPeriod The new timelock period in seconds
     */
    event TimelockPeriodUpdated(uint32 timelockPeriod);

    /**
     * @notice Emitted when the execution period is updated
     * @param executionPeriod The new execution period in seconds
     */
    event ExecutionPeriodUpdated(uint32 executionPeriod);

    // --- Initializer Functions ---

    /**
     * @notice Initializes the freeze guard with timelock parameters and references
     * @param timelockPeriod_ Duration in seconds that transactions must wait before execution
     * @param executionPeriod_ Duration in seconds after timelock during which execution is allowed
     * @param owner_ The address that can update timelock parameters
     * @param freezeVoting_ The FreezeVoting contract that determines freeze status
     * @param childGnosisSafe_ The Safe contract this guard is protecting
     */
    function initialize(
        uint32 timelockPeriod_,
        uint32 executionPeriod_,
        address owner_,
        address freezeVoting_,
        address childGnosisSafe_
    ) external;

    // --- View Functions ---

    /**
     * @notice Returns the required waiting period before timelocked transactions can execute
     * @return timelockPeriod The timelock duration in seconds
     */
    function timelockPeriod() external view returns (uint32 timelockPeriod);

    /**
     * @notice Returns the window during which timelocked transactions can be executed
     * @return executionPeriod The execution window duration in seconds
     */
    function executionPeriod() external view returns (uint32 executionPeriod);

    /**
     * @notice Returns the child Safe contract this guard is protecting
     * @return childGnosisSafe The Safe contract address
     */
    function childGnosisSafe() external view returns (address childGnosisSafe);

    /**
     * @notice Returns when a transaction was timelocked based on its signatures hash
     * @param signaturesHash_ The keccak256 hash of the transaction signatures
     * @return timelockedTimestamp The timestamp when the transaction was timelocked (0 if not timelocked)
     */
    function getTransactionTimelocked(
        bytes32 signaturesHash_
    ) external view returns (uint48 timelockedTimestamp);

    // --- State-Changing Functions ---

    /**
     * @notice Timelocks a transaction for later execution
     * @dev Must be called before the Safe can execute the transaction. All parameters must
     * match exactly when later executing through the Safe. The signatures must be valid
     * for the Safe to accept the transaction.
     * @param to_ Destination address of the transaction
     * @param value_ Amount of ETH to send
     * @param data_ Transaction data payload
     * @param operation_ Operation type (Call, DelegateCall, etc.)
     * @param safeTxGas_ Gas for the Safe transaction execution
     * @param baseGas_ Gas costs not related to the transaction execution
     * @param gasPrice_ Gas price for the transaction
     * @param gasToken_ Token used for gas payment (0x0 for ETH)
     * @param refundReceiver_ Address to receive gas refunds
     * @param signatures_ Packed signatures of Safe owners
     * @param nonce_ Safe nonce for the transaction
     * @custom:throws AlreadyTimelocked if this exact transaction is already timelocked
     * @custom:emits TransactionTimelocked with transaction details
     */
    function timelockTransaction(
        address to_,
        uint256 value_,
        bytes memory data_,
        Enum.Operation operation_,
        uint256 safeTxGas_,
        uint256 baseGas_,
        uint256 gasPrice_,
        address gasToken_,
        address payable refundReceiver_,
        bytes calldata signatures_,
        uint256 nonce_
    ) external;

    /**
     * @notice Updates the timelock period for future transactions
     * @dev Only affects transactions timelocked after this change
     * @param timelockPeriod_ The new timelock period in seconds
     * @custom:access Restricted to owner
     * @custom:emits TimelockPeriodUpdated with new period
     */
    function updateTimelockPeriod(uint32 timelockPeriod_) external;

    /**
     * @notice Updates the execution period for future transactions
     * @dev Only affects transactions timelocked after this change
     * @param executionPeriod_ The new execution period in seconds
     * @custom:access Restricted to owner
     * @custom:emits ExecutionPeriodUpdated with new period
     */
    function updateExecutionPeriod(uint32 executionPeriod_) external;
}
