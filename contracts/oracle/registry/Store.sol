// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.31;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {IStore} from "./interfaces/IStore.sol";

/**
 * @title Store
 * @notice An implementation of Store that can accept Oracle fees in ETH or any arbitrary ERC20 token.
 * @dev Uses fixed-point math with 18 decimals. All fee percentages are scaled by 1e18.
 * For example, 0.1e18 represents 10%.
 */
contract Store is IStore {
    using SafeERC20 for IERC20;

    /*//////////////////////////////////////////////////////////////
                                CONSTANTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Fixed-point scaling factor (18 decimals)
    uint256 public constant FP_SCALING_FACTOR = 1e18;

    /// @notice Seconds per week for late penalty calculation
    uint256 public constant SECONDS_PER_WEEK = 604800;

    /*//////////////////////////////////////////////////////////////
                                 TYPES
    //////////////////////////////////////////////////////////////*/

    enum Roles {
        Owner,
        Withdrawer
    }

    struct ExclusiveRole {
        address member;
    }

    struct Role {
        uint256 managingRole;
        bool isInitialized;
        ExclusiveRole exclusiveRole;
    }

    /*//////////////////////////////////////////////////////////////
                                STORAGE
    //////////////////////////////////////////////////////////////*/

    /// @notice Percentage fee per second per PFC (scaled by 1e18). E.g., 0.1e18 is 10% per second.
    uint256 public fixedOracleFeePerSecondPerPfc;

    /// @notice Weekly delay fee percentage per second (scaled by 1e18)
    uint256 public weeklyDelayFeePerSecondPerPfc;

    /// @notice Final fees by currency address (scaled by 1e18)
    mapping(address => uint256) public finalFees;

    /// @notice Role storage
    mapping(uint256 => Role) private roles;

    /// @notice Timer address for testing (0x0 for production)
    address public timerAddress;

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    event NewFixedOracleFeePerSecondPerPfc(uint256 newOracleFee);
    event NewWeeklyDelayFeePerSecondPerPfc(uint256 newWeeklyDelayFeePerSecondPerPfc);
    event NewFinalFee(address indexed currency, uint256 newFinalFee);
    event ResetExclusiveMember(uint256 indexed roleId, address indexed newMember, address indexed manager);

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    error SenderDoesNotHoldRole();
    error SenderNotRoleManager();
    error InvalidRole();
    error RoleAlreadyExists();
    error CannotSetExclusiveRoleToZero();
    error InvalidManagingRole();
    error RoleMustBeExclusive();
    error ValueSentCannotBeZero();
    error AmountSentCannotBeZero();
    error FeeMustBeLessThan100Percent();

    /*//////////////////////////////////////////////////////////////
                               MODIFIERS
    //////////////////////////////////////////////////////////////*/

    modifier onlyRoleHolder(uint256 roleId) {
        if (!holdsRole(roleId, msg.sender)) revert SenderDoesNotHoldRole();
        _;
    }

    modifier onlyRoleManager(uint256 roleId) {
        if (!holdsRole(roles[roleId].managingRole, msg.sender)) revert SenderNotRoleManager();
        _;
    }

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Construct the Store contract.
     * @param _fixedOracleFeePerSecondPerPfc Initial fixed oracle fee per second (scaled by 1e18).
     * @param _weeklyDelayFeePerSecondPerPfc Initial weekly delay fee per second (scaled by 1e18).
     * @param _timerAddress Timer contract for testing. Set to 0x0 for production.
     */
    constructor(
        uint256 _fixedOracleFeePerSecondPerPfc,
        uint256 _weeklyDelayFeePerSecondPerPfc,
        address _timerAddress
    ) {
        timerAddress = _timerAddress;

        _createExclusiveRole(uint256(Roles.Owner), uint256(Roles.Owner), msg.sender);
        _createExclusiveRole(uint256(Roles.Withdrawer), uint256(Roles.Owner), msg.sender);

        setFixedOracleFeePerSecondPerPfc(_fixedOracleFeePerSecondPerPfc);
        setWeeklyDelayFeePerSecondPerPfc(_weeklyDelayFeePerSecondPerPfc);
    }

    /*//////////////////////////////////////////////////////////////
                      ORACLE FEE CALCULATION/PAYMENT
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Pays Oracle fees in ETH to the store.
     * @dev To be used by contracts whose margin currency is ETH.
     */
    function payOracleFees() external payable override {
        if (msg.value == 0) revert ValueSentCannotBeZero();
    }

    /**
     * @notice Pays oracle fees in the margin currency, erc20Address, to the store.
     * @dev To be used if the margin currency is an ERC20 token rather than ETH.
     * @param erc20Address address of the ERC20 token used to pay the fee.
     * @param amount number of tokens to transfer (raw value). An approval for at least this amount must exist.
     */
    function payOracleFeesErc20(address erc20Address, uint256 amount) external override {
        if (amount == 0) revert AmountSentCannotBeZero();
        IERC20(erc20Address).safeTransferFrom(msg.sender, address(this), amount);
    }

    /**
     * @notice Computes the regular oracle fees that a contract should pay for a period.
     * @dev The late penalty is similar to the regular fee in that it is charged per second over the period.
     *
     * The late penalty percentage increases over time as follows:
     * - 0-1 week since startTime: no late penalty
     * - 1-2 weeks since startTime: 1x late penalty percentage is applied
     * - 2-3 weeks since startTime: 2x late penalty percentage is applied
     * - ...
     *
     * @param startTime defines the beginning time from which the fee is paid.
     * @param endTime end time until which the fee is paid.
     * @param pfc "profit from corruption", the maximum amount of margin currency that a
     * token sponsor could extract from the contract through corrupting the price feed (raw value, 18 decimals).
     * @return regularFee amount owed for the duration from start to end time for the given pfc (raw value, 18 decimals).
     * @return latePenalty penalty percentage, if any, for paying the fee after the deadline (raw value, 18 decimals).
     */
    function computeRegularFee(
        uint256 startTime,
        uint256 endTime,
        uint256 pfc
    ) external view override returns (uint256 regularFee, uint256 latePenalty) {
        uint256 timeDiff = endTime - startTime;

        // regularFee = pfc * timeDiff * fixedOracleFeePerSecondPerPfc / FP_SCALING_FACTOR
        regularFee = (pfc * timeDiff * fixedOracleFeePerSecondPerPfc) / FP_SCALING_FACTOR;

        // Compute how long ago the start time was to compute the delay penalty
        uint256 paymentDelay = getCurrentTime() - startTime;

        // Compute the additional percentage (per second) that will be charged because of the penalty
        // Note: if less than a week has gone by since startTime, paymentDelay / SECONDS_PER_WEEK will truncate to 0
        uint256 penaltyPercentagePerSecond = (weeklyDelayFeePerSecondPerPfc * paymentDelay) / SECONDS_PER_WEEK;

        // Apply the penaltyPercentagePerSecond to the payment period
        latePenalty = (pfc * timeDiff * penaltyPercentagePerSecond) / FP_SCALING_FACTOR;
    }

    /**
     * @notice Computes the final oracle fees that a contract should pay at settlement.
     * @param currency token used to pay the final fee.
     * @return finalFee amount due (raw value, 18 decimals).
     */
    function computeFinalFee(address currency) external view override returns (uint256) {
        return finalFees[currency];
    }

    /*//////////////////////////////////////////////////////////////
                       ADMIN STATE MODIFYING
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Sets a new oracle fee per second.
     * @param newFixedOracleFeePerSecondPerPfc new fee per second charged to use the oracle (scaled by 1e18).
     */
    function setFixedOracleFeePerSecondPerPfc(
        uint256 newFixedOracleFeePerSecondPerPfc
    ) public onlyRoleHolder(uint256(Roles.Owner)) {
        // Oracle fees at or over 100% don't make sense
        if (newFixedOracleFeePerSecondPerPfc >= FP_SCALING_FACTOR) revert FeeMustBeLessThan100Percent();
        fixedOracleFeePerSecondPerPfc = newFixedOracleFeePerSecondPerPfc;
        emit NewFixedOracleFeePerSecondPerPfc(newFixedOracleFeePerSecondPerPfc);
    }

    /**
     * @notice Sets a new weekly delay fee.
     * @param newWeeklyDelayFeePerSecondPerPfc fee escalation per week of late fee payment (scaled by 1e18).
     */
    function setWeeklyDelayFeePerSecondPerPfc(
        uint256 newWeeklyDelayFeePerSecondPerPfc
    ) public onlyRoleHolder(uint256(Roles.Owner)) {
        if (newWeeklyDelayFeePerSecondPerPfc >= FP_SCALING_FACTOR) revert FeeMustBeLessThan100Percent();
        weeklyDelayFeePerSecondPerPfc = newWeeklyDelayFeePerSecondPerPfc;
        emit NewWeeklyDelayFeePerSecondPerPfc(newWeeklyDelayFeePerSecondPerPfc);
    }

    /**
     * @notice Sets a new final fee for a particular currency.
     * @param currency defines the token currency used to pay the final fee.
     * @param newFinalFee final fee amount (raw value, 18 decimals).
     */
    function setFinalFee(address currency, uint256 newFinalFee) public onlyRoleHolder(uint256(Roles.Owner)) {
        finalFees[currency] = newFinalFee;
        emit NewFinalFee(currency, newFinalFee);
    }

    /*//////////////////////////////////////////////////////////////
                             WITHDRAWABLE
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Withdraws ETH from the contract.
     * @param amount amount of ETH to withdraw.
     */
    function withdraw(uint256 amount) external onlyRoleHolder(uint256(Roles.Withdrawer)) {
        Address.sendValue(payable(msg.sender), amount);
    }

    /**
     * @notice Withdraws ERC20 tokens from the contract.
     * @param erc20Address ERC20 token to withdraw.
     * @param amount amount of tokens to withdraw.
     */
    function withdrawErc20(address erc20Address, uint256 amount) external onlyRoleHolder(uint256(Roles.Withdrawer)) {
        IERC20(erc20Address).safeTransfer(msg.sender, amount);
    }

    /*//////////////////////////////////////////////////////////////
                           ROLE MANAGEMENT
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Whether `memberToCheck` is a member of roleId.
     * @param roleId the Role to check.
     * @param memberToCheck the address to check.
     * @return True if `memberToCheck` is a member of `roleId`.
     */
    function holdsRole(uint256 roleId, address memberToCheck) public view returns (bool) {
        Role storage role = roles[roleId];
        if (!role.isInitialized) revert InvalidRole();
        return role.exclusiveRole.member == memberToCheck;
    }

    /**
     * @notice Changes the exclusive role holder of `roleId` to `newMember`.
     * @param roleId the ExclusiveRole membership to modify.
     * @param newMember the new ExclusiveRole member.
     */
    function resetMember(uint256 roleId, address newMember) public onlyRoleManager(roleId) {
        if (newMember == address(0)) revert CannotSetExclusiveRoleToZero();
        roles[roleId].exclusiveRole.member = newMember;
        emit ResetExclusiveMember(roleId, newMember, msg.sender);
    }

    /**
     * @notice Gets the current holder of the exclusive role, `roleId`.
     * @param roleId the ExclusiveRole membership to check.
     * @return the address of the current ExclusiveRole member.
     */
    function getMember(uint256 roleId) public view returns (address) {
        Role storage role = roles[roleId];
        if (!role.isInitialized) revert InvalidRole();
        return role.exclusiveRole.member;
    }

    /*//////////////////////////////////////////////////////////////
                               TESTABLE
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Sets the current time (only works if timerAddress is set).
     * @param time timestamp to set current time to.
     */
    function setCurrentTime(uint256 time) external {
        require(timerAddress != address(0), "Not in test mode");
        Timer(timerAddress).setCurrentTime(time);
    }

    /**
     * @notice Gets the current time.
     * @return uint256 current timestamp (from Timer if in test mode, otherwise block.timestamp).
     */
    function getCurrentTime() public view returns (uint256) {
        if (timerAddress != address(0)) {
            return Timer(timerAddress).getCurrentTime();
        } else {
            return block.timestamp;
        }
    }

    /*//////////////////////////////////////////////////////////////
                          INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function _createExclusiveRole(uint256 roleId, uint256 managingRoleId, address initialMember) internal {
        Role storage role = roles[roleId];
        if (role.isInitialized) revert RoleAlreadyExists();
        if (initialMember == address(0)) revert CannotSetExclusiveRoleToZero();

        role.isInitialized = true;
        role.managingRole = managingRoleId;
        role.exclusiveRole.member = initialMember;

        // Special case: if role manages itself, no need to check managing role
        if (roleId != managingRoleId && !roles[managingRoleId].isInitialized) {
            revert InvalidManagingRole();
        }
    }

    /*//////////////////////////////////////////////////////////////
                                RECEIVE
    //////////////////////////////////////////////////////////////*/

    /// @notice Allow receiving ETH
    receive() external payable {}
}

/**
 * @title Timer
 * @notice Universal store of current contract time for testing environments.
 */
interface Timer {
    function setCurrentTime(uint256 time) external;
    function getCurrentTime() external view returns (uint256);
}
