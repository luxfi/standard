// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.28;

/**
 * @title IVotesERC20StakedV1
 * @notice Non-transferable staking token with reward distribution capabilities
 * @dev This interface defines a staking system where users stake an underlying ERC20
 * token and receive non-transferable staking tokens in return. The contract distributes
 * multiple reward tokens proportionally to stakers based on their stake and time staked.
 *
 * Key features:
 * - Stake ERC20 tokens to receive non-transferable staking tokens
 * - Non-transferable staking shares (soulbound)
 * - Multiple reward token distribution
 * - Minimum staking period enforcement
 * - Proportional reward distribution based on stake
 * - IVotes compatibility for governance
 *
 * Mechanics:
 * - 1:1 minting of staking tokens for staked underlying tokens
 * - Staking tokens implement IVotes (can be used for voting if configured)
 * - Rewards accumulate based on stake size and time
 * - Unstaking subject to minimum period
 * - Anyone can trigger reward distribution
 *
 * Use cases:
 * - veToken-style governance systems
 * - Staking rewards distribution
 * - Long-term alignment incentives
 * - Protocol revenue sharing
 */
interface IVotesERC20StakedV1 {
    // --- Errors ---

    /** @notice Thrown when attempting to transfer staking tokens (they are non-transferable) */
    error NonTransferable();

    /** @notice Thrown when attempting to stake zero tokens */
    error ZeroStake();

    /** @notice Thrown when attempting to unstake zero tokens */
    error ZeroUnstake();

    /** @notice Thrown when user has no staked tokens */
    error ZeroStaked();

    /** @notice Thrown when adding an invalid reward token (e.g., staking token itself) */
    error InvalidRewardsToken(address token);

    /** @notice Thrown when adding a reward token that's already registered */
    error DuplicateRewardsToken();

    /** @notice Thrown when unstaking before minimum staking period */
    error MinimumStakingPeriod();

    /** @notice Thrown when reward token transfer fails */
    error TransferFailed();

    // --- Structs ---

    /**
     * @notice Token metadata
     * @param name The staking token name (e.g., "Staked MyDAO")
     * @param symbol The staking token symbol (e.g., "sMYDAO")
     */
    struct Metadata {
        string name;
        string symbol;
    }

    /**
     * @notice Staking information for an address
     * @param stakedAmount Total tokens currently staked
     * @param lastStakeTimestamp When the user last staked (for minimum period)
     */
    struct StakerData {
        uint256 stakedAmount;
        uint256 lastStakeTimestamp;
    }

    /**
     * @notice Reward token configuration and accounting
     * @param enabled Whether this token is registered for rewards
     * @param rewardsRate Current reward rate per staked token (18 decimals)
     * @param rewardsDistributed Total rewards distributed for this token
     * @param rewardsClaimed Total rewards claimed by all stakers
     * @param stakerRewardsRates Individual staker's last checkpoint rate
     * @param stakerAccumulatedRewards Unclaimed rewards per staker
     */
    struct RewardsTokenData {
        bool enabled;
        uint256 rewardsRate;
        uint256 rewardsDistributed;
        uint256 rewardsClaimed;
        mapping(address staker => uint256 rewardRate) stakerRewardsRates;
        mapping(address staker => uint256 accumulatedRewards) stakerAccumulatedRewards;
    }

    // --- Events ---

    /**
     * @notice Emitted when the minimum staking period is updated
     * @param newMinimumStakingPeriod The new minimum period in seconds
     */
    event MinimumStakingPeriodUpdated(uint256 newMinimumStakingPeriod);

    /**
     * @notice Emitted when tokens are staked
     * @param staker The address that staked
     * @param amount The amount of tokens staked
     */
    event Staked(address indexed staker, uint256 amount);

    /**
     * @notice Emitted when tokens are unstaked
     * @param staker The address that unstaked
     * @param amount The amount of tokens unstaked
     */
    event Unstaked(address indexed staker, uint256 amount);

    /**
     * @notice Emitted when a new reward token is added
     * @param token The reward token address
     */
    event RewardsTokenAdded(address indexed token);

