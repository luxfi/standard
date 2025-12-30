// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.31;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title VotingLUX
 * @author Lux Industries Inc
 * @notice Aggregates voting power: vLUX = xLUX + DLUX
 *
 * GOVERNANCE FORMULA:
 * ┌─────────────────────────────────────────────────────────────────────────────┐
 * │                                                                             │
 * │   vLUX (Voting Power) = xLUX (Liquid Staked) + DLUX (Governance Token)     │
 * │                                                                             │
 * │   • xLUX: Yield-bearing liquid staked LUX (from LiquidLUX vault)           │
 * │   • DLUX: OHM-style governance token (vote-only, no yield)                 │
 * │   • vLUX: Non-transferable aggregated voting power                         │
 * │                                                                             │
 * └─────────────────────────────────────────────────────────────────────────────┘
 *
 * This contract provides read-only aggregation of voting power.
 * It is NOT transferable (no transfer/approve functions).
 * Used by VotingWeightVLUX adapter for Strategy voting weight calculation.
 *
 * NOTE: This is separate from the existing vLUX.sol which uses ve-tokenomics.
 * The existing vLUX remains for backwards compatibility.
 */
contract VotingLUX {
    /// @notice xLUX token (LiquidLUX shares)
    IERC20 public immutable xLUX;
    
    /// @notice DLUX governance token
    IERC20 public immutable dLUX;
    
    /// @notice Token metadata
    string public constant name = "Voting LUX";
    string public constant symbol = "vLUX2";  // vLUX2 to differentiate from existing vLUX
    uint8 public constant decimals = 18;

    // ============ Errors ============
    
    error NonTransferable();

    // ============ Constructor ============
    
    constructor(address _xLUX, address _dLUX) {
        require(_xLUX != address(0) && _dLUX != address(0), "Invalid address");
        xLUX = IERC20(_xLUX);
        dLUX = IERC20(_dLUX);
    }

    // ============ ERC20-like View Functions (Read Only) ============
    
    /**
     * @notice Get voting power for an address
     * @param account The address to query
     * @return Aggregated voting power (xLUX + DLUX balance)
     */
    function balanceOf(address account) external view returns (uint256) {
        return xLUX.balanceOf(account) + dLUX.balanceOf(account);
    }

    /**
     * @notice Get total voting power across all holders
     * @return Aggregated total supply (xLUX + DLUX supply)
     */
    function totalSupply() external view returns (uint256) {
        return xLUX.totalSupply() + dLUX.totalSupply();
    }

    // ============ Checkpointed Voting (if tokens support ERC20Votes) ============
    
    /**
     * @notice Get past voting power at a specific block
     * @dev Falls back to current balance if tokens don't support getPastVotes
     * @param account The address to query
     * @param blockNumber The block number to query
     * @return Aggregated past voting power
     */
    function getPastVotes(address account, uint256 blockNumber) external view returns (uint256) {
        uint256 xLuxVotes = _getPastVotes(address(xLUX), account, blockNumber);
        uint256 dLuxVotes = _getPastVotes(address(dLUX), account, blockNumber);
        return xLuxVotes + dLuxVotes;
    }

    /**
     * @notice Get past total supply at a specific block
     * @param blockNumber The block number to query
     * @return Aggregated past total supply
     */
    function getPastTotalSupply(uint256 blockNumber) external view returns (uint256) {
        uint256 xLuxSupply = _getPastTotalSupply(address(xLUX), blockNumber);
        uint256 dLuxSupply = _getPastTotalSupply(address(dLUX), blockNumber);
        return xLuxSupply + dLuxSupply;
    }

    // ============ Non-Transferable ============
    
    /**
     * @notice Transfer is disabled - voting power is non-transferable
     */
    function transfer(address, uint256) external pure returns (bool) {
        revert NonTransferable();
    }

    /**
     * @notice TransferFrom is disabled - voting power is non-transferable
     */
    function transferFrom(address, address, uint256) external pure returns (bool) {
        revert NonTransferable();
    }

    /**
     * @notice Approve is disabled - voting power is non-transferable
     */
    function approve(address, uint256) external pure returns (bool) {
        revert NonTransferable();
    }

    /**
     * @notice Allowance always returns 0
     */
    function allowance(address, address) external pure returns (uint256) {
        return 0;
    }

    // ============ Component Breakdown ============
    
    /**
     * @notice Get breakdown of voting power components
     * @param account The address to query
     * @return xLuxBalance xLUX component
     * @return dLuxBalance DLUX component
     * @return total Total voting power
     */
    function getVotingPowerBreakdown(address account) external view returns (
        uint256 xLuxBalance,
        uint256 dLuxBalance,
        uint256 total
    ) {
        xLuxBalance = xLUX.balanceOf(account);
        dLuxBalance = dLUX.balanceOf(account);
        total = xLuxBalance + dLuxBalance;
    }

    // ============ Internal ============
    
    /**
     * @dev Try to get past votes, fallback to current balance
     */
    function _getPastVotes(address token, address account, uint256 blockNumber) internal view returns (uint256) {
        // Try ERC20Votes interface
        (bool success, bytes memory data) = token.staticcall(
            abi.encodeWithSignature("getPastVotes(address,uint256)", account, blockNumber)
        );
        
        if (success && data.length >= 32) {
            return abi.decode(data, (uint256));
        }
        
        // Fallback to current balance
        return IERC20(token).balanceOf(account);
    }

    /**
     * @dev Try to get past total supply, fallback to current supply
     */
    function _getPastTotalSupply(address token, uint256 blockNumber) internal view returns (uint256) {
        // Try ERC20Votes interface
        (bool success, bytes memory data) = token.staticcall(
            abi.encodeWithSignature("getPastTotalSupply(uint256)", blockNumber)
        );
        
        if (success && data.length >= 32) {
            return abi.decode(data, (uint256));
        }
        
        // Fallback to current supply
        return IERC20(token).totalSupply();
    }
}
