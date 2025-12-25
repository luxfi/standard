// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

/**
 * @title FraxStrategy
 * @notice Yield strategies for Frax Finance ecosystem
 * @dev Supports:
 *      - sFRAX staking (~5% APY from T-bills)
 *      - sfrxETH liquid staking
 *      - Fraxlend lending markets
 *      - FXS staking (veFXS)
 *
 * Frax Finance is a stablecoin protocol with multiple yield products:
 * - FRAX: Algorithmic stablecoin
 * - sFRAX: Staked FRAX earning T-bill yield
 * - frxETH: Liquid staking ETH token
 * - sfrxETH: Staked frxETH (vault share)
 * - FXS: Governance token
 * - veFXS: Vote-escrowed FXS for boosted yields
 */

import {IYieldStrategy} from "../IYieldStrategy.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

// ═══════════════════════════════════════════════════════════════════════════
// FRAX PROTOCOL INTERFACES
// ═══════════════════════════════════════════════════════════════════════════

/// @notice sFRAX - Staked FRAX (ERC4626 vault)
/// @dev Earns yield from T-bills and other safe assets
interface IsFRAX {
    function deposit(uint256 assets, address receiver) external returns (uint256 shares);
    function redeem(uint256 shares, address receiver, address owner) external returns (uint256 assets);
    function withdraw(uint256 assets, address receiver, address owner) external returns (uint256 shares);
    function convertToAssets(uint256 shares) external view returns (uint256);
    function convertToShares(uint256 assets) external view returns (uint256);
    function totalAssets() external view returns (uint256);
    function pricePerShare() external view returns (uint256);
    function rewardsCycleEnd() external view returns (uint256);
    function lastSync() external view returns (uint256);
    function maxDeposit(address) external view returns (uint256);
    function maxWithdraw(address owner) external view returns (uint256);
}

/// @notice sfrxETH - Staked Frax ETH (ERC4626 vault)
/// @dev Liquid staking ETH derivative with auto-compounding
interface IsfrxETH {
    function deposit(uint256 assets, address receiver) external returns (uint256 shares);
    function redeem(uint256 shares, address receiver, address owner) external returns (uint256 assets);
    function withdraw(uint256 assets, address receiver, address owner) external returns (uint256 shares);
    function convertToAssets(uint256 shares) external view returns (uint256);
    function convertToShares(uint256 assets) external view returns (uint256);
    function totalAssets() external view returns (uint256);
    function pricePerShare() external view returns (uint256);
    function syncRewards() external;
    function rewardsCycleEnd() external view returns (uint256);
}

/// @notice frxETH Minter - Mint frxETH with ETH
interface IfrxETHMinter {
    function submit() external payable;
    function submitAndDeposit(address recipient) external payable returns (uint256 shares);
    function submitAndGive(address recipient) external payable;
    function currentWithheldETH() external view returns (uint256);
    function withholdRatio() external view returns (uint256);
}

/// @notice Fraxlend Pair - Lending market
interface IFraxlendPair {
    function deposit(uint256 _amount, address _receiver) external returns (uint256 _sharesReceived);
    function redeem(uint256 _shares, address _receiver, address _owner) external returns (uint256 _amountToReturn);
    function addCollateral(uint256 _collateralAmount, address _borrower) external;
    function removeCollateral(uint256 _collateralAmount, address _receiver, address _borrower) external;
    function borrow(uint256 _borrowAmount, uint256 _collateralAmount, address _receiver, address _borrower) external returns (uint256 _shares);
    function repay(uint256 _shares, address _borrower) external returns (uint256 _amountRepaid);
    function totalAsset() external view returns (uint128 amount, uint128 shares);
    function totalBorrow() external view returns (uint128 amount, uint128 shares);
    function userCollateralBalance(address _user) external view returns (uint256);
    function userBorrowShares(address _user) external view returns (uint256);
    function toAssetAmount(uint256 _shares, bool _roundUp) external view returns (uint256);
    function toAssetShares(uint256 _amount, bool _roundUp) external view returns (uint256);
    function currentRateInfo() external view returns (
        uint32 lastBlock,
        uint32 feeToProtocolRate,
        uint64 lastTimestamp,
        uint64 ratePerSec,
        uint64 fullUtilizationRate
    );
    function getConstants() external view returns (
        uint256 _LTV_PRECISION,
        uint256 _EXCHANGE_PRECISION,
        uint256 _UTIL_PRECISION,
        uint256 _FEE_PRECISION,
        uint256 _INTEREST_PRECISION
    );
    function asset() external view returns (address);
    function collateralContract() external view returns (address);
    function cleanLiquidationFee() external view returns (uint256);
    function dirtyLiquidationFee() external view returns (uint256);
    function maxLTV() external view returns (uint256);
}

