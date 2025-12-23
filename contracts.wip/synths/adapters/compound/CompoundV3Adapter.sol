// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "../IYieldAdapter.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/// @title IComet
/// @notice Compound V3 (Comet) interface
interface IComet {
    function supply(address asset, uint256 amount) external;
    function withdraw(address asset, uint256 amount) external;
    function balanceOf(address account) external view returns (uint256);
    function borrowBalanceOf(address account) external view returns (uint256);
    function getSupplyRate(uint256 utilization) external view returns (uint64);
    function getBorrowRate(uint256 utilization) external view returns (uint64);
    function getUtilization() external view returns (uint256);
    function totalSupply() external view returns (uint256);
    function totalBorrow() external view returns (uint256);
    function baseToken() external view returns (address);
    function getPrice(address priceFeed) external view returns (uint256);
    function baseTokenPriceFeed() external view returns (address);
    function getAssetInfo(uint8 i) external view returns (AssetInfo memory);
    function numAssets() external view returns (uint8);
    function collateralBalanceOf(address account, address asset) external view returns (uint128);
    
    struct AssetInfo {
        uint8 offset;
        address asset;
        address priceFeed;
        uint64 scale;
        uint64 borrowCollateralFactor;
        uint64 liquidateCollateralFactor;
        uint64 liquidationFactor;
        uint128 supplyCap;
    }
}

/// @title ICometRewards
/// @notice Compound V3 rewards distributor
interface ICometRewards {
    function claim(address comet, address src, bool shouldAccrue) external;
    function getRewardOwed(address comet, address account) external returns (address, uint256);
}

