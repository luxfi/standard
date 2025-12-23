// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.28;

import {IProposerAdapterBaseV1} from "./IProposerAdapterBaseV1.sol";

/**
 * @title IProposerAdapterERC20V1
 * @notice Proposer adapter that uses ERC20 voting power for eligibility
 * @dev Determines proposal creation eligibility based on voting token balance.
 * The token must implement the IVotes interface (e.g., VotesERC20V1) to provide
 * voting power calculations including delegated votes.
 *
 * Eligibility criteria:
 * - Proposer must have voting power >= proposerThreshold
 * - Uses token.getVotes() which includes delegated voting power
 * - Checks current voting power (not historical)
 * - The data parameter in isProposer() is ignored
 *
 * Common use case: DAOs using governance tokens where proposal rights are
 * tied to token holdings or delegated voting power.
 */
interface IProposerAdapterERC20V1 is IProposerAdapterBaseV1 {
    // --- Initializer Functions ---

    /**
     * @notice Initializes the adapter with token and threshold configuration
     * @param token_ The ERC20 token address (must implement IVotes)
     * @param proposerThreshold_ Minimum voting power required to create proposals
     */
    function initialize(address token_, uint256 proposerThreshold_) external;

    // --- View Functions ---

    /**
     * @notice Returns the ERC20 token used for voting power checks
     * @return token The token contract address
     */
    function token() external view returns (address token);

    /**
     * @notice Returns the minimum voting power required to create proposals
     * @return proposerThreshold The threshold value
     */
    function proposerThreshold()
        external
        view
        returns (uint256 proposerThreshold);
}
