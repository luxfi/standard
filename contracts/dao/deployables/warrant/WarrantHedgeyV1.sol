// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.30;

import {
    IWarrantBase
} from "../../interfaces/deployables/IWarrantBase.sol";
import {
    IWarrantHedgeyV1
} from "../../interfaces/deployables/IWarrantHedgeyV1.sol";
import {
    IVotingTokenLockupPlans
} from "../../interfaces/hedgey/IVotingTokenLockupPlans.sol";
import {
    IVotesERC20V1
} from "../../interfaces/deployables/IVotesERC20V1.sol";
import {IVersion} from "../../interfaces/deployables/IVersion.sol";
import {IDeploymentBlock} from "../../interfaces/IDeploymentBlock.sol";
import {WarrantBase} from "./WarrantBase.sol";
import {
    DeploymentBlockInitializable
} from "../../DeploymentBlockInitializable.sol";
import {InitializerEventEmitter} from "../../InitializerEventEmitter.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC165} from "@openzeppelin/contracts/utils/introspection/ERC165.sol";

/**
 * @title WarrantHedgeyV1
 * @author Lux Industriesn Inc
 * @notice Warrant implementation that creates Hedgey TokenLockupPlans upon execution
 * @dev This contract extends WarrantBase to integrate with Hedgey's vesting system.
 * When executed, it creates a vesting plan through Hedgey's TokenLockupPlans contract.
 *
 * Implementation details:
 * - Uses EIP-7201 namespaced storage pattern for Hedgey-specific parameters
 * - Validates vesting parameters to ensure valid Hedgey plans
 * - Supports both absolute and relative time modes for vesting start
 * - Creates linear vesting with optional cliff period
 *
 * @custom:security-contact security@lux.network
 */