    /**
     * @notice Emitted when rewards are distributed
     * @param token The reward token distributed
     * @param amount The amount distributed
     * @param newRate The new reward rate per staked token
     */
    event RewardsDistributed(
        address indexed token,
        uint256 amount,
        uint256 newRate
    );

    /**
     * @notice Emitted when a staker claims rewards
     * @param staker The staker claiming rewards
     * @param token The reward token claimed
     * @param recipient The address receiving the rewards
     * @param amount The amount of rewards claimed
     */
    event RewardsClaimed(
        address indexed staker,
        address indexed token,
        address indexed recipient,
        uint256 amount
    );

    // --- Initializer Functions ---

    /**
     * @notice Initializes the staking contract (part 1 of 2)
     * @dev Split initialization is required for contract address to depend only upon
     * owner address and staked token address.
     * @param owner_ Address that will have owner privileges
     * @param stakedToken_ The ERC20 token that users will stake
     */
    function initialize(address owner_, address stakedToken_) external;

    /**
     * @notice Completes initialization with metadata, minimum staking period, and rewards tokens (part 2 of 2)
     * @dev Can only be called once during deployment. Sets up the staking token
     * and initial reward tokens. The staking token itself cannot be a reward token.
     * @param minimumStakingPeriod_ Minimum seconds before unstaking allowed
     * @param rewardsTokens_ Initial array of reward token addresses
     */
    function initialize2(
        uint256 minimumStakingPeriod_,
        address[] calldata rewardsTokens_
    ) external;

    // --- Pure Functions ---

    /**
     * @notice Returns the clock mode for voting snapshots
     * @dev Returns "mode=timestamp" indicating timestamp-based timing
     * @return clockMode The clock mode string per EIP-6372
     */
    function CLOCK_MODE() external pure returns (string memory clockMode);
    // solhint-disable-previous-line func-name-mixedcase

    // --- View Functions ---

    /**
     * @notice Returns the current clock value (timestamp)
     * @dev Used for voting snapshot timing
     * @return clock The current timestamp as uint48
     */
    function clock() external view returns (uint48 clock);

    /**
     * @notice Returns the token that users stake
     * @return stakedToken The ERC20 token address
     */
    function stakedToken() external view returns (address stakedToken);

    /**
     * @notice Returns the minimum staking period
     * @return minimumStakingPeriod Seconds that must pass before unstaking
     */
    function minimumStakingPeriod()
        external
        view
        returns (uint256 minimumStakingPeriod);

    /**
     * @notice Returns the total amount of tokens staked
     * @return totalStaked Sum of all staked tokens
     */
    function totalStaked() external view returns (uint256 totalStaked);

    /**
     * @notice Returns all registered reward token addresses
     * @return rewardsTokens Array of reward token addresses
     */
    function rewardsTokens()
        external
        view
        returns (address[] memory rewardsTokens);

    /**
     * @notice Returns reward token statistics
     * @param token_ The reward token to query
     * @return rewardsRate Current rate per staked token (18 decimals)
     * @return rewardsDistributed Total distributed for this token
     * @return rewardsClaimed Total claimed by all stakers
     */
    function rewardsTokenData(
        address token_
    )
        external
        view
        returns (
            uint256 rewardsRate,
            uint256 rewardsDistributed,
            uint256 rewardsClaimed
        );

    /**
     * @notice Returns available rewards to distribute for all tokens
     * @dev Calculates contract balance minus already distributed amounts
     * @return distributableRewards Array of amounts per reward token
     */
    function distributableRewards()
        external
        view
        returns (uint256[] memory distributableRewards);

    /**
     * @notice Returns available rewards to distribute for specific tokens
     * @param rewardsTokens_ Array of reward tokens to check
     * @return distributableRewards Array of amounts per token
     */
    function distributableRewards(
        address[] calldata rewardsTokens_
    ) external view returns (uint256[] memory distributableRewards);

    /**
     * @notice Returns staking data for an address
     * @param staker_ The staker to query
     * @return stakedAmount Tokens currently staked
     * @return lastStakeTimestamp When last stake occurred
     */
    function stakerData(
        address staker_
    ) external view returns (uint256 stakedAmount, uint256 lastStakeTimestamp);

