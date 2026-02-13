// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.30;

import {
    IPublicSaleV1
} from "../../interfaces/deployables/IPublicSaleV1.sol";
import {IVersion} from "../../interfaces/deployables/IVersion.sol";
import {IDeploymentBlock} from "../../interfaces/IDeploymentBlock.sol";
import {
    IKYCVerifierV1
} from "../../interfaces/services/IKYCVerifierV1.sol";
import {
    DeploymentBlockInitializable
} from "../../DeploymentBlockInitializable.sol";
import {InitializerEventEmitter} from "../../InitializerEventEmitter.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC165} from "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import {
    Ownable2StepUpgradeable
} from "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import {
    SafeERC20
} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title PublicSaleV1
 * @notice Implementation of a public token sale with KYC verification
 * @dev Supports time-based token sales with configurable parameters
 * @custom:security-contact security@dao.org
 */
contract PublicSaleV1 is
    IPublicSaleV1,
    IVersion,
    DeploymentBlockInitializable,
    InitializerEventEmitter,
    ERC165,
    Ownable2StepUpgradeable
{
    using SafeERC20 for IERC20;

    // ======================================================================
    // STATE VARIABLES
    // ======================================================================

    /**
     * @notice Main storage struct for PublicSaleV1 following EIP-7201
     * @dev Contains all agreement configuration and signer state
     * @custom:storage-location erc7201:DAO.PublicSale.main
     */
    struct PublicSaleStorage {
        bool ownerSettled;
        uint48 saleStartTimestamp;
        uint48 saleEndTimestamp;
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
        uint256 totalCommitments;
        uint256 collectedDecreaseCommitmentFees;
        mapping(address account => uint256 commitmentAmount) commitments;
        mapping(address account => bool settled) settled;
    }

    /**
     * @dev Storage slot for PublicSaleStorage calculated using EIP-7201 formula:
     * keccak256(abi.encode(uint256(keccak256("DAO.PublicSale.main")) - 1)) & ~bytes32(uint256(0xff))
     */
    bytes32 internal constant PUBLIC_SALE_STORAGE_LOCATION =
        0x2954b43716f55c3a12eeb02cbe9a8c7ed7e82022cc9255428b4df142a8f4fa00;

    /**
     * @dev Returns the storage struct for PublicSaleV1
     * Following the EIP-7201 namespaced storage pattern to avoid storage collisions
     * @return $ The storage struct for PublicSaleV1
     */
    function _getPublicSaleStorage()
        internal
        pure
        returns (PublicSaleStorage storage $)
    {
        // solhint-disable-next-line no-inline-assembly
        assembly {
            $.slot := PUBLIC_SALE_STORAGE_LOCATION
        }
    }

    /** @notice Address used to represent native ETH */
    address internal constant NATIVE_ASSET =
        0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    /** @notice Precision for sale token price calculations (18 decimals) */
    uint256 internal constant PRECISION = 10 ** 18;

    // ======================================================================
    // MODIFIERS
    // ======================================================================

    /**
     * @notice Ensures the caller has passed KYC verification
     * @dev Calls the KYC verifier contract to check verification status
     * @param verifyingSignature_ The verifier signature attesting to KYC status
     * @param signatureExpiration_ The expiration timestamp of the signature
     */
    modifier isKYCVerified(
        bytes calldata verifyingSignature_,
        uint48 signatureExpiration_
    ) {
        PublicSaleStorage storage $ = _getPublicSaleStorage();
        IKYCVerifierV1($.kycVerifier).verify(
            msg.sender,
            signatureExpiration_,
            verifyingSignature_
        );
        _;
    }

    // ======================================================================
    // CONSTRUCTOR & INITIALIZERS
    // ======================================================================

    /**
     * @notice Disables initializers on implementation contract deployment
     * @dev Prevents the implementation contract from being initialized
     */
    constructor() {
        _disableInitializers();
    }

    /**
     * @inheritdoc IPublicSaleV1
     */
    function initialize(
        InitializerParams memory params_
    ) public virtual override initializer {
        if (params_.saleStartTimestamp > params_.saleEndTimestamp)
            revert InvalidSaleTimestamps();

        if (params_.saleStartTimestamp < block.timestamp)
            revert InvalidSaleStartTimestamp();

        if (params_.minimumCommitment > params_.maximumCommitment)
            revert InvalidCommitmentAmounts();

        if (params_.minimumTotalCommitment > params_.maximumTotalCommitment)
            revert InvalidTotalCommitmentAmounts();

        if (params_.decreaseCommitmentFee > PRECISION)
            revert InvalidDecreaseCommitmentFee();

        if (params_.protocolFee > PRECISION) revert InvalidProtocolFee();

        __InitializerEventEmitter_init(abi.encode(params_));
        __Ownable_init(params_.owner);
        __DeploymentBlockInitializable_init();

        PublicSaleStorage storage $ = _getPublicSaleStorage();

        $.saleStartTimestamp = params_.saleStartTimestamp;
        $.saleEndTimestamp = params_.saleEndTimestamp;
        $.commitmentToken = params_.commitmentToken;
        $.saleToken = params_.saleToken;
        $.kycVerifier = params_.kycVerifier;
        $.saleProceedsReceiver = params_.saleProceedsReceiver;
        $.protocolFeeReceiver = params_.protocolFeeReceiver;
        $.minimumCommitment = params_.minimumCommitment;
        $.maximumCommitment = params_.maximumCommitment;
        $.minimumTotalCommitment = params_.minimumTotalCommitment;
        $.maximumTotalCommitment = params_.maximumTotalCommitment;
        $.saleTokenPrice = params_.saleTokenPrice;
        $.decreaseCommitmentFee = params_.decreaseCommitmentFee;
        $.protocolFee = params_.protocolFee;

        uint256 saleTokenEscrowAmount = (params_.maximumTotalCommitment *
            PRECISION) / params_.saleTokenPrice;

        // transfer sale token from holder to this contract
        IERC20(params_.saleToken).safeTransferFrom(
            params_.saleTokenHolder,
            address(this),
            saleTokenEscrowAmount
        );
    }

    // ======================================================================
    // IPublicSaleV1
    // ======================================================================

    // --- View Functions ---

    /**
     * @inheritdoc IPublicSaleV1
     */
    function saleState() public view virtual override returns (SaleState) {
        PublicSaleStorage storage $ = _getPublicSaleStorage();

        if (block.timestamp < $.saleStartTimestamp) {
            return SaleState.NOT_STARTED;
        } else if ($.totalCommitments >= $.maximumTotalCommitment) {
            return SaleState.SUCCEEDED;
        } else if (block.timestamp > $.saleEndTimestamp) {
            // sale has ended
            if ($.totalCommitments >= $.minimumTotalCommitment) {
                return SaleState.SUCCEEDED;
            } else {
                return SaleState.FAILED;
            }
        } else {
            return SaleState.ACTIVE;
        }
    }

    /**
     * @inheritdoc IPublicSaleV1
     */
    function ownerSettled() external view virtual override returns (bool) {
        PublicSaleStorage storage $ = _getPublicSaleStorage();
        return $.ownerSettled;
    }

    /**
     * @inheritdoc IPublicSaleV1
     */
    function saleStartTimestamp()
        external
        view
        virtual
        override
        returns (uint48)
    {
        PublicSaleStorage storage $ = _getPublicSaleStorage();
        return $.saleStartTimestamp;
    }

    /**
     * @inheritdoc IPublicSaleV1
     */
    function saleEndTimestamp()
        external
        view
        virtual
        override
        returns (uint48)
    {
        PublicSaleStorage storage $ = _getPublicSaleStorage();
        return $.saleEndTimestamp;
    }

    /**
     * @inheritdoc IPublicSaleV1
     */
    function commitmentToken()
        external
        view
        virtual
        override
        returns (address)
    {
        PublicSaleStorage storage $ = _getPublicSaleStorage();
        return $.commitmentToken;
    }

    /**
     * @inheritdoc IPublicSaleV1
     */
    function saleToken() external view virtual override returns (address) {
        PublicSaleStorage storage $ = _getPublicSaleStorage();
        return $.saleToken;
    }

    /**
     * @inheritdoc IPublicSaleV1
     */
    function kycVerifier() external view virtual override returns (address) {
        PublicSaleStorage storage $ = _getPublicSaleStorage();
        return $.kycVerifier;
    }

    /**
     * @inheritdoc IPublicSaleV1
     */
    function saleProceedsReceiver()
        external
        view
        virtual
        override
        returns (address)
    {
        PublicSaleStorage storage $ = _getPublicSaleStorage();
        return $.saleProceedsReceiver;
    }

    /**
     * @inheritdoc IPublicSaleV1
     */
    function protocolFeeReceiver()
        external
        view
        virtual
        override
        returns (address)
    {
        PublicSaleStorage storage $ = _getPublicSaleStorage();
        return $.protocolFeeReceiver;
    }

    /**
     * @inheritdoc IPublicSaleV1
     */
    function minimumCommitment()
        external
        view
        virtual
        override
        returns (uint256)
    {
        PublicSaleStorage storage $ = _getPublicSaleStorage();
        return $.minimumCommitment;
    }

    /**
     * @inheritdoc IPublicSaleV1
     */
    function maximumCommitment()
        external
        view
        virtual
        override
        returns (uint256)
    {
        PublicSaleStorage storage $ = _getPublicSaleStorage();
        return $.maximumCommitment;
    }

    /**
     * @inheritdoc IPublicSaleV1
     */
    function minimumTotalCommitment()
        external
        view
        virtual
        override
        returns (uint256)
    {
        PublicSaleStorage storage $ = _getPublicSaleStorage();
        return $.minimumTotalCommitment;
    }

    /**
     * @inheritdoc IPublicSaleV1
     */
    function maximumTotalCommitment()
        external
        view
        virtual
        override
        returns (uint256)
    {
        PublicSaleStorage storage $ = _getPublicSaleStorage();
        return $.maximumTotalCommitment;
    }

    /**
     * @inheritdoc IPublicSaleV1
     */
    function saleTokenPrice() external view virtual override returns (uint256) {
        PublicSaleStorage storage $ = _getPublicSaleStorage();
        return $.saleTokenPrice;
    }

    /**
     * @inheritdoc IPublicSaleV1
     */
    function decreaseCommitmentFee()
        external
        view
        virtual
        override
        returns (uint256)
    {
        PublicSaleStorage storage $ = _getPublicSaleStorage();
        return $.decreaseCommitmentFee;
    }

    /**
     * @inheritdoc IPublicSaleV1
     */
    function protocolFee() external view virtual override returns (uint256) {
        PublicSaleStorage storage $ = _getPublicSaleStorage();
        return $.protocolFee;
    }

    /**
     * @inheritdoc IPublicSaleV1
     */
    function totalCommitments()
        external
        view
        virtual
        override
        returns (uint256)
    {
        PublicSaleStorage storage $ = _getPublicSaleStorage();
        return $.totalCommitments;
    }

    /**
     * @inheritdoc IPublicSaleV1
     */
    function collectedDecreaseCommitmentFees()
        external
        view
        virtual
        override
        returns (uint256)
    {
        PublicSaleStorage storage $ = _getPublicSaleStorage();
        return $.collectedDecreaseCommitmentFees;
    }

    /**
     * @inheritdoc IPublicSaleV1
     */
    function commitments(
        address account_
    ) external view virtual override returns (uint256) {
        PublicSaleStorage storage $ = _getPublicSaleStorage();
        return $.commitments[account_];
    }

    /**
     * @inheritdoc IPublicSaleV1
     */
    function settled(
        address account_
    ) external view virtual override returns (bool) {
        PublicSaleStorage storage $ = _getPublicSaleStorage();
        return $.settled[account_];
    }

    // --- State-Changing Functions ---

    /**
     * @inheritdoc IPublicSaleV1
     */
    function increaseCommitmentNative(
        bytes calldata verifyingSignature_,
        uint48 signatureExpiration_
    )
        public
        payable
        virtual
        override
        isKYCVerified(verifyingSignature_, signatureExpiration_)
    {
        PublicSaleStorage storage $ = _getPublicSaleStorage();

        if ($.commitmentToken != NATIVE_ASSET) revert InvalidCommitmentToken();

        _increaseCommitment(msg.sender, msg.value);
    }

    /**
     * @inheritdoc IPublicSaleV1
     */
    function increaseCommitmentERC20(
        uint256 increaseAmount_,
        bytes calldata verifyingSignature_,
        uint48 signatureExpiration_
    )
        public
        virtual
        override
        isKYCVerified(verifyingSignature_, signatureExpiration_)
    {
        PublicSaleStorage storage $ = _getPublicSaleStorage();

        if ($.commitmentToken == NATIVE_ASSET) revert InvalidCommitmentToken();

        _increaseCommitment(msg.sender, increaseAmount_);

        IERC20($.commitmentToken).safeTransferFrom(
            msg.sender,
            address(this),
            increaseAmount_
        );
    }

    /**
     * @inheritdoc IPublicSaleV1
     */
    function decreaseCommitment(
        uint256 decreaseAmount_,
        address recipient_
    ) public virtual override {
        PublicSaleStorage storage $ = _getPublicSaleStorage();

        if (saleState() != SaleState.ACTIVE) revert SaleNotActive();

        if (decreaseAmount_ == 0) revert ZeroAmount();

        if (decreaseAmount_ > $.commitments[msg.sender])
            revert DecreaseAmountExceedsCommitment();

        // throw error if caller's commitment will be less than minimum commitment,
        // unless commitment will be zeroed out
        if (
            $.commitments[msg.sender] - decreaseAmount_ < $.minimumCommitment &&
            $.commitments[msg.sender] != decreaseAmount_
        ) {
            revert MinimumCommitment();
        }

        uint256 _decreaseCommitmentFee = (decreaseAmount_ *
            $.decreaseCommitmentFee) / PRECISION;

        // update state
        $.commitments[msg.sender] -= decreaseAmount_;
        $.totalCommitments -= decreaseAmount_;
        $.collectedDecreaseCommitmentFees += _decreaseCommitmentFee;

        uint256 receivedAmount = decreaseAmount_ - _decreaseCommitmentFee;

        // transfer commitment token to msg.sender
        _transferTokenOrNative($.commitmentToken, recipient_, receivedAmount);

        emit CommitmentDecreased(msg.sender, decreaseAmount_);
    }

    /**
     * @inheritdoc IPublicSaleV1
     */
    function settle(address recipient_) public virtual override {
        PublicSaleStorage storage $ = _getPublicSaleStorage();

        if ($.settled[msg.sender]) revert AlreadySettled();

        if ($.commitments[msg.sender] == 0) revert ZeroCommitment();

        $.settled[msg.sender] = true;

        SaleState state = saleState();

        if (state == SaleState.SUCCEEDED) {
            // send the caller their purchased sale tokens
            uint256 saleTokenAmount = ($.commitments[msg.sender] * PRECISION) /
                $.saleTokenPrice;

            IERC20($.saleToken).safeTransfer(recipient_, saleTokenAmount);

            emit SuccessfulSaleSettled(msg.sender, recipient_, saleTokenAmount);
        } else if (state == SaleState.FAILED) {
            uint256 commitmentTokenAmount = $.commitments[msg.sender];

            _transferTokenOrNative(
                $.commitmentToken,
                recipient_,
                commitmentTokenAmount
            );

            emit FailedSaleSettled(
                msg.sender,
                recipient_,
                commitmentTokenAmount
            );
        } else {
            revert SaleNotEnded();
        }
    }

    /**
     * @inheritdoc IPublicSaleV1
     */
    function ownerSettle() public virtual override onlyOwner {
        PublicSaleStorage storage $ = _getPublicSaleStorage();

        if ($.ownerSettled) revert AlreadySettled();

        $.ownerSettled = true;

        SaleState state = saleState();

        if (state == SaleState.SUCCEEDED) {
            uint256 commitmentTokenAmount;
            if ($.commitmentToken == NATIVE_ASSET) {
                commitmentTokenAmount = address(this).balance;
            } else {
                commitmentTokenAmount = IERC20($.commitmentToken).balanceOf(
                    address(this)
                );
            }

            uint256 _protocolFee = (commitmentTokenAmount * $.protocolFee) /
                PRECISION;
            uint256 saleProceeds = commitmentTokenAmount - _protocolFee;

            // send (commitments + decrease commitment fees - protocol fee) to saleProceedsReceiver
            _transferTokenOrNative(
                $.commitmentToken,
                $.saleProceedsReceiver,
                saleProceeds
            );

            // send protocol fee to protocolFeeReceiver
            _transferTokenOrNative(
                $.commitmentToken,
                $.protocolFeeReceiver,
                _protocolFee
            );

            emit SuccessfulSaleOwnerSettled(
                msg.sender,
                saleProceeds,
                _protocolFee
            );
        } else if (state == SaleState.FAILED) {
            // transfer entire balance of sale tokens to saleProceedsReceiver
            uint256 saleTokenAmount = IERC20($.saleToken).balanceOf(
                address(this)
            );

            IERC20($.saleToken).safeTransfer(
                $.saleProceedsReceiver,
                saleTokenAmount
            );

            // transfer collected decrease commitment fees to saleProceedsReceiver
            uint256 _collectedDecreaseCommitmentFees = $
                .collectedDecreaseCommitmentFees;

            _transferTokenOrNative(
                $.commitmentToken,
                $.saleProceedsReceiver,
                _collectedDecreaseCommitmentFees
            );

            emit FailedSaleOwnerSettled(
                msg.sender,
                saleTokenAmount,
                _collectedDecreaseCommitmentFees
            );
        } else {
            revert SaleNotEnded();
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
     * @dev Supports IPublicSaleV1, IVersion, IDeploymentBlock, and IERC165
     */
    function supportsInterface(
        bytes4 interfaceId_
    ) public view virtual override returns (bool) {
        return
            interfaceId_ == type(IPublicSaleV1).interfaceId ||
            interfaceId_ == type(IVersion).interfaceId ||
            interfaceId_ == type(IDeploymentBlock).interfaceId ||
            super.supportsInterface(interfaceId_);
    }

    // ======================================================================
    // INTERNAL HELPERS
    // ======================================================================

    /**
     * @notice Transfers tokens or native assets to a recipient
     * @param token_ Token address or NATIVE_ASSET constant
     * @param to_ Recipient address
     * @param amount_ Amount to transfer
     */
    function _transferTokenOrNative(
        address token_,
        address to_,
        uint256 amount_
    ) internal {
        if (token_ == NATIVE_ASSET) {
            (bool success, ) = to_.call{value: amount_}("");
            if (!success) {
                revert TransferFailed();
            }
        } else {
            IERC20(token_).safeTransfer(to_, amount_);
        }
    }

    /**
     * @notice Internal function to increase a user's commitment
     * @param account_ Address of the committing user
     * @param increaseAmount_ Amount to increase commitment by
     */
    function _increaseCommitment(
        address account_,
        uint256 increaseAmount_
    ) internal {
        PublicSaleStorage storage $ = _getPublicSaleStorage();

        if (saleState() != SaleState.ACTIVE) revert SaleNotActive();

        if (increaseAmount_ == 0) revert ZeroAmount();

        if ($.totalCommitments + increaseAmount_ > $.maximumTotalCommitment)
            revert MaximumTotalCommitment();

        uint256 previousCommitment = $.commitments[account_];

        // revert if new commitment amount is less than minimum commitment,
        // unless commitment makes total commitments reach maximum total commitment
        if (
            previousCommitment + increaseAmount_ < $.minimumCommitment &&
            $.totalCommitments + increaseAmount_ != $.maximumTotalCommitment
        ) revert MinimumCommitment();

        if (previousCommitment + increaseAmount_ > $.maximumCommitment)
            revert MaximumCommitment();

        // update state
        $.commitments[account_] += increaseAmount_;
        $.totalCommitments += increaseAmount_;

        emit CommitmentIncreased(account_, increaseAmount_);
    }
}
