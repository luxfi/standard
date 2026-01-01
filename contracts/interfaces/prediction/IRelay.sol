// SPDX-License-Identifier: MIT
pragma solidity ^0.8.31;

/**
 * @title IRelay
 * @author Lux Industries
 * @notice Interface for the Relay cross-chain oracle adapter
 */
interface IRelay {
    // ═══════════════════════════════════════════════════════════════════════
    // TYPES
    // ═══════════════════════════════════════════════════════════════════════

    enum AssertionStatus {
        Unknown,
        Pending,
        Disputed,
        Resolved,
        Rejected
    }

    struct Assertion {
        bytes32 assertionId;
        bytes32 marketId;
        bytes32 sourceChainId;
        address asserter;
        bytes32 questionId;
        uint256 outcomeSlotCount;
        uint256 proposalBond;
        uint256 liveness;
        uint256 createdAt;
        uint256 resolvedAt;
        AssertionStatus status;
        uint256[] payouts;
        bytes ancillaryData;
    }

    // ═══════════════════════════════════════════════════════════════════════
    // EVENTS
    // ═══════════════════════════════════════════════════════════════════════

    event AssertionReceived(
        bytes32 indexed assertionId,
        bytes32 indexed marketId,
        bytes32 indexed sourceChainId,
        address asserter,
        bytes32 questionId
    );

    event AssertionForwarded(
        bytes32 indexed assertionId,
        bytes32 indexed oracleQuestionId
    );

    event AssertionResolved(
        bytes32 indexed assertionId,
        bytes32 indexed marketId,
        uint256[] payouts
    );

    event ResolutionBroadcast(
        bytes32 indexed assertionId,
        bytes32 indexed targetChainId,
        bytes32 messageId
    );

    // ═══════════════════════════════════════════════════════════════════════
    // FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════

    /**
     * @notice Receive and process a Warp message from spoke chain
     */
    function receiveWarpMessage(uint32 messageIndex) external;

    /**
     * @notice Resolve an assertion after liveness period
     */
    function resolveAssertion(bytes32 assertionId) external;

    /**
     * @notice Broadcast resolution to spoke chain
     */
    function broadcastResolution(bytes32 assertionId) external returns (bytes32 messageId);

    /**
     * @notice Create assertion locally on C-Chain
     */
    function createLocalAssertion(
        bytes32 marketId,
        bytes32 questionId,
        uint256 outcomeSlotCount,
        uint256 proposalBond,
        uint256 liveness,
        bytes calldata ancillaryData
    ) external returns (bytes32 assertionId);

    /**
     * @notice Get assertion data
     */
    function getAssertion(bytes32 assertionId) external view returns (Assertion memory);

    /**
     * @notice Check if assertion is resolved
     */
    function isResolved(bytes32 assertionId) external view returns (bool);

    /**
     * @notice Get assertion payouts
     */
    function getPayouts(bytes32 assertionId) external view returns (uint256[] memory);

    /**
     * @notice Check if assertion is ready for resolution
     */
    function isReady(bytes32 assertionId) external view returns (bool);
}
