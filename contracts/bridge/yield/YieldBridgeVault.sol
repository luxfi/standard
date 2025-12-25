// SPDX-License-Identifier: MIT
pragma solidity ^0.8.31;

/**
    ██╗   ██╗██╗███████╗██╗     ██████╗     ██████╗ ██████╗ ██╗██████╗  ██████╗ ███████╗
    ╚██╗ ██╔╝██║██╔════╝██║     ██╔══██╗    ██╔══██╗██╔══██╗██║██╔══██╗██╔════╝ ██╔════╝
     ╚████╔╝ ██║█████╗  ██║     ██║  ██║    ██████╔╝██████╔╝██║██║  ██║██║  ███╗█████╗  
      ╚██╔╝  ██║██╔══╝  ██║     ██║  ██║    ██╔══██╗██╔══██╗██║██║  ██║██║   ██║██╔══╝  
       ██║   ██║███████╗███████╗██████╔╝    ██████╔╝██║  ██║██║██████╔╝╚██████╔╝███████╗
       ╚═╝   ╚═╝╚══════╝╚══════╝╚═════╝     ╚═════╝ ╚═╝  ╚═╝╚═╝╚═════╝  ╚═════╝ ╚══════╝

    Yield-Bearing Bridge Vault - Deploys bridged assets to yield strategies
    
    Architecture:
    - Deployed on SOURCE chains (Ethereum, Solana, etc.)
    - Receives bridged assets and deploys to yield strategies
    - Reports yield back to Lux via Warp messaging
    - Supports multiple strategies per asset for diversification
 */

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IYieldStrategy} from "./IYieldStrategy.sol";

/**
 * @title YieldBridgeVault
 * @notice Manages bridged assets with automatic yield deployment
 * @dev Deployed on source chains (Ethereum, etc.) to earn yield on locked assets
 * 
 * When users bridge ETH to Lux:
 * 1. ETH deposited to this vault on Ethereum
 * 2. Vault deploys ETH to yield strategies (Lido, Rocket Pool, etc.)
 * 3. LETH minted on Lux via bridge
 * 4. Yield accumulates and is periodically reported to Lux
 * 5. Yield distributed to LETH holders or protocol treasury
 */
