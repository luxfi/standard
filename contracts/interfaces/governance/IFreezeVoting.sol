// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.31;

/**
 * @title IFreezeVoting
 * @notice Interface for freeze voting mechanisms
 * @dev Allows parent DAOs or token holders to freeze child DAOs
 *
 * Freeze mechanics:
 * - Votes accumulate towards threshold within proposal period
 * - Freeze activates immediately when threshold reached
 * - lastFreezeTime is NEVER cleared (security invariant)
 * - Ensures all pre-freeze timelocked transactions are invalidated
 */
interface IFreezeVoting {
    // ======================================================================
    // ERRORS
    // ======================================================================

    error NoVotes();
    error AlreadyVoted();
    error NotAuthorized();
    error InvalidAddress();
    error FreezeProposalExpired();

    // ======================================================================
    // EVENTS
    // ======================================================================

    /// @notice Emitted when a freeze vote is cast
    event FreezeVoteCast(address indexed voter, uint256 weight);

    /// @notice Emitted when the DAO becomes frozen
    event DAOFrozen(uint256 timestamp);

    /// @notice Emitted when the DAO is unfrozen
    event DAOUnfrozen(uint256 timestamp);

    // ======================================================================
    // STRUCTS
    // ======================================================================

    struct FreezeProposal {
        /// @notice Timestamp when proposal was created
        uint48 createdAt;
        /// @notice Accumulated votes for freeze
        uint256 voteCount;
    }

    // ======================================================================
    // VIEW FUNCTIONS
    // ======================================================================

    /// @notice Check if the DAO is currently frozen
    function isFrozen() external view returns (bool);

    /// @notice Get the last freeze timestamp (never cleared)
    function lastFreezeTime() external view returns (uint48);

    /// @notice Get current freeze proposal creation timestamp
    function freezeProposalCreated() external view returns (uint48);

    /// @notice Get current freeze proposal vote count
    function freezeProposalVoteCount() external view returns (uint256);

    /// @notice Get freeze proposal period duration
    function freezeProposalPeriod() external view returns (uint32);

    /// @notice Get freeze votes threshold
    function freezeVotesThreshold() external view returns (uint256);

    // ======================================================================
    // STATE-CHANGING FUNCTIONS
    // ======================================================================

    /// @notice Cast a freeze vote
    function castFreezeVote() external;
}
