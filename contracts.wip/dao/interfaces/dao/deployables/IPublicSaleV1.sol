// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.28;

/**
 * @title IPublicSaleV1
 * @notice Interface for a public token sale contract with KYC verification
 * @dev Implements a time-based token sale with configurable parameters including:
 * - Sale duration with start and end timestamps
 * - Minimum and maximum commitment amounts per user
 * - Minimum and maximum total commitment amounts for the sale
 * - KYC verification requirement
 * - Configurable fees for decreasing commitments and protocol
 * - Support for both native assets (ETH) and ERC20 tokens as payment
 */
interface IPublicSaleV1 {
    // --- Errors ---

    /**
     * @notice Thrown when the sale start timestamp is in the past during initialization
     */
    error InvalidSaleStartTimestamp();

    /**
     * @notice Thrown when the sale end timestamp is not after the start timestamp
     */
    error InvalidSaleTimestamps();

    /**
     * @notice Thrown when minimum commitment exceeds maximum commitment
     */
    error InvalidCommitmentAmounts();

    /**
     * @notice Thrown when minimum total commitment exceeds maximum total commitment
     */
    error InvalidTotalCommitmentAmounts();

    /**
     * @notice Thrown when a token or native asset transfer fails
     */
    error TransferFailed();

    /**
     * @notice Thrown when attempting to commit during inactive sale period
     */
    error SaleNotActive();

    /**
     * @notice Thrown when attempting to settle before the sale has ended
     */
    error SaleNotEnded();

    /**
     * @notice Thrown when attempting to settle an already settled account
     */
    error AlreadySettled();

    /**
     * @notice Thrown when decrease amount exceeds user's current commitment
     */
    error DecreaseAmountExceedsCommitment();

    /**
     * @notice Thrown when remaining commitment would be below minimum (unless going to zero)
     */
    error MinimumCommitment();

    /**
     * @notice Thrown when commitment would exceed maximum per user
     */
    error MaximumCommitment();

    /**
     * @notice Thrown when total commitments would exceed maximum for the sale
     */
    error MaximumTotalCommitment();

    /**
     * @notice Thrown when an amount parameter is zero
     */
    error ZeroAmount();

    /**
     * @notice Thrown when decrease commitment fee exceeds 100% (PRECISION)
     */
    error InvalidDecreaseCommitmentFee();

    /**
     * @notice Thrown when user attempts to settle with zero commitment
     */
    error ZeroCommitment();

    /**
     * @notice Thrown when protocol fee exceeds 100% (PRECISION)
     */
    error InvalidProtocolFee();

    /**
     * @notice Thrown when using wrong commitment function for the token type
     */
    error InvalidCommitmentToken();

    // --- Structs ---

    /**
     * @notice Parameters for initializing the public sale contract
     * @param saleStartTimestamp Unix timestamp when the sale begins
     * @param saleEndTimestamp Unix timestamp when the sale ends
     * @param owner Address that will own the contract and can call ownerSettle
     * @param saleTokenHolder Address holding the sale tokens to be distributed
     * @param commitmentToken Address of the token users commit (use NATIVE_ASSET constant for ETH)
     * @param saleToken Address of the token being sold
     * @param kycVerifier Address of the KYC verification contract
     * @param saleProceedsReceiver Address that receives sale proceeds
     * @param protocolFeeReceiver Address that receives protocol fees
     * @param minimumCommitment Minimum commitment amount per user
     * @param maximumCommitment Maximum commitment amount per user
     * @param minimumTotalCommitment Minimum total commitments for successful sale
     * @param maximumTotalCommitment Maximum total commitments allowed
     * @param saleTokenPrice Price per sale token in commitment token units (with PRECISION decimals)
     * @param decreaseCommitmentFee Fee percentage for decreasing commitment (with PRECISION decimals)
     * @param protocolFee Fee percentage taken from proceeds (with PRECISION decimals)
     */
    struct InitializerParams {
        uint48 saleStartTimestamp;
        uint48 saleEndTimestamp;
        address owner;
        address saleTokenHolder;
        address commitmentToken;
        address saleToken;
        address kycVerifier;
        address saleProceedsReceiver;
        address protocolFeeReceiver;
        uint256 minimumCommitment;
        uint256 maximumCommitment;
        uint256 minimumTotalCommitment;
        uint256 maximumTotalCommitment;
        uint256 saleTokenPrice;
        uint256 decreaseCommitmentFee;
        uint256 protocolFee;
    }