/// @notice FXS Voting Escrow - Lock FXS for veFXS
interface IveFXS {
    struct LockedBalance {
        int128 amount;
        uint256 end;
    }
    
    function create_lock(uint256 _value, uint256 _unlock_time) external;
    function increase_amount(uint256 _value) external;
    function increase_unlock_time(uint256 _unlock_time) external;
    function withdraw() external;
    function balanceOf(address _addr) external view returns (uint256);
    function balanceOfAt(address _addr, uint256 _block) external view returns (uint256);
    function totalSupply() external view returns (uint256);
    function locked(address _addr) external view returns (LockedBalance memory);
    function locked__end(address _addr) external view returns (uint256);
}

/// @notice FXS Gauge - Earn FXS rewards for liquidity
interface IFraxGauge {
    function stake(uint256 _amount) external;
    function withdraw(uint256 _amount) external;
    function getReward() external returns (uint256);
    function balanceOf(address _addr) external view returns (uint256);
    function earned(address _addr) external view returns (uint256);
    function totalSupply() external view returns (uint256);
    function rewardRate() external view returns (uint256);
    function rewardsDuration() external view returns (uint256);
    function periodFinish() external view returns (uint256);
}

/// @notice Frax Ferry - Cross-chain bridge
interface IFraxFerry {
    function embark(uint256 _amount) external;
    function disembark(uint256 _amount, uint256 _nonce, bytes32[] calldata _proof) external;
    function MIN_WAIT_PERIOD_ADD() external view returns (uint256);
    function MIN_WAIT_PERIOD_EXECUTE() external view returns (uint256);
    function captain() external view returns (address);
    function FRAX() external view returns (address);
}

// ═══════════════════════════════════════════════════════════════════════════
// FRAX TOKEN ADDRESSES (Ethereum Mainnet)
// ═══════════════════════════════════════════════════════════════════════════

/// @notice Frax Protocol token addresses
library FraxAddresses {
    // Core tokens
    address internal constant FRAX = 0x853d955aCEf822Db058eb8505911ED77F175b99e;
    address internal constant FXS = 0x3432B6A60D23Ca0dFCa7761B7ab56459D9C964D0;
    
    // Staked tokens
    address internal constant sFRAX = 0xA663B02CF0a4b149d2aD41910CB81e23e1c41c32;
    address internal constant frxETH = 0x5E8422345238F34275888049021821E8E08CAa1f;
    address internal constant sfrxETH = 0xac3E018457B222d93114458476f3E3416Abbe38F;
    
    // Governance
    address internal constant veFXS = 0xc8418aF6358FFddA74e09Ca9CC3Fe03Ca6aDC5b0;
    
    // Minters
    address internal constant frxETH_MINTER = 0xbAFA44EFE7901E04E39Dad13167D089C559c1138;
    
    // Fraxlend markets (example: FRAX/USDC)
    address internal constant FRAXLEND_FRAX_USDC = 0xDbe88DBAc39263c47629ebbA02b3eF4cf0752A72;
    address internal constant FRAXLEND_FRAX_CRV = 0x3835a58CA93Cdb5f912519ad366826aC9a752510;
    address internal constant FRAXLEND_FRAX_WETH = 0x794F6B13FBd7EB7ef10d1ED205c9a416910207Ff;
}

// ═══════════════════════════════════════════════════════════════════════════
// sFRAX STRATEGY - T-Bill Yield (~5% APY)
// ═══════════════════════════════════════════════════════════════════════════

/**
 * @title sFRAXStrategy
 * @notice Yield strategy for sFRAX (Staked FRAX)
 * @dev sFRAX earns ~5% APY from T-bills and other safe assets
 *
 * Key features:
 * - ERC4626 vault (auto-compounding)
 * - Real yield from US Treasury bills
 * - No lock-up period
 * - 1:1 backed by T-bills and cash equivalents
 */
