// SPDX-License-Identifier: MIT
pragma solidity ^0.8.31;

/**
 *     ██╗   ██╗██╗███████╗██╗     ██████╗     ██████╗ ██████╗ ██╗██████╗  ██████╗ ███████╗
 *     ╚██╗ ██╔╝██║██╔════╝██║     ██╔══██╗    ██╔══██╗██╔══██╗██║██╔══██╗██╔════╝ ██╔════╝
 *      ╚████╔╝ ██║█████╗  ██║     ██║  ██║    ██████╔╝██████╔╝██║██║  ██║██║  ███╗█████╗
 *       ╚██╔╝  ██║██╔══╝  ██║     ██║  ██║    ██╔══██╗██╔══██╗██║██║  ██║██║   ██║██╔══╝
 *        ██║   ██║███████╗███████╗██████╔╝    ██████╔╝██║  ██║██║██████╔╝╚██████╔╝███████╗
 *        ╚═╝   ╚═╝╚══════╝╚══════╝╚═════╝     ╚═════╝ ╚═╝  ╚═╝╚═╝╚═════╝  ╚═════╝ ╚══════╝
 *
 *     Yield-Bearing Bridge Token (yLETH, yLBTC, yLUSD, etc.)
 *
 *     Features:
 *     - Share-based accounting (like ERC4626)
 *     - Receives yield reports from source chain via Warp
 *     - Integrates with Alchemix as collateral (auto-repaying loans)
 *     - Integrates with LPX Perps as collateral
 *     - Configurable yield strategies per source chain
 *     - Claims yield proportionally to all holders
 */

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title YieldBearingBridgeToken
 * @notice Bridge token that earns yield from source chain strategies
 * @dev Deployed on destination chain, receives yield reports via Warp
 *
 * Example: yLETH
 * - User bridges ETH from source chain
 * - ETH deployed to yield strategies on source chain
 * - User receives yield-bearing bridge token on destination chain
 * - Token value increases as yield accrues
 * - Can be used as collateral across DeFi protocols
 */
