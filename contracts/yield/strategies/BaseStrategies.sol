// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import "../IYieldStrategy.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/// @title Base Chain DeFi Yield Strategies
/// @notice Yield strategies for Base chain DeFi protocols
/// @dev Implements strategies for:
///      - Aerodrome (ve(3,3) DEX with gauge rewards)
///      - Moonwell (Compound-fork lending)
///      - Seamless Protocol (Aave V3-fork lending)
///
/// Base Chain Overview:
/// - Chain ID: 8453
/// - Native token: ETH
/// - Primary DEX: Aerodrome (ve(3,3) model)
/// - Lending: Moonwell, Seamless
///
/// Key Addresses (Base Mainnet):
/// - WETH: 0x4200000000000000000000000000000000000006
/// - USDC: 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913
/// - cbETH: 0x2Ae3F1Ec7F1F5012CFEab0185bfc7aa3cf0DEc22
/// - USDbC: 0xd9aAEc86B65D86f6A7B5B1b0c42FFA531710b6CA
/// - AERO: 0x940181a94A35A4569E4529A3CDfB74e38FD98631

// =============================================================================
// AERODROME INTERFACES (Base ve(3,3) DEX)
// =============================================================================

/// @notice Aerodrome Router for swaps and liquidity
interface IAerodromeRouter {
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

    /// @notice Swap tokens along a route
    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        Route[] calldata routes,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts);

    /// @notice Get pair address for tokens
    function pairFor(address tokenA, address tokenB, bool stable, address factory)
        external view returns (address pair);

    /// @notice Get amounts out for swap
    function getAmountsOut(uint256 amountIn, Route[] calldata routes)
        external view returns (uint256[] memory amounts);

    /// @notice Default factory
    function defaultFactory() external view returns (address);
}

/// @notice Aerodrome Gauge for staking LP tokens
interface IAerodromeGauge {
    /// @notice Deposit LP tokens into gauge
    function deposit(uint256 amount) external;

    /// @notice Withdraw LP tokens from gauge
    function withdraw(uint256 amount) external;

    /// @notice Claim AERO rewards
    function getReward(address account) external;

    /// @notice Get earned rewards
    function earned(address account) external view returns (uint256);

    /// @notice Get staked balance
    function balanceOf(address account) external view returns (uint256);

    /// @notice Get reward rate per second
    function rewardRate() external view returns (uint256);

    /// @notice Get total staked in gauge
    function totalSupply() external view returns (uint256);

    /// @notice Get reward token (AERO)
    function rewardToken() external view returns (address);

    /// @notice Get staking token (LP)
    function stakingToken() external view returns (address);
}

/// @notice Aerodrome Voter for gauge voting and bribes
interface IAerodromeVoter {
    /// @notice Vote for gauge weight
    function vote(uint256 tokenId, address[] calldata poolVote, uint256[] calldata weights) external;

    /// @notice Claim bribes
    function claimBribes(address[] memory bribes, address[][] memory tokens, uint256 tokenId) external;

    /// @notice Claim fees from pools
    function claimFees(address[] memory fees, address[][] memory tokens, uint256 tokenId) external;

    /// @notice Get gauge for a pool
    function gauges(address pool) external view returns (address);

    /// @notice Check if gauge is alive
    function isAlive(address gauge) external view returns (bool);
}

/// @notice Aerodrome Pair interface
interface IAerodromePair {
    function token0() external view returns (address);
    function token1() external view returns (address);
    function stable() external view returns (bool);
    function getReserves() external view returns (uint256 reserve0, uint256 reserve1, uint256 blockTimestampLast);
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transfer(address to, uint256 amount) external returns (bool);
}

// =============================================================================
// MOONWELL INTERFACES (Base Lending)
// =============================================================================

/// @notice Moonwell Comptroller (Unit Controller)
interface IMoonwellComptroller {
    /// @notice Enter markets to enable collateral
    function enterMarkets(address[] calldata mTokens) external returns (uint256[] memory);

    /// @notice Exit a market
    function exitMarket(address mToken) external returns (uint256);

    /// @notice Get account liquidity
    function getAccountLiquidity(address account)
        external view returns (uint256 error, uint256 liquidity, uint256 shortfall);

    /// @notice Claim WELL rewards (all markets)
    function claimReward() external;

    /// @notice Claim WELL rewards for specific markets
    function claimReward(address holder, address[] memory mTokens) external;

    /// @notice Get all markets
    function getAllMarkets() external view returns (address[] memory);

    /// @notice Check if market is listed
    function isMarketListed(address mToken) external view returns (bool);

    /// @notice Get collateral factor (1e18 scale)
    function markets(address mToken) external view returns (bool isListed, uint256 collateralFactor);
}

/// @notice Moonwell mToken interface (Compound-style)
interface IMToken {
    /// @notice Supply underlying to mint mTokens
    function mint(uint256 mintAmount) external returns (uint256);

    /// @notice Redeem mTokens for underlying
    function redeem(uint256 redeemTokens) external returns (uint256);

