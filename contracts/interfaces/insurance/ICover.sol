// SPDX-License-Identifier: MIT
pragma solidity ^0.8.31;

/**
 * @title ICover
 * @author Lux Industries
 * @notice Interface for protocol cover/insurance against smart contract risks
 * @dev Provides protection against hacks, exploits, and protocol failures
 */
interface ICover {
    // ═══════════════════════════════════════════════════════════════════════
    // TYPES
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice Claim status
    enum ClaimStatus {
        PENDING,
        APPROVED,
        DENIED,
        PAID
    }

    /// @notice Cover type
    enum CoverType {
        PROTOCOL,     // Smart contract risk
        CUSTODY,      // Custodial risk (bridges, CEX)
        DEFI,         // DeFi composability risk
        STABLECOIN    // Depeg protection
    }

    /**
     * @notice Insurance pool data
     * @param poolId Pool identifier
     * @param name Pool name
     * @param protocol Protocol address being covered
     * @param coverType Type of coverage
     * @param totalCapacity Max coverage capacity
     * @param usedCapacity Currently in-use capacity
     * @param stakedAmount Total staked by underwriters
     * @param basePremiumBps Base annual premium in basis points
     * @param utilizationCap Max utilization percentage
     * @param active Whether pool is active
     */
    struct Pool {
        bytes32 poolId;
        string name;
        address protocol;
        CoverType coverType;
        uint256 totalCapacity;
        uint256 usedCapacity;
        uint256 stakedAmount;
        uint256 basePremiumBps;
        uint256 utilizationCap;
        bool active;
    }

    /**
     * @notice Insurance policy data
     * @param poolId Insurance pool
     * @param holder Policy owner
     * @param coverAmount Coverage amount
     * @param premiumPaid Total premium paid
     * @param startTime Coverage start time
     * @param endTime Coverage end time
     * @param active Whether policy is active
     */
    struct Policy {
        bytes32 poolId;
        address holder;
        uint256 coverAmount;
        uint256 premiumPaid;
        uint256 startTime;
        uint256 endTime;
        bool active;
    }

    /**
     * @notice Claim data
     * @param policyId Policy NFT ID
     * @param poolId Pool identifier
     * @param claimant Who filed the claim
     * @param amount Claim amount
     * @param evidence IPFS hash or description
     * @param submittedAt Filing timestamp
     * @param votesFor Approval votes
     * @param votesAgainst Rejection votes
     * @param votingDeadline Voting end time
     * @param status Current claim status
     */
    struct Claim {
        uint256 policyId;
        bytes32 poolId;
        address claimant;
        uint256 amount;
        string evidence;
        uint256 submittedAt;
        uint256 votesFor;
        uint256 votesAgainst;
        uint256 votingDeadline;
        ClaimStatus status;
    }

    /**
     * @notice Underwriter stake data
     * @param poolId Pool staked in
     * @param amount Staked amount
     * @param stakedAt Stake timestamp
     * @param lastRewardClaim Last reward claim time
     */
    struct Stake {
        bytes32 poolId;
        uint256 amount;
        uint256 stakedAt;
        uint256 lastRewardClaim;
    }

    // ═══════════════════════════════════════════════════════════════════════
    // ERRORS
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice Thrown when pool does not exist
    error PoolNotFound();

    /// @notice Thrown when pool is not active
    error PoolNotActive();

    /// @notice Thrown when pool capacity is insufficient
    error InsufficientCapacity();

    /// @notice Thrown when cover duration is invalid
    error InvalidDuration();

    /// @notice Thrown when amount is invalid
    error InvalidAmount();

    /// @notice Thrown when policy does not exist
    error PolicyNotFound();

    /// @notice Thrown when policy has expired
    error PolicyExpired();

    /// @notice Thrown when policy is not active
    error PolicyNotActive();

    /// @notice Thrown when claim does not exist
    error ClaimNotFound();

    /// @notice Thrown when claim is already resolved
    error ClaimAlreadyResolved();

    /// @notice Thrown when voting period has not ended
    error VotingNotEnded();

    /// @notice Thrown when voting period has ended
    error VotingEnded();

    /// @notice Thrown when user has already voted
    error AlreadyVoted();

    /// @notice Thrown when stake is insufficient
    error InsufficientStake();

    /// @notice Thrown when stake is locked (backing active policies)
    error StakeLocked();

    // ═══════════════════════════════════════════════════════════════════════
    // EVENTS
    // ═══════════════════════════════════════════════════════════════════════

    /**
     * @notice Emitted when a pool is created
     * @param poolId Pool identifier
     * @param name Pool name
     * @param protocol Protocol address
     * @param coverType Type of coverage
     * @param basePremiumBps Base annual premium
     */
    event PoolCreated(
        bytes32 indexed poolId,
        string name,
        address indexed protocol,
        CoverType coverType,
        uint256 basePremiumBps
    );

    /**
     * @notice Emitted when cover is purchased
     * @param policyId Policy NFT ID
     * @param poolId Pool identifier
     * @param holder Policy holder
     * @param coverAmount Coverage amount
     * @param premium Premium paid
     * @param duration Coverage duration
     */
    event CoverPurchased(
        uint256 indexed policyId,
        bytes32 indexed poolId,
        address indexed holder,
        uint256 coverAmount,
        uint256 premium,
        uint256 duration
    );

    /**
     * @notice Emitted when underwriter stakes
     * @param underwriter Staker address
     * @param poolId Pool identifier
     * @param amount Amount staked
     */
    event Staked(
        address indexed underwriter,
        bytes32 indexed poolId,
        uint256 amount
    );

