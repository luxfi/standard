// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import "../IYieldStrategy.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/// @title L2 DEX Yield Strategies
/// @notice Yield strategies for L2 DEX protocols with gauge staking and ve-tokenomics
/// @dev Implements strategies for:
///      - Velodrome (Optimism) - ve(3,3) LP + gauge staking
///      - Camelot (Arbitrum) - LP + xGRAIL staking
///      - Trader Joe (Avalanche) - Liquidity Book LP + JOE staking
///      - Balancer (Multi-chain) - Weighted/Stable pools + veBAL
///
/// Key Features:
/// - LP token deposit/withdrawal
/// - Gauge staking for reward boosting
/// - ve-token locking for governance and yield boost
/// - Multi-reward token harvesting

// =============================================================================
// VELODROME INTERFACES (Optimism ve(3,3))
// =============================================================================

/// @notice Velodrome Router for swaps and liquidity
interface IVelodromeRouter {
    struct Route {
        address from;
        address to;
        bool stable;
        address factory;
    }

    /// @notice Add liquidity to a pool
    function addLiquidity(
        address tokenA,
        address tokenB,
        bool stable,
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    ) external returns (uint256 amountA, uint256 amountB, uint256 liquidity);

    /// @notice Remove liquidity from a pool
    function removeLiquidity(
        address tokenA,
        address tokenB,
        bool stable,
        uint256 liquidity,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    ) external returns (uint256 amountA, uint256 amountB);

    /// @notice Swap tokens
    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        Route[] calldata routes,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts);
}

/// @notice Velodrome Gauge for staking LP tokens and earning VELO rewards
interface IVelodromeGauge {
    /// @notice Deposit LP tokens into gauge
    function deposit(uint256 amount) external;

    /// @notice Withdraw LP tokens from gauge
    function withdraw(uint256 amount) external;

    /// @notice Claim pending rewards
    function getReward(address account) external;

    /// @notice Get pending rewards for account
    function earned(address account) external view returns (uint256);

    /// @notice Get staked balance
    function balanceOf(address account) external view returns (uint256);

    /// @notice Get reward rate per second
    function rewardRate() external view returns (uint256);

    /// @notice Get reward token address
    function rewardToken() external view returns (address);
}

/// @notice Velodrome Voting Escrow for veVELO
interface IVotingEscrow {
    /// @notice Create a new lock
    function create_lock(uint256 _value, uint256 _lock_duration) external returns (uint256);

    /// @notice Increase locked amount
    function increase_amount(uint256 _tokenId, uint256 _value) external;

    /// @notice Extend lock duration
    function increase_unlock_time(uint256 _tokenId, uint256 _lock_duration) external;

    /// @notice Withdraw after lock expires
    function withdraw(uint256 _tokenId) external;

    /// @notice Get voting power of NFT
    function balanceOfNFT(uint256 _tokenId) external view returns (uint256);

    /// @notice Get lock info
    function locked(uint256 _tokenId) external view returns (int128 amount, uint256 end);
}

// =============================================================================
// CAMELOT INTERFACES (Arbitrum)
// =============================================================================

/// @notice Camelot Router for swaps and liquidity
interface ICamelotRouter {
    /// @notice Add liquidity
    function addLiquidity(
        address tokenA,
        address tokenB,
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    ) external returns (uint256 amountA, uint256 amountB, uint256 liquidity);

    /// @notice Remove liquidity
    function removeLiquidity(
        address tokenA,
        address tokenB,
        uint256 liquidity,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    ) external returns (uint256 amountA, uint256 amountB);

    /// @notice Swap with fee-on-transfer support
    function swapExactTokensForTokensSupportingFeeOnTransferTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        address referrer,
        uint256 deadline
    ) external;
}

/// @notice Camelot Nitro Pool for boosted rewards
interface INitroPool {
    /// @notice Deposit spNFT into nitro pool
    function deposit(uint256 amount) external;

    /// @notice Withdraw from nitro pool
    function withdraw(uint256 amount) external;

    /// @notice Harvest pending rewards
    function harvest() external;

    /// @notice Get pending rewards (GRAIL, xGRAIL)
    function pendingRewards(address account) external view returns (uint256, uint256);

    /// @notice Get user deposit info
    function userInfo(address account) external view returns (
        uint256 amount,
        uint256 rewardDebt,
        uint256 pendingXGrail,
        uint256 pendingGrail
    );
}

/// @notice Camelot xGRAIL - escrowed GRAIL with allocation
interface IXGrail {
    /// @notice Convert GRAIL to xGRAIL (instant)
    function convert(uint256 amount) external;

    /// @notice Start xGRAIL redemption for GRAIL
    function redeem(uint256 amount, uint256 duration) external;

    /// @notice Finalize redemption after duration
    function finalizeRedeem(uint256 redeemIndex) external;

    /// @notice Allocate xGRAIL to a plugin
    function allocate(address usageAddress, uint256 amount, bytes calldata usageData) external;

    /// @notice Deallocate xGRAIL from a plugin
    function deallocate(address usageAddress, uint256 amount, bytes calldata usageData) external;

    /// @notice Get xGRAIL balance
    function balanceOf(address account) external view returns (uint256);
}

// =============================================================================
// TRADER JOE INTERFACES (Avalanche Liquidity Book)
// =============================================================================

/// @notice Trader Joe LB Router for Liquidity Book operations
interface ILBRouter {
    struct LiquidityParameters {
        address tokenX;
        address tokenY;
        uint256 binStep;
        uint256 amountX;
        uint256 amountY;
        uint256 amountXMin;
        uint256 amountYMin;
        uint256 activeIdDesired;
        uint256 idSlippage;
        int256[] deltaIds;
        uint256[] distributionX;
        uint256[] distributionY;
        address to;
        address refundTo;
        uint256 deadline;
    }

    /// @notice Add liquidity to Liquidity Book pool
    function addLiquidity(LiquidityParameters calldata liquidityParameters) external returns (
        uint256 amountXAdded,
        uint256 amountYAdded,
        uint256 amountXLeft,
        uint256 amountYLeft,
        uint256[] memory depositIds,
        uint256[] memory liquidityMinted
    );

    /// @notice Remove liquidity from Liquidity Book pool
    function removeLiquidity(
        address tokenX,
        address tokenY,
        uint16 binStep,
        uint256 amountXMin,
        uint256 amountYMin,
        uint256[] calldata ids,
        uint256[] calldata amounts,
        address to,
        uint256 deadline
    ) external returns (uint256 amountX, uint256 amountY);
}

/// @notice Trader Joe Staking for JOE rewards
interface IJoeStaking {
    /// @notice Deposit LP tokens for JOE rewards
    function deposit(uint256 _pid, uint256 _amount) external;