contract YieldBearingBridgeToken is ERC20, Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // ═══════════════════════════════════════════════════════════════════════
    // TYPES
    // ═══════════════════════════════════════════════════════════════════════

    struct YieldReport {
        uint256 totalAssets; // Total assets on source chain
        uint256 yieldAmount; // Yield since last report
        uint256 timestamp; // Report timestamp
        bytes32 reportId; // Unique report ID
        bool processed; // Whether report has been processed
    }

    struct StrategyInfo {
        bytes32 strategyId; // Strategy identifier
        string name; // Human-readable name (e.g., "Lido stETH")
        uint256 allocation; // Allocation percentage (basis points)
        uint256 currentAPY; // Current APY in basis points
        bool isActive; // Whether strategy is active
    }

    // ═══════════════════════════════════════════════════════════════════════
    // STATE
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice Source chain ID (e.g., Ethereum = 1)
    uint32 public immutable sourceChainId;

    /// @notice Underlying asset symbol (e.g., "ETH", "BTC", "USD")
    string public underlyingSymbol;

    /// @notice Total underlying assets (updated via yield reports)
    uint256 public totalUnderlyingAssets;

    /// @notice Virtual offset to prevent first-depositor inflation attack (OZ ERC-4626 approach)
    uint256 private constant VIRTUAL_SHARES = 1e3;
    uint256 private constant VIRTUAL_ASSETS = 1;

    /// @notice Bridge controller
    address public bridge;

    /// @notice Warp messenger for receiving yield reports
    address public constant WARP = 0x0200000000000000000000000000000000000005;

    /// @notice Source chain yield vault address
    address public sourceVault;

    /// @notice Yield reports from source chain
    mapping(bytes32 => YieldReport) public yieldReports;

    /// @notice Latest processed report ID
    bytes32 public latestReportId;

    /// @notice Configured strategies
    StrategyInfo[] public strategies;

    /// @notice Accumulated yield for distribution
    uint256 public pendingYield;

    /// @notice Fee percentage for protocol (basis points)
    uint256 public protocolFee = 1000; // 10%

    /// @notice Fee receiver
    address public feeReceiver;

    /// @notice Basis points denominator
    uint256 public constant BASIS_POINTS = 10000;

    // ═══════════════════════════════════════════════════════════════════════
    // EVENTS
    // ═══════════════════════════════════════════════════════════════════════

    event Deposit(address indexed sender, address indexed receiver, uint256 assets, uint256 shares);
    event Withdraw(address indexed sender, address indexed receiver, uint256 assets, uint256 shares);
    event YieldReported(bytes32 indexed reportId, uint256 yieldAmount, uint256 newTotalAssets);
    event YieldDistributed(uint256 amount, uint256 protocolFeeAmount);
    event StrategyUpdated(bytes32 indexed strategyId, string name, uint256 allocation);
    event BridgeUpdated(address indexed oldBridge, address indexed newBridge);
    event SourceVaultUpdated(address indexed oldVault, address indexed newVault);
    event ProtocolFeeUpdated(uint256 oldFee, uint256 newFee);
    event FeeReceiverUpdated(address indexed oldReceiver, address indexed newReceiver);

    // ═══════════════════════════════════════════════════════════════════════
    // MODIFIERS
    // ═══════════════════════════════════════════════════════════════════════

    modifier onlyBridge() {
        require(msg.sender == bridge, "YieldBearingBridgeToken: only bridge");
        _;
    }

    // ═══════════════════════════════════════════════════════════════════════
    // CONSTRUCTOR
    // ═══════════════════════════════════════════════════════════════════════

    constructor(
        string memory _name,
        string memory _symbol,
        string memory _underlyingSymbol,
        uint32 _sourceChainId,
        address _bridge,
        address _feeReceiver
    ) ERC20(_name, _symbol) Ownable(msg.sender) {
        underlyingSymbol = _underlyingSymbol;
        sourceChainId = _sourceChainId;
        bridge = _bridge;
        feeReceiver = _feeReceiver;
    }

    // ═══════════════════════════════════════════════════════════════════════
    // ERC4626-LIKE INTERFACE (Share-based accounting)
    // ═══════════════════════════════════════════════════════════════════════

    /**
     * @notice Deposit underlying assets and receive shares
     * @dev Called by bridge when user bridges from source chain
     * @param assets Amount of underlying assets
     * @param receiver Address to receive shares
     * @return shares Amount of shares minted
     */
    function deposit(uint256 assets, address receiver) external onlyBridge nonReentrant returns (uint256 shares) {
        shares = convertToShares(assets);
        require(shares > 0, "YieldBearingBridgeToken: zero shares");

        totalUnderlyingAssets += assets;

        _mint(receiver, shares);

        emit Deposit(msg.sender, receiver, assets, shares);
    }

    /**
     * @notice Withdraw underlying assets by burning shares
     * @dev Called by bridge when user bridges back to source chain
     * @param shares Amount of shares to burn
     * @param receiver Address on source chain to receive assets
     * @return assets Amount of underlying assets to release
     */
    function withdraw(uint256 shares, address receiver) external onlyBridge nonReentrant returns (uint256 assets) {
        require(balanceOf(msg.sender) >= shares, "YieldBearingBridgeToken: insufficient shares");

        assets = convertToAssets(shares);
        require(assets > 0, "YieldBearingBridgeToken: zero assets");

        totalUnderlyingAssets -= assets;

        _burn(msg.sender, shares);

        emit Withdraw(msg.sender, receiver, assets, shares);
    }

    /**
     * @notice Convert assets to shares
     * @param assets Amount of underlying assets
     * @return shares Equivalent shares
     */
    function convertToShares(uint256 assets) public view returns (uint256 shares) {
        // Virtual offset prevents first-depositor inflation attack (OZ ERC-4626)
        return (assets * (totalSupply() + VIRTUAL_SHARES)) / (totalUnderlyingAssets + VIRTUAL_ASSETS);
    }

    /**
     * @notice Convert shares to assets
     * @param shares Amount of shares
     * @return assets Equivalent underlying assets
     */
    function convertToAssets(uint256 shares) public view returns (uint256 assets) {
        return (shares * (totalUnderlyingAssets + VIRTUAL_ASSETS)) / (totalSupply() + VIRTUAL_SHARES);
    }

    /**
     * @notice Get total assets backing this token
     * @return Total underlying assets including yield
     */
    function totalAssets() external view returns (uint256) {
        return totalUnderlyingAssets;
    }

    /**
     * @notice Get exchange rate (assets per share)
     * @return Exchange rate in 18 decimals
     */
    function exchangeRate() external view returns (uint256) {
        // Must use virtual offset for consistency with convertToAssets()
        return ((totalUnderlyingAssets + VIRTUAL_ASSETS) * 1e18) / (totalSupply() + VIRTUAL_SHARES);
    }

    /**
     * @notice Get user's underlying asset value
     * @param account User address
     * @return Underlying asset value
     */
    function balanceOfUnderlying(address account) external view returns (uint256) {
        return convertToAssets(balanceOf(account));
    }

    // ═══════════════════════════════════════════════════════════════════════
    // YIELD REPORTING (Receives from source chain via Warp)
    // ═══════════════════════════════════════════════════════════════════════

    /**
     * @notice Process yield report from source chain
     * @dev Called after verifying Warp message from source chain vault
     * @param totalAssetsOnSource Total assets on source chain
     * @param yieldAmount Yield since last report
     * @param timestamp Report timestamp
     * @param reportId Unique report ID
     */
    function processYieldReport(uint256 totalAssetsOnSource, uint256 yieldAmount, uint256 timestamp, bytes32 reportId)
        external
        onlyBridge
    {
        require(!yieldReports[reportId].processed, "YieldBearingBridgeToken: already processed");
        require(timestamp > yieldReports[latestReportId].timestamp, "YieldBearingBridgeToken: stale report");

        // Store report
        yieldReports[reportId] = YieldReport({
            totalAssets: totalAssetsOnSource,
            yieldAmount: yieldAmount,
            timestamp: timestamp,
            reportId: reportId,
            processed: true
        });

        latestReportId = reportId;

        // Update total assets (this increases exchange rate automatically)
        totalUnderlyingAssets = totalAssetsOnSource;

        // Track yield for distribution
        if (yieldAmount > 0) {
            pendingYield += yieldAmount;
        }

        emit YieldReported(reportId, yieldAmount, totalAssetsOnSource);
    }

    /**
     * @notice Distribute pending yield (takes protocol fee)
     * @dev Yield is automatically reflected in exchange rate
     *      This function just handles the protocol fee
     */
    function distributeYield() external {
        require(pendingYield > 0, "YieldBearingBridgeToken: no pending yield");

        uint256 yieldAmount = pendingYield;
        pendingYield = 0;

        // Protocol fee
        uint256 feeAmount = (yieldAmount * protocolFee) / BASIS_POINTS;

        // Fee is minted as shares to fee receiver (dilutes other holders)
        if (feeAmount > 0 && feeReceiver != address(0)) {
            uint256 feeShares = convertToShares(feeAmount);
            _mint(feeReceiver, feeShares);
        }

        emit YieldDistributed(yieldAmount, feeAmount);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // STRATEGY MANAGEMENT
    // ═══════════════════════════════════════════════════════════════════════

    /**
     * @notice Update strategy configuration
     * @dev Strategies are managed on source chain, this is just for display
     * @param strategyId Strategy identifier
     * @param _name Strategy name
     * @param allocation Allocation in basis points
     * @param apy Current APY
     */
    function updateStrategy(bytes32 strategyId, string calldata _name, uint256 allocation, uint256 apy)
        external
        onlyOwner
    {
        // Find existing strategy or add new one
        bool found = false;
        for (uint256 i = 0; i < strategies.length; i++) {
            if (strategies[i].strategyId == strategyId) {
                strategies[i].name = _name;
                strategies[i].allocation = allocation;
                strategies[i].currentAPY = apy;
                strategies[i].isActive = allocation > 0;
                found = true;
                break;
            }
        }

        if (!found) {
            strategies.push(
                StrategyInfo({
                    strategyId: strategyId,
                    name: _name,
                    allocation: allocation,
                    currentAPY: apy,
                    isActive: allocation > 0
                })
            );
        }

        emit StrategyUpdated(strategyId, _name, allocation);
    }

    /**
     * @notice Get all configured strategies
     * @return Array of strategy info
     */
    function getStrategies() external view returns (StrategyInfo[] memory) {
        return strategies;
    }

    /**
     * @notice Get weighted average APY across all strategies
     * @return Weighted APY in basis points
     */
    function getAverageAPY() external view returns (uint256) {
        uint256 totalWeight = 0;
        uint256 weightedAPY = 0;

        for (uint256 i = 0; i < strategies.length; i++) {
            if (strategies[i].isActive) {
                weightedAPY += strategies[i].currentAPY * strategies[i].allocation;
                totalWeight += strategies[i].allocation;
            }
        }

        return totalWeight > 0 ? weightedAPY / totalWeight : 0;
    }

    // ═══════════════════════════════════════════════════════════════════════
    // INTEGRATION HELPERS (For Alchemix & Perps)
    // ═══════════════════════════════════════════════════════════════════════

    /**
     * @notice Get price per share (for Alchemix/Perps integration)
     * @dev Returns the value of 1 share in underlying terms (18 decimals)
     * @return Price per share
     */
    function pricePerShare() external view returns (uint256) {
        // Must use virtual offset for consistency with convertToAssets()
        return ((totalUnderlyingAssets + VIRTUAL_ASSETS) * 1e18) / (totalSupply() + VIRTUAL_SHARES);
    }

    /**
     * @notice Check if token is yield-bearing (for integration detection)
     * @return Always true
     */
    function isYieldBearing() external pure returns (bool) {
        return true;
    }

    /**
     * @notice Get source chain info
     * @return chainId Source chain ID
     * @return vault Source chain vault address
     */
    function getSourceInfo() external view returns (uint32 chainId, address vault) {
        return (sourceChainId, sourceVault);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // ADMIN FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════

    function setBridge(address _bridge) external onlyOwner {
        address oldBridge = bridge;
        bridge = _bridge;
        emit BridgeUpdated(oldBridge, _bridge);
    }

    function setSourceVault(address _sourceVault) external onlyOwner {
        address oldVault = sourceVault;
        sourceVault = _sourceVault;
        emit SourceVaultUpdated(oldVault, _sourceVault);
    }

    function setProtocolFee(uint256 _fee) external onlyOwner {
        require(_fee <= 2000, "YieldBearingBridgeToken: fee too high"); // Max 20%
        uint256 oldFee = protocolFee;
        protocolFee = _fee;
        emit ProtocolFeeUpdated(oldFee, _fee);
    }

    function setFeeReceiver(address _feeReceiver) external onlyOwner {
        address oldReceiver = feeReceiver;
        feeReceiver = _feeReceiver;
        emit FeeReceiverUpdated(oldReceiver, _feeReceiver);
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// CONCRETE IMPLEMENTATIONS
// ═══════════════════════════════════════════════════════════════════════════

/**
 * @title yLETH - Yield-Bearing Bridged ETH
 * @notice ETH bridged from Ethereum, earning staking yield (Lido, Rocket Pool, Aave)
 */
contract yLETH is YieldBearingBridgeToken {
    constructor(address _bridge, address _feeReceiver)
        YieldBearingBridgeToken(
            "Yield-Bearing Bridged ETH",
            "yLETH",
            "ETH",
            1, // Ethereum mainnet
            _bridge,
            _feeReceiver
        )
    { }
}

/**
 * @title yLBTC - Yield-Bearing Bridged BTC
 * @notice BTC bridged, earning yield (eventually Babylon staking, or lending)
 */
contract yLBTC is YieldBearingBridgeToken {
    constructor(address _bridge, address _feeReceiver)
        YieldBearingBridgeToken(
            "Yield-Bearing Bridged BTC",
            "yLBTC",
            "BTC",
            1, // Source chain (could be Bitcoin via bridge)
            _bridge,
            _feeReceiver
        )
    { }
}

/**
 * @title yLUSD - Yield-Bearing Bridged USD
 * @notice USD stablecoins bridged, earning yield (Curve, Aave, Compound)
 */
contract yLUSD is YieldBearingBridgeToken {
    constructor(address _bridge, address _feeReceiver)
        YieldBearingBridgeToken(
            "Yield-Bearing Bridged USD",
            "yLUSD",
            "USD",
            1, // Ethereum mainnet
            _bridge,
            _feeReceiver
        )
    { }
}

/**
 * @title yLSOL - Yield-Bearing Bridged SOL
 * @notice SOL bridged from Solana, earning staking yield (Marinade, Jito)
 */
contract yLSOL is YieldBearingBridgeToken {
    constructor(address _bridge, address _feeReceiver)
        YieldBearingBridgeToken(
            "Yield-Bearing Bridged SOL",
            "yLSOL",
            "SOL",
            101, // Solana (example chain ID)
            _bridge,
            _feeReceiver
        )
    { }
}