contract WarrantHedgeyV1 is
    IWarrantHedgeyV1,
    WarrantBase,
    IVersion,
    DeploymentBlockInitializable,
    InitializerEventEmitter,
    ERC165
{
    // ======================================================================
    // STATE VARIABLES
    // ======================================================================

    /**
     * @notice Hedgey-specific storage struct following EIP-7201
     * @dev Contains parameters for Hedgey TokenLockupPlans integration
     * @custom:storage-location erc7201:DAO.WarrantHedgey.main
     */
    struct WarrantHedgeyStorage {
        /** @notice Address of Hedgey TokenLockupPlans contract */
        address hedgeyTokenLockupPlans;
        /** @notice Start time for vesting (absolute or relative) */
        uint256 hedgeyStart;
        /** @notice Cliff duration from start time */
        uint256 hedgeyRelativeCliff;
        /** @notice Amount of tokens vested per period */
        uint256 hedgeyRate;
        /** @notice Duration of each vesting period */
        uint256 hedgeyPeriod;
    }

    /**
     * @dev Storage slot for WarrantHedgeyStorage calculated using EIP-7201 formula:
     * keccak256(abi.encode(uint256(keccak256("DAO.WarrantHedgey.main")) - 1)) & ~bytes32(uint256(0xff))
     */
    bytes32 internal constant WARRANT_HEDGEY_STORAGE_LOCATION =
        0x9b20bbb986db094441d8fd56960a5c0858e1ec068bbf49851a1aee150a4aee00;

    /**
     * @dev Returns the storage struct for WarrantHedgeyV1
     * Following the EIP-7201 namespaced storage pattern to avoid storage collisions
     */
    function _getWarrantHedgeyStorage()
        internal
        pure
        returns (WarrantHedgeyStorage storage $)
    {
        // solhint-disable-next-line no-inline-assembly
        assembly {
            $.slot := WARRANT_HEDGEY_STORAGE_LOCATION
        }
    }

    // ======================================================================
    // CONSTRUCTOR & INITIALIZERS
    // ======================================================================

    constructor() {
        _disableInitializers();
    }

    /**
     * @inheritdoc IWarrantHedgeyV1
     * @dev Initializes both base warrant and Hedgey-specific parameters
     */
    function initialize(
        InitParams calldata params_
    ) public virtual override initializer {
        // Initialize base warrant functionality
        __WarrantBase_init(
            params_.relativeTime,
            params_.owner,
            params_.warrantHolder,
            params_.warrantToken,
            params_.paymentToken,
            params_.warrantTokenAmount,
            params_.warrantTokenPrice,
            params_.paymentReceiver,
            params_.expiration
        );
        __DeploymentBlockInitializable_init();
        __InitializerEventEmitter_init(abi.encode(params_));

        // Validate Hedgey parameters
        uint256 absoluteCliff = params_.hedgeyStart +
            params_.hedgeyRelativeCliff;
        _validateHedgeyParams(
            params_.warrantToken,
            params_.hedgeyStart,
            absoluteCliff,
            params_.warrantTokenAmount,
            params_.hedgeyRate,
            params_.hedgeyPeriod
        );

        // Store Hedgey-specific parameters
        WarrantHedgeyStorage storage $ = _getWarrantHedgeyStorage();
        $.hedgeyTokenLockupPlans = params_.hedgeyTokenLockupPlans;
        $.hedgeyStart = params_.hedgeyStart;
        $.hedgeyRelativeCliff = params_.hedgeyRelativeCliff;
        $.hedgeyRate = params_.hedgeyRate;
        $.hedgeyPeriod = params_.hedgeyPeriod;
    }

    // ======================================================================
    // IWarrantHedgeyV1
    // ======================================================================

    // --- View Functions ---

    /**
     * @inheritdoc IWarrantHedgeyV1
     */
    function hedgeyTokenLockupPlans()
        public
        view
        virtual
        override
        returns (address)
    {
        WarrantHedgeyStorage storage $ = _getWarrantHedgeyStorage();
        return $.hedgeyTokenLockupPlans;
    }

    /**
     * @inheritdoc IWarrantHedgeyV1
     */
    function hedgeyStart() public view virtual override returns (uint256) {
        WarrantHedgeyStorage storage $ = _getWarrantHedgeyStorage();
        return $.hedgeyStart;
    }

    /**
     * @inheritdoc IWarrantHedgeyV1
     */
    function hedgeyRelativeCliff()
        public
        view
        virtual
        override
        returns (uint256)
    {
        WarrantHedgeyStorage storage $ = _getWarrantHedgeyStorage();
        return $.hedgeyRelativeCliff;
    }

    /**
     * @inheritdoc IWarrantHedgeyV1
     */
    function hedgeyRate() public view virtual override returns (uint256) {
        WarrantHedgeyStorage storage $ = _getWarrantHedgeyStorage();
        return $.hedgeyRate;
    }

    /**
     * @inheritdoc IWarrantHedgeyV1
     */
    function hedgeyPeriod() public view virtual override returns (uint256) {
        WarrantHedgeyStorage storage $ = _getWarrantHedgeyStorage();
        return $.hedgeyPeriod;
    }

    // ======================================================================
    // WarrantBase
    // ======================================================================

    // --- Internal Functions ---

    /**
     * @notice Implementation of warrant execution that creates a Hedgey vesting plan
     * @dev Called by base contract after payment collection and validation
     * @param recipient_ Address that will receive the vested tokens
     */
    function _executeWarrant(address recipient_) internal virtual override {
        WarrantHedgeyStorage storage $ = _getWarrantHedgeyStorage();
        WarrantBaseStorage storage base$ = _getWarrantBaseStorage();

        // Calculate actual start time based on time mode
        uint256 startTime;
        if (base$.relativeTime) {
            startTime =
                IVotesERC20V1(base$.warrantToken).getUnlockTime() +
                $.hedgeyStart;
        } else {
            // Check if we've reached the hedgey start time in absolute mode
            if (block.timestamp < $.hedgeyStart) revert HedgeyStartNotElapsed();
            startTime = $.hedgeyStart;
        }

        // Calculate absolute cliff time
        uint256 hedgeyAbsoluteCliff = startTime + $.hedgeyRelativeCliff;

        // Approve Hedgey contract to transfer tokens
        IERC20(base$.warrantToken).approve(
            $.hedgeyTokenLockupPlans,
            base$.warrantTokenAmount
        );

        // Create vesting plan through Hedgey
        uint256 planId = IVotingTokenLockupPlans($.hedgeyTokenLockupPlans)
            .createPlan(
                recipient_,
                base$.warrantToken,
                base$.warrantTokenAmount,
                startTime,
                hedgeyAbsoluteCliff,
                $.hedgeyRate,
                $.hedgeyPeriod
            );

        emit HedgeyPlanCreated(planId, recipient_);
    }

    // ======================================================================
    // INTERNAL HELPERS
    // ======================================================================

    /**
     * @notice Validates Hedgey vesting parameters and calculates end time
     * @dev Ensures all parameters create a valid vesting schedule
     * @param token_ Address of the token being vested
     * @param start_ Start time of vesting
     * @param cliff_ Absolute cliff time
     * @param amount_ Total amount to vest
     * @param rate_ Amount vested per period
     * @param period_ Duration of each vesting period
     * @custom:throws InvalidAmount if amount is zero
     * @custom:throws InvalidRate if rate is zero
     * @custom:throws RateExceedsAmount if rate is greater than amount
     * @custom:throws InvalidPeriod if period is zero
     * @custom:throws CliffExceedsEnd if cliff time exceeds vesting end time
     */
    function _validateHedgeyParams(
        address token_,
        uint256 start_,
        uint256 cliff_,
        uint256 amount_,
        uint256 rate_,
        uint256 period_
    ) internal pure {
        if (token_ == address(0)) revert InvalidToken();
        if (amount_ == 0) revert InvalidAmount();
        if (rate_ == 0) revert InvalidRate();
        if (rate_ > amount_) revert RateExceedsAmount();
        if (period_ == 0) revert InvalidPeriod();

        // Calculate vesting end time
        uint256 end = (amount_ % rate_ == 0)
            ? (amount_ / rate_) * period_ + start_
            : ((amount_ / rate_) * period_) + period_ + start_;

        if (cliff_ > end) revert CliffExceedsEnd(cliff_, end);
    }

    // ======================================================================
    // IVersion
    // ======================================================================

    /**
     * @inheritdoc IVersion
     */
    function version() public pure virtual override returns (uint16) {
        return 1;
    }

    // ======================================================================
    // ERC165
    // ======================================================================

    /**
     * @notice Check if contract supports a given interface
     * @dev Supports IWarrantHedgeyV1, IWarrantBase, IVersion, IDeploymentBlock, and IERC165
     */
    function supportsInterface(
        bytes4 interfaceId_
    ) public view virtual override returns (bool) {
        return
            interfaceId_ == type(IWarrantHedgeyV1).interfaceId ||
            interfaceId_ == type(IWarrantBase).interfaceId ||
            interfaceId_ == type(IVersion).interfaceId ||
            interfaceId_ == type(IDeploymentBlock).interfaceId ||
            super.supportsInterface(interfaceId_);
    }
}