    /**
     * @notice Returns reward data for a staker and token
     * @param token_ The reward token
     * @param staker_ The staker address
     * @return rewardRate Staker's last checkpoint rate
     * @return accumulatedRewards Unclaimed rewards for this token
     */
    function stakerRewardsData(
        address token_,
        address staker_
    ) external view returns (uint256 rewardRate, uint256 accumulatedRewards);

    /**
     * @notice Returns claimable rewards for all tokens
     * @param staker_ The staker to check
     * @return claimableRewards Array of claimable amounts per reward token
     */
    function claimableRewards(
        address staker_
    ) external view returns (uint256[] memory claimableRewards);

    /**
     * @notice Returns claimable rewards for specific tokens
     * @param staker_ The staker to check
     * @param tokens_ Array of reward tokens to check
     * @return claimableRewards Array of claimable amounts per token
     */
    function claimableRewards(
        address staker_,
        address[] calldata tokens_
    ) external view returns (uint256[] memory claimableRewards);

    // --- State-Changing Functions ---

    /**
     * @notice Adds new reward tokens to the contract
     * @dev Only callable by owner. Cannot add the staking token as a reward.
     * Duplicate tokens will revert.
     * @param rewardsTokens_ Array of new reward token addresses
     * @custom:access Restricted to owner
     * @custom:throws InvalidRewardsToken if token is staking token
     * @custom:throws DuplicateRewardsToken if already registered
     * @custom:emits RewardsTokenAdded for each token
     */
    function addRewardsTokens(address[] calldata rewardsTokens_) external;

    /**
     * @notice Updates the minimum staking period
     * @dev Only callable by owner. Applies to future stakes only.
     * @param newMinimumStakingPeriod_ New period in seconds
     * @custom:access Restricted to owner
     * @custom:emits MinimumStakingPeriodUpdated
     */
    function updateMinimumStakingPeriod(
        uint256 newMinimumStakingPeriod_
    ) external;

    /**
     * @notice Stakes tokens to receive voting power and rewards
     * @dev Transfers tokens from caller and mints staking tokens 1:1.
     * Updates reward checkpoints before staking.
     * @param amount_ Number of tokens to stake
     * @custom:throws ZeroStake if amount is 0
     * @custom:emits Staked
     */
    function stake(uint256 amount_) external;

    /**
     * @notice Unstakes tokens and returns the underlying asset
     * @dev Burns staking tokens and transfers underlying tokens back.
     * Subject to minimum staking period from last stake.
     * Updates reward checkpoints before unstaking.
     * @param amount_ Number of tokens to unstake
     * @custom:throws ZeroUnstake if amount is 0
     * @custom:throws ZeroStaked if no stake exists
     * @custom:throws MinimumStakingPeriod if too early
     * @custom:emits Unstaked
     */
    function unstake(uint256 amount_) external;

    /**
     * @notice Distributes pending rewards for all reward tokens
     * @dev Can be called by anyone. Updates reward rates based on
     * new rewards received since last distribution.
     * @custom:emits RewardsDistributed for each token with new rewards
     */
    function distributeRewards() external;

    /**
     * @notice Distributes pending rewards for specific tokens
     * @dev Can be called by anyone. Only processes specified tokens.
     * @param tokens_ Array of reward tokens to distribute
     * @custom:emits RewardsDistributed for each token with new rewards
     */
    function distributeRewards(address[] calldata tokens_) external;

    /**
     * @notice Claims accumulated rewards for all tokens
     * @dev Updates reward checkpoints and transfers all claimable rewards.
     * @param recipient_ Address to receive the rewards
     * @custom:emits RewardsClaimed for each claimed token
     */
    function claimRewards(address recipient_) external;

    /**
     * @notice Claims accumulated rewards for specific tokens
     * @dev Updates reward checkpoints and transfers claimable rewards.
     * @param recipient_ Address to receive the rewards
     * @param tokens_ Array of reward tokens to claim
     * @custom:emits RewardsClaimed for each claimed token
     */
    function claimRewards(
        address recipient_,
        address[] calldata tokens_
    ) external;
}