    /// @notice Withdraw LP tokens
    function withdraw(uint256 _pid, uint256 _amount) external;

    /// @notice Get pending rewards
    function pendingTokens(uint256 _pid, address _user) external view returns (
        uint256 pendingJoe,
        address bonusTokenAddress,
        string memory bonusTokenSymbol,
        uint256 pendingBonusToken
    );

    /// @notice Get user deposit info
    function userInfo(uint256 _pid, address _user) external view returns (
        uint256 amount,
        uint256 rewardDebt
    );
}

// =============================================================================
// BALANCER INTERFACES (Multi-chain)
// =============================================================================

/// @notice Balancer Vault for pool operations
interface IBalancerVault {
    enum JoinKind {
        INIT,
        EXACT_TOKENS_IN_FOR_BPT_OUT,
        TOKEN_IN_FOR_EXACT_BPT_OUT,
        ALL_TOKENS_IN_FOR_EXACT_BPT_OUT
    }

    enum ExitKind {
        EXACT_BPT_IN_FOR_ONE_TOKEN_OUT,
        EXACT_BPT_IN_FOR_TOKENS_OUT,
        BPT_IN_FOR_EXACT_TOKENS_OUT
    }

    struct JoinPoolRequest {
        address[] assets;
        uint256[] maxAmountsIn;
        bytes userData;
        bool fromInternalBalance;
    }

    struct ExitPoolRequest {
        address[] assets;
        uint256[] minAmountsOut;
        bytes userData;
        bool toInternalBalance;
    }

    /// @notice Join a Balancer pool
    function joinPool(
        bytes32 poolId,
        address sender,
        address recipient,
        JoinPoolRequest memory request
    ) external payable;

    /// @notice Exit a Balancer pool
    function exitPool(
        bytes32 poolId,
        address sender,
        address recipient,
        ExitPoolRequest memory request
    ) external;

    /// @notice Get pool tokens and balances
    function getPoolTokens(bytes32 poolId) external view returns (
        address[] memory tokens,
        uint256[] memory balances,
        uint256 lastChangeBlock
    );
}

/// @notice Balancer Gauge for BPT staking
interface IBalancerGauge {
    /// @notice Deposit BPT into gauge
    function deposit(uint256 value) external;

    /// @notice Withdraw BPT from gauge
    function withdraw(uint256 value) external;

    /// @notice Claim all rewards
    function claim_rewards() external;

    /// @notice Get claimable reward amount
    function claimable_reward(address user, address token) external view returns (uint256);

    /// @notice Get staked balance
    function balanceOf(address account) external view returns (uint256);

    /// @notice Get reward token by index
    function reward_tokens(uint256 index) external view returns (address);
}

/// @notice veBAL - Vote Escrowed BAL
interface IVeBAL {
    /// @notice Create a new lock
    function create_lock(uint256 _value, uint256 _unlock_time) external;

    /// @notice Increase locked amount
    function increase_amount(uint256 _value) external;

    /// @notice Extend lock time
    function increase_unlock_time(uint256 _unlock_time) external;

    /// @notice Withdraw after lock expires
    function withdraw() external;

    /// @notice Get voting power
    function balanceOf(address addr) external view returns (uint256);
}

// =============================================================================
// L2 DEX BASE STRATEGY
// =============================================================================

/// @title L2 DEX Base Strategy
/// @notice Abstract base for L2 DEX yield strategies
/// @dev Common logic for LP deposit, gauge staking, and reward harvesting
abstract contract L2DexBaseStrategy is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // =========================================================================
    // STATE
    // =========================================================================

    /// @notice LP token address
    IERC20 public immutable lpToken;

    /// @notice Token A in the pair
    IERC20 public immutable tokenA;

    /// @notice Token B in the pair
    IERC20 public immutable tokenB;

    /// @notice Controller address (vault)
    address public controller;

    /// @notice Total LP tokens staked
    uint256 public totalStaked;

    /// @notice Total rewards harvested (lifetime)
    uint256 public totalHarvested;

    /// @notice Whether strategy is paused
    bool public isPaused;

    // =========================================================================
    // EVENTS
    // =========================================================================

    /// @notice Emitted when LP tokens are deposited
    event Deposited(address indexed depositor, uint256 amount, uint256 shares);

    /// @notice Emitted when LP tokens are withdrawn
    event Withdrawn(address indexed recipient, uint256 amount, uint256 shares);

    /// @notice Emitted when rewards are harvested
    event Harvested(uint256 rewardAmount, address rewardToken);

    /// @notice Emitted when LP is staked in gauge
    event GaugeStaked(uint256 amount, address indexed gauge);

    /// @notice Emitted when ve-token lock is created
    event LockCreated(uint256 indexed tokenId, uint256 amount, uint256 duration);

    /// @notice Emitted when controller is updated
    event ControllerUpdated(address indexed oldController, address indexed newController);

    // =========================================================================
    // ERRORS
    // =========================================================================

    /// @notice Strategy is paused
    error StrategyPaused();

    /// @notice Caller is not controller or owner
    error OnlyController();

    /// @notice Insufficient shares for withdrawal
    error InsufficientShares();

    /// @notice Amount must be non-zero
    error ZeroAmount();

    /// @notice Invalid address provided
    error InvalidAddress();

    /// @notice Slippage tolerance exceeded
    error SlippageExceeded();

    /// @notice Lock duration invalid
    error InvalidLockDuration();

    // =========================================================================
    // MODIFIERS
    // =========================================================================

    modifier onlyController() {
        if (msg.sender != controller && msg.sender != owner()) revert OnlyController();
        _;
    }

    modifier whenNotPaused() {
        if (isPaused) revert StrategyPaused();
        _;
    }

    // =========================================================================
    // CONSTRUCTOR
    // =========================================================================

    constructor(
        address _lpToken,
        address _tokenA,
        address _tokenB,
        address _controller,
        address _owner
    ) Ownable(_owner) {
        if (_lpToken == address(0)) revert InvalidAddress();
        if (_tokenA == address(0)) revert InvalidAddress();
        if (_tokenB == address(0)) revert InvalidAddress();

        lpToken = IERC20(_lpToken);
        tokenA = IERC20(_tokenA);
        tokenB = IERC20(_tokenB);
        controller = _controller;
    }

    // =========================================================================
    // VIEW FUNCTIONS
    // =========================================================================

    /// @notice
    function underlying() external view returns (address) {
        return address(lpToken);
    }

    /// @notice
    function yieldToken() external view returns (address) {
        return address(lpToken);
    }

    /// @notice
    function isActive() external view returns (bool) {
        return !isPaused && totalStaked > 0;
    }

    // =========================================================================
    // ADMIN FUNCTIONS
    // =========================================================================

    /// @notice Set controller address
    /// @param _controller New controller address
    function setController(address _controller) external onlyOwner {
        emit ControllerUpdated(controller, _controller);
        controller = _controller;
    }

    /// @notice Pause/unpause strategy
    /// @param _paused Whether to pause
    function setPaused(bool _paused) external onlyOwner {
        isPaused = _paused;
    }

    /// @notice Rescue stuck tokens (not the strategy tokens)
    /// @param token Token to rescue
    /// @param amount Amount to rescue
    function rescueTokens(address token, uint256 amount) external onlyOwner {
        require(token != address(lpToken), "Cannot rescue LP token");
        require(token != address(tokenA), "Cannot rescue tokenA");
        require(token != address(tokenB), "Cannot rescue tokenB");
        IERC20(token).safeTransfer(owner(), amount);
    }
}

