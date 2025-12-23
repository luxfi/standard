// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.30;

/**
 * @title IFreezeVotingMultisigV1
 * @notice Freeze voting implementation for multisig-based parent DAOs
 * @dev This contract enables signers of a multisig parent Safe to vote to freeze
 * a child DAO. Unlike the Azorius variant which uses voting adapters for weight
 * calculation, this implementation gives each Safe signer exactly one vote.
 *
 * Key features:
 * - One vote per signer (not weighted)
 * - Automatic new freeze proposal creation if previous one expired
 * - Simple signer verification through parent Safe
 * - Light Account support for gasless voting
 *
 * Freeze voting process:
 * 1. If no active proposal exists, first voter creates one automatically
 * 2. Each signer of the parent Safe can cast one vote
 * 3. When threshold is reached, child DAO is immediately frozen
 * 4. Parent Safe (owner) can unfreeze at any time
 *
 * Security model:
 * - Only current signers of parent Safe can vote
 * - Each signer can only vote once per proposal
 * - Threshold typically requires majority of signers
 */
interface IFreezeVotingMultisigV1 {
    // --- Errors ---

    /** @notice Thrown when a signer attempts to vote twice on the same proposal */
    error AlreadyVoted();

    /** @notice Thrown when a non-signer attempts to vote */
    error NoVotingWeight();

    // --- Events ---

    /**
     * @notice Emitted when a new freeze proposal is created
     * @param creator The signer who triggered the proposal creation (first voter)
     */
    event FreezeProposalCreated(address indexed creator);

    // --- Initializer Functions ---

    /**
     * @notice Initializes the freeze voting contract for a multisig parent Safe
     * @param owner_ The parent Safe that will have unfreeze powers
     * @param freezeVotesThreshold_ Number of signer votes required to freeze
     * @param freezeProposalPeriod_ Duration in seconds that freeze proposals remain active
     * @param parentSafe_ The parent multisig Safe contract address
     * @param lightAccountFactory Factory for Light Account support (ERC-4337)
     */
    function initialize(
        address owner_,
        uint256 freezeVotesThreshold_,
        uint32 freezeProposalPeriod_,
        address parentSafe_,
        address lightAccountFactory
    ) external;

    // --- View Functions ---

    /**
     * @notice Returns the parent multisig Safe contract
     * @dev Used to verify signer status for voting eligibility
     * @return parentSafe The parent Safe address
     */
    function parentSafe() external view returns (address parentSafe);

    /**
     * @notice Checks if an account has already voted on a specific freeze proposal
     * @param freezeProposalCreated_ The timestamp identifying the freeze proposal
     * @param account_ The account to check
     * @return accountHasFreezeVoted True if the account has voted on this proposal
     */
    function accountHasFreezeVoted(
        uint48 freezeProposalCreated_,
        address account_
    ) external view returns (bool accountHasFreezeVoted);

    // --- State-Changing Functions ---

    /**
     * @notice Casts a freeze vote as a signer of the parent Safe
     * @dev If no active freeze proposal exists, creates one automatically.
     * Caller must be a current signer of the parent Safe. Each signer can
     * only vote once per proposal. If votes reach threshold, child DAO is
     * immediately frozen.
     * @param lightAccountIndex_ Index for Light Account resolution (0 for direct voting)
     * @custom:throws NoVotingWeight if caller is not a current Safe signer
     * @custom:throws AlreadyVoted if signer has already voted on this proposal
     * @custom:emits FreezeProposalCreated if new proposal started
     * @custom:emits FreezeVoteCast with voter address and weight of 1
     */
    function castFreezeVote(uint256 lightAccountIndex_) external;

    /**
     * @notice Allows the owner to manually unfreeze the child DAO
     * @dev Only the parent DAO (owner) can call this function. Resets all freeze
     * state including proposal counts and frozen status.
     * @custom:access Restricted to owner (parent DAO)
     */
    function unfreeze() external;
}