/// @title CompoundV3Adapter
/// @notice Yield adapter for Compound V3 (Comet) protocol
/// @dev Implements IYieldAdapter and ILendingAdapter for Compound V3 integration
contract CompoundV3Adapter is IYieldAdapter, ILendingAdapter, Ownable {
    using SafeERC20 for IERC20;

    // ═══════════════════════════════════════════════════════════════════════
    // CONSTANTS
    // ═══════════════════════════════════════════════════════════════════════

    uint256 private constant SECONDS_PER_YEAR = 365.25 days;
    uint256 private constant SCALE = 1e18;
    uint256 private constant FACTOR_SCALE = 1e18;

    // ═══════════════════════════════════════════════════════════════════════
    // STATE
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice Compound V3 Comet contract
    IComet public immutable comet;

    /// @notice Compound V3 rewards contract
    ICometRewards public immutable rewards;

    /// @notice Underlying asset (base token)
    IERC20 public immutable underlying;

    /// @notice Treasury address for harvested rewards
    address public treasury;

    // ═══════════════════════════════════════════════════════════════════════
    // EVENTS
    // ═══════════════════════════════════════════════════════════════════════

    event Supplied(address indexed user, uint256 amount, uint256 shares);
    event Withdrawn(address indexed user, uint256 amount, uint256 shares);
    event Borrowed(address indexed user, uint256 amount);
    event Repaid(address indexed user, uint256 amount);
    event CollateralSupplied(address indexed user, address indexed asset, uint256 amount);
    event CollateralWithdrawn(address indexed user, address indexed asset, uint256 amount);
    event RewardsClaimed(address indexed user, address indexed rewardToken, uint256 amount);
    event TreasuryUpdated(address indexed oldTreasury, address indexed newTreasury);

    // ═══════════════════════════════════════════════════════════════════════
    // ERRORS
    // ═══════════════════════════════════════════════════════════════════════

    error ZeroAmount();
    error ZeroAddress();
    error InsufficientBalance();
    error UnsupportedAsset();

    // ═══════════════════════════════════════════════════════════════════════
    // CONSTRUCTOR
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice Initialize Compound V3 adapter
    /// @param _comet Compound V3 Comet contract address
    /// @param _rewards Compound V3 rewards contract address
    /// @param _treasury Treasury address for rewards
    constructor(
        address _comet,
        address _rewards,
        address _treasury
    ) Ownable(msg.sender) {
        if (_comet == address(0)) revert ZeroAddress();
        if (_treasury == address(0)) revert ZeroAddress();

        comet = IComet(_comet);
        rewards = ICometRewards(_rewards);
        treasury = _treasury;

        // Get base token from Comet
        underlying = IERC20(comet.baseToken());

        // Approve Comet to spend underlying
        underlying.forceApprove(address(comet), type(uint256).max);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // IYIELDADAPTER IMPLEMENTATION
    // ═══════════════════════════════════════════════════════════════════════

    /// @inheritdoc IYieldAdapter
    function price() external view override returns (uint256) {
        // Compound V3 shares are 1:1 with underlying for base token
        // The price is fetched from the oracle
        address priceFeed = comet.baseTokenPriceFeed();
        return comet.getPrice(priceFeed);
    }

    /// @inheritdoc IYieldAdapter
    function apy() external view override returns (uint256) {
        uint256 utilization = comet.getUtilization();
        uint64 supplyRate = comet.getSupplyRate(utilization);
        // Convert per-second rate to APY
        // APY = (1 + rate)^seconds_per_year - 1
        // Simplified: rate * seconds_per_year (for small rates)
        return uint256(supplyRate) * SECONDS_PER_YEAR;
    }

    /// @inheritdoc IYieldAdapter
    function tvl() external view override returns (uint256) {
        return comet.totalSupply();
    }

    /// @inheritdoc IYieldAdapter
    function wrap(uint256 amount) external override returns (uint256 shares) {
        if (amount == 0) revert ZeroAmount();

        uint256 balanceBefore = comet.balanceOf(address(this));

        // Transfer underlying from user
        underlying.safeTransferFrom(msg.sender, address(this), amount);

        // Supply to Compound V3
        comet.supply(address(underlying), amount);

        shares = comet.balanceOf(address(this)) - balanceBefore;

        emit Supplied(msg.sender, amount, shares);
    }

    /// @inheritdoc IYieldAdapter
    function unwrap(uint256 shares) external override returns (uint256 amount) {
        if (shares == 0) revert ZeroAmount();

        uint256 balanceBefore = underlying.balanceOf(address(this));

        // Withdraw from Compound V3
        comet.withdraw(address(underlying), shares);

        amount = underlying.balanceOf(address(this)) - balanceBefore;

        // Transfer to user
        underlying.safeTransfer(msg.sender, amount);

        emit Withdrawn(msg.sender, amount, shares);
    }

    /// @inheritdoc IYieldAdapter
    function harvest() external override returns (uint256 harvested) {
        if (address(rewards) == address(0)) return 0;

        // Claim COMP rewards
        (address rewardToken, uint256 owed) = rewards.getRewardOwed(address(comet), address(this));
        
        if (owed > 0) {
            rewards.claim(address(comet), address(this), true);
            
            // Transfer rewards to treasury
            IERC20(rewardToken).safeTransfer(treasury, owed);
            harvested = owed;

            emit RewardsClaimed(address(this), rewardToken, harvested);
        }
    }

    // ═══════════════════════════════════════════════════════════════════════
    // ILENDINGADAPTER IMPLEMENTATION
    // ═══════════════════════════════════════════════════════════════════════

    /// @inheritdoc ILendingAdapter
    function maxLTV(address asset) external view override returns (uint256) {
        // Find asset info
        uint8 numAssets = comet.numAssets();
        for (uint8 i = 0; i < numAssets; i++) {
            IComet.AssetInfo memory info = comet.getAssetInfo(i);
            if (info.asset == asset) {
                // borrowCollateralFactor is scaled by 1e18
                return info.borrowCollateralFactor;
            }
        }
        return 0;
    }

    /// @inheritdoc ILendingAdapter
    function borrowRate() external view override returns (uint256) {
        uint256 utilization = comet.getUtilization();
        uint64 rate = comet.getBorrowRate(utilization);
        return uint256(rate) * SECONDS_PER_YEAR;
    }

    /// @inheritdoc ILendingAdapter
    function supplyRate() external view override returns (uint256) {
        uint256 utilization = comet.getUtilization();
        uint64 rate = comet.getSupplyRate(utilization);
        return uint256(rate) * SECONDS_PER_YEAR;
    }

    /// @inheritdoc ILendingAdapter
    function borrow(uint256 amount) external override returns (uint256 borrowed) {
        if (amount == 0) revert ZeroAmount();

        uint256 balanceBefore = underlying.balanceOf(address(this));

        // Withdraw/borrow from Compound V3
        // In Comet, withdrawing more than your supply creates a borrow
        comet.withdraw(address(underlying), amount);

        borrowed = underlying.balanceOf(address(this)) - balanceBefore;

        // Transfer to user
        underlying.safeTransfer(msg.sender, borrowed);

        emit Borrowed(msg.sender, borrowed);
    }

    /// @inheritdoc ILendingAdapter
    function repay(uint256 amount) external override returns (uint256 repaid) {
        if (amount == 0) revert ZeroAmount();

        // Transfer from user
        underlying.safeTransferFrom(msg.sender, address(this), amount);

        // Supply to Compound V3 (repays borrow first)
        comet.supply(address(underlying), amount);

        repaid = amount;

        emit Repaid(msg.sender, repaid);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // COLLATERAL FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice Supply collateral to Compound V3
    /// @param asset Collateral asset address
    /// @param amount Amount to supply
    function supplyCollateral(address asset, uint256 amount) external {
        if (amount == 0) revert ZeroAmount();
        if (asset == address(0)) revert ZeroAddress();

        // Transfer from user
        IERC20(asset).safeTransferFrom(msg.sender, address(this), amount);

        // Approve if needed
        IERC20(asset).forceApprove(address(comet), amount);

        // Supply collateral
        comet.supply(asset, amount);

        emit CollateralSupplied(msg.sender, asset, amount);
    }

    /// @notice Withdraw collateral from Compound V3
    /// @param asset Collateral asset address
    /// @param amount Amount to withdraw
    function withdrawCollateral(address asset, uint256 amount) external {
        if (amount == 0) revert ZeroAmount();
        if (asset == address(0)) revert ZeroAddress();

        // Withdraw collateral
        comet.withdraw(asset, amount);

        // Transfer to user
        IERC20(asset).safeTransfer(msg.sender, amount);

        emit CollateralWithdrawn(msg.sender, asset, amount);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // VIEW FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice Get user's supply balance
    /// @param user User address
    /// @return Supply balance in base token
    function getSupplyBalance(address user) external view returns (uint256) {
        return comet.balanceOf(user);
    }

    /// @notice Get user's borrow balance
    /// @param user User address
    /// @return Borrow balance in base token
    function getBorrowBalance(address user) external view returns (uint256) {
        return comet.borrowBalanceOf(user);
    }

    /// @notice Get user's collateral balance
    /// @param user User address
    /// @param asset Collateral asset
    /// @return Collateral balance
    function getCollateralBalance(address user, address asset) external view returns (uint256) {
        return comet.collateralBalanceOf(user, asset);
    }

    /// @notice Get protocol utilization rate
    /// @return Utilization scaled by 1e18
    function getUtilization() external view returns (uint256) {
        return comet.getUtilization();
    }

    /// @notice Get total borrows
    /// @return Total borrowed amount
    function getTotalBorrows() external view returns (uint256) {
        return comet.totalBorrow();
    }

    // ═══════════════════════════════════════════════════════════════════════
    // ADMIN FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice Update treasury address
    /// @param _treasury New treasury address
    function setTreasury(address _treasury) external onlyOwner {
        if (_treasury == address(0)) revert ZeroAddress();
        address old = treasury;
        treasury = _treasury;
        emit TreasuryUpdated(old, _treasury);
    }

    /// @notice Emergency withdraw
    /// @param token Token to withdraw
    /// @param amount Amount to withdraw
    function emergencyWithdraw(address token, uint256 amount) external onlyOwner {
        IERC20(token).safeTransfer(owner(), amount);
    }
}