// =============================================================================
// VELODROME STRATEGY (Optimism)
// =============================================================================

/// @title Velodrome Strategy
/// @notice ve(3,3) LP + gauge staking strategy for Optimism
/// @dev Deposits LP tokens into Velodrome gauges for VELO rewards
///      Supports veVELO locking for boosted rewards
contract VelodromeStrategy is L2DexBaseStrategy {
    using SafeERC20 for IERC20;

    // =========================================================================
    // CONSTANTS
    // =========================================================================

    /// @notice Velodrome Router (Optimism)
    address public constant ROUTER = 0xa062aE8A9c5e11aaA026fc2670B0D65cCc8B2858;

    /// @notice VELO token (Optimism)
    address public constant VELO = 0x9560e827aF36c94D2Ac33a39bCE1Fe78631088Db;

    /// @notice veVELO (Optimism)
    address public constant VE_VELO = 0xFAf8FD17D9840595845582fCB047DF13f006787d;

    /// @notice Max lock duration (4 years)
    uint256 public constant MAX_LOCK = 4 * 365 days;

    // =========================================================================
    // STATE
    // =========================================================================

    /// @notice Gauge address for this LP
    IVelodromeGauge public gauge;

    /// @notice Whether pool is stable or volatile
    bool public isStable;

    /// @notice veVELO token ID (0 if no lock)
    uint256 public veTokenId;

    // =========================================================================
    // CONSTRUCTOR
    // =========================================================================

    /// @notice Initialize Velodrome strategy
    /// @param _lpToken LP token address
    /// @param _tokenA First token in pair
    /// @param _tokenB Second token in pair
    /// @param _gauge Velodrome gauge address
    /// @param _isStable Whether pool is stable (true) or volatile (false)
    /// @param _controller Controller address
    /// @param _owner Owner address
    constructor(
        address _lpToken,
        address _tokenA,
        address _tokenB,
        address _gauge,
        bool _isStable,
        address _controller,
        address _owner
    ) L2DexBaseStrategy(_lpToken, _tokenA, _tokenB, _controller, _owner) {
        gauge = IVelodromeGauge(_gauge);
        isStable = _isStable;

        // Approve gauge to spend LP tokens
        lpToken.approve(_gauge, type(uint256).max);
    }

    // =========================================================================
    // YIELD STRATEGY INTERFACE
    // =========================================================================

    /// @notice
    function deposit(uint256 amount) external payable onlyController whenNotPaused nonReentrant returns (uint256 shares) {
        if (amount == 0) revert ZeroAmount();

        // Transfer LP tokens from controller
        lpToken.safeTransferFrom(msg.sender, address(this), amount);

        // Stake in gauge
        gauge.deposit(amount);

        totalStaked += amount;
        shares = amount; // 1:1 for LP strategies

        emit Deposited(msg.sender, amount, shares);
        emit GaugeStaked(amount, address(gauge));
    }

    /// @notice
    function withdraw(uint256 shares) external onlyController nonReentrant returns (uint256 amount) {
        if (shares == 0) revert ZeroAmount();
        if (shares > totalStaked) revert InsufficientShares();

        // Withdraw from gauge
        gauge.withdraw(shares);

        // Transfer LP to controller
        lpToken.safeTransfer(msg.sender, shares);

        totalStaked -= shares;
        amount = shares;

        emit Withdrawn(msg.sender, amount, shares);
    }

    /// @notice
    function harvest() external returns (uint256 harvested) {
        // Claim VELO rewards
        gauge.getReward(address(this));

        harvested = IERC20(VELO).balanceOf(address(this));

        if (harvested > 0) {
            totalHarvested += harvested;
            // Transfer rewards to controller
            IERC20(VELO).safeTransfer(controller, harvested);
            emit Harvested(harvested, VELO);
        }
    }

    /// @notice
    function totalAssets() external view returns (uint256) {
        return totalStaked;
    }

    /// @notice
    function currentAPY() external view returns (uint256) {
        // Simplified APY calculation based on reward rate
        uint256 rewardRate = gauge.rewardRate();
        if (totalStaked == 0 || rewardRate == 0) return 0;

        // Annual rewards / total staked * 10000 (basis points)
        uint256 annualRewards = rewardRate * 365 days;
        return (annualRewards * 10000) / totalStaked;
    }

    /// @notice
    function name() external pure returns (string memory) {
        return "Velodrome ve(3,3)";
    }

    // =========================================================================
    // VELODROME SPECIFIC
    // =========================================================================

    /// @notice Get pending VELO rewards
    /// @return Pending VELO amount
    function pendingRewards() external view returns (uint256) {
        return gauge.earned(address(this));
    }

    /// @notice Create veVELO lock for boost
    /// @param amount VELO amount to lock
    /// @param duration Lock duration in seconds
    function createLock(uint256 amount, uint256 duration) external onlyOwner returns (uint256 tokenId) {
        if (duration > MAX_LOCK) revert InvalidLockDuration();

        IERC20(VELO).safeTransferFrom(msg.sender, address(this), amount);
        IERC20(VELO).approve(VE_VELO, amount);

        tokenId = IVotingEscrow(VE_VELO).create_lock(amount, duration);
        veTokenId = tokenId;

        emit LockCreated(tokenId, amount, duration);
    }

    /// @notice Increase lock amount
    /// @param amount Additional VELO to lock
    function increaseLockAmount(uint256 amount) external onlyOwner {
        require(veTokenId != 0, "No lock exists");
        IERC20(VELO).safeTransferFrom(msg.sender, address(this), amount);
        IERC20(VELO).approve(VE_VELO, amount);
        IVotingEscrow(VE_VELO).increase_amount(veTokenId, amount);
    }

    /// @notice Extend lock duration
    /// @param newDuration New lock duration
    function extendLock(uint256 newDuration) external onlyOwner {
        require(veTokenId != 0, "No lock exists");
        if (newDuration > MAX_LOCK) revert InvalidLockDuration();
        IVotingEscrow(VE_VELO).increase_unlock_time(veTokenId, newDuration);
    }

    /// @notice Withdraw after lock expires
    function withdrawLock() external onlyOwner {
        require(veTokenId != 0, "No lock exists");
        IVotingEscrow(VE_VELO).withdraw(veTokenId);
        IERC20(VELO).safeTransfer(owner(), IERC20(VELO).balanceOf(address(this)));
        veTokenId = 0;
    }

    /// @notice Get current boost multiplier
    /// @return Boost multiplier (1e18 = 1x)
    function getBoostMultiplier() external view returns (uint256) {
        if (veTokenId == 0) return 1e18;
        uint256 votingPower = IVotingEscrow(VE_VELO).balanceOfNFT(veTokenId);
        // Simplified - real calculation involves total voting power
        return 1e18 + (votingPower * 15e17 / 1e24); // Up to 2.5x
    }

    /// @notice Emergency withdraw all from gauge
    function emergencyWithdraw() external onlyOwner {
        uint256 staked = gauge.balanceOf(address(this));
        if (staked > 0) {
            gauge.withdraw(staked);
            lpToken.safeTransfer(owner(), staked);
            totalStaked = 0;
        }
    }
}