    /// @notice Redeem mTokens for exact underlying amount
    function redeemUnderlying(uint256 redeemAmount) external returns (uint256);

    /// @notice Borrow underlying
    function borrow(uint256 borrowAmount) external returns (uint256);

    /// @notice Repay borrow
    function repayBorrow(uint256 repayAmount) external returns (uint256);

    /// @notice Get mToken balance
    function balanceOf(address owner) external view returns (uint256);

    /// @notice Get underlying balance (accrues interest)
    function balanceOfUnderlying(address owner) external returns (uint256);

    /// @notice Get current borrow balance (accrues interest)
    function borrowBalanceCurrent(address account) external returns (uint256);

    /// @notice Get current exchange rate (accrues interest)
    function exchangeRateCurrent() external returns (uint256);

    /// @notice Get stored exchange rate (no accrual)
    function exchangeRateStored() external view returns (uint256);

    /// @notice Get underlying token address
    function underlying() external view returns (address);

    /// @notice Get supply rate per timestamp
    function supplyRatePerTimestamp() external view returns (uint256);

    /// @notice Get borrow rate per timestamp
    function borrowRatePerTimestamp() external view returns (uint256);

    /// @notice Get total supply
    function totalSupply() external view returns (uint256);

    /// @notice Get cash (uninvested underlying)
    function getCash() external view returns (uint256);

    /// @notice Get total borrows
    function totalBorrows() external view returns (uint256);

    /// @notice Get decimals
    function decimals() external view returns (uint8);

    /// @notice Approve
    function approve(address spender, uint256 amount) external returns (bool);
}

// =============================================================================
// SEAMLESS INTERFACES (Base Lending - Aave V3 Fork)
// =============================================================================

/// @notice Seamless Pool interface (Aave V3 style)
interface ISeamlessPool {
    /// @notice Supply assets to the pool
    function supply(
        address asset,
        uint256 amount,
        address onBehalfOf,
        uint16 referralCode
    ) external;

    /// @notice Withdraw assets from the pool
    function withdraw(
        address asset,
        uint256 amount,
        address to
    ) external returns (uint256);

    /// @notice Borrow assets from the pool
    function borrow(
        address asset,
        uint256 amount,
        uint256 interestRateMode,
        uint16 referralCode,
        address onBehalfOf
    ) external;

    /// @notice Repay borrowed assets
    function repay(
        address asset,
        uint256 amount,
        uint256 interestRateMode,
        address onBehalfOf
    ) external returns (uint256);

    /// @notice Get user account data
    function getUserAccountData(address user) external view returns (
        uint256 totalCollateralBase,
        uint256 totalDebtBase,
        uint256 availableBorrowsBase,
        uint256 currentLiquidationThreshold,
        uint256 ltv,
        uint256 healthFactor
    );

    /// @notice Get reserve data
    function getReserveData(address asset) external view returns (ReserveData memory);

    /// @notice Get aToken address for asset
    function getReserveAToken(address asset) external view returns (address);

    struct ReserveData {
        uint256 configuration;
        uint128 liquidityIndex;
        uint128 currentLiquidityRate;
        uint128 variableBorrowIndex;
        uint128 currentVariableBorrowRate;
        uint128 currentStableBorrowRate;
        uint40 lastUpdateTimestamp;
        uint16 id;
        address aTokenAddress;
        address stableDebtTokenAddress;
        address variableDebtTokenAddress;
        address interestRateStrategyAddress;
        uint128 accruedToTreasury;
        uint128 unbacked;
        uint128 isolationModeTotalDebt;
    }
}

/// @notice Seamless Rewards Controller
interface ISeamlessRewards {
    /// @notice Claim all rewards for assets
    function claimAllRewards(address[] calldata assets, address to)
        external returns (address[] memory rewardsList, uint256[] memory claimedAmounts);

    /// @notice Get user rewards
    function getUserRewards(address[] calldata assets, address user, address reward)
        external view returns (uint256);

    /// @notice Get all user rewards
    function getAllUserRewards(address[] calldata assets, address user)
        external view returns (address[] memory rewardsList, uint256[] memory unclaimedAmounts);
}

/// @notice Seamless aToken interface
interface ISeamlessAToken {
    function balanceOf(address account) external view returns (uint256);
    function scaledBalanceOf(address account) external view returns (uint256);
    function UNDERLYING_ASSET_ADDRESS() external view returns (address);
    function POOL() external view returns (address);
}

// =============================================================================
// AERODROME STRATEGY
// =============================================================================

