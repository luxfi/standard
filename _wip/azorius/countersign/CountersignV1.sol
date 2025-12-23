// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.30;

import {
    IKYCVerifierV1
} from "../../interfaces/dao/services/IKYCVerifierV1.sol";
import {IVersion} from "../../interfaces/dao/deployables/IVersion.sol";
import {
    ICountersignV1
} from "../../interfaces/dao/deployables/ICountersignV1.sol";
import {IDeploymentBlock} from "../../interfaces/dao/IDeploymentBlock.sol";
import {IMultisend} from "../../interfaces/safe/IMultiSend.sol";
import {
    DeploymentBlockInitializable
} from "../../DeploymentBlockInitializable.sol";
import {InitializerEventEmitter} from "../../InitializerEventEmitter.sol";
import {ERC165} from "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import {
    Ownable2StepUpgradeable
} from "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";

/**
 * @title CountersignV1
 * @author Lux Industriesn Inc
 * @notice Implementation of multi-party agreement system with KYC verification
 * @dev This contract implements ICountersignV1, facilitating agreements that require
 * multiple parties to sign and execute conditional transactions.
 *
 * Implementation details:
 * - Uses EIP-7201 namespaced storage pattern for upgradeability safety
 * - Integrates with external KYC verifier for compliance
 * - Supports weighted voting with configurable thresholds
 * - Two-phase execution: initial execution and follow-up executions
 * - Uses delegatecall to MultiSend for transaction execution
 * - Tracks signing and execution status per signer
 *
 * Agreement lifecycle:
 * 1. Initialize with signers, weights, deadlines, and transactions
 * 2. Signers sign during signing period (KYC verification required)
 * 3. After signing deadline, execute if minimum weight met
 * 4. Initial execution runs pre-execution and all signed signer transactions
 * 5. Follow-up executions can retry failed non-required signer transactions
 *
 * Security model:
 * - Required signers must all sign and execute successfully
 * - Non-required signers can fail without blocking execution
 * - KYC verification prevents unauthorized signatures
 * - Time-bounded signing and execution periods
 * - Owner-only execution after signing period
 *
 * @custom:security-contact security@lux.network
 */
