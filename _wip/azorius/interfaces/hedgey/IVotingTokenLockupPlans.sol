// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.30;

interface IVotingTokenLockupPlans {
    /// @notice function to create a lockup plan.
    /// @dev this function will pull the tokens into this contract for escrow, increment the planIds, mint an NFT to the recipient, and create the storage Plan and map it to the newly minted NFT token ID in storage
    /// @param recipient the address of the recipient and beneficiary of the plan
    /// @param token the address of the ERC20 token
    /// @param amount the amount of tokens to be locked in the plan
    /// @param start the start date of the lockup plan, unix time
    /// @param cliff a cliff date which is a discrete date where tokens are not unlocked until this date, and then vest in a large single chunk on the cliff date
    /// @param rate the amount of tokens that vest in a single period
    /// @param period the amount of time in between each unlock time stamp, in seconds. A period of 1 means that tokens vest every second in a 'streaming' style.
    function createPlan(
        address recipient,
        address token,
        uint256 amount,
        uint256 start,
        uint256 cliff,
        uint256 rate,
        uint256 period
    ) external returns (uint256 newPlanId);
}
