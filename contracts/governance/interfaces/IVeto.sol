// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.31;

/**
 * @title IVeto
 * @notice Interface for veto voting mechanisms
 * @dev Allows parent DAOs or token holders to veto child DAOs
 *
 * Veto mechanics:
 * - Votes accumulate towards threshold within proposal period
 * - Veto activates immediately when threshold reached
 * - lastVetoTime is NEVER cleared (security invariant)
 * - Ensures all pre-veto timelocked transactions are invalidated
 */
interface IVeto {
    // ======================================================================
    // ERRORS
    // ======================================================================

    error NoVotes();
    error AlreadyVoted();
    error NotAuthorized();
    error InvalidAddress();
    error VetoProposalExpired();

    // ======================================================================
    // EVENTS
    // ======================================================================

    /// @notice Emitted when a veto vote is cast
    event VetoVoteCast(address indexed voter, uint256 weight);

    /// @notice Emitted when the DAO is vetoed
    event DAOVetoed(uint256 timestamp);

    /// @notice Emitted when the DAO veto is lifted
    event DAOVetoLifted(uint256 timestamp);

    // ======================================================================
    // STRUCTS
    // ======================================================================

    struct VetoProposal {
        /// @notice Timestamp when proposal was created
        uint48 createdAt;
        /// @notice Accumulated votes for veto
        uint256 voteCount;
    }

    // ======================================================================
    // VIEW FUNCTIONS
    // ======================================================================

    /// @notice Check if the DAO is currently vetoed
    function isVetoed() external view returns (bool);

    /// @notice Get the last veto timestamp (never cleared)
    function lastVetoTime() external view returns (uint48);

    /// @notice Get current veto proposal creation timestamp
    function vetoProposalCreated() external view returns (uint48);

    /// @notice Get current veto proposal vote count
    function vetoProposalVoteCount() external view returns (uint256);

    /// @notice Get veto proposal period duration
    function vetoProposalPeriod() external view returns (uint32);

    /// @notice Get veto votes threshold
    function vetoVotesThreshold() external view returns (uint256);

    // ======================================================================
    // STATE-CHANGING FUNCTIONS
    // ======================================================================

    /// @notice Cast a veto vote
    function castVetoVote() external;
}
