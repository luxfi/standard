// SPDX-License-Identifier: MIT
pragma solidity ^0.8.31;

import {IERC20, SafeERC20} from "@luxfi/standard/tokens/ERC20.sol";
import {Ownable} from "@luxfi/standard/access/Access.sol";
import {ReentrancyGuard} from "@luxfi/standard/utils/Utils.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

/**
 * @title ProtocolLiquidity
 * @author Lux Industries Inc
 * @notice Build Protocol Owned Liquidity (POL) over time
 * @dev Implements OHM-style LP bonding for permanent protocol liquidity
 *
 * ## How POL Building Works
 *
 * 1. **LP Bonding**: Users deposit LP tokens → receive ASHA at discount
 *    - Protocol keeps LP tokens permanently (POL)
 *    - Discount incentivizes LP migration to protocol ownership
 *    - Vesting prevents immediate sell pressure
 *
 * 2. **Single-Sided Deposits**: Users deposit single asset
 *    - Protocol pairs with treasury reserves to create LP
 *    - User receives ASHA at smaller discount
 *    - Simpler UX for users who don't want to manage LP
 *
 * 3. **Revenue Accumulation**: Protocol earns trading fees from owned LP
 *    - Fees compound into more liquidity
 *    - Creates sustainable protocol revenue
 *
 * ## Liquidity Growth Phases
 *
 * Phase 1: Bootstrap (high discounts, aggressive accumulation)
 * Phase 2: Growth (moderate discounts, steady accumulation)
 * Phase 3: Maturity (low discounts, maintenance mode)
 *
 * ## Key Principle: Liquidity is Protocol Infrastructure
 * Deep liquidity enables: stable pricing, large trades, confidence
 */
interface ILiquidityPool {
    function token0() external view returns (address);
    function token1() external view returns (address);
    function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32 timestamp);
    function totalSupply() external view returns (uint256);
}

interface IMintable {
    function mint(address to, uint256 amount) external;
}

interface IPriceOracle {
    function getPrice(address token) external view returns (uint256 priceInSats);
}

