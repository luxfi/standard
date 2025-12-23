// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.30;

/**
 * @title ICountersignV1
 * @notice Multi-party agreement system with KYC verification and weighted signatures
 * @dev This contract facilitates the creation of agreements that require multiple parties
 * to sign and execute transactions. It supports KYC verification through an external
 * verifier contract, weighted signing, and conditional transaction execution.
 *
 * Key features:
 * - Signers with configurable weights and required status
 * - KYC verification for all signers through external verifier
 * - Two-phase process: signing period followed by execution period
 * - Pre-execution transactions that run before signer transactions
 * - Per-signer transaction bundles executed upon signature
 * - Minimum weight threshold for agreement validity
 *
 * Workflow:
 * 1. Contract is initialized with signers, deadlines, and transaction details
 * 2. Signers call sign() during the signing period (KYC verification required)
 * 3. After signing deadline, if minimum weight is met, execute() can be called
 * 4. Execute runs pre-execution transactions, then all signer transactions
 *
 * Use cases:
 * - Legal agreements requiring multiple party consent
 * - Investment rounds with multiple investors
 * - Multi-party business agreements with conditional execution
 * - DAO formation with initial member agreements
 */
interface ICountersignV1 {
    // --- Errors ---

    /** @notice Thrown when a non-signer attempts to sign */
    error InvalidSigner();

    /** @notice Thrown when attempting to sign after the signing deadline */
    error SigningDeadlineElapsed();

    /** @notice Thrown when attempting to execute after the execution deadline */
    error ExecutionDeadlineElapsed();

    /** @notice Thrown when a signer attempts to sign more than once */
    error SignerAlreadySigned();

    /** @notice Thrown when executing without all required signers having signed */
    error RequiredSignerNotSigned(address signer);

    /** @notice Thrown when a required signer's transaction bundle fails during execution */
    error RequiredSignerTxFailed(address signer);

    /** @notice Thrown when the total weight of signatures doesn't meet the minimum threshold */
    error MinimumWeightNotMet();

    /** @notice Thrown when attempting to execute before the signing deadline has passed */
    error SigningDeadlineNotElapsed();

    /** @notice Thrown when pre-execution transactions fail during execution */
    error PreExecutionTxFailed();

    // --- Structs ---

    /**
     * @notice Initialization parameters for a signer
     * @param account The address of the signer
     * @param required Whether this signer must sign for the agreement to be valid
     * @param weight The signing weight of this signer (contributes to minimum threshold)
     * @param transactions Encoded transaction data to execute when this signer signs
     */
    struct SignerInitialization {
        address account;
        bool required;
        uint256 weight;
        bytes transactions;
    }

    /**
     * @notice Complete state information for a signer
     * @param isSigner Whether this address is a valid signer
     * @param required Whether this signer must sign for execution to proceed
     * @param signed Whether this signer has signed the agreement
     * @param executed Whether this signer's transactions have been executed
     * @param signedTimestamp The timestamp when this signer signed (0 if not signed)
     * @param weight The signing weight of this signer
     * @param transactions The encoded transactions to execute for this signer
     */
    struct Signer {
        bool isSigner;
        bool required;
        bool signed;
        bool executed;
        uint48 signedTimestamp;
        uint256 weight;
        bytes transactions;
    }

    // --- Events ---

    /**
     * @notice Emitted when a signer successfully signs the agreement
     * @param signer The address of the signer
     */
    event Signed(address indexed signer);

    /**
     * @notice Emitted when a signer's transaction bundle is successfully executed
     * @param signer The address of the signer whose transactions were executed
     */
    event SignerTxExecuted(address indexed signer);

    /**
     * @notice Emitted when a signer's transaction bundle fails during execution
     * @dev Non-required signer transaction failures are logged but don't revert execution
     * @param signer The address of the signer whose transactions failed
     */
    event SignerTxFailed(address indexed signer);

    // --- Initializer Functions ---

    /**
     * @notice Initializes the countersign agreement with all parameters
     * @dev Can only be called once during deployment. Sets up the complete agreement structure.
     * @param owner_ The address with owner privileges (can be a Safe or EOA)
     * @param agreementUri_ IPFS URI or other link to the agreement document
     * @param verificationContract_ Address of the KYC verifier contract
     * @param signingDeadline_ Timestamp after which no more signatures are accepted
     * @param executionDeadline_ Timestamp after which execution is no longer allowed
     * @param multisend_ Address of the Gnosis MultiSend contract for batch transactions
     * @param minWeight_ Minimum total weight required from signers for valid execution
     * @param preExecutionTransactions_ Encoded transactions to execute before signer transactions
     * @param signerInitializations_ Array of signer configurations including their transactions
     */
    function initialize(
        address owner_,
        string memory agreementUri_,
        address verificationContract_,
        uint48 signingDeadline_,
        uint48 executionDeadline_,
        address multisend_,
        uint256 minWeight_,
        bytes memory preExecutionTransactions_,
        SignerInitialization[] memory signerInitializations_
    ) external;

