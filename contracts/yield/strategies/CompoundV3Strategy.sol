// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import "../IYieldStrategy.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/// @title Compound V3 (Comet) Strategy
/// @notice Supplies assets to Compound V3 for lending yields
/// @dev Compound V3 features:
///      - Single-asset markets (cUSDCv3, cWETHv3, etc.)
///      - Base asset earns supply yield
///      - COMP rewards for suppliers
///      - Cleaner architecture than V2

// ═══════════════════════════════════════════════════════════════════════════════
// COMPOUND V3 INTERFACES
// ═══════════════════════════════════════════════════════════════════════════════

interface IComet {
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
    
    function supply(address asset, uint256 amount) external;
    function withdraw(address asset, uint256 amount) external;
    function balanceOf(address account) external view returns (uint256);
    function baseToken() external view returns (address);
    function baseTokenPriceFeed() external view returns (address);
    function getSupplyRate(uint256 utilization) external view returns (uint64);
    function getUtilization() external view returns (uint256);
    function totalSupply() external view returns (uint256);
    function totalBorrow() external view returns (uint256);
    function baseTrackingSupplySpeed() external view returns (uint256);
    function baseTrackingBorrowSpeed() external view returns (uint256);
}

interface ICometRewards {
    struct RewardConfig {
        address token;
        uint64 rescaleFactor;
        bool shouldUpscale;
    }
    
    function claim(address comet, address src, bool shouldAccrue) external;
    function getRewardOwed(address comet, address account) external returns (address, uint256);
    function rewardConfig(address comet) external view returns (RewardConfig memory);
}

// ═══════════════════════════════════════════════════════════════════════════════
// COMPOUND V3 STRATEGY
// ═══════════════════════════════════════════════════════════════════════════════