/// @title Aerodrome LP Strategy
/// @notice Provides liquidity to Aerodrome pools and stakes in gauges for AERO rewards
/// @dev Implements ve(3,3) LP staking with auto-compounding of rewards
contract AerodromeStrategy is Ownable, ReentrancyGuard{
    using SafeERC20 for IERC20;

    // =========================================================================
    // CONSTANTS (Base Mainnet)
    // =========================================================================

    /// @notice Aerodrome Router
    address public constant ROUTER = 0xcF77a3Ba9A5CA399B7c97c74d54e5b1Beb874E43;

    /// @notice Aerodrome Voter
    address public constant VOTER = 0x16613524e02ad97eDfeF371bC883F2F5d6C480A5;

    /// @notice AERO token
    address public constant AERO = 0x940181a94A35A4569E4529A3CDfB74e38FD98631;

    /// @notice WETH on Base
    address public constant WETH = 0x4200000000000000000000000000000000000006;

    /// @notice Seconds per year for APY calculation
    uint256 internal constant SECONDS_PER_YEAR = 365.25 days;

    // =========================================================================
    // STATE
    // =========================================================================

    /// @notice LP token pair
    IAerodromePair public immutable pair;

    /// @notice Gauge for staking LP
    IAerodromeGauge public immutable gauge;

    /// @notice Token A of the pair
    IERC20 public immutable tokenA;

    /// @notice Token B of the pair
    IERC20 public immutable tokenB;

    /// @notice Whether pool is stable (correlated assets)
    bool public immutable isStable;

    /// @notice Controller address
    address public controller;

    /// @notice Total LP shares in gauge
    uint256 public stakedLP;

    /// @notice Total deposited in underlying terms
    uint256 public totalDeposited;

    /// @notice Whether strategy is paused
    bool public isPaused;

    /// @notice Accumulated harvested rewards
    uint256 public totalHarvested;

    // =========================================================================
    // EVENTS
    // =========================================================================

    event Deposited(address indexed depositor, uint256 amountA, uint256 amountB, uint256 lpReceived);
    event Withdrawn(address indexed recipient, uint256 amountA, uint256 amountB, uint256 lpBurned);
    event Harvested(uint256 aeroAmount, uint256 compoundedValue);
    event ControllerUpdated(address indexed oldController, address indexed newController);
    event RewardsCompounded(uint256 aeroSwapped, uint256 lpMinted);

    // =========================================================================
    // ERRORS
    // =========================================================================

    error StrategyPaused();
    error OnlyController();
    error InsufficientLP();
    error ZeroAmount();
    error InvalidPair();
    error InvalidGauge();
    error SlippageExceeded();

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

    /// @notice Create Aerodrome LP strategy
    /// @param _pair LP pair address
    /// @param _gauge Gauge address for staking
    /// @param _controller Controller that can deposit/withdraw
    /// @param _owner Owner address
    constructor(
        address _pair,
        address _gauge,
        address _controller,
        address _owner
    ) Ownable(_owner) {
        if (_pair == address(0)) revert InvalidPair();
        if (_gauge == address(0)) revert InvalidGauge();

        pair = IAerodromePair(_pair);
        gauge = IAerodromeGauge(_gauge);
        tokenA = IERC20(pair.token0());
        tokenB = IERC20(pair.token1());
        isStable = pair.stable();
        controller = _controller;

        // Approve router for token swaps
        tokenA.approve(ROUTER, type(uint256).max);
        tokenB.approve(ROUTER, type(uint256).max);
        IERC20(AERO).approve(ROUTER, type(uint256).max);

        // Approve gauge for LP staking
        IERC20(_pair).approve(_gauge, type(uint256).max);
    }

    // =========================================================================
    // YIELD STRATEGY INTERFACE
    // =========================================================================

    /// @notice
    /// @dev For Aerodrome, amount is interpreted as tokenA amount
    function deposit(uint256 amount) external onlyController whenNotPaused nonReentrant returns (uint256 shares) {
        if (amount == 0) revert ZeroAmount();

        // Transfer tokenA from controller
        tokenA.safeTransferFrom(msg.sender, address(this), amount);

        // Calculate proportional tokenB amount based on reserves
        (uint256 reserveA, uint256 reserveB,) = pair.getReserves();
        uint256 amountB = (amount * reserveB) / reserveA;

        // Transfer tokenB from controller
        tokenB.safeTransferFrom(msg.sender, address(this), amountB);

        // Add liquidity
        (uint256 usedA, uint256 usedB, uint256 lpReceived) = IAerodromeRouter(ROUTER).addLiquidity(
            address(tokenA),
            address(tokenB),
            isStable,
            amount,
            amountB,
            (amount * 99) / 100, // 1% slippage
            (amountB * 99) / 100,
            address(this),
            block.timestamp + 300
        );

        // Refund unused tokens
        if (amount > usedA) {
            tokenA.safeTransfer(msg.sender, amount - usedA);
        }
        if (amountB > usedB) {
            tokenB.safeTransfer(msg.sender, amountB - usedB);
        }

        // Stake LP in gauge
        gauge.deposit(lpReceived);

        stakedLP += lpReceived;
        totalDeposited += usedA + usedB;
        shares = lpReceived;

        emit Deposited(msg.sender, usedA, usedB, lpReceived);
    }

    /// @notice
    function withdraw(uint256 shares) external onlyController nonReentrant returns (uint256 amount) {
        if (shares == 0) revert ZeroAmount();
        if (shares > stakedLP) revert InsufficientLP();

        // Withdraw LP from gauge
        gauge.withdraw(shares);

        // Remove liquidity
        (uint256 amountA, uint256 amountB) = IAerodromeRouter(ROUTER).removeLiquidity(
            address(tokenA),
            address(tokenB),
            isStable,
            shares,
            0, // Accept any amount (controller handles slippage)
            0,
            msg.sender,
            block.timestamp + 300
        );

        stakedLP -= shares;
        amount = amountA + amountB;

        if (amount <= totalDeposited) {
            totalDeposited -= amount;
        } else {
            totalDeposited = 0;
        }

        emit Withdrawn(msg.sender, amountA, amountB, shares);
    }

    /// @notice
    function harvest() external returns (uint256 harvested) {
        // Claim AERO rewards
        gauge.getReward(address(this));

        uint256 aeroBalance = IERC20(AERO).balanceOf(address(this));
        if (aeroBalance == 0) return 0;

        // Swap half to tokenA, half to tokenB
        uint256 halfAero = aeroBalance / 2;

        // Build routes for swaps
        IAerodromeRouter.Route[] memory routeA = new IAerodromeRouter.Route[](1);
        routeA[0] = IAerodromeRouter.Route({
            from: AERO,
            to: address(tokenA),
            stable: false,
            factory: IAerodromeRouter(ROUTER).defaultFactory()
        });

        IAerodromeRouter.Route[] memory routeB = new IAerodromeRouter.Route[](1);
        routeB[0] = IAerodromeRouter.Route({
            from: AERO,
            to: address(tokenB),
            stable: false,
            factory: IAerodromeRouter(ROUTER).defaultFactory()
        });

        // Execute swaps
        uint256[] memory amountsA = IAerodromeRouter(ROUTER).swapExactTokensForTokens(
            halfAero,
            0,
            routeA,
            address(this),
            block.timestamp + 300
        );

        uint256[] memory amountsB = IAerodromeRouter(ROUTER).swapExactTokensForTokens(
            aeroBalance - halfAero,
            0,
            routeB,
            address(this),
            block.timestamp + 300
        );

        // Add liquidity with swapped tokens
        uint256 tokenABalance = IERC20(tokenA).balanceOf(address(this));
        uint256 tokenBBalance = IERC20(tokenB).balanceOf(address(this));

        if (tokenABalance > 0 && tokenBBalance > 0) {
            (,, uint256 lpMinted) = IAerodromeRouter(ROUTER).addLiquidity(
                address(tokenA),
                address(tokenB),
                isStable,
                tokenABalance,
                tokenBBalance,
                0,
                0,
                address(this),
                block.timestamp + 300
            );

            // Stake new LP
            if (lpMinted > 0) {
                gauge.deposit(lpMinted);
                stakedLP += lpMinted;
            }

            emit RewardsCompounded(aeroBalance, lpMinted);
        }

        harvested = aeroBalance;
        totalHarvested += harvested;

        emit Harvested(aeroBalance, amountsA[amountsA.length - 1] + amountsB[amountsB.length - 1]);
    }

    /// @notice
    function totalAssets() external view returns (uint256) {
        if (stakedLP == 0) return 0;

        (uint256 reserveA, uint256 reserveB,) = pair.getReserves();
        uint256 totalLPSupply = pair.totalSupply();

        // Calculate our share of reserves
        uint256 shareA = (stakedLP * reserveA) / totalLPSupply;
        uint256 shareB = (stakedLP * reserveB) / totalLPSupply;

        return shareA + shareB;
    }

    /// @notice
    function currentAPY() external view returns (uint256) {
        uint256 totalStaked = gauge.totalSupply();
        if (totalStaked == 0) return 0;

        // Get reward rate (AERO per second)
        uint256 rewardRate = gauge.rewardRate();

        // Annualize: rewardRate * secondsPerYear
        uint256 annualRewards = rewardRate * SECONDS_PER_YEAR;

        // Estimate AERO value in terms of underlying
        // Simplified: assume 1 AERO = 0.1 ETH worth
        // In production, use oracle or TWAP
        uint256 rewardValue = annualRewards / 10;

        // APY = (annualRewards / totalStaked) * 10000 (basis points)
        return (rewardValue * 10000) / totalStaked;
    }

    /// @notice
    function underlying() external view returns (address) {
        return address(tokenA);
    }

    /// @notice
    function yieldToken() external view returns (address) {
        return address(pair);
    }

    /// @notice
    function isActive() external view returns (bool) {
        return !isPaused && stakedLP > 0;
    }

    /// @notice
    function name() external pure returns (string memory) {
        return "Aerodrome LP";
    }

    // =========================================================================
    // VIEW FUNCTIONS
    // =========================================================================

    /// @notice Get pending AERO rewards
    function pendingRewards() external view returns (uint256) {
        return gauge.earned(address(this));
    }

    /// @notice Get LP token balances
    function getLPBalance() external view returns (uint256 staked, uint256 unstaked) {
        staked = stakedLP;
        unstaked = pair.balanceOf(address(this));
    }

    /// @notice Get reserve ratios
    function getReserves() external view returns (uint256 reserveA, uint256 reserveB) {
        (reserveA, reserveB,) = pair.getReserves();
    }

    // =========================================================================
    // ADMIN FUNCTIONS
    // =========================================================================

    /// @notice Set controller address
    function setController(address _controller) external onlyOwner {
        emit ControllerUpdated(controller, _controller);
        controller = _controller;
    }

    /// @notice Pause/unpause strategy
    function setPaused(bool _paused) external onlyOwner {
        isPaused = _paused;
    }

    /// @notice Emergency withdraw all LP
    function emergencyWithdraw() external onlyOwner {
        if (stakedLP > 0) {
            gauge.withdraw(stakedLP);
            IERC20(address(pair)).safeTransfer(owner(), stakedLP);
            stakedLP = 0;
            totalDeposited = 0;
        }
    }

    /// @notice Rescue stuck tokens
    function rescueTokens(address token, uint256 amount) external onlyOwner {
        require(token != address(pair), "Cannot rescue LP");
        require(token != address(gauge), "Cannot rescue gauge");
        IERC20(token).safeTransfer(owner(), amount);
    }
}

