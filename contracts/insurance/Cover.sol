// SPDX-License-Identifier: MIT
pragma solidity ^0.8.31;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";

/**
 * @title Cover
 * @author Lux Industries
 * @notice Protocol cover/insurance for smart contract risks
 * @dev Provides protection against hacks, exploits, and protocol failures
 *
 * Key features:
 * - Per-protocol risk pools
 * - Underwriter staking with rewards
 * - Claim assessment via governance
 * - NFT-based cover policies
 * - Dynamic pricing based on utilization
 */
contract Cover is ERC721, ReentrancyGuard, AccessControl, Pausable {
    using SafeERC20 for IERC20;

    // ═══════════════════════════════════════════════════════════════════════
    // TYPES
    // ═══════════════════════════════════════════════════════════════════════

    enum ClaimStatus {
        PENDING,
        APPROVED,
        DENIED,
        PAID
    }

    enum CoverType {
        PROTOCOL,     // Smart contract risk
        CUSTODY,      // Custodial risk (bridges, CEX)
        DEFI,         // DeFi composability risk
        STABLECOIN    // Depeg protection
    }

    struct Pool {
        bytes32 poolId;
        string name;
        address protocol;          // Protocol being covered
        CoverType coverType;
        uint256 totalCapacity;     // Max coverage capacity
        uint256 usedCapacity;      // Currently in-use capacity
        uint256 stakedAmount;      // Total staked by underwriters
        uint256 basePremiumBps;    // Base annual premium in bps
        uint256 utilizationCap;    // Max utilization (e.g., 8000 = 80%)
        bool active;
    }

    struct Policy {
        bytes32 poolId;
        address holder;
        uint256 coverAmount;       // Coverage amount
        uint256 premiumPaid;       // Total premium paid
        uint256 startTime;
        uint256 endTime;
        bool active;
    }

    struct Claim {
        uint256 policyId;
        bytes32 poolId;
        address claimant;
        uint256 amount;
        string evidence;           // IPFS hash or description
        uint256 submittedAt;
        uint256 votesFor;
        uint256 votesAgainst;
        uint256 votingDeadline;
        ClaimStatus status;
    }

    struct Stake {
        bytes32 poolId;
        uint256 amount;
        uint256 stakedAt;
        uint256 lastRewardClaim;
    }

    // ═══════════════════════════════════════════════════════════════════════
    // CONSTANTS
    // ═══════════════════════════════════════════════════════════════════════

    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant ASSESSOR_ROLE = keccak256("ASSESSOR_ROLE");
    bytes32 public constant UNDERWRITER_ROLE = keccak256("UNDERWRITER_ROLE");

    uint256 public constant BPS = 10000;
    uint256 public constant YEAR = 365 days;
    uint256 public constant MIN_COVER_DURATION = 7 days;
    uint256 public constant MAX_COVER_DURATION = 365 days;
    uint256 public constant CLAIM_VOTING_PERIOD = 7 days;
    uint256 public constant PAYOUT_DELAY = 3 days;

    // ═══════════════════════════════════════════════════════════════════════
    // STATE
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice Capital token (LUSD or similar stablecoin)
    IERC20 public immutable capitalToken;

    /// @notice Insurance pools
    mapping(bytes32 => Pool) public pools;

    /// @notice All pool IDs
    bytes32[] public poolIds;

    /// @notice Policies by ID
    mapping(uint256 => Policy) public policies;

    /// @notice Claims
    mapping(uint256 => Claim) public claims;

    /// @notice Underwriter stakes
    mapping(address => mapping(bytes32 => Stake)) public stakes;

    /// @notice Claim votes (claimId => voter => voted)
    mapping(uint256 => mapping(address => bool)) public claimVotes;

    /// @notice Next policy ID
    uint256 public nextPolicyId = 1;

    /// @notice Next claim ID
    uint256 public nextClaimId = 1;

    /// @notice Protocol fee in basis points
    uint256 public protocolFeeBps = 1000; // 10%

    /// @notice Fee receiver
    address public feeReceiver;

    /// @notice Treasury for payouts
    address public treasury;

    /// @notice Minimum stake amount
    uint256 public minStakeAmount = 1000e18; // 1000 tokens

    // ═══════════════════════════════════════════════════════════════════════
    // EVENTS
    // ═══════════════════════════════════════════════════════════════════════

    event PoolCreated(
        bytes32 indexed poolId,
        string name,
        address indexed protocol,
        CoverType coverType,
        uint256 basePremiumBps
    );

    event CoverPurchased(
        uint256 indexed policyId,
        bytes32 indexed poolId,
        address indexed holder,
        uint256 coverAmount,
        uint256 premium,
        uint256 duration
    );

    event Staked(
        address indexed underwriter,
        bytes32 indexed poolId,
        uint256 amount
    );

    event Unstaked(
        address indexed underwriter,
        bytes32 indexed poolId,
        uint256 amount
    );

    event ClaimSubmitted(
        uint256 indexed claimId,
        uint256 indexed policyId,
        address indexed claimant,
        uint256 amount
    );

    event ClaimVoted(
        uint256 indexed claimId,
        address indexed voter,
        bool approve,
        uint256 weight
    );

    event ClaimResolved(
        uint256 indexed claimId,
        ClaimStatus status,
        uint256 payout
    );

    event RewardsClaimed(
        address indexed underwriter,
        bytes32 indexed poolId,
        uint256 amount
    );

    // ═══════════════════════════════════════════════════════════════════════
    // ERRORS
    // ═══════════════════════════════════════════════════════════════════════

    error PoolNotFound();
    error PoolNotActive();
    error InsufficientCapacity();
    error InvalidDuration();
    error InvalidAmount();
    error PolicyNotFound();
    error PolicyExpired();
    error PolicyNotActive();
    error ClaimNotFound();
    error ClaimAlreadyResolved();
    error VotingNotEnded();
    error VotingEnded();
    error AlreadyVoted();
    error InsufficientStake();
    error StakeLocked();

    // ═══════════════════════════════════════════════════════════════════════
    // CONSTRUCTOR
    // ═══════════════════════════════════════════════════════════════════════

    constructor(
        address _capitalToken,
        address _feeReceiver,
        address _treasury,
        address _admin
    ) ERC721("Lux Cover", "COVER") {
        capitalToken = IERC20(_capitalToken);
        feeReceiver = _feeReceiver;
        treasury = _treasury;

        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        _grantRole(ADMIN_ROLE, _admin);
        _grantRole(ASSESSOR_ROLE, _admin);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // POOL MANAGEMENT
    // ═══════════════════════════════════════════════════════════════════════

    /**
     * @notice Create a new insurance pool
     * @param name Pool name
     * @param protocol Protocol address being covered
     * @param coverType Type of coverage
     * @param basePremiumBps Base annual premium rate
     * @param utilizationCap Maximum utilization percentage
     */
    function createPool(
        string calldata name,
        address protocol,
        CoverType coverType,
        uint256 basePremiumBps,
        uint256 utilizationCap
    ) external onlyRole(ADMIN_ROLE) returns (bytes32 poolId) {
        poolId = keccak256(abi.encodePacked(name, protocol, block.timestamp));

        pools[poolId] = Pool({
            poolId: poolId,
            name: name,
            protocol: protocol,
            coverType: coverType,
            totalCapacity: 0,
            usedCapacity: 0,
            stakedAmount: 0,
            basePremiumBps: basePremiumBps,
            utilizationCap: utilizationCap,
            active: true
        });

        poolIds.push(poolId);

        emit PoolCreated(poolId, name, protocol, coverType, basePremiumBps);
    }

    /**
     * @notice Set pool active status
     */
    function setPoolActive(bytes32 poolId, bool active) external onlyRole(ADMIN_ROLE) {
        Pool storage pool = pools[poolId];
        if (pool.poolId == bytes32(0)) revert PoolNotFound();
        pool.active = active;
    }

    // ═══════════════════════════════════════════════════════════════════════
    // UNDERWRITING
    // ═══════════════════════════════════════════════════════════════════════

    /**
     * @notice Stake capital to underwrite a pool
     * @param poolId Pool to stake in
     * @param amount Amount to stake
     */
    function stake(
        bytes32 poolId,
        uint256 amount
    ) external nonReentrant whenNotPaused {
        Pool storage pool = pools[poolId];
        if (pool.poolId == bytes32(0)) revert PoolNotFound();
        if (!pool.active) revert PoolNotActive();
        if (amount < minStakeAmount) revert InsufficientStake();

        capitalToken.safeTransferFrom(msg.sender, address(this), amount);

        Stake storage s = stakes[msg.sender][poolId];
        if (s.amount > 0) {
            // Claim pending rewards first
            _claimRewards(msg.sender, poolId);
        }

        s.poolId = poolId;
        s.amount += amount;
        s.stakedAt = block.timestamp;
        s.lastRewardClaim = block.timestamp;

        pool.stakedAmount += amount;
        // Capacity = 2x staked amount (leverage)
        pool.totalCapacity = pool.stakedAmount * 2;

        _grantRole(UNDERWRITER_ROLE, msg.sender);

        emit Staked(msg.sender, poolId, amount);
    }

    /**
     * @notice Unstake capital from a pool
     * @param poolId Pool to unstake from
     * @param amount Amount to unstake
     */
    function unstake(
        bytes32 poolId,
        uint256 amount
    ) external nonReentrant {
        Stake storage s = stakes[msg.sender][poolId];
        if (s.amount < amount) revert InsufficientStake();

        // Check if stake is locked due to active claims
        Pool storage pool = pools[poolId];
        if (pool.usedCapacity > 0) {
            // Can only unstake excess not backing active policies
            uint256 minStake = pool.usedCapacity / 2;
            if (pool.stakedAmount - amount < minStake) revert StakeLocked();
        }

        // Claim rewards first
        _claimRewards(msg.sender, poolId);

        s.amount -= amount;
        pool.stakedAmount -= amount;
        pool.totalCapacity = pool.stakedAmount * 2;

        capitalToken.safeTransfer(msg.sender, amount);

        emit Unstaked(msg.sender, poolId, amount);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // COVER PURCHASE
    // ═══════════════════════════════════════════════════════════════════════

    /**
     * @notice Purchase cover for a protocol
     * @param poolId Pool to purchase from
     * @param coverAmount Amount of coverage
     * @param duration Duration in seconds
     */
    function buyCover(
        bytes32 poolId,
        uint256 coverAmount,
        uint256 duration
    ) external nonReentrant whenNotPaused returns (uint256 policyId) {
        Pool storage pool = pools[poolId];
        if (pool.poolId == bytes32(0)) revert PoolNotFound();
        if (!pool.active) revert PoolNotActive();
        if (duration < MIN_COVER_DURATION || duration > MAX_COVER_DURATION) revert InvalidDuration();
        if (coverAmount == 0) revert InvalidAmount();

        // Check capacity
        uint256 newUtilization = ((pool.usedCapacity + coverAmount) * BPS) / pool.totalCapacity;
        if (newUtilization > pool.utilizationCap) revert InsufficientCapacity();

        // Calculate premium
        uint256 premium = calculatePremium(poolId, coverAmount, duration);

        // Transfer premium
        capitalToken.safeTransferFrom(msg.sender, address(this), premium);

        // Apply protocol fee
        uint256 protocolFee = (premium * protocolFeeBps) / BPS;
        if (protocolFee > 0) {
            capitalToken.safeTransfer(feeReceiver, protocolFee);
        }

        // Update pool
        pool.usedCapacity += coverAmount;

        // Create policy
        policyId = nextPolicyId++;
        policies[policyId] = Policy({
            poolId: poolId,
            holder: msg.sender,
            coverAmount: coverAmount,
            premiumPaid: premium,
            startTime: block.timestamp,
            endTime: block.timestamp + duration,
            active: true
        });

        // Mint NFT
        _mint(msg.sender, policyId);

        emit CoverPurchased(policyId, poolId, msg.sender, coverAmount, premium, duration);
    }

    /**
     * @notice Calculate premium for coverage
     * @param poolId Pool ID
     * @param coverAmount Coverage amount
     * @param duration Duration in seconds
     */
    function calculatePremium(
        bytes32 poolId,
        uint256 coverAmount,
        uint256 duration
    ) public view returns (uint256) {
        Pool storage pool = pools[poolId];
        if (pool.poolId == bytes32(0)) return 0;

        // Base premium (annualized)
        uint256 basePremium = (coverAmount * pool.basePremiumBps) / BPS;

        // Adjust for utilization (higher util = higher premium)
        uint256 utilization = pool.totalCapacity > 0
            ? (pool.usedCapacity * BPS) / pool.totalCapacity
            : 0;

        // Premium multiplier based on utilization (1x at 0%, 2x at 80%)
        uint256 multiplier = BPS + (utilization * BPS) / pool.utilizationCap;

        // Pro-rata for duration
        uint256 premium = (basePremium * duration * multiplier) / (YEAR * BPS);

        return premium;
    }

    // ═══════════════════════════════════════════════════════════════════════
    // CLAIMS
    // ═══════════════════════════════════════════════════════════════════════

    /**
     * @notice Submit a claim for a policy
     * @param policyId Policy ID
     * @param amount Claim amount
     * @param evidence IPFS hash or evidence description
     */
    function submitClaim(
        uint256 policyId,
        uint256 amount,
        string calldata evidence
    ) external nonReentrant returns (uint256 claimId) {
        Policy storage policy = policies[policyId];
        if (policy.holder == address(0)) revert PolicyNotFound();
        if (!policy.active) revert PolicyNotActive();
        if (block.timestamp > policy.endTime) revert PolicyExpired();
        if (amount > policy.coverAmount) revert InvalidAmount();

        address holder = ownerOf(policyId);
        if (msg.sender != holder) revert PolicyNotFound();

        claimId = nextClaimId++;
        claims[claimId] = Claim({
            policyId: policyId,
            poolId: policy.poolId,
            claimant: msg.sender,
            amount: amount,
            evidence: evidence,
            submittedAt: block.timestamp,
            votesFor: 0,
            votesAgainst: 0,
            votingDeadline: block.timestamp + CLAIM_VOTING_PERIOD,
            status: ClaimStatus.PENDING
        });

        emit ClaimSubmitted(claimId, policyId, msg.sender, amount);
    }

    /**
     * @notice Vote on a claim
     * @param claimId Claim ID
     * @param approve True to approve, false to deny
     */
    function voteClaim(
        uint256 claimId,
        bool approve
    ) external onlyRole(ASSESSOR_ROLE) {
        Claim storage claim = claims[claimId];
        if (claim.claimant == address(0)) revert ClaimNotFound();
        if (claim.status != ClaimStatus.PENDING) revert ClaimAlreadyResolved();
        if (block.timestamp > claim.votingDeadline) revert VotingEnded();
        if (claimVotes[claimId][msg.sender]) revert AlreadyVoted();

        claimVotes[claimId][msg.sender] = true;

        // Weight by stake in pool
        Stake storage s = stakes[msg.sender][claim.poolId];
        uint256 weight = s.amount > 0 ? s.amount : 1e18;

        if (approve) {
            claim.votesFor += weight;
        } else {
            claim.votesAgainst += weight;
        }

        emit ClaimVoted(claimId, msg.sender, approve, weight);
    }

    /**
     * @notice Resolve a claim after voting period
     * @param claimId Claim ID
     */
    function resolveClaim(uint256 claimId) external nonReentrant {
        Claim storage claim = claims[claimId];
        if (claim.claimant == address(0)) revert ClaimNotFound();
        if (claim.status != ClaimStatus.PENDING) revert ClaimAlreadyResolved();
        if (block.timestamp < claim.votingDeadline) revert VotingNotEnded();

        uint256 payout = 0;

        if (claim.votesFor > claim.votesAgainst) {
            claim.status = ClaimStatus.APPROVED;

            // Mark policy as used
            Policy storage policy = policies[claim.policyId];
            policy.active = false;

            // Update pool capacity
            Pool storage pool = pools[claim.poolId];
            pool.usedCapacity -= policy.coverAmount;

            // Payout from treasury
            payout = claim.amount;
            capitalToken.safeTransferFrom(treasury, claim.claimant, payout);

            claim.status = ClaimStatus.PAID;
        } else {
            claim.status = ClaimStatus.DENIED;
        }

        emit ClaimResolved(claimId, claim.status, payout);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // REWARDS
    // ═══════════════════════════════════════════════════════════════════════

    /**
     * @notice Claim staking rewards
     * @param poolId Pool ID
     */
    function claimRewards(bytes32 poolId) external nonReentrant returns (uint256) {
        return _claimRewards(msg.sender, poolId);
    }

    function _claimRewards(address underwriter, bytes32 poolId) internal returns (uint256 rewards) {
        Stake storage s = stakes[underwriter][poolId];
        if (s.amount == 0) return 0;

        Pool storage pool = pools[poolId];

        // Rewards from premium payments (distributed to stakers)
        // Simplified: 80% of premiums go to underwriters
        // In production, track premium accumulation more granularly

        uint256 timeStaked = block.timestamp - s.lastRewardClaim;
        uint256 poolShare = (s.amount * BPS) / pool.stakedAmount;

        // Estimate rewards based on utilization and premium rate
        uint256 estimatedPremiums = (pool.usedCapacity * pool.basePremiumBps * timeStaked) / (YEAR * BPS);
        rewards = (estimatedPremiums * poolShare * 8000) / (BPS * BPS); // 80% to underwriters

        if (rewards > 0) {
            s.lastRewardClaim = block.timestamp;
            capitalToken.safeTransfer(underwriter, rewards);
            emit RewardsClaimed(underwriter, poolId, rewards);
        }
    }

    // ═══════════════════════════════════════════════════════════════════════
    // VIEW FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════

    function getPool(bytes32 poolId) external view returns (Pool memory) {
        return pools[poolId];
    }

    function getPolicy(uint256 policyId) external view returns (Policy memory) {
        return policies[policyId];
    }

    function getClaim(uint256 claimId) external view returns (Claim memory) {
        return claims[claimId];
    }

    function getStake(address underwriter, bytes32 poolId) external view returns (Stake memory) {
        return stakes[underwriter][poolId];
    }

    function getAllPools() external view returns (bytes32[] memory) {
        return poolIds;
    }

    function getPoolUtilization(bytes32 poolId) external view returns (uint256) {
        Pool storage pool = pools[poolId];
        if (pool.totalCapacity == 0) return 0;
        return (pool.usedCapacity * BPS) / pool.totalCapacity;
    }

    function getAvailableCapacity(bytes32 poolId) external view returns (uint256) {
        Pool storage pool = pools[poolId];
        uint256 maxUsable = (pool.totalCapacity * pool.utilizationCap) / BPS;
        if (maxUsable <= pool.usedCapacity) return 0;
        return maxUsable - pool.usedCapacity;
    }

    // ═══════════════════════════════════════════════════════════════════════
    // ADMIN
    // ═══════════════════════════════════════════════════════════════════════

    function setFeeReceiver(address _feeReceiver) external onlyRole(ADMIN_ROLE) {
        feeReceiver = _feeReceiver;
    }

    function setTreasury(address _treasury) external onlyRole(ADMIN_ROLE) {
        treasury = _treasury;
    }

    function setProtocolFee(uint256 _feeBps) external onlyRole(ADMIN_ROLE) {
        require(_feeBps <= 2000, "Fee too high"); // Max 20%
        protocolFeeBps = _feeBps;
    }

    function setMinStake(uint256 _minStake) external onlyRole(ADMIN_ROLE) {
        minStakeAmount = _minStake;
    }

    function pause() external onlyRole(ADMIN_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(ADMIN_ROLE) {
        _unpause();
    }

    // Required overrides
    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC721, AccessControl)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }
}
