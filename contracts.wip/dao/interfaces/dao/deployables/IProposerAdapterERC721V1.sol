// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.28;

import {IProposerAdapterBaseV1} from "./IProposerAdapterBaseV1.sol";

/**
 * @title IProposerAdapterERC721V1
 * @notice Proposer adapter that uses NFT ownership for eligibility
 * @dev Determines proposal creation eligibility based on the number of NFTs owned.
 * Works with standard ERC721 contracts without requiring special interfaces.
 *
 * Eligibility criteria:
 * - Proposer must own NFTs >= proposerThreshold
 * - Uses token.balanceOf() to count NFTs
 * - Checks current ownership (not historical)
 * - The data parameter in isProposer() is ignored
 *
 * Common use case: NFT-based DAOs where proposal rights are tied to
 * NFT collection ownership (e.g., own 1+ NFTs to propose).
 */
interface IProposerAdapterERC721V1 is IProposerAdapterBaseV1 {
    // --- Initializer Functions ---

    /**
     * @notice Initializes the adapter with NFT token and threshold configuration
     * @param token_ The ERC721 NFT contract address
     * @param proposerThreshold_ Minimum number of NFTs required to create proposals
     */
    function initialize(address token_, uint256 proposerThreshold_) external;

    // --- View Functions ---

    /**
     * @notice Returns the ERC721 token used for ownership checks
     * @return token The NFT contract address
     */
    function token() external view returns (address token);

    /**
     * @notice Returns the minimum number of NFTs required to create proposals
     * @return proposerThreshold The threshold value
     */
    function proposerThreshold()
        external
        view
        returns (uint256 proposerThreshold);
}