// =============================================================================
// MOONWELL STRATEGY
// =============================================================================

/// @title Moonwell Lending Strategy
/// @notice Supplies assets to Moonwell on Base for yield
/// @dev Compound-fork with WELL token rewards
contract MoonwellStrategy is Ownable, ReentrancyGuard{
    using SafeERC20 for IERC20;

    // =========================================================================
    // CONSTANTS (Base Mainnet)
    // =========================================================================

    /// @notice Moonwell Comptroller
    address public constant COMPTROLLER = 0xfBb21d0380beE3312B33c4353c8936a0F13EF26C;

    /// @notice WELL token
    address public constant WELL = 0xA88594D404727625A9437C3f886C7643872296AE;

    /// @notice Seconds per year for APY calculation
    uint256 internal constant SECONDS_PER_YEAR = 365.25 days;

    /// @notice Mantissa for exchange rate (1e18)
    uint256 internal constant MANTISSA = 1e18;

    // =========================================================================
    // STATE
    // =========================================================================

    /// @notice mToken address
    IMToken public immutable mToken;

    /// @notice Underlying asset
    IERC20 public immutable underlyingAsset;

    /// @notice Controller address
    address public controller;

    /// @notice Total mTokens held
    uint256 public mTokenBalance;

    /// @notice Total deposited (for yield tracking)
    uint256 public totalDeposited;

    /// @notice Whether strategy is paused
    bool public isPaused;

    // =========================================================================
    // EVENTS
    // =========================================================================

    event Deposited(address indexed depositor, uint256 underlyingAmount, uint256 mTokensReceived);
    event Withdrawn(address indexed recipient, uint256 underlyingAmount, uint256 mTokensBurned);
    event Harvested(uint256 wellAmount);
    event ControllerUpdated(address indexed oldController, address indexed newController);

    // =========================================================================
    // ERRORS
    // =========================================================================

    error StrategyPaused();
    error OnlyController();
    error InsufficientMTokens();
    error ZeroAmount();
    error InvalidMToken();
    error MintFailed(uint256 errorCode);
    error RedeemFailed(uint256 errorCode);

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

    /// @notice Create Moonwell lending strategy
    /// @param _mToken mToken address (e.g., mUSDC)
    /// @param _controller Controller that can deposit/withdraw
    /// @param _owner Owner address
    constructor(
        address _mToken,
        address _controller,
        address _owner
    ) Ownable(_owner) {
        if (_mToken == address(0)) revert InvalidMToken();

        mToken = IMToken(_mToken);
        underlyingAsset = IERC20(mToken.underlying());
        controller = _controller;

        // Approve mToken to spend underlying
        underlyingAsset.approve(_mToken, type(uint256).max);

        // Enter market to enable collateral
        address[] memory markets = new address[](1);
        markets[0] = _mToken;
        IMoonwellComptroller(COMPTROLLER).enterMarkets(markets);
    }

    // =========================================================================
    // YIELD STRATEGY INTERFACE
    // =========================================================================

    /// @notice
    function deposit(uint256 amount) external onlyController whenNotPaused nonReentrant returns (uint256 shares) {
        if (amount == 0) revert ZeroAmount();

        // Transfer underlying from controller
        underlyingAsset.safeTransferFrom(msg.sender, address(this), amount);

        // Get mTokens before mint
        uint256 mTokensBefore = mToken.balanceOf(address(this));

        // Mint mTokens
        uint256 error = mToken.mint(amount);
        if (error != 0) revert MintFailed(error);

        // Calculate mTokens received
        shares = mToken.balanceOf(address(this)) - mTokensBefore;

        mTokenBalance += shares;
        totalDeposited += amount;

        emit Deposited(msg.sender, amount, shares);
    }

    /// @notice
    function withdraw(uint256 shares) external onlyController nonReentrant returns (uint256 amount) {
        if (shares == 0) revert ZeroAmount();
        if (shares > mTokenBalance) revert InsufficientMTokens();

        // Get underlying before redeem
        uint256 underlyingBefore = underlyingAsset.balanceOf(address(this));

        // Redeem mTokens
        uint256 error = mToken.redeem(shares);
        if (error != 0) revert RedeemFailed(error);

        // Calculate underlying received
        amount = underlyingAsset.balanceOf(address(this)) - underlyingBefore;

        // Transfer to controller
        underlyingAsset.safeTransfer(msg.sender, amount);

        mTokenBalance -= shares;
        if (amount <= totalDeposited) {
            totalDeposited -= amount;
        } else {
            totalDeposited = 0;
        }

        emit Withdrawn(msg.sender, amount, shares);
    }

    /// @notice
    function harvest() external returns (uint256 harvested) {
        // Claim WELL rewards
        address[] memory markets = new address[](1);
        markets[0] = address(mToken);
        IMoonwellComptroller(COMPTROLLER).claimReward(address(this), markets);

        harvested = IERC20(WELL).balanceOf(address(this));

        if (harvested > 0) {
            // Transfer WELL to owner for manual compounding
            // Or implement swap logic here
            IERC20(WELL).safeTransfer(owner(), harvested);
            emit Harvested(harvested);
        }
    }

    /// @notice
    function totalAssets() external view returns (uint256) {
        if (mTokenBalance == 0) return 0;

        // Calculate underlying value using exchange rate
        uint256 exchangeRate = mToken.exchangeRateStored();
        return (mTokenBalance * exchangeRate) / MANTISSA;
    }

    /// @notice
    function currentAPY() external view returns (uint256) {
        // Get supply rate per timestamp (scaled by 1e18)
        uint256 supplyRatePerTimestamp = mToken.supplyRatePerTimestamp();

        // Annualize: rate * seconds_per_year * 10000 (basis points)
        return (supplyRatePerTimestamp * SECONDS_PER_YEAR * 10000) / MANTISSA;
    }

    /// @notice
    function underlying() external view returns (address) {
        return address(underlyingAsset);
    }

    /// @notice
    function yieldToken() external view returns (address) {
        return address(mToken);
    }

    /// @notice
    function isActive() external view returns (bool) {
        return !isPaused && mTokenBalance > 0;
    }

    /// @notice
    function name() external pure returns (string memory) {
        return "Moonwell Lending";
    }

    // =========================================================================
    // VIEW FUNCTIONS
    // =========================================================================

    /// @notice Get current exchange rate
    function getExchangeRate() external view returns (uint256) {
        return mToken.exchangeRateStored();
    }

    /// @notice Get supply and borrow rates
    function getRates() external view returns (uint256 supplyRate, uint256 borrowRate) {
        supplyRate = mToken.supplyRatePerTimestamp();
        borrowRate = mToken.borrowRatePerTimestamp();
    }

    /// @notice Get account liquidity
    function getAccountLiquidity() external view returns (uint256 error, uint256 liquidity, uint256 shortfall) {
        return IMoonwellComptroller(COMPTROLLER).getAccountLiquidity(address(this));
    }

    /// @notice Get underlying balance (accrues interest)
    function getUnderlyingBalance() external returns (uint256) {
        return mToken.balanceOfUnderlying(address(this));
    }

    // =========================================================================
    // ADMIN FUNCTIONS
    // =========================================================================

    /// @notice Set controller address
    function setController(address _controller) external onlyOwner {
        emit ControllerUpdated(controller, _controller);
        controller = _controller;
    }

    /// @notice Pause/unpause strategy
    function setPaused(bool _paused) external onlyOwner {
        isPaused = _paused;
    }

    /// @notice Emergency withdraw all assets
    function emergencyWithdraw() external onlyOwner {
        if (mTokenBalance > 0) {
            mToken.redeem(mTokenBalance);
            uint256 balance = underlyingAsset.balanceOf(address(this));
            underlyingAsset.safeTransfer(owner(), balance);
            mTokenBalance = 0;
            totalDeposited = 0;
        }
    }

    /// @notice Rescue stuck tokens
    function rescueTokens(address token, uint256 amount) external onlyOwner {
        require(token != address(underlyingAsset), "Cannot rescue underlying");
        require(token != address(mToken), "Cannot rescue mToken");
        IERC20(token).safeTransfer(owner(), amount);
    }
}