contract CountersignV1 is
    ICountersignV1,
    IVersion,
    DeploymentBlockInitializable,
    InitializerEventEmitter,
    ERC165,
    Ownable2StepUpgradeable
{
    // ======================================================================
    // STATE VARIABLES
    // ======================================================================

    /**
     * @notice Main storage struct for CountersignV1 following EIP-7201
     * @dev Contains all agreement configuration and signer state
     * @custom:storage-location erc7201:DAO.Countersign.main
     */
    struct CountersignStorage {
        /** @notice Whether the initial execution has been completed */
        bool initialExecutionComplete;
        /** @notice URI pointing to the agreement document (e.g., IPFS hash) */
        string agreementUri;
        /** @notice Address of the KYC verifier contract for signature validation */
        address kycVerifier;
        /** @notice Timestamp after which no more signatures are accepted */
        uint48 signingDeadline;
        /** @notice Timestamp after which execution is no longer allowed */
        uint48 executionDeadline;
        /** @notice Address of the MultiSend contract for batch transaction execution */
        address multisend;
        /** @notice Minimum total weight required from signers for valid execution */
        uint256 minWeight;
        /** @notice Array of all signer addresses (both required and optional) */
        address[] signerAddresses;
        /** @notice Maps signer addresses to their complete data including status and transactions */
        mapping(address signer => Signer signerData) signerData;
        /** @notice Encoded transactions to execute before any signer transactions */
        bytes preExecutionTransactions;
    }

    /**
     * @dev Storage slot for CountersignStorage calculated using EIP-7201 formula:
     * keccak256(abi.encode(uint256(keccak256("DAO.Countersign.main")) - 1)) & ~bytes32(uint256(0xff))
     */
    bytes32 internal constant COUNTERSIGN_STORAGE_LOCATION =
        0x17e3324905ecbcdb5282616f8444afa635592330380c984274eec8eac2a85400;

    /**
     * @dev Returns the storage struct for CountersignV1
     * Following the EIP-7201 namespaced storage pattern to avoid storage collisions
     * @return $ The storage struct for CountersignV1
     */
    function _getCountersignStorage()
        internal
        pure
        returns (CountersignStorage storage $)
    {
        // solhint-disable-next-line no-inline-assembly
        assembly {
            $.slot := COUNTERSIGN_STORAGE_LOCATION
        }
    }

    // ======================================================================
    // CONSTRUCTOR & INITIALIZERS
    // ======================================================================

    constructor() {
        _disableInitializers();
    }

    /**
     * @inheritdoc ICountersignV1
     * @dev Sets up the complete agreement structure including:
     * - Agreement parameters and deadlines
     * - KYC verifier and MultiSend references
     * - Pre-execution transactions
     * - All signer configurations with their weights and transactions
     * Execution deadline must be after signing deadline.
     */
    function initialize(
        address owner_,
        string memory agreementUri_,
        address kycVerifier_,
        uint48 signingDeadline_,
        uint48 executionDeadline_,
        address multisend_,
        uint256 minWeight_,
        bytes memory preExecutionTransactions_,
        SignerInitialization[] memory signerInitializations_
    ) public virtual override initializer {
        __InitializerEventEmitter_init(
            abi.encode(
                owner_,
                agreementUri_,
                kycVerifier_,
                signingDeadline_,
                executionDeadline_,
                multisend_,
                minWeight_,
                preExecutionTransactions_,
                signerInitializations_
            )
        );
        __Ownable_init(owner_);
        __DeploymentBlockInitializable_init();

        CountersignStorage storage $ = _getCountersignStorage();
        $.agreementUri = agreementUri_;
        $.kycVerifier = kycVerifier_;
        $.signingDeadline = signingDeadline_;
        $.executionDeadline = executionDeadline_;
        $.multisend = multisend_;
        $.minWeight = minWeight_;
        $.preExecutionTransactions = preExecutionTransactions_;

        // Initialize all signers with their configuration
        for (uint256 i = 0; i < signerInitializations_.length; ) {
            SignerInitialization memory signerInit = signerInitializations_[i];

            // Add to signers array for iteration
            $.signerAddresses.push(signerInit.account);

            // Configure signer data
            Signer storage signer = $.signerData[signerInit.account];
            signer.isSigner = true;
            signer.required = signerInit.required;
            signer.weight = signerInit.weight;
            signer.transactions = signerInit.transactions;

            unchecked {
                ++i;
            }
        }
    }

    // ======================================================================
    // ICountersignV1
    // ======================================================================

    // --- View Functions ---

    /**
     * @inheritdoc ICountersignV1
     */
    function initialExecutionComplete()
        public
        view
        virtual
        override
        returns (bool)
    {
        CountersignStorage storage $ = _getCountersignStorage();
        return $.initialExecutionComplete;
    }

    /**
     * @inheritdoc ICountersignV1
     */
    function agreementUri()
        public
        view
        virtual
        override
        returns (string memory)
    {
        CountersignStorage storage $ = _getCountersignStorage();
        return $.agreementUri;
    }

    /**
     * @inheritdoc ICountersignV1
     */
    function kycVerifier() public view virtual override returns (address) {
        CountersignStorage storage $ = _getCountersignStorage();
        return $.kycVerifier;
    }

    /**
     * @inheritdoc ICountersignV1
     */
    function signingDeadline() public view virtual override returns (uint48) {
        CountersignStorage storage $ = _getCountersignStorage();
        return $.signingDeadline;
    }

    /**
     * @inheritdoc ICountersignV1
     */
    function executionDeadline() public view virtual override returns (uint48) {
        CountersignStorage storage $ = _getCountersignStorage();
        return $.executionDeadline;
    }

    /**
     * @inheritdoc ICountersignV1
     */
    function multisend() public view virtual override returns (address) {
        CountersignStorage storage $ = _getCountersignStorage();
        return $.multisend;
    }

    /**
     * @inheritdoc ICountersignV1
     */
    function minWeight() public view virtual override returns (uint256) {
        CountersignStorage storage $ = _getCountersignStorage();
        return $.minWeight;
    }

    /**
     * @inheritdoc ICountersignV1
     */
    function signerAddresses()
        public
        view
        virtual
        override
        returns (address[] memory)
    {
        CountersignStorage storage $ = _getCountersignStorage();
        return $.signerAddresses;
    }

    /**
     * @inheritdoc ICountersignV1
     */
    function signerData(
        address signer_
    )
        public
        view
        override
        returns (bool, bool, bool, bool, uint48, uint256, bytes memory)
    {
        CountersignStorage storage $ = _getCountersignStorage();
        Signer storage signer = $.signerData[signer_];

        return (
            signer.isSigner,
            signer.required,
            signer.signed,
            signer.executed,
            signer.signedTimestamp,
            signer.weight,
            signer.transactions
        );
    }

    /**
     * @inheritdoc ICountersignV1
     */
    function preExecutionTransactions()
        public
        view
        virtual
        override
        returns (bytes memory)
    {
        CountersignStorage storage $ = _getCountersignStorage();
        return $.preExecutionTransactions;
    }

    // --- State-Changing Functions ---

    /**
     * @inheritdoc ICountersignV1
     * @dev Validates signer eligibility and KYC status before recording signature.
     * Updates signer state and timestamp upon successful signature.
     */
    function sign(
        bytes calldata verifyingSignature_,
        uint48 signatureExpiration_
    ) public virtual override {
        CountersignStorage storage $ = _getCountersignStorage();

        // Check 1: Ensure we're within the signing period
        if (block.timestamp > $.signingDeadline) {
            revert SigningDeadlineElapsed();
        }

        Signer storage signer = $.signerData[msg.sender];

        // Check 2: Verify caller is a valid signer
        if (!signer.isSigner) {
            revert InvalidSigner();
        }

        // Check 3: Prevent double signing
        if (signer.signed) {
            revert SignerAlreadySigned();
        }

        // Check 4: Verify KYC status through external verifier
        IKYCVerifierV1($.kycVerifier).verify(
            msg.sender,
            signatureExpiration_,
            verifyingSignature_
        );

        // Record signature
        signer.signed = true;
        signer.signedTimestamp = uint48(block.timestamp);

        // Emit event for transparency
        emit Signed(msg.sender);
    }

    /**
     * @inheritdoc ICountersignV1
     * @dev Executes the agreement after validating timing constraints.
     * Initial execution runs pre-execution transactions and all signer transactions.
     * Follow-up executions retry failed non-required signer transactions.
     * Only the owner can trigger execution to ensure proper authorization.
     */
    function execute() public virtual override onlyOwner {
        CountersignStorage storage $ = _getCountersignStorage();

        // Check 1: Ensure signing period has ended
        if (block.timestamp < $.signingDeadline) {
            revert SigningDeadlineNotElapsed();
        }

        // Check 2: Ensure we're within execution window
        if (block.timestamp > $.executionDeadline) {
            revert ExecutionDeadlineElapsed();
        }

        // Execute based on current state
        if (!$.initialExecutionComplete) {
            // First execution: validate requirements and execute all transactions
            _initialExecution($);
        } else {
            // Follow-up executions: retry failed non-required signer transactions
            _followUpExecutions($);
        }
    }

    // ======================================================================
    // IVersion
    // ======================================================================

    // --- Pure Functions ---

    /**
     * @inheritdoc IVersion
     */
    function version() public pure virtual override returns (uint16) {
        return 1;
    }

    // ======================================================================
    // ERC165
    // ======================================================================

    // --- View Functions ---

    /**
     * @inheritdoc ERC165
     * @dev Supports ICountersignV1, IVersion, IDeploymentBlock, and IERC165
     */
    function supportsInterface(
        bytes4 interfaceId_
    ) public view virtual override returns (bool) {
        return
            interfaceId_ == type(ICountersignV1).interfaceId ||
            interfaceId_ == type(IVersion).interfaceId ||
            interfaceId_ == type(IDeploymentBlock).interfaceId ||
            super.supportsInterface(interfaceId_);
    }

    // ======================================================================
    // INTERNAL HELPERS
    // ======================================================================

    /**
     * @notice Handles the initial execution of the agreement
     * @dev Executes pre-execution transactions first, then processes all signer transactions.
     * Validates that all required signers have signed and minimum weight is met.
     * @param $ Storage pointer to avoid repeated SLOAD operations
     * @custom:throws PreExecutionTxFailed if pre-execution transactions fail
     * @custom:throws RequiredSignerNotSigned if a required signer hasn't signed
     * @custom:throws RequiredSignerTxFailed if a required signer's transactions fail
     * @custom:throws MinimumWeightNotMet if total executed weight is below threshold
     */
    function _initialExecution(CountersignStorage storage $) internal {
        // Step 1: Execute pre-execution transactions if any
        if ($.preExecutionTransactions.length > 0) {
            // solhint-disable-next-line avoid-low-level-calls
            (bool success, ) = $.multisend.delegatecall(
                abi.encodeCall(IMultisend.multiSend, $.preExecutionTransactions)
            );

            if (!success) {
                revert PreExecutionTxFailed();
            }
        }

        uint256 executedWeight;

        // Step 2: Process all signers
        for (uint256 i = 0; i < $.signerAddresses.length; ) {
            address signerAddress = $.signerAddresses[i];
            Signer storage signer = $.signerData[signerAddress];

            // Check if signer has signed
            if (!signer.signed) {
                // Required signers must sign
                if (signer.required)
                    revert RequiredSignerNotSigned(signerAddress);

                unchecked {
                    ++i;
                }
                continue;
            }

            // Execute signer's transactions if any
            if (signer.transactions.length > 0) {
                // solhint-disable-next-line avoid-low-level-calls
                (bool success, ) = $.multisend.delegatecall(
                    abi.encodeCall(IMultisend.multiSend, signer.transactions)
                );

                if (success) {
                    // Mark as executed and accumulate weight
                    signer.executed = true;
                    executedWeight += signer.weight;
                    emit SignerTxExecuted(signerAddress);
                } else {
                    // Required signer transactions must succeed
                    if (signer.required) {
                        revert RequiredSignerTxFailed(signerAddress);
                    } else {
                        // Non-required failures are logged but don't revert
                        emit SignerTxFailed(signerAddress);
                    }
                }
            }

            unchecked {
                ++i;
            }
        }

        // Step 3: Validate minimum weight requirement
        if (executedWeight < $.minWeight) {
            revert MinimumWeightNotMet();
        }

        // Mark initial execution as complete
        $.initialExecutionComplete = true;
    }

    /**
     * @notice Handles follow-up executions after initial execution
     * @dev Attempts to execute transactions for signers who signed but whose
     * transactions failed during initial execution. Only processes non-required
     * signers as required signer failures would have reverted initial execution.
     * @param $ Storage pointer to avoid repeated SLOAD operations
     */
    function _followUpExecutions(CountersignStorage storage $) internal {
        // Process all signers looking for unexecuted transactions
        for (uint256 i = 0; i < $.signerAddresses.length; ) {
            address signerAddress = $.signerAddresses[i];
            Signer storage signer = $.signerData[signerAddress];

            // Skip if:
            // - Signer didn't sign
            // - Already executed successfully
            // - No transactions to execute
            if (
                !signer.signed ||
                signer.executed ||
                signer.transactions.length == 0
            ) {
                unchecked {
                    ++i;
                }
                continue;
            }

            // Attempt to execute signer's transactions
            // solhint-disable-next-line avoid-low-level-calls
            (bool success, ) = $.multisend.delegatecall(
                abi.encodeCall(IMultisend.multiSend, signer.transactions)
            );

            if (success) {
                // Mark as executed on success
                signer.executed = true;
                emit SignerTxExecuted(signerAddress);
            } else {
                // Log failure (no revert for follow-up executions)
                emit SignerTxFailed(signerAddress);
            }

            unchecked {
                ++i;
            }
        }
    }
}