// =============================================================================
// CAMELOT STRATEGY (Arbitrum)
// =============================================================================

/// @title Camelot Strategy
/// @notice LP + xGRAIL staking strategy for Arbitrum
/// @dev Deposits LP tokens into Camelot Nitro Pools for boosted rewards
contract CamelotStrategy is L2DexBaseStrategy {
    using SafeERC20 for IERC20;

    // =========================================================================
    // CONSTANTS
    // =========================================================================

    /// @notice Camelot Router (Arbitrum)
    address public constant ROUTER = 0xc873fEcbd354f5A56E00E710B90EF4201db2448d;

    /// @notice GRAIL token (Arbitrum)
    address public constant GRAIL = 0x3d9907F9a368ad0a51Be60f7Da3b97cf940982D8;

    /// @notice xGRAIL token (Arbitrum)
    address public constant XGRAIL = 0x3CAaE25Ee616f2C8E13C74dA0813402eae3F496b;

    /// @notice Min redemption duration (15 days)
    uint256 public constant MIN_REDEEM_DURATION = 15 days;

    /// @notice Max redemption duration (180 days for 1:1)
    uint256 public constant MAX_REDEEM_DURATION = 180 days;

    // =========================================================================
    // STATE
    // =========================================================================

    /// @notice Nitro Pool address
    INitroPool public nitroPool;

    /// @notice Accumulated xGRAIL balance
    uint256 public xGrailBalance;

    /// @notice Active redemption indices
    uint256[] public activeRedemptions;

    // =========================================================================
    // CONSTRUCTOR
    // =========================================================================

    /// @notice Initialize Camelot strategy
    /// @param _lpToken LP token address (spNFT or LP)
    /// @param _tokenA First token in pair
    /// @param _tokenB Second token in pair
    /// @param _nitroPool Nitro Pool address
    /// @param _controller Controller address
    /// @param _owner Owner address
    constructor(
        address _lpToken,
        address _tokenA,
        address _tokenB,
        address _nitroPool,
        address _controller,
        address _owner
    ) L2DexBaseStrategy(_lpToken, _tokenA, _tokenB, _controller, _owner) {
        nitroPool = INitroPool(_nitroPool);

        // Approve nitro pool
        lpToken.approve(_nitroPool, type(uint256).max);
    }

    // =========================================================================
    // YIELD STRATEGY INTERFACE
    // =========================================================================

    /// @notice
    function deposit(uint256 amount) external payable onlyController whenNotPaused nonReentrant returns (uint256 shares) {
        if (amount == 0) revert ZeroAmount();

        // Transfer LP tokens from controller
        lpToken.safeTransferFrom(msg.sender, address(this), amount);

        // Deposit into Nitro Pool
        nitroPool.deposit(amount);

        totalStaked += amount;
        shares = amount;

        emit Deposited(msg.sender, amount, shares);
        emit GaugeStaked(amount, address(nitroPool));
    }

    /// @notice
    function withdraw(uint256 shares) external onlyController nonReentrant returns (uint256 amount) {
        if (shares == 0) revert ZeroAmount();
        if (shares > totalStaked) revert InsufficientShares();

        // Withdraw from Nitro Pool
        nitroPool.withdraw(shares);

        // Transfer LP to controller
        lpToken.safeTransfer(msg.sender, shares);

        totalStaked -= shares;
        amount = shares;

        emit Withdrawn(msg.sender, amount, shares);
    }

    /// @notice
    function harvest() external returns (uint256 harvested) {
        // Harvest GRAIL and xGRAIL rewards
        nitroPool.harvest();

        // Get GRAIL balance
        uint256 grailBalance = IERC20(GRAIL).balanceOf(address(this));

        // Get xGRAIL balance
        uint256 newXGrail = IXGrail(XGRAIL).balanceOf(address(this)) - xGrailBalance;
        xGrailBalance = IXGrail(XGRAIL).balanceOf(address(this));

        // Transfer GRAIL to controller
        if (grailBalance > 0) {
            IERC20(GRAIL).safeTransfer(controller, grailBalance);
            emit Harvested(grailBalance, GRAIL);
        }

        harvested = grailBalance;
        totalHarvested += grailBalance;
    }

    /// @notice
    function totalAssets() external view returns (uint256) {
        return totalStaked;
    }

    /// @notice
    function currentAPY() external view returns (uint256) {
        // Fetch pending rewards for APY estimation
        (uint256 pendingGrail, uint256 pendingXGrail) = nitroPool.pendingRewards(address(this));

        if (totalStaked == 0) return 0;

        // Combine rewards (xGRAIL valued at 50% of GRAIL due to vesting)
        uint256 totalPending = pendingGrail + (pendingXGrail / 2);

        // Annualize (assuming rewards accumulated over ~1 day)
        return (totalPending * 365 * 10000) / totalStaked;
    }

    /// @notice
    function name() external pure returns (string memory) {
        return "Camelot xGRAIL";
    }

    // =========================================================================
    // CAMELOT SPECIFIC
    // =========================================================================

    /// @notice Get pending rewards
    /// @return pendingGrail Pending GRAIL
    /// @return pendingXGrail Pending xGRAIL
    function pendingRewards() external view returns (uint256 pendingGrail, uint256 pendingXGrail) {
        return nitroPool.pendingRewards(address(this));
    }

    /// @notice Convert GRAIL to xGRAIL
    /// @param amount GRAIL amount to convert
    function convertToXGrail(uint256 amount) external onlyOwner {
        IERC20(GRAIL).approve(XGRAIL, amount);
        IXGrail(XGRAIL).convert(amount);
        xGrailBalance = IXGrail(XGRAIL).balanceOf(address(this));
    }

    /// @notice Start xGRAIL redemption for GRAIL
    /// @param amount xGRAIL amount to redeem
    /// @param duration Redemption duration (15-180 days)
    function startRedemption(uint256 amount, uint256 duration) external onlyOwner {
        require(duration >= MIN_REDEEM_DURATION && duration <= MAX_REDEEM_DURATION, "Invalid duration");
        IXGrail(XGRAIL).redeem(amount, duration);
        activeRedemptions.push(activeRedemptions.length);
    }

    /// @notice Finalize a redemption
    /// @param redeemIndex Index of redemption to finalize
    function finalizeRedemption(uint256 redeemIndex) external onlyOwner {
        IXGrail(XGRAIL).finalizeRedeem(redeemIndex);
        // Transfer redeemed GRAIL to controller
        uint256 grailBalance = IERC20(GRAIL).balanceOf(address(this));
        if (grailBalance > 0) {
            IERC20(GRAIL).safeTransfer(controller, grailBalance);
        }
    }

    /// @notice Allocate xGRAIL to a plugin for yield boost
    /// @param usageAddress Plugin address
    /// @param amount xGRAIL amount
    /// @param usageData Plugin-specific data
    function allocateXGrail(address usageAddress, uint256 amount, bytes calldata usageData) external onlyOwner {
        IXGrail(XGRAIL).allocate(usageAddress, amount, usageData);
    }

    /// @notice Deallocate xGRAIL from a plugin
    /// @param usageAddress Plugin address
    /// @param amount xGRAIL amount
    /// @param usageData Plugin-specific data
    function deallocateXGrail(address usageAddress, uint256 amount, bytes calldata usageData) external onlyOwner {
        IXGrail(XGRAIL).deallocate(usageAddress, amount, usageData);
    }

    /// @notice Get xGRAIL balance
    /// @return Current xGRAIL balance
    function getXGrailBalance() external view returns (uint256) {
        return IXGrail(XGRAIL).balanceOf(address(this));
    }

    /// @notice Emergency withdraw all
    function emergencyWithdraw() external onlyOwner {
        (uint256 staked,,,) = nitroPool.userInfo(address(this));
        if (staked > 0) {
            nitroPool.withdraw(staked);
            lpToken.safeTransfer(owner(), staked);
            totalStaked = 0;
        }
    }
}