contract sFRAXStrategy is Ownable {
    using SafeERC20 for IERC20;

    // ═══════════════════════════════════════════════════════════════════════
    // CONSTANTS
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice FRAX stablecoin
    address public constant FRAX = FraxAddresses.FRAX;

    /// @notice sFRAX vault
    IsFRAX public constant SFRAX = IsFRAX(FraxAddresses.sFRAX);

    // ═══════════════════════════════════════════════════════════════════════
    // STATE
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice Vault that controls this strategy
    address public vault;

    /// @notice Total sFRAX shares held
    uint256 public totalShares;

    /// @notice Total amount deposited
    uint256 public totalDeposited;

    /// @notice Strategy active status
    bool public active = true;

    // ═══════════════════════════════════════════════════════════════════════
    // EVENTS
    // ═══════════════════════════════════════════════════════════════════════

    event Deposited(uint256 fraxAmount, uint256 sharesReceived);
    event Withdrawn(uint256 sharesRedeemed, uint256 fraxReceived);

    // ═══════════════════════════════════════════════════════════════════════
    // MODIFIERS
    // ═══════════════════════════════════════════════════════════════════════

    modifier onlyVault() {
        require(msg.sender == vault, "sFRAXStrategy: only vault");
        _;
    }

    // ═══════════════════════════════════════════════════════════════════════
    // CONSTRUCTOR
    // ═══════════════════════════════════════════════════════════════════════

    constructor(address _vault) Ownable(msg.sender) {
        vault = _vault;
        
        // Approve sFRAX to spend FRAX
        IERC20(FRAX).approve(address(SFRAX), type(uint256).max);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // YIELD STRATEGY INTERFACE
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice
    function deposit(uint256 amount) external onlyVault returns (uint256 shares) {
        require(active, "sFRAXStrategy: not active");

        // Transfer FRAX from vault
        IERC20(FRAX).safeTransferFrom(msg.sender, address(this), amount);

        // Deposit into sFRAX vault
        shares = SFRAX.deposit(amount, address(this));
        totalShares += shares;
        totalDeposited += amount;

        emit Deposited(amount, shares);
    }

    /// @notice
    function withdraw(uint256 amount) external onlyVault returns (uint256 assets) {
        require(amount <= totalShares, "sFRAXStrategy: insufficient shares");

        // Redeem from sFRAX vault
        assets = SFRAX.redeem(amount, vault, address(this));
        totalShares -= amount;
        if (assets <= totalDeposited) {
            totalDeposited -= assets;
        } else {
            totalDeposited = 0;
        }

        emit Withdrawn(amount, assets);
    }

    /// @notice
    function harvest() external returns (uint256 harvested) {
        // sFRAX is auto-compounding - yield is reflected in share price
        // No explicit harvest needed
        harvested = 0;
    }

    /// @notice
    function totalAssets() external view returns (uint256) {
        return SFRAX.convertToAssets(totalShares);
    }

    /// @notice
    function currentAPY() external pure returns (uint256) {
        // sFRAX yields ~5% from T-bills
        return 500; // 5.00% in basis points
    }

    /// @notice
    function asset() external pure returns (address) {
        return FRAX;
    }

    /// @notice
    function isActive() external view returns (bool) {
        return active;
    }

    /// @notice
    function name() external pure returns (string memory) {
        return "sFRAX T-Bill Strategy";
    }

    // ═══════════════════════════════════════════════════════════════════════
    // VIEW FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice Get current price per share
    function pricePerShare() external view returns (uint256) {
        return SFRAX.pricePerShare();
    }

    /// @notice Get next rewards cycle end
    function rewardsCycleEnd() external view returns (uint256) {
        return SFRAX.rewardsCycleEnd();
    }

    // ═══════════════════════════════════════════════════════════════════════
    // ADMIN FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════

    function setActive(bool _active) external onlyOwner {
        active = _active;
    }

    function setVault(address _vault) external onlyOwner {
        vault = _vault;
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// sfrxETH STRATEGY - Liquid Staking ETH
// ═══════════════════════════════════════════════════════════════════════════

/**
 * @title sfrxETHStrategy
 * @notice Yield strategy for sfrxETH (Staked Frax ETH)
 * @dev Liquid staking with auto-compounding rewards
 *
 * Key features:
 * - ETH staking yield (~4-5% APY)
 * - No validator management
 * - Auto-compounding via ERC4626
 * - Liquid - can be traded on secondary markets
 */
contract sfrxETHStrategy is Ownable {
    using SafeERC20 for IERC20;

    // ═══════════════════════════════════════════════════════════════════════
    // CONSTANTS
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice frxETH token
    address public constant FRXETH = FraxAddresses.frxETH;

    /// @notice sfrxETH vault
    IsfrxETH public constant SFRXETH = IsfrxETH(FraxAddresses.sfrxETH);

    /// @notice frxETH minter
    IfrxETHMinter public constant MINTER = IfrxETHMinter(FraxAddresses.frxETH_MINTER);

    // ═══════════════════════════════════════════════════════════════════════
    // STATE
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice Vault that controls this strategy
    address public vault;

    /// @notice Total sfrxETH shares held
    uint256 public totalShares;

    /// @notice Total amount deposited
    uint256 public totalDeposited;

    /// @notice Strategy active status
    bool public active = true;

    // ═══════════════════════════════════════════════════════════════════════
    // EVENTS
    // ═══════════════════════════════════════════════════════════════════════

    event DepositedETH(uint256 ethAmount, uint256 sharesReceived);
    event DepositedFrxETH(uint256 frxEthAmount, uint256 sharesReceived);
    event Withdrawn(uint256 sharesRedeemed, uint256 frxEthReceived);

    // ═══════════════════════════════════════════════════════════════════════
    // MODIFIERS
    // ═══════════════════════════════════════════════════════════════════════

    modifier onlyVault() {
        require(msg.sender == vault, "sfrxETHStrategy: only vault");
        _;
    }

    // ═══════════════════════════════════════════════════════════════════════
    // CONSTRUCTOR
    // ═══════════════════════════════════════════════════════════════════════

    constructor(address _vault) Ownable(msg.sender) {
        vault = _vault;
        
        // Approve sfrxETH to spend frxETH
        IERC20(FRXETH).approve(address(SFRXETH), type(uint256).max);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // YIELD STRATEGY INTERFACE
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice
    function deposit(uint256 amount) external onlyVault returns (uint256 shares) {
        require(active, "sfrxETHStrategy: not active");

        // Deposit frxETH
        IERC20(FRXETH).safeTransferFrom(msg.sender, address(this), amount);
        shares = SFRXETH.deposit(amount, address(this));

        totalShares += shares;
        totalDeposited += amount;

        emit DepositedFrxETH(amount, shares);
    }

    /// @notice
    function withdraw(uint256 amount) external onlyVault returns (uint256 assets) {
        require(amount <= totalShares, "sfrxETHStrategy: insufficient shares");

        // Redeem sfrxETH for frxETH
        assets = SFRXETH.redeem(amount, vault, address(this));
        totalShares -= amount;
        if (assets <= totalDeposited) {
            totalDeposited -= assets;
        } else {
            totalDeposited = 0;
        }

        emit Withdrawn(amount, assets);
    }

    /// @notice
    function harvest() external returns (uint256 harvested) {
        // sfrxETH is auto-compounding - yield is reflected in share price
        // Sync rewards to update share price
        SFRXETH.syncRewards();
        harvested = 0;
    }

    /// @notice
    function totalAssets() external view returns (uint256) {
        return SFRXETH.convertToAssets(totalShares);
    }

    /// @notice
    function currentAPY() external pure returns (uint256) {
        // sfrxETH yields ~4-5% from ETH staking
        return 450; // 4.50% in basis points
    }

    /// @notice
    function asset() external pure returns (address) {
        return FRXETH;
    }

    /// @notice
    function isActive() external view returns (bool) {
        return active;
    }

    /// @notice
    function name() external pure returns (string memory) {
        return "sfrxETH Liquid Staking Strategy";
    }

    // ═══════════════════════════════════════════════════════════════════════
    // VIEW FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice Get current price per share (frxETH per sfrxETH)
    function pricePerShare() external view returns (uint256) {
        return SFRXETH.pricePerShare();
    }

    /// @notice Get next rewards cycle end
    function rewardsCycleEnd() external view returns (uint256) {
        return SFRXETH.rewardsCycleEnd();
    }

    // ═══════════════════════════════════════════════════════════════════════
    // ADMIN FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════

    function setActive(bool _active) external onlyOwner {
        active = _active;
    }

    function setVault(address _vault) external onlyOwner {
        vault = _vault;
    }

    receive() external payable {}
}

// ═══════════════════════════════════════════════════════════════════════════
// FRAXLEND STRATEGY - Lending Markets
// ═══════════════════════════════════════════════════════════════════════════

/**
 * @title FraxlendStrategy
 * @notice Yield strategy for Fraxlend lending markets
 * @dev Earns interest from borrowers in isolated lending pairs
 *
 * Key features:
 * - Isolated risk per pair
 * - Variable interest rates
 * - Multiple collateral types supported
 * - Auto-compounding interest
 */
contract FraxlendStrategy is Ownable {
    using SafeERC20 for IERC20;

    // ═══════════════════════════════════════════════════════════════════════
    // STATE
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice Fraxlend pair contract
    IFraxlendPair public immutable pair;

    /// @notice Asset being lent (e.g., FRAX)
    address public immutable underlyingAsset;

    /// @notice Collateral token
    address public immutable collateral;

    /// @notice Vault that controls this strategy
    address public vault;

    /// @notice Total lending shares held
    uint256 public totalShares;

    /// @notice Total amount deposited
    uint256 public totalDeposited;

    /// @notice Strategy active status
    bool public active = true;

    // ═══════════════════════════════════════════════════════════════════════
    // EVENTS
    // ═══════════════════════════════════════════════════════════════════════

    event Deposited(uint256 assetAmount, uint256 sharesReceived);
    event Withdrawn(uint256 sharesRedeemed, uint256 assetReceived);

    // ═══════════════════════════════════════════════════════════════════════
    // MODIFIERS
    // ═══════════════════════════════════════════════════════════════════════

    modifier onlyVault() {
        require(msg.sender == vault, "FraxlendStrategy: only vault");
        _;
    }

    // ═══════════════════════════════════════════════════════════════════════
    // CONSTRUCTOR
    // ═══════════════════════════════════════════════════════════════════════

    constructor(
        address _vault,
        address _pair
    ) Ownable(msg.sender) {
        vault = _vault;
        pair = IFraxlendPair(_pair);
        underlyingAsset = pair.asset();
        collateral = pair.collateralContract();

        // Approve pair to spend asset
        IERC20(underlyingAsset).approve(_pair, type(uint256).max);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // YIELD STRATEGY INTERFACE
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice
    function deposit(uint256 amount) external onlyVault returns (uint256 shares) {
        require(active, "FraxlendStrategy: not active");

        // Transfer asset from vault
        IERC20(underlyingAsset).safeTransferFrom(msg.sender, address(this), amount);

        // Deposit into Fraxlend pair
        shares = pair.deposit(amount, address(this));
        totalShares += shares;
        totalDeposited += amount;

        emit Deposited(amount, shares);
    }

    /// @notice
    function withdraw(uint256 amount) external onlyVault returns (uint256 assets) {
        require(amount <= totalShares, "FraxlendStrategy: insufficient shares");

        // Redeem from Fraxlend pair
        assets = pair.redeem(amount, vault, address(this));
        totalShares -= amount;
        if (assets <= totalDeposited) {
            totalDeposited -= assets;
        } else {
            totalDeposited = 0;
        }

        emit Withdrawn(amount, assets);
    }

    /// @notice
    function harvest() external returns (uint256 harvested) {
        // Fraxlend interest is auto-compounding
        // No explicit harvest needed
        harvested = 0;
    }

    /// @notice
    function totalAssets() external view returns (uint256) {
        return pair.toAssetAmount(totalShares, false);
    }

    /// @notice
    function currentAPY() external view returns (uint256) {
        // Get current rate per second and annualize
        (,,, uint64 ratePerSec,) = pair.currentRateInfo();
        
        // Annualize: rate * seconds per year
        // ratePerSec is in 1e18 precision
        uint256 annualRate = uint256(ratePerSec) * 365 days;
        
        // Convert to basis points (1e18 = 100% = 10000 bps)
        return annualRate / 1e14;
    }

    /// @notice
    function asset() external view returns (address) {
        return underlyingAsset;
    }

    /// @notice
    function isActive() external view returns (bool) {
        return active;
    }

    /// @notice
    function name() external pure returns (string memory) {
        return "Fraxlend Lending Strategy";
    }

    // ═══════════════════════════════════════════════════════════════════════
    // VIEW FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice Get utilization rate of the pair
    function utilizationRate() external view returns (uint256) {
        (uint128 totalAssetAmount,) = pair.totalAsset();
        (uint128 totalBorrowAmount,) = pair.totalBorrow();
        
        if (totalAssetAmount == 0) return 0;
        return (uint256(totalBorrowAmount) * 1e18) / uint256(totalAssetAmount);
    }

    /// @notice Get max LTV for the pair
    function maxLTV() external view returns (uint256) {
        return pair.maxLTV();
    }

    // ═══════════════════════════════════════════════════════════════════════
    // ADMIN FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════

    function setActive(bool _active) external onlyOwner {
        active = _active;
    }

    function setVault(address _vault) external onlyOwner {
        vault = _vault;
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// veFXS STRATEGY - Governance Staking
// ═══════════════════════════════════════════════════════════════════════════

/**
 * @title veFXSStrategy
 * @notice Yield strategy for vote-escrowed FXS (veFXS)
 * @dev Lock FXS for veFXS to earn boosted rewards
 *
 * Key features:
 * - Time-weighted voting power
 * - Boost FXS rewards up to 4x
 * - Governance participation
 * - Lock periods from 1 week to 4 years
 *
 * Note: This is a long-term strategy with lock-up periods
 */
contract veFXSStrategy is Ownable {
    using SafeERC20 for IERC20;

    // ═══════════════════════════════════════════════════════════════════════
    // CONSTANTS
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice FXS token
    address public constant FXS = FraxAddresses.FXS;

    /// @notice veFXS contract
    IveFXS public constant VEFXS = IveFXS(FraxAddresses.veFXS);

    /// @notice Maximum lock time (4 years)
    uint256 public constant MAX_LOCK_TIME = 4 * 365 days;

    /// @notice Minimum lock time (1 week)
    uint256 public constant MIN_LOCK_TIME = 7 days;

    // ═══════════════════════════════════════════════════════════════════════
    // STATE
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice Vault that controls this strategy
    address public vault;

    /// @notice Total FXS locked
    uint256 public totalLocked;

    /// @notice Lock end timestamp
    uint256 public lockEnd;

    /// @notice Default lock duration for new deposits
    uint256 public defaultLockDuration = 365 days;

    /// @notice Strategy active status
    bool public active = true;

    // ═══════════════════════════════════════════════════════════════════════
    // EVENTS
    // ═══════════════════════════════════════════════════════════════════════

    event Locked(uint256 fxsAmount, uint256 unlockTime);
    event LockExtended(uint256 newUnlockTime);
    event Withdrawn(uint256 fxsAmount);

    // ═══════════════════════════════════════════════════════════════════════
    // MODIFIERS
    // ═══════════════════════════════════════════════════════════════════════

    modifier onlyVault() {
        require(msg.sender == vault, "veFXSStrategy: only vault");
        _;
    }

    // ═══════════════════════════════════════════════════════════════════════
    // CONSTRUCTOR
    // ═══════════════════════════════════════════════════════════════════════

    constructor(address _vault) Ownable(msg.sender) {
        vault = _vault;
        
        // Approve veFXS to spend FXS
        IERC20(FXS).approve(address(VEFXS), type(uint256).max);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // YIELD STRATEGY INTERFACE
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice
    function deposit(uint256 amount) external payable onlyVault returns (uint256 shares) {
        require(active, "veFXSStrategy: not active");
        require(msg.value == 0, "veFXSStrategy: no ETH");

        // Transfer FXS from vault
        IERC20(FXS).safeTransferFrom(msg.sender, address(this), amount);

        if (totalLocked == 0) {
            // Create new lock
            uint256 unlockTime = block.timestamp + defaultLockDuration;
            // Round down to week
            unlockTime = (unlockTime / 1 weeks) * 1 weeks;
            
            VEFXS.create_lock(amount, unlockTime);
            lockEnd = unlockTime;
        } else {
            // Increase existing lock amount
            VEFXS.increase_amount(amount);
        }

        totalLocked += amount;
        shares = amount; // 1:1 for simplicity

        emit Locked(amount, lockEnd);
    }

    /// @notice
    function withdraw(uint256 shares) external onlyVault returns (uint256 amount) {
        require(block.timestamp >= lockEnd, "veFXSStrategy: still locked");
        require(shares <= totalLocked, "veFXSStrategy: insufficient shares");

        // Withdraw all locked FXS
        VEFXS.withdraw();

        amount = IERC20(FXS).balanceOf(address(this));
        totalLocked = 0;
        lockEnd = 0;

        // Transfer to vault
        IERC20(FXS).safeTransfer(vault, amount);

        emit Withdrawn(amount);
    }

    /// @notice
    function harvest() external returns (uint256 harvested) {
        // veFXS doesn't have direct rewards - value comes from:
        // 1. Protocol fee sharing
        // 2. Gauge boost (claimed via gauges)
        // 3. Governance airdrops
        harvested = 0;
    }

    /// @notice
    function totalAssets() external view returns (uint256) {
        return totalLocked;
    }

    /// @notice
    function currentAPY() external pure returns (uint256) {
        // veFXS APY varies based on protocol fees and gauge boosts
        // Typically 10-30% depending on lock duration and participation
        return 1500; // 15% in basis points (conservative estimate)
    }

    /// @notice
    function underlying() external pure returns (address) {
        return FXS;
    }

    /// @notice
    function yieldToken() external pure returns (address) {
        return FraxAddresses.veFXS;
    }

    /// @notice
    function isActive() external view returns (bool) {
        return active;
    }

    /// @notice
    function name() external pure returns (string memory) {
        return "veFXS Governance Strategy";
    }

    // ═══════════════════════════════════════════════════════════════════════
    // veFXS SPECIFIC FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice Extend lock period
    function extendLock(uint256 newUnlockTime) external onlyOwner {
        require(newUnlockTime > lockEnd, "veFXSStrategy: must extend");
        require(newUnlockTime <= block.timestamp + MAX_LOCK_TIME, "veFXSStrategy: too long");
        
        // Round down to week
        newUnlockTime = (newUnlockTime / 1 weeks) * 1 weeks;
        
        VEFXS.increase_unlock_time(newUnlockTime);
        lockEnd = newUnlockTime;

        emit LockExtended(newUnlockTime);
    }

    /// @notice Get current voting power
    function votingPower() external view returns (uint256) {
        return VEFXS.balanceOf(address(this));
    }

    /// @notice Get lock end timestamp
    function getLockEnd() external view returns (uint256) {
        return lockEnd;
    }

    /// @notice Check if lock has expired
    function isExpired() external view returns (bool) {
        return block.timestamp >= lockEnd;
    }

    // ═══════════════════════════════════════════════════════════════════════
    // ADMIN FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════

    function setActive(bool _active) external onlyOwner {
        active = _active;
    }

    function setVault(address _vault) external onlyOwner {
        vault = _vault;
    }

    function setDefaultLockDuration(uint256 _duration) external onlyOwner {
        require(_duration >= MIN_LOCK_TIME, "veFXSStrategy: too short");
        require(_duration <= MAX_LOCK_TIME, "veFXSStrategy: too long");
        defaultLockDuration = _duration;
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// FRAX GAUGE STRATEGY - Liquidity Mining
// ═══════════════════════════════════════════════════════════════════════════

/**
 * @title FraxGaugeStrategy
 * @notice Yield strategy for Frax gauge staking
 * @dev Stake LP tokens in Frax gauges for FXS rewards
 *
 * Key features:
 * - FXS emissions
 * - veFXS boost up to 4x
 * - Multiple gauge support
 */
contract FraxGaugeStrategy is Ownable {
    using SafeERC20 for IERC20;

    // ═══════════════════════════════════════════════════════════════════════
    // STATE
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice FXS token
    address public constant FXS = FraxAddresses.FXS;

    /// @notice Frax gauge contract
    IFraxGauge public immutable gauge;

    /// @notice LP token to stake
    address public immutable lpToken;

    /// @notice Vault that controls this strategy
    address public vault;

    /// @notice Total LP tokens staked
    uint256 public totalStaked;

    /// @notice Strategy active status
    bool public active = true;

    // ═══════════════════════════════════════════════════════════════════════
    // EVENTS
    // ═══════════════════════════════════════════════════════════════════════

    event Staked(uint256 amount);
    event Unstaked(uint256 amount);
    event RewardsHarvested(uint256 fxsAmount);

    // ═══════════════════════════════════════════════════════════════════════
    // MODIFIERS
    // ═══════════════════════════════════════════════════════════════════════

    modifier onlyVault() {
        require(msg.sender == vault, "FraxGaugeStrategy: only vault");
        _;
    }

    // ═══════════════════════════════════════════════════════════════════════
    // CONSTRUCTOR
    // ═══════════════════════════════════════════════════════════════════════

    constructor(
        address _vault,
        address _gauge,
        address _lpToken
    ) Ownable(msg.sender) {
        vault = _vault;
        gauge = IFraxGauge(_gauge);
        lpToken = _lpToken;

        // Approve gauge to spend LP token
        IERC20(_lpToken).approve(_gauge, type(uint256).max);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // YIELD STRATEGY INTERFACE
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice
    function deposit(uint256 amount) external payable onlyVault returns (uint256 shares) {
        require(active, "FraxGaugeStrategy: not active");
        require(msg.value == 0, "FraxGaugeStrategy: no ETH");

        // Transfer LP tokens from vault
        IERC20(lpToken).safeTransferFrom(msg.sender, address(this), amount);

        // Stake in gauge
        gauge.stake(amount);
        totalStaked += amount;
        shares = amount;

        emit Staked(amount);
    }

    /// @notice
    function withdraw(uint256 shares) external onlyVault returns (uint256 amount) {
        require(shares <= totalStaked, "FraxGaugeStrategy: insufficient staked");

        // Unstake from gauge
        gauge.withdraw(shares);
        totalStaked -= shares;
        amount = shares;

        // Transfer to vault
        IERC20(lpToken).safeTransfer(vault, amount);

        emit Unstaked(amount);
    }

    /// @notice
    function harvest() external returns (uint256 harvested) {
        // Claim FXS rewards
        harvested = gauge.getReward();

        if (harvested > 0) {
            // Transfer FXS to vault
            IERC20(FXS).safeTransfer(vault, harvested);
            emit RewardsHarvested(harvested);
        }
    }

    /// @notice
    function totalAssets() external view returns (uint256) {
        return totalStaked;
    }

    /// @notice
    function currentAPY() external view returns (uint256) {
        // Calculate APY from reward rate
        uint256 rewardRate = gauge.rewardRate();
        uint256 totalSupply = gauge.totalSupply();
        
        if (totalSupply == 0) return 0;
        
        // Annualize: (rewardRate * seconds/year) / totalSupply
        // Assume FXS price relative to LP token value
        uint256 annualRewards = rewardRate * 365 days;
        return (annualRewards * 10000) / totalSupply;
    }

    /// @notice
    function underlying() external view returns (address) {
        return lpToken;
    }

    /// @notice
    function yieldToken() external view returns (address) {
        return FXS;
    }

    /// @notice
    function isActive() external view returns (bool) {
        return active;
    }

    /// @notice
    function name() external pure returns (string memory) {
        return "Frax Gauge Strategy";
    }

    // ═══════════════════════════════════════════════════════════════════════
    // VIEW FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice Get pending FXS rewards
    function pendingRewards() external view returns (uint256) {
        return gauge.earned(address(this));
    }

    // ═══════════════════════════════════════════════════════════════════════
    // ADMIN FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════

    function setActive(bool _active) external onlyOwner {
        active = _active;
    }

    function setVault(address _vault) external onlyOwner {
        vault = _vault;
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// FACTORY CONTRACTS
// ═══════════════════════════════════════════════════════════════════════════

/**
 * @title FraxStrategyFactory
 * @notice Factory for deploying Frax yield strategies
 */
contract FraxStrategyFactory {
    event sFRAXStrategyDeployed(address strategy, address vault);
    event sfrxETHStrategyDeployed(address strategy, address vault);
    event FraxlendStrategyDeployed(address strategy, address vault, address pair);
    event veFXSStrategyDeployed(address strategy, address vault);
    event GaugeStrategyDeployed(address strategy, address vault, address gauge);

    /// @notice Deploy sFRAX strategy
    function deploysFRAXStrategy(address vault) external returns (address) {
        sFRAXStrategy strategy = new sFRAXStrategy(vault);
        emit sFRAXStrategyDeployed(address(strategy), vault);
        return address(strategy);
    }

    /// @notice Deploy sfrxETH strategy
    function deploysfrxETHStrategy(address vault) external returns (address) {
        sfrxETHStrategy strategy = new sfrxETHStrategy(vault);
        emit sfrxETHStrategyDeployed(address(strategy), vault);
        return address(strategy);
    }

    /// @notice Deploy Fraxlend strategy
    function deployFraxlendStrategy(address vault, address pair) external returns (address) {
        FraxlendStrategy strategy = new FraxlendStrategy(vault, pair);
        emit FraxlendStrategyDeployed(address(strategy), vault, pair);
        return address(strategy);
    }

    /// @notice Deploy veFXS strategy
    function deployveFXSStrategy(address vault) external returns (address) {
        veFXSStrategy strategy = new veFXSStrategy(vault);
        emit veFXSStrategyDeployed(address(strategy), vault);
        return address(strategy);
    }

    /// @notice Deploy gauge strategy
    function deployGaugeStrategy(
        address vault,
        address gauge,
        address lpToken
    ) external returns (address) {
        FraxGaugeStrategy strategy = new FraxGaugeStrategy(vault, gauge, lpToken);
        emit GaugeStrategyDeployed(address(strategy), vault, gauge);
        return address(strategy);
    }
}