contract YieldBridgeVault is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // ═══════════════════════════════════════════════════════════════════════
    // TYPES
    // ═══════════════════════════════════════════════════════════════════════

    struct StrategyAllocation {
        address strategy;       // Strategy contract address
        uint256 targetWeight;   // Target allocation in basis points (10000 = 100%)
        uint256 depositedAmount; // Amount deposited to this strategy
        bool isActive;          // Whether strategy is accepting deposits
    }

    struct AssetConfig {
        address asset;              // Asset address (address(0) for native ETH)
        uint256 totalDeposited;     // Total amount deposited by bridge users
        uint256 totalInStrategies;  // Total amount deployed to strategies
        uint256 lastHarvestTime;    // Last yield harvest timestamp
        uint256 accumulatedYield;   // Yield accumulated since last distribution
        uint256 reserveRatio;       // % kept liquid for withdrawals (basis points)
        bool isSupported;           // Whether asset is supported
    }

    struct YieldReport {
        address asset;
        uint256 totalAssets;
        uint256 yieldAmount;
        uint256 timestamp;
        bytes32 reportId;
    }

    // ═══════════════════════════════════════════════════════════════════════
    // STATE
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice Lux chain ID for Warp messages
    uint32 public immutable luxChainId;

    /// @notice Bridge controller address (MPC or multisig)
    address public bridge;

    /// @notice Yield receiver on Lux chain
    address public yieldReceiver;

    /// @notice Asset configurations
    mapping(address => AssetConfig) public assetConfigs;

    /// @notice Strategies per asset (asset => strategy[])
    mapping(address => StrategyAllocation[]) public strategies;

    /// @notice Supported assets list
    address[] public supportedAssets;

    /// @notice Minimum harvest interval
    uint256 public harvestInterval = 1 days;

    /// @notice Default reserve ratio (10% = 1000 basis points)
    uint256 public constant DEFAULT_RESERVE_RATIO = 1000;

    /// @notice Basis points denominator
    uint256 public constant BASIS_POINTS = 10000;

    // ═══════════════════════════════════════════════════════════════════════
    // EVENTS
    // ═══════════════════════════════════════════════════════════════════════

    event AssetDeposited(address indexed asset, address indexed depositor, uint256 amount);
    event AssetWithdrawn(address indexed asset, address indexed recipient, uint256 amount);
    event StrategyAdded(address indexed asset, address indexed strategy, uint256 targetWeight);
    event StrategyRemoved(address indexed asset, address indexed strategy);
    event YieldHarvested(address indexed asset, uint256 amount, uint256 timestamp);
    event YieldDistributed(address indexed asset, uint256 amount, bytes32 reportId);
    event StrategyRebalanced(address indexed asset, address indexed strategy, uint256 newAmount);

    // ═══════════════════════════════════════════════════════════════════════
    // MODIFIERS
    // ═══════════════════════════════════════════════════════════════════════

    modifier onlyBridge() {
        require(msg.sender == bridge, "YieldBridgeVault: only bridge");
        _;
    }

    modifier assetSupported(address asset) {
        require(assetConfigs[asset].isSupported, "YieldBridgeVault: asset not supported");
        _;
    }

    // ═══════════════════════════════════════════════════════════════════════
    // CONSTRUCTOR
    // ═══════════════════════════════════════════════════════════════════════

    constructor(
        uint32 _luxChainId,
        address _bridge,
        address _yieldReceiver
    ) Ownable(msg.sender) {
        luxChainId = _luxChainId;
        bridge = _bridge;
        yieldReceiver = _yieldReceiver;
    }

    // ═══════════════════════════════════════════════════════════════════════
    // BRIDGE OPERATIONS
    // ═══════════════════════════════════════════════════════════════════════

    /**
     * @notice Deposit assets when user bridges to Lux
     * @dev Called by bridge when locking assets on source chain
     * @param asset Asset address (address(0) for native ETH)
     * @param amount Amount being bridged
     */
    function depositFromBridge(
        address asset,
        uint256 amount
    ) external payable onlyBridge assetSupported(asset) nonReentrant {
        if (asset == address(0)) {
            require(msg.value == amount, "YieldBridgeVault: ETH amount mismatch");
        } else {
            IERC20(asset).safeTransferFrom(msg.sender, address(this), amount);
        }

        AssetConfig storage config = assetConfigs[asset];
        config.totalDeposited += amount;

        // Deploy to strategies (keeping reserve liquid)
        _deployToStrategies(asset, amount);

        emit AssetDeposited(asset, msg.sender, amount);
    }

    /**
     * @notice Withdraw assets when user bridges back from Lux
     * @dev Called by bridge when unlocking assets on source chain
     * @param asset Asset address
     * @param recipient Recipient address
     * @param amount Amount to withdraw
     */
    function withdrawToBridge(
        address asset,
        address recipient,
        uint256 amount
    ) external onlyBridge assetSupported(asset) nonReentrant {
        AssetConfig storage config = assetConfigs[asset];
        require(config.totalDeposited >= amount, "YieldBridgeVault: insufficient balance");

        // First try liquid balance
        uint256 liquidBalance = _getLiquidBalance(asset);
        
        if (liquidBalance < amount) {
            // Need to withdraw from strategies
            uint256 needed = amount - liquidBalance;
            _withdrawFromStrategies(asset, needed);
        }

        config.totalDeposited -= amount;

        if (asset == address(0)) {
            (bool success, ) = recipient.call{value: amount}("");
            require(success, "YieldBridgeVault: ETH transfer failed");
        } else {
            IERC20(asset).safeTransfer(recipient, amount);
        }

        emit AssetWithdrawn(asset, recipient, amount);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // YIELD OPERATIONS
    // ═══════════════════════════════════════════════════════════════════════

    /**
     * @notice Harvest yield from all strategies for an asset
     * @param asset Asset to harvest
     * @return totalYield Total yield harvested
     */
    function harvestYield(address asset) external assetSupported(asset) returns (uint256 totalYield) {
        AssetConfig storage config = assetConfigs[asset];
        require(
            block.timestamp >= config.lastHarvestTime + harvestInterval,
            "YieldBridgeVault: harvest too soon"
        );

        StrategyAllocation[] storage assetStrategies = strategies[asset];
        
        for (uint256 i = 0; i < assetStrategies.length; i++) {
            if (assetStrategies[i].isActive) {
                uint256 harvested = IYieldStrategy(assetStrategies[i].strategy).harvest();
                totalYield += harvested;
            }
        }

        config.accumulatedYield += totalYield;
        config.lastHarvestTime = block.timestamp;

        emit YieldHarvested(asset, totalYield, block.timestamp);
    }

    /**
     * @notice Distribute accumulated yield to Lux chain
     * @dev Sends Warp message with yield report
     * @param asset Asset to distribute yield for
     * @return reportId Unique report identifier
     */
    function distributeYield(address asset) external assetSupported(asset) returns (bytes32 reportId) {
        AssetConfig storage config = assetConfigs[asset];
        uint256 yieldAmount = config.accumulatedYield;
        require(yieldAmount > 0, "YieldBridgeVault: no yield to distribute");

        // Generate report ID
        reportId = keccak256(abi.encodePacked(
            asset,
            yieldAmount,
            block.timestamp,
            block.number
        ));

        // Create yield report
        YieldReport memory report = YieldReport({
            asset: asset,
            totalAssets: getTotalAssets(asset),
            yieldAmount: yieldAmount,
            timestamp: block.timestamp,
            reportId: reportId
        });

        // Reset accumulated yield
        config.accumulatedYield = 0;

        // Send to Lux via Warp (actual implementation depends on Warp interface)
        _sendYieldReport(report);

        emit YieldDistributed(asset, yieldAmount, reportId);
    }

    /**
     * @notice Get total assets including yield for an asset
     * @param asset Asset address
     * @return Total assets in underlying terms
     */
    function getTotalAssets(address asset) public view returns (uint256) {
        uint256 liquid = _getLiquidBalance(asset);
        uint256 inStrategies = 0;

        StrategyAllocation[] storage assetStrategies = strategies[asset];
        for (uint256 i = 0; i < assetStrategies.length; i++) {
            if (assetStrategies[i].isActive) {
                inStrategies += IYieldStrategy(assetStrategies[i].strategy).totalAssets();
            }
        }

        return liquid + inStrategies;
    }

    /**
     * @notice Get current APY for an asset (weighted average of strategies)
     * @param asset Asset address
     * @return Weighted average APY in basis points
     */
    function getCurrentAPY(address asset) external view returns (uint256) {
        StrategyAllocation[] storage assetStrategies = strategies[asset];
        if (assetStrategies.length == 0) return 0;

        uint256 totalWeight = 0;
        uint256 weightedAPY = 0;

        for (uint256 i = 0; i < assetStrategies.length; i++) {
            if (assetStrategies[i].isActive) {
                uint256 strategyAPY = IYieldStrategy(assetStrategies[i].strategy).currentAPY();
                weightedAPY += strategyAPY * assetStrategies[i].targetWeight;
                totalWeight += assetStrategies[i].targetWeight;
            }
        }

        return totalWeight > 0 ? weightedAPY / totalWeight : 0;
    }

    // ═══════════════════════════════════════════════════════════════════════
    // STRATEGY MANAGEMENT
    // ═══════════════════════════════════════════════════════════════════════

    /**
     * @notice Add a yield strategy for an asset
     * @param asset Asset address
     * @param strategy Strategy contract address
     * @param targetWeight Target allocation weight (basis points)
     */
    function addStrategy(
        address asset,
        address strategy,
        uint256 targetWeight
    ) external onlyOwner assetSupported(asset) {
        require(targetWeight <= BASIS_POINTS, "YieldBridgeVault: invalid weight");
        require(IYieldStrategy(strategy).asset() == asset, "YieldBridgeVault: asset mismatch");

        strategies[asset].push(StrategyAllocation({
            strategy: strategy,
            targetWeight: targetWeight,
            depositedAmount: 0,
            isActive: true
        }));

        // Approve strategy to spend asset
        if (asset != address(0)) {
            IERC20(asset).approve(strategy, type(uint256).max);
        }

        emit StrategyAdded(asset, strategy, targetWeight);
    }

    /**
     * @notice Remove a strategy (withdraws all funds first)
     * @param asset Asset address
     * @param strategyIndex Index of strategy to remove
     */
    function removeStrategy(
        address asset,
        uint256 strategyIndex
    ) external onlyOwner {
        StrategyAllocation[] storage assetStrategies = strategies[asset];
        require(strategyIndex < assetStrategies.length, "YieldBridgeVault: invalid index");

        StrategyAllocation storage allocation = assetStrategies[strategyIndex];
        
        // Withdraw all funds from strategy
        if (allocation.depositedAmount > 0) {
            IYieldStrategy(allocation.strategy).withdraw(allocation.depositedAmount);
        }

        address removedStrategy = allocation.strategy;

        // Remove strategy (swap and pop)
        assetStrategies[strategyIndex] = assetStrategies[assetStrategies.length - 1];
        assetStrategies.pop();

        emit StrategyRemoved(asset, removedStrategy);
    }

    /**
     * @notice Rebalance strategies to match target weights
     * @param asset Asset to rebalance
     */
    function rebalance(address asset) external onlyOwner assetSupported(asset) {
        uint256 totalAssets = getTotalAssets(asset);
        uint256 reserveAmount = (totalAssets * assetConfigs[asset].reserveRatio) / BASIS_POINTS;
        uint256 deployableAmount = totalAssets - reserveAmount;

        StrategyAllocation[] storage assetStrategies = strategies[asset];

        // Calculate and execute rebalancing
        for (uint256 i = 0; i < assetStrategies.length; i++) {
            if (!assetStrategies[i].isActive) continue;

            uint256 targetAmount = (deployableAmount * assetStrategies[i].targetWeight) / BASIS_POINTS;
            uint256 currentAmount = IYieldStrategy(assetStrategies[i].strategy).totalAssets();

            if (currentAmount < targetAmount) {
                // Need to deposit more
                uint256 toDeposit = targetAmount - currentAmount;
                _depositToStrategy(asset, assetStrategies[i].strategy, toDeposit);
            } else if (currentAmount > targetAmount) {
                // Need to withdraw some
                uint256 toWithdraw = currentAmount - targetAmount;
                IYieldStrategy(assetStrategies[i].strategy).withdraw(toWithdraw);
            }

            assetStrategies[i].depositedAmount = targetAmount;
            emit StrategyRebalanced(asset, assetStrategies[i].strategy, targetAmount);
        }
    }

    // ═══════════════════════════════════════════════════════════════════════
    // ASSET MANAGEMENT
    // ═══════════════════════════════════════════════════════════════════════

    /**
     * @notice Add support for a new asset
     * @param asset Asset address (address(0) for native ETH)
     * @param reserveRatio Reserve ratio in basis points
     */
    function addSupportedAsset(
        address asset,
        uint256 reserveRatio
    ) external onlyOwner {
        require(!assetConfigs[asset].isSupported, "YieldBridgeVault: already supported");
        require(reserveRatio <= BASIS_POINTS, "YieldBridgeVault: invalid reserve ratio");

        assetConfigs[asset] = AssetConfig({
            asset: asset,
            totalDeposited: 0,
            totalInStrategies: 0,
            lastHarvestTime: block.timestamp,
            accumulatedYield: 0,
            reserveRatio: reserveRatio > 0 ? reserveRatio : DEFAULT_RESERVE_RATIO,
            isSupported: true
        });

        supportedAssets.push(asset);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // INTERNAL FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════

    function _deployToStrategies(address asset, uint256 amount) internal {
        AssetConfig storage config = assetConfigs[asset];
        
        // Keep reserve liquid
        uint256 reserveAmount = (amount * config.reserveRatio) / BASIS_POINTS;
        uint256 toDeployAmount = amount - reserveAmount;

        if (toDeployAmount == 0) return;

        StrategyAllocation[] storage assetStrategies = strategies[asset];
        
        for (uint256 i = 0; i < assetStrategies.length; i++) {
            if (!assetStrategies[i].isActive) continue;

            uint256 strategyAmount = (toDeployAmount * assetStrategies[i].targetWeight) / BASIS_POINTS;
            if (strategyAmount > 0) {
                _depositToStrategy(asset, assetStrategies[i].strategy, strategyAmount);
                assetStrategies[i].depositedAmount += strategyAmount;
                config.totalInStrategies += strategyAmount;
            }
        }
    }

    function _withdrawFromStrategies(address asset, uint256 amount) internal {
        StrategyAllocation[] storage assetStrategies = strategies[asset];
        uint256 remaining = amount;

        // Withdraw proportionally from all strategies
        for (uint256 i = 0; i < assetStrategies.length && remaining > 0; i++) {
            if (!assetStrategies[i].isActive) continue;

            uint256 strategyBalance = IYieldStrategy(assetStrategies[i].strategy).totalAssets();
            uint256 toWithdraw = remaining > strategyBalance ? strategyBalance : remaining;

            if (toWithdraw > 0) {
                IYieldStrategy(assetStrategies[i].strategy).withdraw(toWithdraw);
                assetStrategies[i].depositedAmount -= toWithdraw;
                assetConfigs[asset].totalInStrategies -= toWithdraw;
                remaining -= toWithdraw;
            }
        }
    }

    function _depositToStrategy(address asset, address strategy, uint256 amount) internal {
        if (asset == address(0)) {
            // Native ETH - need to wrap or send directly depending on strategy
            IYieldStrategy(strategy).deposit(amount);
        } else {
            IYieldStrategy(strategy).deposit(amount);
        }
    }

    function _getLiquidBalance(address asset) internal view returns (uint256) {
        if (asset == address(0)) {
            return address(this).balance;
        } else {
            return IERC20(asset).balanceOf(address(this));
        }
    }

    function _sendYieldReport(YieldReport memory report) internal {
        // Encode and send via Warp messaging
        // This is a placeholder - actual implementation depends on Warp precompile
        bytes memory payload = abi.encode(
            uint8(2), // Message type: YIELD_REPORT
            luxChainId,
            yieldReceiver,
            report.asset,
            report.totalAssets,
            report.yieldAmount,
            report.timestamp,
            report.reportId
        );

        // IWarp(WARP_PRECOMPILE).sendWarpMessage(payload);
        // For now, just emit event (cross-chain messaging handled by relayer)
    }

    // ═══════════════════════════════════════════════════════════════════════
    // ADMIN FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════

    function setBridge(address _bridge) external onlyOwner {
        bridge = _bridge;
    }

    function setYieldReceiver(address _yieldReceiver) external onlyOwner {
        yieldReceiver = _yieldReceiver;
    }

    function setHarvestInterval(uint256 _interval) external onlyOwner {
        harvestInterval = _interval;
    }

    function setReserveRatio(address asset, uint256 ratio) external onlyOwner {
        require(ratio <= BASIS_POINTS, "YieldBridgeVault: invalid ratio");
        assetConfigs[asset].reserveRatio = ratio;
    }

    // ═══════════════════════════════════════════════════════════════════════
    // VIEW FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════

    function getStrategies(address asset) external view returns (StrategyAllocation[] memory) {
        return strategies[asset];
    }

    function getSupportedAssets() external view returns (address[] memory) {
        return supportedAssets;
    }

    receive() external payable {}
}