// =============================================================================
// TRADER JOE STRATEGY (Avalanche)
// =============================================================================

/// @title Trader Joe Strategy
/// @notice Liquidity Book LP + JOE staking strategy for Avalanche
/// @dev Concentrated liquidity via Liquidity Book with JOE reward staking
contract TraderJoeStrategy is L2DexBaseStrategy {
    using SafeERC20 for IERC20;

    // =========================================================================
    // CONSTANTS
    // =========================================================================

    /// @notice Trader Joe LB Router (Avalanche)
    address public constant LB_ROUTER = 0xb4315e873dBcf96Ffd0acd8EA43f689D8c20fB30;

    /// @notice JOE token (Avalanche)
    address public constant JOE = 0x6e84a6216eA6dACC71eE8E6b0a5B7322EEbC0fDd;

    /// @notice JOE Staking contract (MasterChef)
    address public constant JOE_STAKING = 0x188bED1968b795d5c9022F6a0bb5931Ac4c18F00;

    // =========================================================================
    // STATE
    // =========================================================================

    /// @notice Pool ID in JOE staking
    uint256 public poolId;

    /// @notice Bin step for the LB pair
    uint256 public binStep;

    /// @notice Active bin IDs where liquidity is deposited
    uint256[] public activeBinIds;

    /// @notice Liquidity amounts per bin
    mapping(uint256 => uint256) public liquidityPerBin;

    // =========================================================================
    // CONSTRUCTOR
    // =========================================================================

    /// @notice Initialize Trader Joe strategy
    /// @param _lpToken LB pair token address
    /// @param _tokenX Token X in pair
    /// @param _tokenY Token Y in pair
    /// @param _poolId Pool ID in JOE staking
    /// @param _binStep Bin step for the pair
    /// @param _controller Controller address
    /// @param _owner Owner address
    constructor(
        address _lpToken,
        address _tokenX,
        address _tokenY,
        uint256 _poolId,
        uint256 _binStep,
        address _controller,
        address _owner
    ) L2DexBaseStrategy(_lpToken, _tokenX, _tokenY, _controller, _owner) {
        poolId = _poolId;
        binStep = _binStep;

        // Approve staking contract
        lpToken.approve(JOE_STAKING, type(uint256).max);
    }

    // =========================================================================
    // YIELD STRATEGY INTERFACE
    // =========================================================================

    /// @notice
    function deposit(uint256 amount) external payable onlyController whenNotPaused nonReentrant returns (uint256 shares) {
        if (amount == 0) revert ZeroAmount();

        // Transfer LP tokens from controller
        lpToken.safeTransferFrom(msg.sender, address(this), amount);

        // Stake in JOE staking
        IJoeStaking(JOE_STAKING).deposit(poolId, amount);

        totalStaked += amount;
        shares = amount;

        emit Deposited(msg.sender, amount, shares);
        emit GaugeStaked(amount, JOE_STAKING);
    }

    /// @notice
    function withdraw(uint256 shares) external onlyController nonReentrant returns (uint256 amount) {
        if (shares == 0) revert ZeroAmount();
        if (shares > totalStaked) revert InsufficientShares();

        // Withdraw from JOE staking
        IJoeStaking(JOE_STAKING).withdraw(poolId, shares);

        // Transfer LP to controller
        lpToken.safeTransfer(msg.sender, shares);

        totalStaked -= shares;
        amount = shares;

        emit Withdrawn(msg.sender, amount, shares);
    }

    /// @notice
    function harvest() external returns (uint256 harvested) {
        // Claim JOE rewards (deposit 0 to trigger claim)
        IJoeStaking(JOE_STAKING).deposit(poolId, 0);

        harvested = IERC20(JOE).balanceOf(address(this));

        if (harvested > 0) {
            totalHarvested += harvested;
            IERC20(JOE).safeTransfer(controller, harvested);
            emit Harvested(harvested, JOE);
        }
    }

    /// @notice
    function totalAssets() external view returns (uint256) {
        return totalStaked;
    }

    /// @notice
    function currentAPY() external view returns (uint256) {
        (uint256 pendingJoe,,,) = IJoeStaking(JOE_STAKING).pendingTokens(poolId, address(this));

        if (totalStaked == 0) return 0;

        // Annualize
        return (pendingJoe * 365 * 10000) / totalStaked;
    }

    /// @notice
    function name() external pure returns (string memory) {
        return "Trader Joe LB";
    }

    // =========================================================================
    // TRADER JOE SPECIFIC
    // =========================================================================

    /// @notice Get pending JOE rewards
    /// @return pendingJoe Pending JOE amount
    /// @return bonusToken Bonus token address
    /// @return bonusSymbol Bonus token symbol
    /// @return pendingBonus Pending bonus token amount
    function pendingRewards() external view returns (
        uint256 pendingJoe,
        address bonusToken,
        string memory bonusSymbol,
        uint256 pendingBonus
    ) {
        return IJoeStaking(JOE_STAKING).pendingTokens(poolId, address(this));
    }

    /// @notice Get staked amount
    /// @return amount Staked LP amount
    function stakedAmount() external view returns (uint256 amount) {
        (amount,) = IJoeStaking(JOE_STAKING).userInfo(poolId, address(this));
    }

    /// @notice Add concentrated liquidity via LB Router
    /// @param params Liquidity parameters
    function addConcentratedLiquidity(ILBRouter.LiquidityParameters calldata params) external onlyOwner returns (
        uint256 amountXAdded,
        uint256 amountYAdded,
        uint256[] memory depositIds,
        uint256[] memory liquidityMinted
    ) {
        // Transfer tokens
        IERC20(params.tokenX).safeTransferFrom(msg.sender, address(this), params.amountX);
        IERC20(params.tokenY).safeTransferFrom(msg.sender, address(this), params.amountY);

        // Approve router
        IERC20(params.tokenX).approve(LB_ROUTER, params.amountX);
        IERC20(params.tokenY).approve(LB_ROUTER, params.amountY);

        // Add liquidity
        uint256 amountXLeft;
        uint256 amountYLeft;
        (amountXAdded, amountYAdded, amountXLeft, amountYLeft, depositIds, liquidityMinted) =
            ILBRouter(LB_ROUTER).addLiquidity(params);

        // Track active bins
        for (uint256 i = 0; i < depositIds.length; i++) {
            if (liquidityMinted[i] > 0) {
                activeBinIds.push(depositIds[i]);
                liquidityPerBin[depositIds[i]] += liquidityMinted[i];
            }
        }

        // Return unused tokens
        if (amountXLeft > 0) {
            IERC20(params.tokenX).safeTransfer(msg.sender, amountXLeft);
        }
        if (amountYLeft > 0) {
            IERC20(params.tokenY).safeTransfer(msg.sender, amountYLeft);
        }
    }

    /// @notice Remove concentrated liquidity
    /// @param ids Bin IDs to remove from
    /// @param amounts Amounts to remove per bin
    /// @param amountXMin Minimum token X to receive
    /// @param amountYMin Minimum token Y to receive
    function removeConcentratedLiquidity(
        uint256[] calldata ids,
        uint256[] calldata amounts,
        uint256 amountXMin,
        uint256 amountYMin
    ) external onlyOwner returns (uint256 amountX, uint256 amountY) {
        (amountX, amountY) = ILBRouter(LB_ROUTER).removeLiquidity(
            address(tokenA),
            address(tokenB),
            uint16(binStep),
            amountXMin,
            amountYMin,
            ids,
            amounts,
            msg.sender,
            block.timestamp
        );

        // Update tracking
        for (uint256 i = 0; i < ids.length; i++) {
            liquidityPerBin[ids[i]] -= amounts[i];
        }
    }

    /// @notice Get active bin count
    /// @return Number of active bins
    function getActiveBinCount() external view returns (uint256) {
        return activeBinIds.length;
    }

    /// @notice Emergency withdraw all
    function emergencyWithdraw() external onlyOwner {
        (uint256 staked,) = IJoeStaking(JOE_STAKING).userInfo(poolId, address(this));
        if (staked > 0) {
            IJoeStaking(JOE_STAKING).withdraw(poolId, staked);
            lpToken.safeTransfer(owner(), staked);
            totalStaked = 0;
        }
    }
}