    // --- Enums ---

    /**
     * @notice Represents the current state of the sale
     * @dev NOT_STARTED: Before saleStartTimestamp
     * @dev ACTIVE: Between start and end timestamps with capacity remaining
     * @dev SUCCEEDED: Reached maximum total commitment OR (sale ended AND reached minimum total commitment)
     * @dev FAILED: Ended without reaching minimum commitment
     */
    enum SaleState {
        NOT_STARTED,
        ACTIVE,
        SUCCEEDED,
        FAILED
    }

    // --- Events ---

    /**
     * @notice Emitted when a user increases their commitment
     * @param account Address of the user
     * @param amount Amount of commitment increase
     */
    event CommitmentIncreased(address indexed account, uint256 amount);

    /**
     * @notice Emitted when a user decreases their commitment
     * @param account Address of the user
     * @param amount Amount of commitment decrease (before fees)
     */
    event CommitmentDecreased(address indexed account, uint256 amount);

    /**
     * @notice Emitted when a user settles after successful sale
     * @param account Address of the user
     * @param recipient Address receiving the sale tokens
     * @param saleTokenAmount Amount of sale tokens received
     */
    event SuccessfulSaleSettled(
        address indexed account,
        address indexed recipient,
        uint256 saleTokenAmount
    );

    /**
     * @notice Emitted when a user settles after failed sale
     * @param account Address of the user
     * @param recipient Address receiving the refunded commitment
     * @param commitmentTokenAmount Amount of commitment tokens refunded
     */
    event FailedSaleSettled(
        address indexed account,
        address indexed recipient,
        uint256 commitmentTokenAmount
    );

    /**
     * @notice Emitted when owner settles after successful sale
     * @param owner Address of the contract owner
     * @param saleProceeds Amount sent to saleProceedsReceiver
     * @param protocolFee Amount sent to protocolFeeReceiver
     */
    event SuccessfulSaleOwnerSettled(
        address indexed owner,
        uint256 saleProceeds,
        uint256 protocolFee
    );

    /**
     * @notice Emitted when owner settles after failed sale
     * @param owner Address of the contract owner
     * @param saleTokenAmount Amount of sale tokens returned
     * @param decreaseCommitmentFees Amount of collected fees returned
     */
    event FailedSaleOwnerSettled(
        address indexed owner,
        uint256 saleTokenAmount,
        uint256 decreaseCommitmentFees
    );

    // --- Initializer Functions ---

    /**
     * @notice Initializes the public sale contract
     * @param params_ Initialization parameters
     */
    function initialize(InitializerParams memory params_) external;

    // --- View Functions ---

    /**
     * @notice Returns the current state of the sale
     * @return state Current sale state
     */
    function saleState() external view returns (SaleState state);

    /**
     * @notice Returns whether the owner has settled
     * @return settled True if owner has settled, false otherwise
     */
    function ownerSettled() external view returns (bool settled);

    /**
     * @notice Returns the sale start timestamp
     * @return timestamp Unix timestamp when sale starts
     */
    function saleStartTimestamp() external view returns (uint48 timestamp);

    /**
     * @notice Returns the sale end timestamp
     * @return timestamp Unix timestamp when sale ends
     */
    function saleEndTimestamp() external view returns (uint48 timestamp);

    /**
     * @notice Returns the commitment token address
     * @return token Address of the token used for commitments (or NATIVE_ASSET for ETH)
     */
    function commitmentToken() external view returns (address token);

    /**
     * @notice Returns the sale token address
     * @return token Address of the token being sold
     */
    function saleToken() external view returns (address token);

    /**
     * @notice Returns the KYC verifier address
     * @return verifier Address of the KYC verification contract
     */
    function kycVerifier() external view returns (address verifier);

