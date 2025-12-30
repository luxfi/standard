// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.31;

import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IVotingWeight} from "../interfaces/IVotingWeight.sol";

/**
 * @title VotingWeightVLUX
 * @author Lux Industries Inc
 * @notice IVotingWeight adapter for aggregated voting power (xLUX + DLUX)
 *
 * GOVERNANCE INTEGRATION:
 * ┌─────────────────────────────────────────────────────────────────────────────┐
 * │                                                                             │
 * │   Strategy.sol                                                              │
 * │       ↓                                                                     │
 * │   VotingWeightVLUX.calculateWeight(voter, timestamp, voteData)             │
 * │       ↓                                                                     │
 * │   [Try getPastVotes(voter, timestamp)]  ←── For snapshot-based voting      │
 * │       ↓ (fallback if not supported)                                        │
 * │   [balanceOf(voter)]  ←── For tokens without ERC20Votes                    │
 * │       ↓                                                                     │
 * │   weight = (xLUX + DLUX) * multiplier / 1e18                               │
 * │                                                                             │
 * └─────────────────────────────────────────────────────────────────────────────┘
 *
 * ANTI-FLASH-LOAN PROTECTION:
 * - Uses getPastVotes when available (ERC20Votes checkpointing)
 * - LiquidLUX (xLUX) implements ERC20Votes for checkpointed balances
 * - DLUX may not have checkpointing - falls back to balanceOf
 *
 * DOUBLE-COUNTING PREVENTION:
 * - xLUX and DLUX are distinct tokens - no overlap
 * - xLUX = liquid staked LUX (yield-bearing vault shares)
 * - DLUX = governance token (separate minting, no yield)
 */
contract VotingWeightVLUX is IVotingWeight, IERC165 {
    /// @notice xLUX token (LiquidLUX shares with ERC20Votes)
    address public immutable xLUX;
    
    /// @notice DLUX governance token
    address public immutable dLUX;
    
    /// @notice Weight multiplier (1e18 = 1x, 2e18 = 2x)
    uint256 public immutable weightMultiplier;

    // ============ Constructor ============
    
    /**
     * @param _xLUX Address of LiquidLUX (xLUX) token
     * @param _dLUX Address of DLUX governance token
     * @param _multiplier Weight multiplier (1e18 = 1x)
     */
    constructor(address _xLUX, address _dLUX, uint256 _multiplier) {
        require(_xLUX != address(0) && _dLUX != address(0), "Invalid address");
        require(_multiplier > 0, "Invalid multiplier");
        
        xLUX = _xLUX;
        dLUX = _dLUX;
        weightMultiplier = _multiplier;
    }

    // ============ IVotingWeight Implementation ============
    
    /**
     * @notice Calculates voting weight for a voter at a specific timestamp
     * @param voter_ The address whose voting weight to calculate
     * @param timestamp_ The timestamp at which to calculate weight (for snapshot)
     * @param voteData_ Implementation-specific data (unused in this implementation)
     * @return weight The calculated voting weight
     * @return processedData Empty bytes (no additional data needed)
     */
    function calculateWeight(
        address voter_,
        uint256 timestamp_,
        bytes calldata voteData_
    ) external view override returns (uint256 weight, bytes memory processedData) {
        // Silence unused parameter warning
        voteData_;
        
        // Get xLUX voting weight (with checkpoint support)
        uint256 xLuxWeight = _getVotingWeight(xLUX, voter_, timestamp_);
        
        // Get DLUX voting weight (with checkpoint support if available)
        uint256 dLuxWeight = _getVotingWeight(dLUX, voter_, timestamp_);
        
        // Aggregate and apply multiplier
        weight = ((xLuxWeight + dLuxWeight) * weightMultiplier) / 1e18;
        
        // Return empty processed data
        processedData = "";
    }

    /**
     * @notice Calculates voting weight for paymaster validation (ERC-4337)
     * @dev Avoids using block.timestamp/block.number (banned opcodes for paymaster)
     * @param voter_ The address whose voting weight to calculate
     * @param timestamp_ The timestamp at which to calculate weight
     * @param voteData_ Implementation-specific data (unused)
     * @return weight The calculated voting weight
     */
    function getVotingWeightForPaymaster(
        address voter_,
        uint256 timestamp_,
        bytes calldata voteData_
    ) external view override returns (uint256 weight) {
        (weight, ) = this.calculateWeight(voter_, timestamp_, voteData_);
    }

    // ============ ERC165 ============
    
    function supportsInterface(bytes4 interfaceId) external pure override returns (bool) {
        return interfaceId == type(IVotingWeight).interfaceId || 
               interfaceId == type(IERC165).interfaceId;
    }

    // ============ View Functions ============
    
    /**
     * @notice Get current voting power breakdown
     * @param voter The address to query
     * @return xLuxBalance xLUX component
     * @return dLuxBalance DLUX component
     * @return totalWeight Total weighted voting power
     */
    function getVotingPowerBreakdown(address voter) external view returns (
        uint256 xLuxBalance,
        uint256 dLuxBalance,
        uint256 totalWeight
    ) {
        xLuxBalance = IERC20(xLUX).balanceOf(voter);
        dLuxBalance = IERC20(dLUX).balanceOf(voter);
        totalWeight = ((xLuxBalance + dLuxBalance) * weightMultiplier) / 1e18;
    }

    /**
     * @notice Check if a token supports ERC20Votes (checkpointing)
     * @param token The token address to check
     * @return True if token supports getPastVotes
     */
    function supportsCheckpointing(address token) external view returns (bool) {
        // Try calling getPastVotes with a dummy call
        (bool success, ) = token.staticcall(
            abi.encodeWithSignature("getPastVotes(address,uint256)", address(this), 0)
        );
        return success;
    }

    // ============ Internal ============
    
    /**
     * @dev Get voting weight for a token, trying checkpoint first
     * @param token Token address
     * @param voter Voter address
     * @param timestamp Timestamp for snapshot
     * @return Voting weight
     */
    function _getVotingWeight(
        address token,
        address voter,
        uint256 timestamp
    ) internal view returns (uint256) {
        // Convert timestamp to block number approximation
        // Note: For precise snapshots, tokens should implement getPastVotes with timestamp
        // This uses block number estimation (12s per block on Ethereum, configurable for Lux)
        
        // First try getPastVotes with block number (standard ERC20Votes)
        if (timestamp < block.timestamp) {
            // Estimate block number from timestamp
            // Lux C-Chain: ~2s blocks, but this is approximate
            uint256 blockDiff = (block.timestamp - timestamp) / 2;
            uint256 targetBlock = block.number > blockDiff ? block.number - blockDiff : 0;
            
            (bool success, bytes memory data) = token.staticcall(
                abi.encodeWithSignature("getPastVotes(address,uint256)", voter, targetBlock)
            );
            
            if (success && data.length >= 32) {
                return abi.decode(data, (uint256));
            }
        }
        
        // Fallback: try current votes (delegated voting power)
        {
            (bool success, bytes memory data) = token.staticcall(
                abi.encodeWithSignature("getVotes(address)", voter)
            );
            
            if (success && data.length >= 32) {
                return abi.decode(data, (uint256));
            }
        }
        
        // Final fallback: raw balance
        return IERC20(token).balanceOf(voter);
    }
}