    // --- View Functions ---

    /**
     * @notice Returns whether the initial execution has been completed
     * @dev True after execute() has been successfully called
     * @return isComplete Whether execution is complete
     */
    function initialExecutionComplete() external view returns (bool isComplete);

    /**
     * @notice Returns the URI of the agreement document
     * @dev Typically an IPFS hash or URL to the legal agreement
     * @return agreementUri The agreement document URI
     */
    function agreementUri() external view returns (string memory agreementUri);

    /**
     * @notice Returns the address of the KYC verifier contract
     * @dev This contract validates signer signatures against KYC requirements
     * @return kycVerifier The KYC verifier contract address
     */
    function kycVerifier() external view returns (address kycVerifier);

    /**
     * @notice Returns the deadline for signers to sign the agreement
     * @dev After this timestamp, sign() will revert
     * @return signingDeadline The signing deadline timestamp
     */
    function signingDeadline() external view returns (uint48 signingDeadline);

    /**
     * @notice Returns the deadline for executing the agreement
     * @dev After this timestamp, execute() will revert
     * @return executionDeadline The execution deadline timestamp
     */
    function executionDeadline()
        external
        view
        returns (uint48 executionDeadline);

    /**
     * @notice Returns the address of the MultiSend contract used for batch execution
     * @dev Used to execute multiple transactions in a single call
     * @return multisend The MultiSend contract address
     */
    function multisend() external view returns (address multisend);

    /**
     * @notice Returns the minimum weight required for agreement execution
     * @dev Sum of signer weights must meet or exceed this threshold
     * @return minWeight The minimum weight threshold
     */
    function minWeight() external view returns (uint256 minWeight);

    /**
     * @notice Returns an array of all signer addresses
     * @dev Includes both required and optional signers
     * @return signerAddresses Array of signer addresses
     */
    function signerAddresses()
        external
        view
        returns (address[] memory signerAddresses);

    /**
     * @notice Returns complete data for a specific signer
     * @param signer_ The address to query
     * @return isSigner Whether this address is a valid signer
     * @return required Whether this signer is required for execution
     * @return signed Whether this signer has signed
     * @return executed Whether this signer's transactions have been executed
     * @return signedTimestamp When this signer signed (0 if not signed)
     * @return weight This signer's signing weight
     * @return transactions This signer's transaction data
     */
    function signerData(
        address signer_
    )
        external
        view
        returns (
            bool isSigner,
            bool required,
            bool signed,
            bool executed,
            uint48 signedTimestamp,
            uint256 weight,
            bytes memory transactions
        );

    /**
     * @notice Returns the pre-execution transaction data
     * @dev These transactions are executed before any signer transactions
     * @return preExecutionTransactions Encoded transaction data for pre-execution
     */
    function preExecutionTransactions()
        external
        view
        returns (bytes memory preExecutionTransactions);

    // --- State-Changing Functions ---

    /**
     * @notice Allows a valid signer to sign the agreement
     * @dev Caller must be in the signers list and pass KYC verification.
     * Can only be called during the signing period (before signingDeadline).
     * Each signer can only sign once.
     * @param verifyingSignature_ The verifier signature attesting to KYC status
     * @param signatureExpiration_ The expiration timestamp of the signature
     * @custom:throws InvalidSigner if caller is not a valid signer
     * @custom:throws SigningDeadlineElapsed if past the signing deadline
     * @custom:throws SignerAlreadySigned if caller has already signed
     * @custom:throws KYCVerificationFailed if KYC verification fails
     * @custom:emits Signed when signature is recorded
     */
    function sign(
        bytes calldata verifyingSignature_,
        uint48 signatureExpiration_
    ) external;

    /**
     * @notice Executes the agreement after signing period ends
     * @dev Can be called by anyone after signing deadline has passed.
     * Validates that all required signers have signed and minimum weight is met.
     * Executes pre-execution transactions first, then all signer transactions.
     * Can only be executed once and must be before execution deadline.
     * @custom:throws SigningDeadlineNotElapsed if called during signing period
     * @custom:throws ExecutionDeadlineElapsed if past execution deadline
     * @custom:throws RequiredSignerNotSigned if a required signer hasn't signed
     * @custom:throws MinimumWeightNotMet if total weight is below threshold
     * @custom:throws PreExecutionTxFailed if pre-execution transactions fail
     * @custom:throws RequiredSignerTxFailed if a required signer's transactions fail
     * @custom:emits SignerTxExecuted for each successful signer transaction bundle
     * @custom:emits SignerTxFailed for each failed non-required signer transaction bundle
     */
    function execute() external;
}
