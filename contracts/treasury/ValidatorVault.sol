// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.31;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

interface ILiquidLUXValidator {
    function depositValidatorRewards(uint256 amount) external;
}

/**
 * @title ValidatorVault
 * @notice Manages validator and delegator reward distribution
 *
 * VALIDATOR ECONOMICS:
 * ┌─────────────────────────────────────────────────────────────────┐
 * │  FeeSplitter ──► ValidatorVault                                 │
 * │                       │                                         │
 * │       ┌───────────────┼───────────────┐                         │
 * │       ▼               ▼               ▼                         │
 * │  Validators      Delegators       Reserve                       │
 * │  (commission)    (pro-rata)       (slashing)                    │
 * └─────────────────────────────────────────────────────────────────┘
 *
 * LIQUIDLUX INTEGRATION (NO PERFORMANCE FEE):
 * ┌─────────────────────────────────────────────────────────────────┐
 * │  ValidatorVault → LiquidLUX.depositValidatorRewards()           │
 * │                                                                 │
 * │  • Validators are EXEMPT from 10% performance fee               │
 * │  • 100% of validator rewards go to xLUX holders                 │
 * │  • Use forwardRewardsToLiquidLUX() to push accumulated rewards  │
 * └─────────────────────────────────────────────────────────────────┘
 *
 * Validators register and set commission rates.
 * Delegators stake with validators and earn rewards.
 * This is a C-Chain mirror of P-Chain staking economics.
 */