// =============================================================================
// BALANCER STRATEGY (Multi-chain)
// =============================================================================

/// @title Balancer Strategy
/// @notice Weighted/Stable pools + veBAL strategy
/// @dev Supports Ethereum, Arbitrum, Polygon, Optimism, Base
contract BalancerStrategy is L2DexBaseStrategy {
    using SafeERC20 for IERC20;

    // =========================================================================
    // CONSTANTS
    // =========================================================================

    /// @notice Balancer Vault (same address on all chains)
    address public constant BALANCER_VAULT = 0xBA12222222228d8Ba445958a75a0704d566BF2C8;

    /// @notice BAL token (Ethereum - other chains have bridged BAL)
    address public constant BAL = 0xba100000625a3754423978a60c9317c58a424e3D;

    /// @notice veBAL (Ethereum only)
    address public constant VE_BAL = 0xC128a9954e6c874eA3d62ce62B468bA073093F25;

    /// @notice Max lock duration (1 year)
    uint256 public constant MAX_LOCK = 365 days;

    // =========================================================================
    // STATE
    // =========================================================================

    /// @notice Balancer pool ID
    bytes32 public poolId;

    /// @notice Gauge address
    IBalancerGauge public gauge;

    /// @notice Pool tokens
    address[] public poolTokens;

    /// @notice Whether pool is weighted (true) or stable (false)
    bool public isWeightedPool;

    /// @notice veBAL lock end time (0 if no lock)
    uint256 public lockEnd;

    // =========================================================================
    // CONSTRUCTOR
    // =========================================================================

    /// @notice Initialize Balancer strategy
    /// @param _lpToken BPT (Balancer Pool Token) address
    /// @param _tokenA First pool token
    /// @param _tokenB Second pool token
    /// @param _poolId Balancer pool ID
    /// @param _gauge Balancer gauge address
    /// @param _isWeightedPool Whether pool is weighted
    /// @param _controller Controller address
    /// @param _owner Owner address
    constructor(
        address _lpToken,
        address _tokenA,
        address _tokenB,
        bytes32 _poolId,
        address _gauge,
        bool _isWeightedPool,
        address _controller,
        address _owner
    ) L2DexBaseStrategy(_lpToken, _tokenA, _tokenB, _controller, _owner) {
        poolId = _poolId;
        gauge = IBalancerGauge(_gauge);
        isWeightedPool = _isWeightedPool;

        // Get pool tokens
        (address[] memory tokens,,) = IBalancerVault(BALANCER_VAULT).getPoolTokens(_poolId);
        poolTokens = tokens;

        // Approve gauge
        lpToken.approve(_gauge, type(uint256).max);
    }

    // =========================================================================
    // YIELD STRATEGY INTERFACE
    // =========================================================================

    /// @notice
    function deposit(uint256 amount) external payable onlyController whenNotPaused nonReentrant returns (uint256 shares) {
        if (amount == 0) revert ZeroAmount();

        // Transfer BPT from controller
        lpToken.safeTransferFrom(msg.sender, address(this), amount);

        // Stake in gauge
        gauge.deposit(amount);

        totalStaked += amount;
        shares = amount;

        emit Deposited(msg.sender, amount, shares);
        emit GaugeStaked(amount, address(gauge));
    }

    /// @notice
    function withdraw(uint256 shares) external onlyController nonReentrant returns (uint256 amount) {
        if (shares == 0) revert ZeroAmount();
        if (shares > totalStaked) revert InsufficientShares();

        // Withdraw from gauge
        gauge.withdraw(shares);

        // Transfer BPT to controller
        lpToken.safeTransfer(msg.sender, shares);

        totalStaked -= shares;
        amount = shares;

        emit Withdrawn(msg.sender, amount, shares);
    }

    /// @notice
    function harvest() external returns (uint256 harvested) {
        // Claim all reward tokens
        gauge.claim_rewards();

        // Get BAL balance
        harvested = IERC20(BAL).balanceOf(address(this));

        if (harvested > 0) {
            totalHarvested += harvested;
            IERC20(BAL).safeTransfer(controller, harvested);
            emit Harvested(harvested, BAL);
        }

        // Also transfer any other reward tokens
        for (uint256 i = 0; i < 8; i++) {
            try gauge.reward_tokens(i) returns (address rewardToken) {
                if (rewardToken == address(0)) break;
                if (rewardToken == BAL) continue;

                uint256 rewardBalance = IERC20(rewardToken).balanceOf(address(this));
                if (rewardBalance > 0) {
                    IERC20(rewardToken).safeTransfer(controller, rewardBalance);
                    emit Harvested(rewardBalance, rewardToken);
                }
            } catch {
                break;
            }
        }
    }

    /// @notice
    function totalAssets() external view returns (uint256) {
        return totalStaked;
    }

    /// @notice
    function currentAPY() external view returns (uint256) {
        uint256 pendingBal = gauge.claimable_reward(address(this), BAL);

        if (totalStaked == 0) return 0;

        // Annualize (assuming ~1 week accumulation)
        return (pendingBal * 52 * 10000) / totalStaked;
    }

    /// @notice
    function name() external pure returns (string memory) {
        return "Balancer veBAL";
    }

    // =========================================================================
    // BALANCER SPECIFIC
    // =========================================================================

    /// @notice Get pending BAL rewards
    /// @return Pending BAL amount
    function pendingRewards() external view returns (uint256) {
        return gauge.claimable_reward(address(this), BAL);
    }

    /// @notice Get all pending reward tokens
    /// @return tokens Reward token addresses
    /// @return amounts Pending amounts
    function getAllPendingRewards() external view returns (address[] memory tokens, uint256[] memory amounts) {
        // Count reward tokens
        uint256 count = 0;
        for (uint256 i = 0; i < 8; i++) {
            try gauge.reward_tokens(i) returns (address token) {
                if (token == address(0)) break;
                count++;
            } catch {
                break;
            }
        }

        tokens = new address[](count);
        amounts = new uint256[](count);

        for (uint256 i = 0; i < count; i++) {
            tokens[i] = gauge.reward_tokens(i);
            amounts[i] = gauge.claimable_reward(address(this), tokens[i]);
        }
    }

    /// @notice Join Balancer pool with multiple tokens
    /// @param maxAmountsIn Maximum amounts of each token to deposit
    /// @param minBptOut Minimum BPT to receive
    function joinPool(uint256[] calldata maxAmountsIn, uint256 minBptOut) external onlyOwner returns (uint256 bptReceived) {
        require(maxAmountsIn.length == poolTokens.length, "Length mismatch");

        // Transfer and approve tokens
        for (uint256 i = 0; i < poolTokens.length; i++) {
            if (maxAmountsIn[i] > 0) {
                IERC20(poolTokens[i]).safeTransferFrom(msg.sender, address(this), maxAmountsIn[i]);
                IERC20(poolTokens[i]).approve(BALANCER_VAULT, maxAmountsIn[i]);
            }
        }

        // Encode userData for EXACT_TOKENS_IN_FOR_BPT_OUT
        bytes memory userData = abi.encode(
            IBalancerVault.JoinKind.EXACT_TOKENS_IN_FOR_BPT_OUT,
            maxAmountsIn,
            minBptOut
        );

        IBalancerVault.JoinPoolRequest memory request = IBalancerVault.JoinPoolRequest({
            assets: poolTokens,
            maxAmountsIn: maxAmountsIn,
            userData: userData,
            fromInternalBalance: false
        });

        uint256 bptBefore = lpToken.balanceOf(address(this));
        IBalancerVault(BALANCER_VAULT).joinPool(poolId, address(this), address(this), request);
        bptReceived = lpToken.balanceOf(address(this)) - bptBefore;
    }

    /// @notice Exit Balancer pool for multiple tokens
    /// @param bptIn BPT amount to burn
    /// @param minAmountsOut Minimum amounts of each token to receive
    function exitPool(uint256 bptIn, uint256[] calldata minAmountsOut) external onlyOwner {
        require(minAmountsOut.length == poolTokens.length, "Length mismatch");

        // Encode userData for EXACT_BPT_IN_FOR_TOKENS_OUT
        bytes memory userData = abi.encode(
            IBalancerVault.ExitKind.EXACT_BPT_IN_FOR_TOKENS_OUT,
            bptIn
        );

        IBalancerVault.ExitPoolRequest memory request = IBalancerVault.ExitPoolRequest({
            assets: poolTokens,
            minAmountsOut: minAmountsOut,
            userData: userData,
            toInternalBalance: false
        });

        IBalancerVault(BALANCER_VAULT).exitPool(poolId, address(this), msg.sender, request);
    }

    /// @notice Create veBAL lock (Ethereum only)
    /// @param amount BAL amount to lock
    /// @param unlockTime Unlock timestamp
    function createVeBALLock(uint256 amount, uint256 unlockTime) external onlyOwner {
        require(unlockTime > block.timestamp, "Unlock must be future");
        require(unlockTime <= block.timestamp + MAX_LOCK, "Lock too long");

        IERC20(BAL).safeTransferFrom(msg.sender, address(this), amount);
        IERC20(BAL).approve(VE_BAL, amount);

        IVeBAL(VE_BAL).create_lock(amount, unlockTime);
        lockEnd = unlockTime;

        emit LockCreated(0, amount, unlockTime - block.timestamp);
    }

    /// @notice Increase veBAL lock amount
    /// @param amount Additional BAL to lock
    function increaseVeBALAmount(uint256 amount) external onlyOwner {
        require(lockEnd > 0, "No lock exists");
        IERC20(BAL).safeTransferFrom(msg.sender, address(this), amount);
        IERC20(BAL).approve(VE_BAL, amount);
        IVeBAL(VE_BAL).increase_amount(amount);
    }

    /// @notice Extend veBAL lock time
    /// @param newUnlockTime New unlock timestamp
    function extendVeBALLock(uint256 newUnlockTime) external onlyOwner {
        require(lockEnd > 0, "No lock exists");
        require(newUnlockTime > lockEnd, "Must extend");
        require(newUnlockTime <= block.timestamp + MAX_LOCK, "Lock too long");
        IVeBAL(VE_BAL).increase_unlock_time(newUnlockTime);
        lockEnd = newUnlockTime;
    }

    /// @notice Withdraw veBAL after lock expires
    function withdrawVeBAL() external onlyOwner {
        require(lockEnd > 0 && block.timestamp >= lockEnd, "Lock not expired");
        IVeBAL(VE_BAL).withdraw();
        IERC20(BAL).safeTransfer(owner(), IERC20(BAL).balanceOf(address(this)));
        lockEnd = 0;
    }

    /// @notice Get veBAL voting power
    /// @return Current voting power
    function getVotingPower() external view returns (uint256) {
        return IVeBAL(VE_BAL).balanceOf(address(this));
    }

    /// @notice Get pool token balances
    /// @return tokens Token addresses
    /// @return balances Token balances in pool
    function getPoolBalances() external view returns (address[] memory tokens, uint256[] memory balances) {
        (tokens, balances,) = IBalancerVault(BALANCER_VAULT).getPoolTokens(poolId);
    }

    /// @notice Emergency withdraw all
    function emergencyWithdraw() external onlyOwner {
        uint256 staked = gauge.balanceOf(address(this));
        if (staked > 0) {
            gauge.withdraw(staked);
            lpToken.safeTransfer(owner(), staked);
            totalStaked = 0;
        }
    }
}