// =============================================================================
// SEAMLESS STRATEGY
// =============================================================================

/// @title Seamless Protocol Lending Strategy
/// @notice Supplies assets to Seamless Protocol on Base for yield
/// @dev Aave V3 fork with native Base integrations
contract SeamlessStrategy is Ownable, ReentrancyGuard{
    using SafeERC20 for IERC20;

    // =========================================================================
    // CONSTANTS (Base Mainnet)
    // =========================================================================

    /// @notice Seamless Pool
    address public constant POOL = 0x8F44Fd754285aa6A2b8B9B97739B79746e0475a7;

    /// @notice Seamless Rewards Controller
    address public constant REWARDS = 0x91Ac2FfF8CBeF5859eAA6DdA661feBd533cD3780;

    /// @notice SEAM token
    address public constant SEAM = 0x1C7a460413dD4e964f96D8dFC56E7223cE88CD85;

    /// @notice Seconds per year for APY calculation
    uint256 internal constant SECONDS_PER_YEAR = 365.25 days;

    /// @notice RAY (1e27) for rate scaling
    uint256 internal constant RAY = 1e27;

    /// @notice Referral code (0 = none)
    uint16 internal constant REFERRAL_CODE = 0;

    // =========================================================================
    // STATE
    // =========================================================================

    /// @notice Underlying asset
    IERC20 public immutable underlyingAsset;

    /// @notice aToken address
    ISeamlessAToken public aToken;

    /// @notice Controller address
    address public controller;

    /// @notice Total deposited (for yield tracking)
    uint256 public totalDeposited;

    /// @notice Whether strategy is paused
    bool public isPaused;

    // =========================================================================
    // EVENTS
    // =========================================================================

    event Deposited(address indexed depositor, uint256 amount);
    event Withdrawn(address indexed recipient, uint256 amount);
    event Harvested(uint256 seamAmount);
    event ControllerUpdated(address indexed oldController, address indexed newController);

    // =========================================================================
    // ERRORS
    // =========================================================================

    error StrategyPaused();
    error OnlyController();
    error InsufficientBalance();
    error ZeroAmount();
    error InvalidAsset();

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

    /// @notice Create Seamless lending strategy
    /// @param _underlying Underlying asset address
    /// @param _controller Controller that can deposit/withdraw
    /// @param _owner Owner address
    constructor(
        address _underlying,
        address _controller,
        address _owner
    ) Ownable(_owner) {
        if (_underlying == address(0)) revert InvalidAsset();

        underlyingAsset = IERC20(_underlying);
        controller = _controller;

        // Get aToken address from pool
        ISeamlessPool.ReserveData memory reserveData = ISeamlessPool(POOL).getReserveData(_underlying);
        aToken = ISeamlessAToken(reserveData.aTokenAddress);

        // Approve pool to spend underlying
        underlyingAsset.approve(POOL, type(uint256).max);
    }

    // =========================================================================
    // YIELD STRATEGY INTERFACE
    // =========================================================================

    /// @notice
    function deposit(uint256 amount) external onlyController whenNotPaused nonReentrant returns (uint256 shares) {
        if (amount == 0) revert ZeroAmount();

        // Transfer underlying from controller
        underlyingAsset.safeTransferFrom(msg.sender, address(this), amount);

        // Supply to Seamless
        ISeamlessPool(POOL).supply(
            address(underlyingAsset),
            amount,
            address(this),
            REFERRAL_CODE
        );

        totalDeposited += amount;
        shares = amount; // 1:1 for aTokens

        emit Deposited(msg.sender, amount);
    }

    /// @notice
    function withdraw(uint256 shares) external onlyController nonReentrant returns (uint256 amount) {
        if (shares == 0) revert ZeroAmount();

        uint256 balance = aToken.balanceOf(address(this));
        if (shares > balance) revert InsufficientBalance();

        // Withdraw from Seamless
        amount = ISeamlessPool(POOL).withdraw(
            address(underlyingAsset),
            shares,
            msg.sender
        );

        if (amount <= totalDeposited) {
            totalDeposited -= amount;
        } else {
            totalDeposited = 0;
        }

        emit Withdrawn(msg.sender, amount);
    }

    /// @notice
    function harvest() external returns (uint256 harvested) {
        // Build assets array
        address[] memory assets = new address[](1);
        assets[0] = address(aToken);

        // Claim all rewards
        (address[] memory rewardsList, uint256[] memory amounts) =
            ISeamlessRewards(REWARDS).claimAllRewards(assets, address(this));

        // Sum all rewards (may be multiple tokens)
        for (uint256 i = 0; i < amounts.length; i++) {
            harvested += amounts[i];
        }

        if (harvested > 0) {
            // Transfer SEAM to owner for manual compounding
            uint256 seamBalance = IERC20(SEAM).balanceOf(address(this));
            if (seamBalance > 0) {
                IERC20(SEAM).safeTransfer(owner(), seamBalance);
            }
            emit Harvested(harvested);
        }
    }

    /// @notice
    function totalAssets() external view returns (uint256) {
        return aToken.balanceOf(address(this));
    }

    /// @notice
    function currentAPY() external view returns (uint256) {
        // Get reserve data
        ISeamlessPool.ReserveData memory data = ISeamlessPool(POOL).getReserveData(address(underlyingAsset));

        // Current liquidity rate is in RAY (1e27), annual
        uint256 liquidityRate = uint256(data.currentLiquidityRate);

        // Convert to basis points: (rate / RAY) * 10000
        return (liquidityRate * 10000) / RAY;
    }

    /// @notice
    function underlying() external view returns (address) {
        return address(underlyingAsset);
    }

    /// @notice
    function yieldToken() external view returns (address) {
        return address(aToken);
    }

    /// @notice
    function isActive() external view returns (bool) {
        return !isPaused && aToken.balanceOf(address(this)) > 0;
    }

    /// @notice
    function name() external pure returns (string memory) {
        return "Seamless Lending";
    }

    // =========================================================================
    // VIEW FUNCTIONS
    // =========================================================================

    /// @notice Get aToken balance
    function getATokenBalance() external view returns (uint256) {
        return aToken.balanceOf(address(this));
    }

    /// @notice Get user account data
    function getAccountData() external view returns (
        uint256 totalCollateral,
        uint256 totalDebt,
        uint256 availableBorrows,
        uint256 liquidationThreshold,
        uint256 ltv,
        uint256 healthFactor
    ) {
        return ISeamlessPool(POOL).getUserAccountData(address(this));
    }

    /// @notice Get pending rewards
    function getPendingRewards() external view returns (uint256) {
        address[] memory assets = new address[](1);
        assets[0] = address(aToken);

        return ISeamlessRewards(REWARDS).getUserRewards(assets, address(this), SEAM);
    }

    /// @notice Get reserve data
    function getReserveData() external view returns (
        uint256 liquidityRate,
        uint256 variableBorrowRate,
        uint256 stableBorrowRate
    ) {
        ISeamlessPool.ReserveData memory data = ISeamlessPool(POOL).getReserveData(address(underlyingAsset));
        liquidityRate = uint256(data.currentLiquidityRate);
        variableBorrowRate = uint256(data.currentVariableBorrowRate);
        stableBorrowRate = uint256(data.currentStableBorrowRate);
    }

    // =========================================================================
    // ADMIN FUNCTIONS
    // =========================================================================

    /// @notice Set controller address
    function setController(address _controller) external onlyOwner {
        emit ControllerUpdated(controller, _controller);
        controller = _controller;
    }

    /// @notice Pause/unpause strategy
    function setPaused(bool _paused) external onlyOwner {
        isPaused = _paused;
    }

    /// @notice Emergency withdraw all assets
    function emergencyWithdraw() external onlyOwner {
        uint256 balance = aToken.balanceOf(address(this));
        if (balance > 0) {
            ISeamlessPool(POOL).withdraw(
                address(underlyingAsset),
                type(uint256).max, // Max withdrawal
                owner()
            );
            totalDeposited = 0;
        }
    }

    /// @notice Rescue stuck tokens
    function rescueTokens(address token, uint256 amount) external onlyOwner {
        require(token != address(underlyingAsset), "Cannot rescue underlying");
        require(token != address(aToken), "Cannot rescue aToken");
        IERC20(token).safeTransfer(owner(), amount);
    }
}