contract ValidatorVault is ReentrancyGuard, Ownable {
    using SafeERC20 for IERC20;

    // ============ Constants ============
    
    uint256 public constant BPS = 10000;
    uint256 public constant MAX_COMMISSION = 2000; // 20% max commission

    // ============ Types ============
    
    struct Validator {
        address rewardAddress;   // Where to send rewards
        uint256 commissionBps;   // Commission rate (e.g., 1000 = 10%)
        uint256 totalDelegated;  // Total LUX delegated to this validator
        uint256 pendingRewards;  // Accumulated rewards
        bool active;
    }
    
    struct Delegation {
        bytes32 validatorId;     // Which validator
        uint256 amount;          // Amount delegated
        uint256 rewardDebt;      // For reward calculation
    }

    // ============ State ============
    
    IERC20 public immutable lux;
    
    /// @notice Validators by ID (could be NodeID hash)
    mapping(bytes32 => Validator) public validators;
    bytes32[] public validatorIds;
    
    /// @notice Delegations by user
    mapping(address => Delegation[]) public delegations;
    
    /// @notice Total delegated across all validators
    uint256 public totalDelegated;
    
    /// @notice Accumulated rewards per share (scaled by 1e18)
    uint256 public accRewardPerShare;
    
    /// @notice Reserve for slashing coverage
    uint256 public slashingReserve;
    uint256 public slashingReserveBps = 500; // 5% to reserve

    /// @notice LiquidLUX vault for reward forwarding (no perf fee path)
    ILiquidLUXValidator public liquidLux;
    
    /// @notice Accumulated rewards pending forward to LiquidLUX
    uint256 public pendingLiquidLuxRewards;

    /// @notice Stats
    uint256 public totalReceived;
    uint256 public totalDistributed;
    uint256 public totalToLiquidLux;

    // ============ Events ============
    
    event ValidatorRegistered(bytes32 indexed validatorId, address rewardAddress, uint256 commissionBps);
    event ValidatorUpdated(bytes32 indexed validatorId, uint256 commissionBps, bool active);
    event Delegated(address indexed delegator, bytes32 indexed validatorId, uint256 amount);
    event Undelegated(address indexed delegator, bytes32 indexed validatorId, uint256 amount);
    event RewardsClaimed(address indexed delegator, uint256 amount);
    event RewardsDistributed(uint256 amount, uint256 toReserve);
    event RewardsToLiquidLux(uint256 amount);
    event LiquidLuxUpdated(address indexed newLiquidLux);

    // ============ Errors ============
    
    error ValidatorNotFound();
    error ValidatorNotActive();
    error InvalidCommission();
    error InsufficientDelegation();
    error NothingToClaim();
    error LiquidLuxNotSet();
    error NothingToForward();

    // ============ Constructor ============
    
    constructor(address _lux) Ownable(msg.sender) {
        lux = IERC20(_lux);
    }

    // ============ Receive Rewards ============
    
    /// @notice Receive rewards from FeeSplitter
    receive() external payable {
        _distributeRewards(msg.value);
    }
    
    function depositRewards(uint256 amount) external {
        lux.safeTransferFrom(msg.sender, address(this), amount);
        _distributeRewards(amount);
    }
    
    function _distributeRewards(uint256 amount) internal {
        if (amount == 0 || totalDelegated == 0) return;
        
        totalReceived += amount;
        
        // Take slashing reserve cut
        uint256 toReserve = (amount * slashingReserveBps) / BPS;
        slashingReserve += toReserve;
        
        uint256 toDistribute = amount - toReserve;
        
        // Update accumulated rewards per share
        accRewardPerShare += (toDistribute * 1e18) / totalDelegated;
        
        emit RewardsDistributed(toDistribute, toReserve);
    }

    // ============ LiquidLUX Integration ============
    
    /**
     * @notice Forward accumulated rewards to LiquidLUX (no performance fee)
     * @dev Validators are exempt from the 10% performance fee
     */
    function forwardRewardsToLiquidLUX() external nonReentrant {
        if (address(liquidLux) == address(0)) revert LiquidLuxNotSet();
        
        // Calculate forwardable amount (balance minus delegated and slashing reserve)
        uint256 balance = lux.balanceOf(address(this));
        uint256 reserved = totalDelegated + slashingReserve;
        
        if (balance <= reserved) revert NothingToForward();
        
        uint256 forwardable = balance - reserved;
        
        // Approve exact amount (no infinite approvals)
        lux.forceApprove(address(liquidLux), forwardable);
        
        // Push to LiquidLUX (no perf fee path)
        liquidLux.depositValidatorRewards(forwardable);
        
        // Clear approval
        lux.forceApprove(address(liquidLux), 0);
        
        totalToLiquidLux += forwardable;
        
        emit RewardsToLiquidLux(forwardable);
    }

    /**
     * @notice Forward specific amount to LiquidLUX
     * @param amount Amount of rewards to forward
     */
    function forwardAmountToLiquidLUX(uint256 amount) external nonReentrant {
        if (address(liquidLux) == address(0)) revert LiquidLuxNotSet();
        
        uint256 balance = lux.balanceOf(address(this));
        uint256 reserved = totalDelegated + slashingReserve;
        
        if (balance <= reserved || amount > balance - reserved) revert NothingToForward();
        
        // Approve exact amount
        lux.forceApprove(address(liquidLux), amount);
        
        // Push to LiquidLUX
        liquidLux.depositValidatorRewards(amount);
        
        // Clear approval
        lux.forceApprove(address(liquidLux), 0);
        
        totalToLiquidLux += amount;
        
        emit RewardsToLiquidLux(amount);
    }

    // ============ Validator Management ============
    
    /// @notice Register a new validator
    function registerValidator(
        bytes32 validatorId,
        address rewardAddress,
        uint256 commissionBps
    ) external onlyOwner {
        if (commissionBps > MAX_COMMISSION) revert InvalidCommission();
        
        validators[validatorId] = Validator({
            rewardAddress: rewardAddress,
            commissionBps: commissionBps,
            totalDelegated: 0,
            pendingRewards: 0,
            active: true
        });
        
        validatorIds.push(validatorId);
        
        emit ValidatorRegistered(validatorId, rewardAddress, commissionBps);
    }
    
    /// @notice Update validator settings
    function updateValidator(
        bytes32 validatorId,
        uint256 commissionBps,
        bool active
    ) external onlyOwner {
        Validator storage v = validators[validatorId];
        if (v.rewardAddress == address(0)) revert ValidatorNotFound();
        if (commissionBps > MAX_COMMISSION) revert InvalidCommission();
        
        v.commissionBps = commissionBps;
        v.active = active;
        
        emit ValidatorUpdated(validatorId, commissionBps, active);
    }

    // ============ Delegation ============
    
    /// @notice Delegate LUX to a validator
    function delegate(bytes32 validatorId, uint256 amount) external nonReentrant {
        Validator storage v = validators[validatorId];
        if (v.rewardAddress == address(0)) revert ValidatorNotFound();
        if (!v.active) revert ValidatorNotActive();
        
        lux.safeTransferFrom(msg.sender, address(this), amount);
        
        // Update validator
        v.totalDelegated += amount;
        totalDelegated += amount;
        
        // Create delegation record
        delegations[msg.sender].push(Delegation({
            validatorId: validatorId,
            amount: amount,
            rewardDebt: (amount * accRewardPerShare) / 1e18
        }));
        
        emit Delegated(msg.sender, validatorId, amount);
    }
    
    /// @notice Undelegate from a validator
    function undelegate(uint256 delegationIndex) external nonReentrant {
        Delegation[] storage userDelegations = delegations[msg.sender];
        if (delegationIndex >= userDelegations.length) revert InsufficientDelegation();
        
        Delegation memory d = userDelegations[delegationIndex];
        Validator storage v = validators[d.validatorId];
        
        // Claim pending rewards first
        uint256 pending = _pendingReward(d);
        if (pending > 0) {
            // Deduct validator commission
            uint256 commission = (pending * v.commissionBps) / BPS;
            v.pendingRewards += commission;
            
            uint256 delegatorReward = pending - commission;
            lux.safeTransfer(msg.sender, delegatorReward);
            totalDistributed += delegatorReward;
        }
        
        // Update state
        v.totalDelegated -= d.amount;
        totalDelegated -= d.amount;
        
        // Return delegated amount
        lux.safeTransfer(msg.sender, d.amount);
        
        // Remove delegation (swap and pop)
        userDelegations[delegationIndex] = userDelegations[userDelegations.length - 1];
        userDelegations.pop();
        
        emit Undelegated(msg.sender, d.validatorId, d.amount);
    }

    // ============ Rewards ============
    
    /// @notice Claim pending rewards for all delegations
    function claimRewards() external nonReentrant {
        Delegation[] storage userDelegations = delegations[msg.sender];
        uint256 totalReward = 0;
        
        for (uint256 i = 0; i < userDelegations.length; i++) {
            Delegation storage d = userDelegations[i];
            Validator storage v = validators[d.validatorId];
            
            uint256 pending = _pendingReward(d);
            if (pending > 0) {
                // Deduct validator commission
                uint256 commission = (pending * v.commissionBps) / BPS;
                v.pendingRewards += commission;
                
                totalReward += pending - commission;
                
                // Update reward debt
                d.rewardDebt = (d.amount * accRewardPerShare) / 1e18;
            }
        }
        
        if (totalReward == 0) revert NothingToClaim();
        
        lux.safeTransfer(msg.sender, totalReward);
        totalDistributed += totalReward;
        
        emit RewardsClaimed(msg.sender, totalReward);
    }
    
    /// @notice Validator claims their commission
    function claimValidatorRewards(bytes32 validatorId) external nonReentrant {
        Validator storage v = validators[validatorId];
        if (v.rewardAddress != msg.sender) revert ValidatorNotFound();
        
        uint256 amount = v.pendingRewards;
        if (amount == 0) revert NothingToClaim();
        
        v.pendingRewards = 0;
        lux.safeTransfer(msg.sender, amount);
        totalDistributed += amount;
        
        emit RewardsClaimed(msg.sender, amount);
    }
    
    function _pendingReward(Delegation memory d) internal view returns (uint256) {
        return ((d.amount * accRewardPerShare) / 1e18) - d.rewardDebt;
    }

    // ============ Admin ============
    
    function setSlashingReserveBps(uint256 bps) external onlyOwner {
        require(bps <= 2000, "Max 20%");
        slashingReserveBps = bps;
    }
    
    /// @notice Set LiquidLUX vault address
    function setLiquidLUX(address _liquidLux) external onlyOwner {
        require(_liquidLux != address(0), "Invalid address");
        
        // Clear any existing approval
        if (address(liquidLux) != address(0)) {
            lux.forceApprove(address(liquidLux), 0);
        }
        
        liquidLux = ILiquidLUXValidator(_liquidLux);
        
        emit LiquidLuxUpdated(_liquidLux);
    }
    
    /// @notice Use slashing reserve to cover slashed validator
    function slash(bytes32 validatorId, uint256 amount) external onlyOwner {
        require(amount <= slashingReserve, "Insufficient reserve");
        slashingReserve -= amount;
        // Slashing logic - redistribute to affected delegators
    }

    // ============ View ============
    
    function getValidatorCount() external view returns (uint256) {
        return validatorIds.length;
    }
    
    function getDelegationCount(address user) external view returns (uint256) {
        return delegations[user].length;
    }
    
    function getPendingRewards(address user) external view returns (uint256 total) {
        Delegation[] memory userDelegations = delegations[user];
        for (uint256 i = 0; i < userDelegations.length; i++) {
            Delegation memory d = userDelegations[i];
            Validator memory v = validators[d.validatorId];
            
            uint256 pending = _pendingReward(d);
            uint256 commission = (pending * v.commissionBps) / BPS;
            total += pending - commission;
        }
    }
    
    function getValidatorInfo(bytes32 validatorId) external view returns (
        address rewardAddress,
        uint256 commissionBps,
        uint256 totalDelegatedAmount,
        uint256 pendingRewards,
        bool active
    ) {
        Validator memory v = validators[validatorId];
        return (v.rewardAddress, v.commissionBps, v.totalDelegated, v.pendingRewards, v.active);
    }
    
    /// @notice Get stats including LiquidLUX forwarding
    function getStats() external view returns (
        uint256 received,
        uint256 distributed,
        uint256 toLiquidLux,
        uint256 inReserve
    ) {
        return (totalReceived, totalDistributed, totalToLiquidLux, slashingReserve);
    }
    
    /// @notice Get forwardable amount to LiquidLUX
    function getForwardableAmount() external view returns (uint256) {
        uint256 balance = lux.balanceOf(address(this));
        uint256 reserved = totalDelegated + slashingReserve;
        
        if (balance <= reserved) return 0;
        return balance - reserved;
    }
}
