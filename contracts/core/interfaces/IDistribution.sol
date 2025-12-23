// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/**
 * @title IDistribution - Universal Distribution Primitive
 * @notice Who receives yield?
 * @dev Distribution routes yield from sources to recipients
 * 
 * CRITICAL INSIGHT:
 *   Rebasing is DISTRIBUTION, not yield.
 *   Supply changes are distribution mechanisms, not value creation.
 * 
 * Distribution Targets:
 *   - LP rewards (Compound, GMX)
 *   - Protocol treasury (all protocols)
 *   - Credit settlement (Alchemix)
 *   - Rebasing supply (Olympus)
 *   - Staking rewards (validators)
 *   - Insurance reserves (risk pools)
 */

/// @notice Distribution mechanism type
enum DistributionType {
    DIRECT,         // Direct transfer to recipients
    REBASING,       // Supply-level distribution (OHM)
    STREAMING,      // Continuous distribution over time (Sablier)
    VESTING,        // Time-locked distribution
    PROPORTIONAL,   // Pro-rata to stake/share holders
    PRIORITY        // Ordered distribution (senior/junior)
}

/// @notice Recipient classification
enum RecipientClass {
    LP_PROVIDER,    // Liquidity providers
    STAKER,         // Token stakers
    TREASURY,       // Protocol treasury
    INSURANCE,      // Insurance/reserve pool
    OBLIGATION,     // Credit settlement
    GOVERNANCE      // DAO/governance
}

interface IDistribution {
    // ═══════════════════════════════════════════════════════════════════════════
    // EVENTS
    // ═══════════════════════════════════════════════════════════════════════════
    
    event YieldReceived(address indexed source, uint256 amount);
    event DistributionExecuted(uint256 totalAmount, uint256 recipientCount);
    event RecipientAdded(address indexed recipient, RecipientClass class, uint256 share);
    event RecipientRemoved(address indexed recipient);
    event ShareUpdated(address indexed recipient, uint256 oldShare, uint256 newShare);
    event RebaseExecuted(uint256 supplyDelta, bool positive);
    
    // ═══════════════════════════════════════════════════════════════════════════
    // CORE STATE
    // ═══════════════════════════════════════════════════════════════════════════
    
    /// @notice Type of distribution mechanism
    function distributionType() external view returns (DistributionType);
    
    /// @notice Total yield distributed lifetime
    function totalDistributed() external view returns (uint256);
    
    /// @notice Yield pending distribution
    function pendingDistribution() external view returns (uint256);
    
    /// @notice Number of distribution recipients
    function recipientCount() external view returns (uint256);
    
    // ═══════════════════════════════════════════════════════════════════════════
    // DISTRIBUTION OPERATIONS
    // ═══════════════════════════════════════════════════════════════════════════
    
    /// @notice Distribute yield to all recipients
    /// @param amount Amount to distribute (0 = all pending)
    /// @return distributed Actual amount distributed
    function distribute(uint256 amount) external returns (uint256 distributed);
    
    /// @notice Distribute to a specific recipient
    /// @param recipient Target recipient
    /// @param amount Amount to distribute
    function distributeTo(address recipient, uint256 amount) external;
    
    /// @notice Execute rebase (for rebasing distribution)
    /// @dev Only valid for REBASING distribution type
    /// @return supplyDelta Change in supply (positive or negative)
    function rebase() external returns (int256 supplyDelta);
    
    /// @notice Claim pending distribution (for pull-based distribution)
    /// @param recipient Address claiming
    /// @return claimed Amount claimed
    function claim(address recipient) external returns (uint256 claimed);
    
    // ═══════════════════════════════════════════════════════════════════════════
    // RECIPIENT MANAGEMENT
    // ═══════════════════════════════════════════════════════════════════════════
    
    /// @notice Add a distribution recipient
    /// @param recipient Address to add
    /// @param class Recipient classification
    /// @param share Share in basis points (10000 = 100%)
    function addRecipient(address recipient, RecipientClass class, uint256 share) external;
    
    /// @notice Remove a distribution recipient
    /// @param recipient Address to remove
    function removeRecipient(address recipient) external;
    
    /// @notice Update recipient share
    /// @param recipient Address to update
    /// @param newShare New share in basis points
    function updateShare(address recipient, uint256 newShare) external;
    
    /// @notice Get recipient's share
    /// @param recipient Address to query
    /// @return share Current share in basis points
    function getShare(address recipient) external view returns (uint256 share);
    
    /// @notice Get recipient's pending claim
    /// @param recipient Address to query
    /// @return pending Amount available to claim
    function getPending(address recipient) external view returns (uint256 pending);
    
    // ═══════════════════════════════════════════════════════════════════════════
    // ROUTING
    // ═══════════════════════════════════════════════════════════════════════════
    
    /// @notice Route yield to obligation settlement first
    /// @param obligationId Target obligation
    /// @param percentage Percentage to route (basis points)
    function routeToObligation(bytes32 obligationId, uint256 percentage) external;
    
    /// @notice Route yield to insurance/reserve first
    /// @param percentage Percentage to route (basis points)
    function routeToReserve(uint256 percentage) external;
    
    /// @notice Configure distribution priority
    /// @param classes Ordered list of recipient classes
    function setPriority(RecipientClass[] calldata classes) external;
}

/**
 * @title DistributionLib
 * @notice Helper functions for distribution calculations
 */
library DistributionLib {
    uint256 constant BASIS_POINTS = 10000;
    
    /// @notice Calculate share amount from total
    function calculateShare(
        uint256 total,
        uint256 shareBps
    ) internal pure returns (uint256) {
        return (total * shareBps) / BASIS_POINTS;
    }
    
    /// @notice Check if distribution type supports rebasing
    function supportsRebasing(DistributionType dtype) internal pure returns (bool) {
        return dtype == DistributionType.REBASING;
    }
    
    /// @notice Check if distribution type is streaming
    function isStreaming(DistributionType dtype) internal pure returns (bool) {
        return dtype == DistributionType.STREAMING || 
               dtype == DistributionType.VESTING;
    }
}
