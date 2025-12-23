// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.30;

/**
 * @title IVotingWeightERC721V1
 * @notice Interface for ERC721 voting weight calculation
 * @dev ERC721-specific functionality for voting weight calculation.
 * This interface provides access to the weight per token configuration.
 * Implementations should also implement IVotingWeightV1.
 */
interface IVotingWeightERC721V1 {
    // --- Errors ---

    /** @notice Thrown when voteData contains no token IDs */
    error NoTokenIds();

    /** @notice Thrown when voteData contains duplicate token IDs */
    error DuplicateTokenId(uint256 tokenId);

    /** @notice Thrown when voter doesn't own a token ID */
    error NotTokenOwner(uint256 tokenId, address actualOwner);

    // --- Initializer Functions ---

    /**
     * @notice Initializes the voting weight strategy for an ERC721 token
     * @param token_ The NFT token address
     * @param weightPerToken_ The voting weight per NFT owned
     */
    function initialize(address token_, uint256 weightPerToken_) external;

    // --- View Functions ---

    /**
     * @notice Returns the address of the NFT used for voting weight
     * @dev Used by frontends to display token information
     * @return tokenAddress The NFT contract address
     */
    function token() external view returns (address tokenAddress);

    /**
     * @notice Returns the weight per NFT token
     * @dev Useful for frontends to display voting power calculations
     * @return weightPerToken The voting weight granted by each NFT
     */
    function weightPerToken() external view returns (uint256 weightPerToken);
}