contract ProtocolLiquidity is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // ═══════════════════════════════════════════════════════════════════════
    // CONSTANTS
    // ═══════════════════════════════════════════════════════════════════════

    uint256 public constant BPS = 10000;
    uint256 public constant MAX_DISCOUNT = 3000; // 30% max discount

    // ═══════════════════════════════════════════════════════════════════════
    // STATE
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice Protocol token (ASHA)
    address public immutable protocolToken;

    /// @notice Treasury that holds POL
    address public immutable treasury;

    /// @notice Price oracle for valuations
    IPriceOracle public oracle;

    /// @notice LP pool configuration
    struct PoolConfig {
        address lpToken;           // LP token address
        address token0;            // First token in pair
        address token1;            // Second token in pair
        uint256 discount;          // Discount in BPS (e.g., 1500 = 15%)
        uint256 vestingPeriod;     // Vesting duration
        uint256 maxCapacity;       // Max LP to accept
        uint256 totalDeposited;    // Current deposits
        bool active;               // Whether accepting deposits
    }

    /// @notice Single-sided deposit configuration
    struct SingleSidedConfig {
        address token;             // Token to accept
        uint256 discount;          // Discount (lower than LP)
        uint256 vestingPeriod;     // Vesting duration
        uint256 maxCapacity;       // Max to accept
        uint256 totalDeposited;    // Current deposits
        address pairedPool;        // LP pool to create liquidity in
        bool active;
    }

    /// @notice User's vesting position
    struct VestingPosition {
        uint256 totalOwed;         // Total ASHA owed
        uint256 claimed;           // Amount claimed
        uint256 vestingStart;
        uint256 vestingEnd;
    }

    /// @notice LP pool configs by ID
    mapping(uint256 => PoolConfig) public pools;
    uint256 public nextPoolId;

    /// @notice Single-sided configs by ID
    mapping(uint256 => SingleSidedConfig) public singleSided;
    uint256 public nextSingleSidedId;

    /// @notice User vesting positions: user => positionId => position
    mapping(address => mapping(uint256 => VestingPosition)) public positions;
    mapping(address => uint256) public userPositionCount;

    /// @notice Protocol liquidity stats
    uint256 public totalPOLValue;       // Total POL value in sats
    uint256 public totalASHABonded;     // Total ASHA distributed via bonding

    // ═══════════════════════════════════════════════════════════════════════
    // EVENTS
    // ═══════════════════════════════════════════════════════════════════════

    event PoolAdded(uint256 indexed poolId, address lpToken, uint256 discount);
    event SingleSidedAdded(uint256 indexed id, address token, uint256 discount);
    event LPBonded(address indexed user, uint256 indexed poolId, uint256 lpAmount, uint256 ashaOwed);
    event SingleSidedDeposit(address indexed user, uint256 indexed configId, uint256 amount, uint256 ashaOwed);
    event Claimed(address indexed user, uint256 indexed positionId, uint256 amount);
    event PoolCapacityUpdated(uint256 indexed poolId, uint256 newCapacity);
    event DiscountUpdated(uint256 indexed poolId, uint256 newDiscount);
    event PoolActiveStatusUpdated(uint256 indexed poolId, bool active);
    event OracleUpdated(address indexed newOracle);

    // ═══════════════════════════════════════════════════════════════════════
    // ERRORS
    // ═══════════════════════════════════════════════════════════════════════

    error PoolNotActive();
    error ExceedsCapacity();
    error InvalidDiscount();
    error NothingToClaim();
    error InvalidPool();
    error ZeroAddress();
    error TooManyPositions();

    uint256 public constant MAX_BATCH_SIZE = 50;

    // ═══════════════════════════════════════════════════════════════════════
    // CONSTRUCTOR
    // ═══════════════════════════════════════════════════════════════════════

    constructor(
        address protocolToken_,
        address treasury_,
        address oracle_,
        address owner_
    ) Ownable(owner_) {
        if (protocolToken_ == address(0)) revert ZeroAddress();
        if (treasury_ == address(0)) revert ZeroAddress();
        if (oracle_ == address(0)) revert ZeroAddress();
        if (owner_ == address(0)) revert ZeroAddress();
        protocolToken = protocolToken_;
        treasury = treasury_;
        oracle = IPriceOracle(oracle_);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // ADMIN: POOL MANAGEMENT
    // ═══════════════════════════════════════════════════════════════════════

    /**
     * @notice Add LP pool for bonding
     * @param lpToken LP token address
     * @param discount Discount in BPS
     * @param vestingPeriod Vesting duration
     * @param maxCapacity Maximum LP to accept
     */
    function addPool(
        address lpToken,
        uint256 discount,
        uint256 vestingPeriod,
        uint256 maxCapacity
    ) external onlyOwner returns (uint256 poolId) {
        if (lpToken == address(0)) revert ZeroAddress();
        if (discount > MAX_DISCOUNT) revert InvalidDiscount();

        ILiquidityPool pool = ILiquidityPool(lpToken);

        poolId = nextPoolId++;
        pools[poolId] = PoolConfig({
            lpToken: lpToken,
            token0: pool.token0(),
            token1: pool.token1(),
            discount: discount,
            vestingPeriod: vestingPeriod,
            maxCapacity: maxCapacity,
            totalDeposited: 0,
            active: true
        });

        emit PoolAdded(poolId, lpToken, discount);
    }

    /**
     * @notice Add single-sided deposit option
     */
    function addSingleSided(
        address token,
        uint256 discount,
        uint256 vestingPeriod,
        uint256 maxCapacity,
        address pairedPool
    ) external onlyOwner returns (uint256 id) {
        if (token == address(0)) revert ZeroAddress();
        if (pairedPool == address(0)) revert ZeroAddress();
        if (discount > MAX_DISCOUNT) revert InvalidDiscount();

        id = nextSingleSidedId++;
        singleSided[id] = SingleSidedConfig({
            token: token,
            discount: discount,
            vestingPeriod: vestingPeriod,
            maxCapacity: maxCapacity,
            totalDeposited: 0,
            pairedPool: pairedPool,
            active: true
        });

        emit SingleSidedAdded(id, token, discount);
    }

    /**
     * @notice Update pool discount (for phase transitions)
     */
    function setPoolDiscount(uint256 poolId, uint256 newDiscount) external onlyOwner {
        if (newDiscount > MAX_DISCOUNT) revert InvalidDiscount();
        pools[poolId].discount = newDiscount;
        emit DiscountUpdated(poolId, newDiscount);
    }

    /**
     * @notice Update pool capacity
     */
    function setPoolCapacity(uint256 poolId, uint256 newCapacity) external onlyOwner {
        pools[poolId].maxCapacity = newCapacity;
        emit PoolCapacityUpdated(poolId, newCapacity);
    }

    /**
     * @notice Toggle pool active status
     */
    function setPoolActive(uint256 poolId, bool active) external onlyOwner {
        pools[poolId].active = active;
        emit PoolActiveStatusUpdated(poolId, active);
    }

    /**
     * @notice Update oracle
     */
    function setOracle(address newOracle) external onlyOwner {
        if (newOracle == address(0)) revert ZeroAddress();
        oracle = IPriceOracle(newOracle);
        emit OracleUpdated(newOracle);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // USER: LP BONDING
    // ═══════════════════════════════════════════════════════════════════════

    /**
     * @notice Bond LP tokens for ASHA at discount
     * @param poolId Pool to bond to
     * @param lpAmount Amount of LP tokens
     * @return positionId User's vesting position ID
     */
    function bondLP(uint256 poolId, uint256 lpAmount) external nonReentrant returns (uint256 positionId) {
        PoolConfig storage pool = pools[poolId];

        if (!pool.active) revert PoolNotActive();
        if (pool.totalDeposited + lpAmount > pool.maxCapacity) revert ExceedsCapacity();

        // Calculate LP value in sats
        uint256 lpValue = _getLPValue(pool.lpToken, lpAmount);

        // Calculate ASHA owed with discount
        // If discount is 1500 (15%), user gets 115 ASHA for 100 sats of LP
        uint256 ashaPrice = oracle.getPrice(protocolToken);
        uint256 ashaOwed = (lpValue * (BPS + pool.discount)) / (ashaPrice);

        // Transfer LP to treasury (permanent POL)
        IERC20(pool.lpToken).safeTransferFrom(msg.sender, treasury, lpAmount);

        // Create vesting position
        positionId = userPositionCount[msg.sender]++;
        positions[msg.sender][positionId] = VestingPosition({
            totalOwed: ashaOwed,
            claimed: 0,
            vestingStart: block.timestamp,
            vestingEnd: block.timestamp + pool.vestingPeriod
        });

        // Update stats
        pool.totalDeposited += lpAmount;
        totalPOLValue += lpValue;
        totalASHABonded += ashaOwed;

        emit LPBonded(msg.sender, poolId, lpAmount, ashaOwed);
    }

    /**
     * @notice Single-sided deposit for ASHA
     * @param configId Single-sided config ID
     * @param amount Token amount to deposit
     */
    function depositSingleSided(uint256 configId, uint256 amount) external nonReentrant returns (uint256 positionId) {
        SingleSidedConfig storage config = singleSided[configId];

        if (!config.active) revert PoolNotActive();
        if (config.totalDeposited + amount > config.maxCapacity) revert ExceedsCapacity();

        // Calculate value in sats
        uint256 tokenPrice = oracle.getPrice(config.token);
        uint256 value = (amount * tokenPrice) / 1e18;

        // Calculate ASHA owed (smaller discount than LP)
        uint256 ashaPrice = oracle.getPrice(protocolToken);
        uint256 ashaOwed = (value * (BPS + config.discount)) / ashaPrice;

        // Transfer to treasury
        IERC20(config.token).safeTransferFrom(msg.sender, treasury, amount);

        // Create vesting position
        positionId = userPositionCount[msg.sender]++;
        positions[msg.sender][positionId] = VestingPosition({
            totalOwed: ashaOwed,
            claimed: 0,
            vestingStart: block.timestamp,
            vestingEnd: block.timestamp + config.vestingPeriod
        });

        config.totalDeposited += amount;
        totalASHABonded += ashaOwed;

        emit SingleSidedDeposit(msg.sender, configId, amount, ashaOwed);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // USER: CLAIMING
    // ═══════════════════════════════════════════════════════════════════════

    /**
     * @notice Claim vested ASHA
     * @param positionId Position to claim from
     */
    function claim(uint256 positionId) external nonReentrant {
        VestingPosition storage pos = positions[msg.sender][positionId];

        uint256 claimable = _claimable(pos);
        if (claimable == 0) revert NothingToClaim();

        pos.claimed += claimable;

        // Mint ASHA to user
        IMintable(protocolToken).mint(msg.sender, claimable);

        emit Claimed(msg.sender, positionId, claimable);
    }

    /**
     * @notice Claim from multiple positions (max MAX_BATCH_SIZE)
     * @dev Use claimBatch for users with > MAX_BATCH_SIZE positions
     */
    function claimAll() external nonReentrant {
        uint256 count = userPositionCount[msg.sender];
        if (count > MAX_BATCH_SIZE) revert TooManyPositions();

        uint256 total = 0;
        for (uint256 i = 0; i < count; i++) {
            VestingPosition storage pos = positions[msg.sender][i];
            uint256 claimableAmt = _claimable(pos);
            if (claimableAmt > 0) {
                pos.claimed += claimableAmt;
                total += claimableAmt;
                emit Claimed(msg.sender, i, claimableAmt);
            }
        }

        if (total == 0) revert NothingToClaim();
        IMintable(protocolToken).mint(msg.sender, total);
    }

    /**
     * @notice Claim from a batch of positions
     * @param startIndex Starting position index
     * @param count Number of positions to claim (max MAX_BATCH_SIZE)
     */
    function claimBatch(uint256 startIndex, uint256 count) external nonReentrant {
        if (count > MAX_BATCH_SIZE) revert TooManyPositions();

        uint256 userCount = userPositionCount[msg.sender];
        uint256 endIndex = startIndex + count;
        if (endIndex > userCount) endIndex = userCount;

        uint256 total = 0;
        for (uint256 i = startIndex; i < endIndex; i++) {
            VestingPosition storage pos = positions[msg.sender][i];
            uint256 claimableAmt = _claimable(pos);
            if (claimableAmt > 0) {
                pos.claimed += claimableAmt;
                total += claimableAmt;
                emit Claimed(msg.sender, i, claimableAmt);
            }
        }

        if (total == 0) revert NothingToClaim();
        IMintable(protocolToken).mint(msg.sender, total);
    }

    /**
     * @notice Get user's position count
     */
    function getPositionCount(address user) external view returns (uint256) {
        return userPositionCount[user];
    }

    // ═══════════════════════════════════════════════════════════════════════
    // VIEW FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════

    /**
     * @notice Get claimable amount for position
     */
    function claimable(address user, uint256 positionId) external view returns (uint256) {
        return _claimable(positions[user][positionId]);
    }

    /**
     * @notice Get total claimable across all positions
     */
    function totalClaimable(address user) external view returns (uint256 total) {
        uint256 count = userPositionCount[user];
        for (uint256 i = 0; i < count; i++) {
            total += _claimable(positions[user][i]);
        }
    }

    /**
     * @notice Get pool info
     */
    function getPool(uint256 poolId) external view returns (PoolConfig memory) {
        return pools[poolId];
    }

    /**
     * @notice Get current bond price for pool (ASHA per LP token)
     */
    function getBondPrice(uint256 poolId) external view returns (uint256) {
        PoolConfig storage pool = pools[poolId];
        if (pool.lpToken == address(0)) revert InvalidPool();

        uint256 lpValue = _getLPValue(pool.lpToken, 1e18);
        uint256 ashaPrice = oracle.getPrice(protocolToken);

        return (lpValue * (BPS + pool.discount)) / ashaPrice;
    }

    /**
     * @notice Get protocol liquidity stats
     */
    function getStats() external view returns (
        uint256 polValue,
        uint256 ashaBonded,
        uint256 activePools,
        uint256 activeSingleSided
    ) {
        polValue = totalPOLValue;
        ashaBonded = totalASHABonded;

        for (uint256 i = 0; i < nextPoolId; i++) {
            if (pools[i].active) activePools++;
        }
        for (uint256 i = 0; i < nextSingleSidedId; i++) {
            if (singleSided[i].active) activeSingleSided++;
        }
    }

    // ═══════════════════════════════════════════════════════════════════════
    // INTERNAL
    // ═══════════════════════════════════════════════════════════════════════

    function _claimable(VestingPosition storage pos) internal view returns (uint256) {
        if (pos.totalOwed == 0) return 0;

        uint256 elapsed = block.timestamp - pos.vestingStart;
        uint256 vestingDuration = pos.vestingEnd - pos.vestingStart;

        uint256 vested;
        if (elapsed >= vestingDuration) {
            vested = pos.totalOwed;
        } else {
            vested = (pos.totalOwed * elapsed) / vestingDuration;
        }

        return vested - pos.claimed;
    }

    /**
     * @notice Calculate LP token value in sats using fair pricing
     * @dev Uses geometric mean for flash-loan resistant valuation
     *      Fair value = 2 * sqrt(reserve0 * reserve1) normalized by prices
     *      This prevents manipulation via single-sided reserve inflation
     */
    function _getLPValue(address lpToken, uint256 lpAmount) internal view returns (uint256) {
        ILiquidityPool pool = ILiquidityPool(lpToken);

        (uint112 reserve0, uint112 reserve1,) = pool.getReserves();
        uint256 totalSupply = pool.totalSupply();

        // Get prices of underlying tokens
        uint256 price0 = oracle.getPrice(pool.token0());
        uint256 price1 = oracle.getPrice(pool.token1());

        // Calculate fair reserves using geometric mean (flash-loan resistant)
        // k = reserve0 * reserve1 (constant product)
        // Fair value uses sqrt(k) * 2 * sqrt(price0 * price1) for price-normalized valuation
        uint256 k = uint256(reserve0) * uint256(reserve1);

        // Normalize reserves by price to get value: sqrt(reserve0 * price0 * reserve1 * price1)
        // Then multiply by 2 for total pool value
        uint256 sqrtK = Math.sqrt(k);
        uint256 sqrtPriceProduct = Math.sqrt((price0 * price1) / 1e18);
        uint256 fairPoolValue = 2 * sqrtK * sqrtPriceProduct / 1e9; // Adjust decimals

        // User's share of fair pool value
        return (fairPoolValue * lpAmount) / totalSupply;
    }
}
