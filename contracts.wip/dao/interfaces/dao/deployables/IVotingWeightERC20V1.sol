// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.28;

/**
 * @title IVotingWeightERC20V1
 * @notice Interface for ERC20 voting weight calculation
 * @dev ERC20-specific functionality for voting weight calculation.
 * This interface provides access to the weight multiplier configuration.
 * Implementations should also implement IVotingWeightV1.
 */
interface IVotingWeightERC20V1 {
    // --- Initializer Functions ---

    /**
     * @notice Initializes the voting weight strategy for an ERC20 token
     * @dev The token must implement IVotes (ERC20Votes or similar)
     * @param token_ The voting token address
     * @param weightPerToken_ The voting weight multiplier per token (use 1e18 for 1:1)
     */
    function initialize(address token_, uint256 weightPerToken_) external;

    // --- View Functions ---

    /**
     * @notice Returns the address of the token used for voting weight
     * @dev Used by frontends to display token information
     * @return tokenAddress The token contract address
     */
    function token() external view returns (address tokenAddress);

    /**
     * @notice Returns the weight multiplier per token
     * @dev Useful for frontends to display voting power calculations
     * @return weightPerToken The multiplier applied to token balances
     */
    function weightPerToken() external view returns (uint256 weightPerToken);
}