// =============================================================================
// FACTORY
// =============================================================================

/// @title L2 DEX Strategy Factory
/// @notice Factory for deploying L2 DEX yield strategies
contract L2DexStrategyFactory is Ownable {

    // =========================================================================
    // EVENTS
    // =========================================================================

    /// @notice Emitted when a strategy is deployed
    event StrategyDeployed(
        address indexed strategy,
        string strategyType,
        address indexed lpToken,
        address indexed gauge
    );

    // =========================================================================
    // CONSTRUCTOR
    // =========================================================================

    constructor() Ownable(msg.sender) {}

    // =========================================================================
    // DEPLOYMENT FUNCTIONS
    // =========================================================================

    /// @notice Deploy Velodrome strategy
    /// @param lpToken LP token address
    /// @param tokenA Token A address
    /// @param tokenB Token B address
    /// @param gauge Gauge address
    /// @param isStable Whether pool is stable
    /// @param controller Controller address
    /// @return strategy Deployed strategy address
    function deployVelodromeStrategy(
        address lpToken,
        address tokenA,
        address tokenB,
        address gauge,
        bool isStable,
        address controller
    ) external onlyOwner returns (address strategy) {
        VelodromeStrategy strat = new VelodromeStrategy(
            lpToken,
            tokenA,
            tokenB,
            gauge,
            isStable,
            controller,
            msg.sender
        );
        strategy = address(strat);
        emit StrategyDeployed(strategy, "Velodrome", lpToken, gauge);
    }

    /// @notice Deploy Camelot strategy
    /// @param lpToken LP token address
    /// @param tokenA Token A address
    /// @param tokenB Token B address
    /// @param nitroPool Nitro Pool address
    /// @param controller Controller address
    /// @return strategy Deployed strategy address
    function deployCamelotStrategy(
        address lpToken,
        address tokenA,
        address tokenB,
        address nitroPool,
        address controller
    ) external onlyOwner returns (address strategy) {
        CamelotStrategy strat = new CamelotStrategy(
            lpToken,
            tokenA,
            tokenB,
            nitroPool,
            controller,
            msg.sender
        );
        strategy = address(strat);
        emit StrategyDeployed(strategy, "Camelot", lpToken, nitroPool);
    }

    /// @notice Deploy Trader Joe strategy
    /// @param lpToken LB pair address
    /// @param tokenX Token X address
    /// @param tokenY Token Y address
    /// @param poolId Pool ID in staking
    /// @param binStep Bin step
    /// @param controller Controller address
    /// @return strategy Deployed strategy address
    function deployTraderJoeStrategy(
        address lpToken,
        address tokenX,
        address tokenY,
        uint256 poolId,
        uint256 binStep,
        address controller
    ) external onlyOwner returns (address strategy) {
        TraderJoeStrategy strat = new TraderJoeStrategy(
            lpToken,
            tokenX,
            tokenY,
            poolId,
            binStep,
            controller,
            msg.sender
        );
        strategy = address(strat);
        emit StrategyDeployed(strategy, "TraderJoe", lpToken, address(0));
    }

    /// @notice Deploy Balancer strategy
    /// @param lpToken BPT address
    /// @param tokenA Token A address
    /// @param tokenB Token B address
    /// @param poolId Balancer pool ID
    /// @param gauge Gauge address
    /// @param isWeightedPool Whether pool is weighted
    /// @param controller Controller address
    /// @return strategy Deployed strategy address
    function deployBalancerStrategy(
        address lpToken,
        address tokenA,
        address tokenB,
        bytes32 poolId,
        address gauge,
        bool isWeightedPool,
        address controller
    ) external onlyOwner returns (address strategy) {
        BalancerStrategy strat = new BalancerStrategy(
            lpToken,
            tokenA,
            tokenB,
            poolId,
            gauge,
            isWeightedPool,
            controller,
            msg.sender
        );
        strategy = address(strat);
        emit StrategyDeployed(strategy, "Balancer", lpToken, gauge);
    }
}
