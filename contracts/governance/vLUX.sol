// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title vLUX - Vote-Escrowed LUX
 * @notice Lock LUX to receive voting power for gauge weight allocation
 *
 * VE-TOKENOMICS:
 * ┌─────────────────────────────────────────────────────────────────┐
 * │  Lock LUX for 1 week to 4 years                                 │
 * │  Longer lock = More voting power                                │
 * │                                                                 │
 * │  vLUX = LUX_amount * (lock_time / MAX_LOCK_TIME)                │
 * │                                                                 │
 * │  Example:                                                       │
 * │  - 1000 LUX locked 4 years = 1000 vLUX                          │
 * │  - 1000 LUX locked 1 year  = 250 vLUX                           │
 * │  - 1000 LUX locked 1 week  = ~5 vLUX                            │
 * │                                                                 │
 * │  Voting power decays linearly as lock expires                   │
 * └─────────────────────────────────────────────────────────────────┘
 *
 * USE CASES:
 * - Vote on gauge weights (where fees go)
 * - Vote on protocol parameters
 * - Boost rewards in various pools
 * - Governance proposals
 */
contract vLUX is ReentrancyGuard {
    using SafeERC20 for IERC20;

    // ============ Constants ============
    
    /// @notice Minimum lock time: 1 week
    uint256 public constant MIN_LOCK_TIME = 1 weeks;
    
    /// @notice Maximum lock time: 4 years
    uint256 public constant MAX_LOCK_TIME = 4 * 365 days;
    
    /// @notice Week in seconds (for epoch calculations)
    uint256 public constant WEEK = 7 days;

    // ============ Types ============
    
    struct LockedBalance {
        uint256 amount;     // Locked LUX amount
        uint256 end;        // Lock end timestamp (rounded to week)
    }
    
    struct Point {
        int128 bias;        // Current voting power
        int128 slope;       // Decay rate per second
        uint256 ts;         // Timestamp
        uint256 blk;        // Block number
    }

    // ============ State ============
    
    /// @notice The LUX token
    IERC20 public immutable lux;
    
    /// @notice Total locked LUX
    uint256 public totalLocked;
    
    /// @notice Locked balances per user
    mapping(address => LockedBalance) public locked;
    
    /// @notice Current epoch
    uint256 public epoch;
    
    /// @notice Point history (global)
    mapping(uint256 => Point) public pointHistory;
    
    /// @notice User point history
    mapping(address => mapping(uint256 => Point)) public userPointHistory;
    
    /// @notice User point epoch
    mapping(address => uint256) public userPointEpoch;
    
    /// @notice Slope changes at timestamps
    mapping(uint256 => int128) public slopeChanges;
    
    /// @notice Token name
    string public constant name = "Vote-Escrowed LUX";
    
    /// @notice Token symbol
    string public constant symbol = "vLUX";
    
    /// @notice Decimals
    uint8 public constant decimals = 18;

    // ============ Events ============
    
    event Deposit(
        address indexed user,
        uint256 amount,
        uint256 lockTime,
        uint256 indexed lockEnd,
        uint256 ts
    );
    event Withdraw(address indexed user, uint256 amount, uint256 ts);
    event Supply(uint256 prevSupply, uint256 newSupply);

    // ============ Errors ============
    
    error LockTooShort();
    error LockTooLong();
    error LockExpired();
    error LockNotExpired();
    error NoExistingLock();
    error WithdrawOldTokensFirst();
    error ZeroAmount();
    error CanOnlyIncreaseLockEnd();
    error VotingPowerTooHigh();

    // ============ Constructor ============
    
    constructor(address _lux) {
        lux = IERC20(_lux);
        pointHistory[0] = Point({
            bias: 0,
            slope: 0,
            ts: block.timestamp,
            blk: block.number
        });
    }

    // ============ External Functions ============
    
    /// @notice Create a new lock
    /// @param amount Amount of LUX to lock
    /// @param unlockTime Timestamp when lock expires (rounded down to week)
    function createLock(uint256 amount, uint256 unlockTime) external nonReentrant {
        if (amount == 0) revert ZeroAmount();
        if (locked[msg.sender].amount != 0) revert WithdrawOldTokensFirst();
        
        uint256 roundedUnlock = (unlockTime / WEEK) * WEEK; // Round to week
        
        if (roundedUnlock <= block.timestamp) revert LockTooShort();
        if (roundedUnlock < block.timestamp + MIN_LOCK_TIME) revert LockTooShort();
        if (roundedUnlock > block.timestamp + MAX_LOCK_TIME) revert LockTooLong();
        
        _depositFor(msg.sender, amount, roundedUnlock, locked[msg.sender], 0);
    }
    
    /// @notice Increase locked amount
    /// @param amount Additional LUX to lock
    function increaseAmount(uint256 amount) external nonReentrant {
        if (amount == 0) revert ZeroAmount();
        LockedBalance memory _locked = locked[msg.sender];
        if (_locked.amount == 0) revert NoExistingLock();
        if (_locked.end <= block.timestamp) revert LockExpired();
        
        _depositFor(msg.sender, amount, 0, _locked, 1);
    }
    
    /// @notice Extend lock time
    /// @param newUnlockTime New unlock timestamp
    function increaseUnlockTime(uint256 newUnlockTime) external nonReentrant {
        LockedBalance memory _locked = locked[msg.sender];
        if (_locked.amount == 0) revert NoExistingLock();
        if (_locked.end <= block.timestamp) revert LockExpired();
        
        uint256 roundedUnlock = (newUnlockTime / WEEK) * WEEK;
        
        if (roundedUnlock <= _locked.end) revert CanOnlyIncreaseLockEnd();
        if (roundedUnlock > block.timestamp + MAX_LOCK_TIME) revert LockTooLong();
        
        _depositFor(msg.sender, 0, roundedUnlock, _locked, 2);
    }
    
    /// @notice Withdraw all tokens after lock expires
    function withdraw() external nonReentrant {
        LockedBalance memory _locked = locked[msg.sender];
        if (_locked.end > block.timestamp) revert LockNotExpired();
        
        uint256 amount = _locked.amount;
        
        locked[msg.sender] = LockedBalance(0, 0);
        uint256 prevSupply = totalLocked;
        totalLocked -= amount;
        
        // Update point history
        _checkpoint(msg.sender, _locked, LockedBalance(0, 0));
        
        lux.safeTransfer(msg.sender, amount);
        
        emit Withdraw(msg.sender, amount, block.timestamp);
        emit Supply(prevSupply, totalLocked);
    }

    // ============ View Functions ============
    
    /// @notice Get current voting power for user
    /// @param user Address to query
    /// @return Voting power (vLUX balance)
    function balanceOf(address user) external view returns (uint256) {
        return _balanceOf(user, block.timestamp);
    }
    
    /// @notice Get voting power at specific timestamp
    function balanceOfAt(address user, uint256 ts) external view returns (uint256) {
        return _balanceOf(user, ts);
    }
    
    /// @notice Get total voting power
    function totalSupply() external view returns (uint256) {
        return _totalSupply(block.timestamp);
    }
    
    /// @notice Get total voting power at timestamp
    function totalSupplyAt(uint256 ts) external view returns (uint256) {
        return _totalSupply(ts);
    }
    
    /// @notice Get lock info for user
    function getLocked(address user) external view returns (uint256 amount, uint256 end) {
        LockedBalance memory _locked = locked[user];
        return (_locked.amount, _locked.end);
    }

    // ============ Internal Functions ============
    
    function _depositFor(
        address user,
        uint256 amount,
        uint256 unlockTime,
        LockedBalance memory oldLocked,
        uint256 depositType
    ) internal {
        uint256 prevSupply = totalLocked;
        
        if (amount > 0) {
            lux.safeTransferFrom(msg.sender, address(this), amount);
        }
        
        LockedBalance memory newLocked = LockedBalance({
            amount: oldLocked.amount + amount,
            end: unlockTime == 0 ? oldLocked.end : unlockTime
        });
        
        locked[user] = newLocked;
        totalLocked += amount;
        
        _checkpoint(user, oldLocked, newLocked);
        
        emit Deposit(user, amount, newLocked.end - block.timestamp, newLocked.end, block.timestamp);
        emit Supply(prevSupply, totalLocked);
    }
    
    function _checkpoint(
        address user,
        LockedBalance memory oldLocked,
        LockedBalance memory newLocked
    ) internal {
        Point memory uOld;
        Point memory uNew;
        int128 oldSlope = 0;
        int128 newSlope = 0;
        
        if (user != address(0)) {
            if (oldLocked.end > block.timestamp && oldLocked.amount > 0) {
                uOld.slope = int128(int256(oldLocked.amount / MAX_LOCK_TIME));
                uOld.bias = uOld.slope * int128(int256(oldLocked.end - block.timestamp));
            }
            if (newLocked.end > block.timestamp && newLocked.amount > 0) {
                uNew.slope = int128(int256(newLocked.amount / MAX_LOCK_TIME));
                uNew.bias = uNew.slope * int128(int256(newLocked.end - block.timestamp));
            }
            
            oldSlope = slopeChanges[oldLocked.end];
            if (newLocked.end != 0) {
                if (newLocked.end == oldLocked.end) {
                    newSlope = oldSlope;
                } else {
                    newSlope = slopeChanges[newLocked.end];
                }
            }
        }
        
        Point memory lastPoint = pointHistory[epoch];
        uint256 lastCheckpoint = lastPoint.ts;
        
        // Fill history
        uint256 ti = (lastCheckpoint / WEEK) * WEEK;
        for (uint256 i = 0; i < 255; i++) {
            ti += WEEK;
            int128 dSlope = 0;
            if (ti > block.timestamp) {
                ti = block.timestamp;
            } else {
                dSlope = slopeChanges[ti];
            }
            lastPoint.bias -= lastPoint.slope * int128(int256(ti - lastCheckpoint));
            lastPoint.slope += dSlope;
            if (lastPoint.bias < 0) {
                lastPoint.bias = 0;
            }
            if (lastPoint.slope < 0) {
                lastPoint.slope = 0;
            }
            lastCheckpoint = ti;
            lastPoint.ts = ti;
            lastPoint.blk = block.number;
            epoch += 1;
            if (ti == block.timestamp) {
                break;
            }
            pointHistory[epoch] = lastPoint;
        }
        
        // Update global state
        lastPoint.slope += (uNew.slope - uOld.slope);
        lastPoint.bias += (uNew.bias - uOld.bias);
        if (lastPoint.slope < 0) {
            lastPoint.slope = 0;
        }
        if (lastPoint.bias < 0) {
            lastPoint.bias = 0;
        }
        pointHistory[epoch] = lastPoint;
        
        // Update slope changes
        if (oldLocked.end > block.timestamp) {
            oldSlope += uOld.slope;
            if (newLocked.end == oldLocked.end) {
                oldSlope -= uNew.slope;
            }
            slopeChanges[oldLocked.end] = oldSlope;
        }
        if (newLocked.end > block.timestamp) {
            if (newLocked.end > oldLocked.end) {
                newSlope -= uNew.slope;
                slopeChanges[newLocked.end] = newSlope;
            }
        }
        
        // Update user point
        if (user != address(0)) {
            uint256 userEpoch = userPointEpoch[user] + 1;
            userPointEpoch[user] = userEpoch;
            uNew.ts = block.timestamp;
            uNew.blk = block.number;
            userPointHistory[user][userEpoch] = uNew;
        }
    }
    
    function _balanceOf(address user, uint256 ts) internal view returns (uint256) {
        uint256 _epoch = userPointEpoch[user];
        if (_epoch == 0) {
            return 0;
        }
        Point memory lastPoint = userPointHistory[user][_epoch];
        lastPoint.bias -= lastPoint.slope * int128(int256(ts - lastPoint.ts));
        if (lastPoint.bias < 0) {
            lastPoint.bias = 0;
        }
        return uint256(int256(lastPoint.bias));
    }
    
    function _totalSupply(uint256 ts) internal view returns (uint256) {
        Point memory lastPoint = pointHistory[epoch];
        lastPoint.bias -= lastPoint.slope * int128(int256(ts - lastPoint.ts));
        if (lastPoint.bias < 0) {
            lastPoint.bias = 0;
        }
        return uint256(int256(lastPoint.bias));
    }
}