// =============================================================================
// FACTORY
// =============================================================================

/// @title Base Strategies Factory
/// @notice Factory for deploying Base chain yield strategies
contract BaseStrategiesFactory is Ownable {

    // =========================================================================
    // EVENTS
    // =========================================================================

    event AerodromeStrategyDeployed(
        address indexed strategy,
        address indexed pair,
        address indexed gauge
    );

    event MoonwellStrategyDeployed(
        address indexed strategy,
        address indexed mToken,
        address indexed underlying
    );

    event SeamlessStrategyDeployed(
        address indexed strategy,
        address indexed underlying
    );

    // =========================================================================
    // CONSTRUCTOR
    // =========================================================================

    constructor() Ownable(msg.sender) {}

    // =========================================================================
    // DEPLOYMENT FUNCTIONS
    // =========================================================================

    /// @notice Deploy Aerodrome LP strategy
    /// @param pair LP pair address
    /// @param gauge Gauge address
    /// @param controller Controller address
    function deployAerodromeStrategy(
        address pair,
        address gauge,
        address controller
    ) external onlyOwner returns (address) {
        AerodromeStrategy strategy = new AerodromeStrategy(
            pair,
            gauge,
            controller,
            msg.sender
        );

        emit AerodromeStrategyDeployed(address(strategy), pair, gauge);
        return address(strategy);
    }

    /// @notice Deploy Moonwell lending strategy
    /// @param mToken mToken address
    /// @param controller Controller address
    function deployMoonwellStrategy(
        address mToken,
        address controller
    ) external onlyOwner returns (address) {
        MoonwellStrategy strategy = new MoonwellStrategy(
            mToken,
            controller,
            msg.sender
        );

        emit MoonwellStrategyDeployed(address(strategy), mToken, IMToken(mToken).underlying());
        return address(strategy);
    }

    /// @notice Deploy Seamless lending strategy
    /// @param underlying Underlying asset address
    /// @param controller Controller address
    function deploySeamlessStrategy(
        address underlying,
        address controller
    ) external onlyOwner returns (address) {
        SeamlessStrategy strategy = new SeamlessStrategy(
            underlying,
            controller,
            msg.sender
        );

        emit SeamlessStrategyDeployed(address(strategy), underlying);
        return address(strategy);
    }
}