/// @title Compound V3 Strategy
/// @notice Supplies base asset to Compound V3 markets
/// @dev Earns supply APY + COMP rewards
contract CompoundV3Strategy is Ownable, ReentrancyGuard{
    using SafeERC20 for IERC20;

    string public name;
    string public constant protocol = "Compound V3";
    string public constant version = "1.0.0";
    
    // Compound V3 Mainnet
    address public constant COMP_TOKEN = 0xc00e94Cb662C3520282E6f5717214004A7f26888;
    address public constant COMET_REWARDS = 0x1B0e765F6224C21223AeA2af16c1C46E38885a40;
    
    /// @notice Comet (cToken V3) contract
    IComet public immutable comet;
    
    /// @notice Base asset (USDC, WETH, etc.)
    IERC20 public immutable baseAsset;
    
    /// @notice CometRewards contract
    ICometRewards public immutable cometRewards;
    
    /// @notice Accumulated COMP rewards
    uint256 public accumulatedRewards;
    
    uint256 public totalDeposited;
    uint256 public lastHarvest;
    bool public isPaused;

    event Supplied(uint256 amount);
    event Withdrawn(uint256 amount);
    event RewardsClaimed(uint256 compAmount);

    constructor(
        string memory _name,
        address _comet,
        address _owner
    ) Ownable(_owner) {
        name = _name;
        comet = IComet(_comet);
        baseAsset = IERC20(comet.baseToken());
        cometRewards = ICometRewards(COMET_REWARDS);
        
        lastHarvest = block.timestamp;
        
        // Approve comet
        baseAsset.approve(_comet, type(uint256).max);
    }

    function asset() external view returns (address) {
        return address(baseAsset);
    }

    function deposit(uint256 amount) external nonReentrant returns (uint256 shares) {
        require(!isPaused, "Paused");
        
        baseAsset.safeTransferFrom(msg.sender, address(this), amount);
        
        // Supply to Compound V3
        comet.supply(address(baseAsset), amount);
        
        totalDeposited += amount;
        shares = amount; // 1:1 for base asset supply
        
        emit Supplied(amount);
    }

    function withdraw(uint256 amount) 
        external 

        nonReentrant 
        returns (uint256 assets) 
    {
        require(amount <= comet.balanceOf(address(this)), "Insufficient balance");
        
        // Withdraw from Compound V3
        comet.withdraw(address(baseAsset), amount);
        
        baseAsset.safeTransfer(msg.sender, amount);
        
        totalDeposited -= amount;
        assets = amount;
        
        emit Withdrawn(amount);
    }

    function harvest() external nonReentrant returns (uint256 yield) {
        // Claim COMP rewards
        cometRewards.claim(address(comet), address(this), true);
        
        uint256 compBalance = IERC20(COMP_TOKEN).balanceOf(address(this));
        accumulatedRewards += compBalance;
        lastHarvest = block.timestamp;
        yield = compBalance;
        
        emit RewardsClaimed(compBalance);
    }

    function totalAssets() external view returns (uint256) {
        // Compound V3 balance includes accrued interest
        return comet.balanceOf(address(this));
    }

    function currentAPY() external view returns (uint256) {
        // Get current utilization
        uint256 utilization = comet.getUtilization();
        
        // Get supply rate (per second, scaled by 1e18)
        uint64 supplyRate = comet.getSupplyRate(utilization);
        
        // Convert to APY in basis points
        // APY = (1 + rate)^31536000 - 1 ≈ rate * 31536000 for small rates
        uint256 apyBps = (uint256(supplyRate) * 365 days) / 1e14;
        
        return apyBps;
    }

    function isActive() external view returns (bool) {
        return !isPaused && comet.balanceOf(address(this)) > 0;
    }

    /// @notice Get pending COMP rewards
    function getPendingRewards() external returns (uint256) {
        (, uint256 owed) = cometRewards.getRewardOwed(address(comet), address(this));
        return owed;
    }

    /// @notice Get current utilization rate
    function getUtilization() external view returns (uint256) {
        return comet.getUtilization();
    }

    /// @notice Get market info
    function getMarketInfo() external view returns (
        uint256 totalSupply,
        uint256 totalBorrow,
        uint256 utilization,
        uint256 supplyRate
    ) {
        totalSupply = comet.totalSupply();
        totalBorrow = comet.totalBorrow();
        utilization = comet.getUtilization();
        supplyRate = comet.getSupplyRate(utilization);
    }

    /// @notice Send accumulated rewards to treasury
    function sendRewardsToTreasury(address treasury) external onlyOwner {
        uint256 compBalance = IERC20(COMP_TOKEN).balanceOf(address(this));
        if (compBalance > 0) {
            IERC20(COMP_TOKEN).safeTransfer(treasury, compBalance);
        }
    }

    function setPaused(bool paused) external onlyOwner {
        isPaused = paused;
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// CONCRETE IMPLEMENTATIONS
// ═══════════════════════════════════════════════════════════════════════════════

/// @title Compound V3 USDC Strategy (Mainnet)
/// @notice Supplies USDC to cUSDCv3
contract CompoundV3USDCStrategy is CompoundV3Strategy {
    // cUSDCv3 on Mainnet
    address public constant CUSDC_V3 = 0xc3d688B66703497DAA19211EEdff47f25384cdc3;
    
    constructor(address _owner) 
        CompoundV3Strategy("Compound V3 USDC", CUSDC_V3, _owner) 
    {}
}

/// @title Compound V3 WETH Strategy (Mainnet)
/// @notice Supplies WETH to cWETHv3
contract CompoundV3WETHStrategy is CompoundV3Strategy {
    // cWETHv3 on Mainnet
    address public constant CWETH_V3 = 0xA17581A9E3356d9A858b789D68B4d866e593aE94;
    
    constructor(address _owner) 
        CompoundV3Strategy("Compound V3 WETH", CWETH_V3, _owner) 
    {}
}

/// @title Compound V3 USDC Strategy (Base)
/// @notice Supplies USDC to cUSDCv3 on Base
contract CompoundV3USDCBaseStrategy is CompoundV3Strategy {
    // cUSDCv3 on Base
    address public constant CUSDC_V3_BASE = 0x9c4ec768c28520B50860ea7a15bd7213a9fF58bf;
    
    constructor(address _owner) 
        CompoundV3Strategy("Compound V3 USDC (Base)", CUSDC_V3_BASE, _owner) 
    {}
}

/// @title Compound V3 USDbC Strategy (Base)
/// @notice Supplies bridged USDC to cUSDbCv3 on Base
contract CompoundV3USDbCBaseStrategy is CompoundV3Strategy {
    // cUSDbCv3 on Base (bridged USDC)
    address public constant CUSDBC_V3_BASE = 0x9c4ec768c28520B50860ea7a15bd7213a9fF58bf; // Same as native on Base
    
    constructor(address _owner) 
        CompoundV3Strategy("Compound V3 USDbC (Base)", CUSDBC_V3_BASE, _owner) 
    {}
}