    /**
     * @notice Emitted when underwriter unstakes
     * @param underwriter Staker address
     * @param poolId Pool identifier
     * @param amount Amount unstaked
     */
    event Unstaked(
        address indexed underwriter,
        bytes32 indexed poolId,
        uint256 amount
    );

    /**
     * @notice Emitted when a claim is submitted
     * @param claimId Claim identifier
     * @param policyId Policy NFT ID
     * @param claimant Who filed the claim
     * @param amount Claim amount
     */
    event ClaimSubmitted(
        uint256 indexed claimId,
        uint256 indexed policyId,
        address indexed claimant,
        uint256 amount
    );

    /**
     * @notice Emitted when a claim vote is cast
     * @param claimId Claim identifier
     * @param voter Voter address
     * @param approve Whether vote is to approve
     * @param weight Vote weight
     */
    event ClaimVoted(
        uint256 indexed claimId,
        address indexed voter,
        bool approve,
        uint256 weight
    );

    /**
     * @notice Emitted when a claim is resolved
     * @param claimId Claim identifier
     * @param status Final status
     * @param payout Payout amount (0 if denied)
     */
    event ClaimResolved(
        uint256 indexed claimId,
        ClaimStatus status,
        uint256 payout
    );

    /**
     * @notice Emitted when staking rewards are claimed
     * @param underwriter Staker address
     * @param poolId Pool identifier
     * @param amount Reward amount
     */
    event RewardsClaimed(
        address indexed underwriter,
        bytes32 indexed poolId,
        uint256 amount
    );

    // ═══════════════════════════════════════════════════════════════════════
    // POOL MANAGEMENT
    // ═══════════════════════════════════════════════════════════════════════

    /**
     * @notice Create a new insurance pool
     * @dev Must be called by ADMIN_ROLE
     * @param name Pool name
     * @param protocol Protocol address being covered
     * @param coverType Type of coverage
     * @param basePremiumBps Base annual premium rate
     * @param utilizationCap Maximum utilization percentage
     * @return poolId New pool identifier
     */
    function createPool(
        string calldata name,
        address protocol,
        CoverType coverType,
        uint256 basePremiumBps,
        uint256 utilizationCap
    ) external returns (bytes32 poolId);

    // ═══════════════════════════════════════════════════════════════════════
    // UNDERWRITING
    // ═══════════════════════════════════════════════════════════════════════

    /**
     * @notice Stake capital to underwrite a pool
     * @param poolId Pool to stake in
     * @param amount Amount to stake
     */
    function stake(bytes32 poolId, uint256 amount) external;

    /**
     * @notice Unstake capital from a pool
     * @param poolId Pool to unstake from
     * @param amount Amount to unstake
     */
    function unstake(bytes32 poolId, uint256 amount) external;

    // ═══════════════════════════════════════════════════════════════════════
    // COVER PURCHASE
    // ═══════════════════════════════════════════════════════════════════════

    /**
     * @notice Purchase cover for a protocol
     * @param poolId Pool to purchase from
     * @param coverAmount Amount of coverage
     * @param duration Duration in seconds
     * @return policyId New policy NFT ID
     */
    function buyCover(
        bytes32 poolId,
        uint256 coverAmount,
        uint256 duration
    ) external returns (uint256 policyId);

    /**
     * @notice Renew an existing cover policy
     * @param policyId Policy to renew
     * @param additionalDuration Additional duration to add
     * @return newPremium Premium paid for renewal
     */
    function renewCover(uint256 policyId, uint256 additionalDuration) external returns (uint256 newPremium);

    // ═══════════════════════════════════════════════════════════════════════
    // CLAIMS
    // ═══════════════════════════════════════════════════════════════════════

    /**
     * @notice Submit a claim for a policy
     * @param policyId Policy NFT ID
     * @param amount Claim amount
     * @param evidence IPFS hash or evidence description
     * @return claimId New claim identifier
     */
    function fileClaim(
        uint256 policyId,
        uint256 amount,
        string calldata evidence
    ) external returns (uint256 claimId);

    /**
     * @notice Vote on a pending claim
     * @dev Must be called by ASSESSOR_ROLE
     * @param claimId Claim to vote on
     * @param approve True to approve, false to deny
     */
    function voteClaim(uint256 claimId, bool approve) external;

    /**
     * @notice Resolve a claim after voting period
     * @param claimId Claim to resolve
     */
    function resolveClaim(uint256 claimId) external;

    // ═══════════════════════════════════════════════════════════════════════
    // VIEW FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════

    /**
     * @notice Get pool details
     * @param poolId Pool identifier
     * @return Pool data
     */
    function getPool(bytes32 poolId) external view returns (Pool memory);

    /**
     * @notice Get policy details
     * @param policyId Policy NFT ID
     * @return Policy data
     */
    function getPolicy(uint256 policyId) external view returns (Policy memory);

    /**
     * @notice Get claim details
     * @param claimId Claim identifier
     * @return Claim data
     */
    function getClaim(uint256 claimId) external view returns (Claim memory);

    /**
     * @notice Get underwriter stake
     * @param underwriter Staker address
     * @param poolId Pool identifier
     * @return Stake data
     */
    function getStake(address underwriter, bytes32 poolId) external view returns (Stake memory);

    /**
     * @notice Calculate cover price
     * @param poolId Pool identifier
     * @param coverAmount Coverage amount
     * @param duration Duration in seconds
     * @return Premium amount
     */
    function getCoverPrice(
        bytes32 poolId,
        uint256 coverAmount,
        uint256 duration
    ) external view returns (uint256);

    /**
     * @notice Get pool utilization percentage
     * @param poolId Pool identifier
     * @return Utilization in basis points (e.g., 5000 = 50%)
     */
    function getPoolUtilization(bytes32 poolId) external view returns (uint256);
}