    /**
     * @notice Returns the sale proceeds receiver address
     * @return receiver Address that receives sale proceeds
     */
    function saleProceedsReceiver() external view returns (address receiver);

    /**
     * @notice Returns the protocol fee receiver address
     * @return receiver Address that receives protocol fees
     */
    function protocolFeeReceiver() external view returns (address receiver);

    /**
     * @notice Returns the minimum commitment per user
     * @return amount Minimum commitment amount
     */
    function minimumCommitment() external view returns (uint256 amount);

    /**
     * @notice Returns the maximum commitment per user
     * @return amount Maximum commitment amount
     */
    function maximumCommitment() external view returns (uint256 amount);

    /**
     * @notice Returns the minimum total commitment for successful sale
     * @return amount Minimum total commitment amount
     */
    function minimumTotalCommitment() external view returns (uint256 amount);

    /**
     * @notice Returns the maximum total commitment allowed
     * @return amount Maximum total commitment amount
     */
    function maximumTotalCommitment() external view returns (uint256 amount);

    /**
     * @notice Returns the price per sale token
     * @return price Price in commitment token units (with PRECISION decimals)
     */
    function saleTokenPrice() external view returns (uint256 price);

    /**
     * @notice Returns the fee for decreasing commitment
     * @return fee Fee percentage (with PRECISION decimals)
     */
    function decreaseCommitmentFee() external view returns (uint256 fee);

    /**
     * @notice Returns the protocol fee
     * @return fee Fee percentage (with PRECISION decimals)
     */
    function protocolFee() external view returns (uint256 fee);

    /**
     * @notice Returns the total commitments in the sale
     * @return total Total commitment amount
     */
    function totalCommitments() external view returns (uint256 total);

    /**
     * @notice Returns the collected decrease commitment fees
     * @return fees Total fees collected
     */
    function collectedDecreaseCommitmentFees()
        external
        view
        returns (uint256 fees);

    /**
     * @notice Returns a user's commitment amount
     * @param account_ Address to query
     * @return amount Commitment amount
     */
    function commitments(
        address account_
    ) external view returns (uint256 amount);

    /**
     * @notice Returns whether a user has settled
     * @param account_ Address to query
     * @return hasSettled True if settled, false otherwise
     */
    function settled(address account_) external view returns (bool hasSettled);

    // --- State-Changing Functions ---

    /**
     * @notice Increases commitment using native asset (ETH)
     * @param verifyingSignature_ The verifier signature attesting to KYC status
     * @param signatureExpiration_ The expiration timestamp of the signature
     * @dev Reverts if commitment token is not NATIVE_ASSET
     */
    function increaseCommitmentNative(
        bytes calldata verifyingSignature_,
        uint48 signatureExpiration_
    ) external payable;

    /**
     * @notice Increases commitment using ERC20 tokens
     * @param increaseAmount_ Amount to increase commitment by
     * @param verifyingSignature_ The verifier signature attesting to KYC status
     * @param signatureExpiration_ The expiration timestamp of the signature
     * @dev Reverts if commitment token is NATIVE_ASSET
     */
    function increaseCommitmentERC20(
        uint256 increaseAmount_,
        bytes calldata verifyingSignature_,
        uint48 signatureExpiration_
    ) external;

    /**
     * @notice Decreases commitment and sends funds to recipient
     * @param decreaseAmount_ Amount to decrease commitment by
     * @param recipient_ Address to receive the commitment tokens
     * @dev Fee is deducted from the decrease amount
     */
    function decreaseCommitment(
        uint256 decreaseAmount_,
        address recipient_
    ) external;

    /**
     * @notice Settles user's commitment after sale ends
     * @param recipient_ Address to receive tokens (sale tokens if successful, commitment tokens if failed)
     * @dev Can only be called after sale has ended
     */
    function settle(address recipient_) external;

    /**
     * @notice Owner settles the sale proceeds and fees
     * @dev Can only be called by owner after sale has ended
     */
    function ownerSettle() external;
}
