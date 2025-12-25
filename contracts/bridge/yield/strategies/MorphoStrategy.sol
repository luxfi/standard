// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import "../IYieldStrategy.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/// @title Morpho Protocol Yield Strategies
/// @notice Yield strategies for Morpho Blue isolated lending and MetaMorpho vaults
/// @dev Morpho is a lending protocol with two main components:
///      - Morpho Blue: Isolated lending markets with customizable oracles and IRMs
///      - MetaMorpho: ERC4626 vault aggregator for passive lending
///
/// Key Features:
/// - Isolated risk markets (each market is independent)
/// - Customizable oracles (Chainlink, TWAP, etc.)
/// - Customizable Interest Rate Models (IRMs)
/// - MetaMorpho for simplified yield aggregation
///
/// Mainnet Addresses:
/// - Morpho Blue: 0xBBBBBbbBBb9cC5e90e3b3Af64bdAF62C37EEFFCb
/// - MetaMorpho Factory: 0xA9c3D3a366466Fa809d1Ae982Fb2c46E5fC41101

// =============================================================================
// MORPHO INTERFACES
// =============================================================================

/// @notice Morpho Blue - Isolated lending protocol
interface IMorpho {
    /// @notice Market parameters that uniquely identify a market
    struct MarketParams {
        address loanToken;
        address collateralToken;
        address oracle;
        address irm;
        uint256 lltv;
    }

    /// @notice Market state
    struct Market {
        uint128 totalSupplyAssets;
        uint128 totalSupplyShares;
        uint128 totalBorrowAssets;
        uint128 totalBorrowShares;
        uint128 lastUpdate;
        uint128 fee;
    }

    /// @notice User position in a market
    struct Position {
        uint256 supplyShares;
        uint128 borrowShares;
        uint128 collateral;
    }

    /// @notice Supply assets to a market
    function supply(
        MarketParams memory marketParams,
        uint256 assets,
        uint256 shares,
        address onBehalf,
        bytes memory data
    ) external returns (uint256 assetsSupplied, uint256 sharesSupplied);

    /// @notice Withdraw assets from a market
    function withdraw(
        MarketParams memory marketParams,
        uint256 assets,
        uint256 shares,
        address onBehalf,
        address receiver
    ) external returns (uint256 assetsWithdrawn, uint256 sharesWithdrawn);

    /// @notice Borrow assets from a market
    function borrow(
        MarketParams memory marketParams,
        uint256 assets,
        uint256 shares,
        address onBehalf,
        address receiver
    ) external returns (uint256 assetsBorrowed, uint256 sharesBorrowed);

    /// @notice Repay borrowed assets
    function repay(
        MarketParams memory marketParams,
        uint256 assets,
        uint256 shares,
        address onBehalf,
        bytes memory data
    ) external returns (uint256 assetsRepaid, uint256 sharesRepaid);

    /// @notice Supply collateral to a market
    function supplyCollateral(
        MarketParams memory marketParams,
        uint256 assets,
        address onBehalf,
        bytes memory data
    ) external;

    /// @notice Withdraw collateral from a market
    function withdrawCollateral(
        MarketParams memory marketParams,
        uint256 assets,
        address onBehalf,
        address receiver
    ) external;

    /// @notice Liquidate an underwater position
    function liquidate(
        MarketParams memory marketParams,
        address borrower,
        uint256 seizedAssets,
        uint256 repaidShares,
        bytes memory data
    ) external returns (uint256, uint256);

    /// @notice Accrue interest for a market
    function accrueInterest(MarketParams memory marketParams) external;

    /// @notice Get market state by ID
    function market(bytes32 id) external view returns (Market memory);

    /// @notice Get user position in a market
    function position(bytes32 id, address user) external view returns (Position memory);

    /// @notice Get market params from ID
    function idToMarketParams(bytes32 id) external view returns (MarketParams memory);
}

/// @notice MetaMorpho - ERC4626 vault aggregator for Morpho Blue
interface IMetaMorpho {
    // ERC4626 standard
    function deposit(uint256 assets, address receiver) external returns (uint256 shares);
    function mint(uint256 shares, address receiver) external returns (uint256 assets);
    function withdraw(uint256 assets, address receiver, address owner) external returns (uint256 shares);
    function redeem(uint256 shares, address receiver, address owner) external returns (uint256 assets);
    function convertToAssets(uint256 shares) external view returns (uint256);
    function convertToShares(uint256 assets) external view returns (uint256);
    function maxDeposit(address) external view returns (uint256);
    function maxMint(address) external view returns (uint256);
    function maxWithdraw(address owner) external view returns (uint256);
    function maxRedeem(address owner) external view returns (uint256);
    function previewDeposit(uint256 assets) external view returns (uint256);
    function previewMint(uint256 shares) external view returns (uint256);
    function previewWithdraw(uint256 assets) external view returns (uint256);
    function previewRedeem(uint256 shares) external view returns (uint256);
    function totalAssets() external view returns (uint256);
    function asset() external view returns (address);
    function balanceOf(address account) external view returns (uint256);
    function totalSupply() external view returns (uint256);
    function name() external view returns (string memory);
    function symbol() external view returns (string memory);
    function decimals() external view returns (uint8);

    // MetaMorpho specific
    function curator() external view returns (address);
    function guardian() external view returns (address);
    function fee() external view returns (uint96);
    function feeRecipient() external view returns (address);
    function timelock() external view returns (uint256);
    function supplyQueueLength() external view returns (uint256);
    function withdrawQueueLength() external view returns (uint256);
    function supplyQueue(uint256 index) external view returns (bytes32);
    function withdrawQueue(uint256 index) external view returns (bytes32);
    function config(bytes32 id) external view returns (uint184 cap, bool enabled, uint64 removableAt);
    function idle() external view returns (uint256);
    function lastTotalAssets() external view returns (uint256);
}

/// @notice Morpho Chainlink Oracle V2
interface IMorphoChainlinkOracleV2 {
    function price() external view returns (uint256);
    function SCALE_FACTOR() external view returns (uint256);
}

/// @notice Interest Rate Model interface
interface IIrm {
    function borrowRateView(
        IMorpho.MarketParams memory marketParams,
        IMorpho.Market memory market
    ) external view returns (uint256);

    function borrowRate(
        IMorpho.MarketParams memory marketParams,
        IMorpho.Market memory market
    ) external returns (uint256);
}

// =============================================================================
// MORPHO BLUE STRATEGY
// =============================================================================

/// @title Morpho Blue Strategy
/// @notice Yield strategy for Morpho Blue isolated lending markets
/// @dev Supplies to a single Morpho Blue market for yield
contract MorphoBlueStrategy is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // =========================================================================
    // CONSTANTS
    // =========================================================================

    /// @notice Morpho Blue contract (Ethereum mainnet)
    address public constant MORPHO = 0xBBBBBbbBBb9cC5e90e3b3Af64bdAF62C37EEFFCb;

    /// @notice Seconds per year for APY calculation
    uint256 internal constant SECONDS_PER_YEAR = 365.25 days;

    /// @notice WAD precision (1e18)
    uint256 internal constant WAD = 1e18;

    /// @notice Virtual shares for share/asset conversion
    uint256 internal constant VIRTUAL_SHARES = 1e6;

    /// @notice Virtual assets for share/asset conversion
    uint256 internal constant VIRTUAL_ASSETS = 1;

    // =========================================================================
    // STATE
    // =========================================================================

    /// @notice Market parameters for this strategy
    IMorpho.MarketParams public marketParams;

    /// @notice Cached market ID
    bytes32 public marketId;

    /// @notice Underlying loan token
    IERC20 public immutable loanToken;

    /// @notice Controller address
    address public controller;

    /// @notice Total deposited for yield tracking
    uint256 public totalDeposited;

    /// @notice Whether strategy is paused
    bool public isPaused;

    /// @notice Strategy name
    string private _name;

    // =========================================================================
    // EVENTS
    // =========================================================================

    event Deposited(address indexed depositor, uint256 assets, uint256 shares);
    event Withdrawn(address indexed recipient, uint256 assets, uint256 shares);
    event Harvested(uint256 yield);
    event ControllerUpdated(address indexed oldController, address indexed newController);

    // =========================================================================
    // ERRORS
    // =========================================================================

    error StrategyPaused();
    error OnlyController();
    error InsufficientShares();
    error DepositFailed();
    error WithdrawFailed();
    error ZeroAmount();
    error InvalidMarket();

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

    /// @notice Initialize Morpho Blue strategy
    /// @param _marketParams Market parameters (loanToken, collateralToken, oracle, irm, lltv)
    /// @param _controller Controller address
    /// @param strategyName Name for identification
    /// @param _owner Owner address
    constructor(
        IMorpho.MarketParams memory _marketParams,
        address _controller,
        string memory strategyName,
        address _owner
    ) Ownable(_owner) {
        if (_marketParams.loanToken == address(0)) revert InvalidMarket();

        marketParams = _marketParams;
        marketId = _computeMarketId(_marketParams);
        loanToken = IERC20(_marketParams.loanToken);
        controller = _controller;
        _name = strategyName;

        // Approve Morpho to spend loan token
        loanToken.approve(MORPHO, type(uint256).max);
    }

    // =========================================================================
    // YIELD STRATEGY INTERFACE
    // =========================================================================

    /// @notice
    function deposit(uint256 amount) external payable onlyController whenNotPaused nonReentrant returns (uint256 shares) {
        if (amount == 0) revert ZeroAmount();

        // Transfer assets from controller
        loanToken.safeTransferFrom(msg.sender, address(this), amount);

        // Supply to Morpho Blue
        (uint256 assetsSupplied, uint256 sharesSupplied) = IMorpho(MORPHO).supply(
            marketParams,
            amount,
            0, // shares = 0, supplying by assets
            address(this),
            "" // no callback data
        );

        if (assetsSupplied == 0) revert DepositFailed();

        totalDeposited += assetsSupplied;
        shares = sharesSupplied;

        emit Deposited(msg.sender, assetsSupplied, sharesSupplied);
    }

    /// @notice
    function withdraw(uint256 shares) external onlyController nonReentrant returns (uint256 amount) {
        if (shares == 0) revert ZeroAmount();

        IMorpho.Position memory pos = IMorpho(MORPHO).position(marketId, address(this));
        if (shares > pos.supplyShares) revert InsufficientShares();

        // Withdraw from Morpho Blue by shares
        (uint256 assetsWithdrawn,) = IMorpho(MORPHO).withdraw(
            marketParams,
            0, // assets = 0, withdrawing by shares
            shares,
            address(this),
            msg.sender
        );

        if (assetsWithdrawn == 0) revert WithdrawFailed();

        if (assetsWithdrawn <= totalDeposited) {
            totalDeposited -= assetsWithdrawn;
        } else {
            totalDeposited = 0;
        }

        amount = assetsWithdrawn;

        emit Withdrawn(msg.sender, assetsWithdrawn, shares);
    }

    /// @notice
    function harvest() external returns (uint256 harvested) {
        // Accrue interest first
        IMorpho(MORPHO).accrueInterest(marketParams);

        uint256 currentValue = totalAssets();

        if (currentValue > totalDeposited) {
            harvested = currentValue - totalDeposited;
            totalDeposited = currentValue;
            emit Harvested(harvested);
        }
    }

    /// @notice
    function totalAssets() public view returns (uint256) {
        IMorpho.Position memory pos = IMorpho(MORPHO).position(marketId, address(this));
        if (pos.supplyShares == 0) return 0;

        IMorpho.Market memory mkt = IMorpho(MORPHO).market(marketId);
        return _toAssets(pos.supplyShares, mkt.totalSupplyAssets, mkt.totalSupplyShares);
    }

    /// @notice
    function currentAPY() external view returns (uint256) {
        IMorpho.Market memory mkt = IMorpho(MORPHO).market(marketId);

        if (mkt.totalSupplyAssets == 0) return 0;

        // Get borrow rate from IRM
        uint256 borrowRate = IIrm(marketParams.irm).borrowRateView(marketParams, mkt);

        // Calculate utilization
        uint256 utilization = (uint256(mkt.totalBorrowAssets) * WAD) / uint256(mkt.totalSupplyAssets);

        // Calculate fee-adjusted supply rate
        // supplyRate = borrowRate * utilization * (1 - fee)
        uint256 fee = mkt.fee;
        uint256 supplyRate = (borrowRate * utilization * (WAD - fee)) / (WAD * WAD);

        // Annualize (rate is per second)
        // APY in basis points = rate * SECONDS_PER_YEAR * 10000 / WAD
        uint256 apy = (supplyRate * SECONDS_PER_YEAR * 10000) / WAD;

        return apy;
    }

    /// @notice
    function underlying() external view returns (address) {
        return address(loanToken);
    }

    /// @notice
    function yieldToken() external view returns (address) {
        return MORPHO; // No separate yield token, shares tracked in Morpho
    }

    /// @notice
    function isActive() external view returns (bool) {
        if (isPaused) return false;
        IMorpho.Position memory pos = IMorpho(MORPHO).position(marketId, address(this));
        return pos.supplyShares > 0;
    }

    /// @notice
    function name() external view returns (string memory) {
        return _name;
    }

    // =========================================================================
    // MORPHO-SPECIFIC FUNCTIONS
    // =========================================================================

    /// @notice Get current supply shares in the market
    function supplyShares() external view returns (uint256) {
        IMorpho.Position memory pos = IMorpho(MORPHO).position(marketId, address(this));
        return pos.supplyShares;
    }

    /// @notice Get market state
    function getMarket() external view returns (IMorpho.Market memory) {
        return IMorpho(MORPHO).market(marketId);
    }

    /// @notice Get market utilization rate
    function getUtilization() external view returns (uint256) {
        IMorpho.Market memory mkt = IMorpho(MORPHO).market(marketId);
        if (mkt.totalSupplyAssets == 0) return 0;
        return (uint256(mkt.totalBorrowAssets) * WAD) / uint256(mkt.totalSupplyAssets);
    }

    /// @notice Convert shares to assets using Morpho math
    function sharesToAssets(uint256 shares) external view returns (uint256) {
        IMorpho.Market memory mkt = IMorpho(MORPHO).market(marketId);
        return _toAssets(shares, mkt.totalSupplyAssets, mkt.totalSupplyShares);
    }

    /// @notice Convert assets to shares using Morpho math
    function assetsToShares(uint256 assets) external view returns (uint256) {
        IMorpho.Market memory mkt = IMorpho(MORPHO).market(marketId);
        return _toShares(assets, mkt.totalSupplyAssets, mkt.totalSupplyShares);
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
        IMorpho.Position memory pos = IMorpho(MORPHO).position(marketId, address(this));
        if (pos.supplyShares > 0) {
            (uint256 assets,) = IMorpho(MORPHO).withdraw(
                marketParams,
                0,
                pos.supplyShares,
                address(this),
                owner()
            );
            totalDeposited = 0;
            emit Withdrawn(owner(), assets, pos.supplyShares);
        }
    }

    /// @notice Rescue stuck tokens (not the strategy token)
    function rescueTokens(address token, uint256 amount) external onlyOwner {
        require(token != address(loanToken), "Cannot rescue loan token");
        IERC20(token).safeTransfer(owner(), amount);
    }

    // =========================================================================
    // INTERNAL FUNCTIONS
    // =========================================================================

    /// @notice Compute market ID from params
    /// @dev marketId = keccak256(abi.encode(marketParams))
    function _computeMarketId(IMorpho.MarketParams memory params) internal pure returns (bytes32) {
        return keccak256(abi.encode(params));
    }

    /// @notice Convert shares to assets (Morpho math with virtual amounts)
    function _toAssets(
        uint256 shares,
        uint256 totalAssetsMkt,
        uint256 totalSharesMkt
    ) internal pure returns (uint256) {
        return (shares * (totalAssetsMkt + VIRTUAL_ASSETS)) / (totalSharesMkt + VIRTUAL_SHARES);
    }

    /// @notice Convert assets to shares (Morpho math with virtual amounts)
    function _toShares(
        uint256 assets,
        uint256 totalAssetsMkt,
        uint256 totalSharesMkt
    ) internal pure returns (uint256) {
        return (assets * (totalSharesMkt + VIRTUAL_SHARES)) / (totalAssetsMkt + VIRTUAL_ASSETS);
    }
}

// =============================================================================
// METAMORPHO STRATEGY
// =============================================================================

/// @title MetaMorpho Strategy
/// @notice Yield strategy for MetaMorpho ERC4626 vaults
/// @dev MetaMorpho aggregates yield from multiple Morpho Blue markets
contract MetaMorphoStrategy is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // =========================================================================
    // CONSTANTS
    // =========================================================================

    /// @notice Seconds per year for APY calculation
    uint256 internal constant SECONDS_PER_YEAR = 365.25 days;

    /// @notice WAD precision (1e18)
    uint256 internal constant WAD = 1e18;

    /// @notice Morpho Blue address for market queries
    address public constant MORPHO = 0xBBBBBbbBBb9cC5e90e3b3Af64bdAF62C37EEFFCb;

    // =========================================================================
    // STATE
    // =========================================================================

    /// @notice MetaMorpho vault
    IMetaMorpho public immutable vault;

    /// @notice Underlying asset
    IERC20 public immutable underlyingAsset;

    /// @notice Controller address
    address public controller;

    /// @notice Shares held in MetaMorpho
    uint256 public vaultShares;

    /// @notice Total deposited for yield tracking
    uint256 public totalDeposited;

    /// @notice Whether strategy is paused
    bool public isPaused;

    /// @notice Strategy name
    string private _name;

    // =========================================================================
    // EVENTS
    // =========================================================================

    event Deposited(address indexed depositor, uint256 assets, uint256 shares);
    event Withdrawn(address indexed recipient, uint256 assets, uint256 shares);
    event Harvested(uint256 yield);
    event ControllerUpdated(address indexed oldController, address indexed newController);

    // =========================================================================
    // ERRORS
    // =========================================================================

    error StrategyPaused();
    error OnlyController();
    error InsufficientShares();
    error DepositFailed();
    error WithdrawFailed();
    error ZeroAmount();
    error InvalidVault();
    error ExceedsMaxDeposit();

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

    /// @notice Initialize MetaMorpho strategy
    /// @param _vault MetaMorpho vault address
    /// @param _controller Controller address
    /// @param strategyName Name for identification
    /// @param _owner Owner address
    constructor(
        address _vault,
        address _controller,
        string memory strategyName,
        address _owner
    ) Ownable(_owner) {
        if (_vault == address(0)) revert InvalidVault();

        vault = IMetaMorpho(_vault);
        underlyingAsset = IERC20(vault.asset());
        controller = _controller;
        _name = strategyName;

        // Approve vault to spend underlying
        underlyingAsset.approve(_vault, type(uint256).max);
    }

    // =========================================================================
    // YIELD STRATEGY INTERFACE
    // =========================================================================

    /// @notice
    function deposit(uint256 amount) external payable onlyController whenNotPaused nonReentrant returns (uint256 shares) {
        if (amount == 0) revert ZeroAmount();

        // Check max deposit
        uint256 maxDep = vault.maxDeposit(address(this));
        if (amount > maxDep) revert ExceedsMaxDeposit();

        // Transfer assets from controller
        underlyingAsset.safeTransferFrom(msg.sender, address(this), amount);

        // Deposit to MetaMorpho (ERC4626)
        shares = vault.deposit(amount, address(this));

        if (shares == 0) revert DepositFailed();

        vaultShares += shares;
        totalDeposited += amount;

        emit Deposited(msg.sender, amount, shares);
    }

    /// @notice
    function withdraw(uint256 shares) external onlyController nonReentrant returns (uint256 amount) {
        if (shares == 0) revert ZeroAmount();
        if (shares > vaultShares) revert InsufficientShares();

        // Redeem from MetaMorpho (ERC4626)
        uint256 assets = vault.redeem(shares, msg.sender, address(this));

        if (assets == 0) revert WithdrawFailed();

        vaultShares -= shares;
        if (assets <= totalDeposited) {
            totalDeposited -= assets;
        } else {
            totalDeposited = 0;
        }

        amount = assets;

        emit Withdrawn(msg.sender, assets, shares);
    }

    /// @notice
    function harvest() external returns (uint256 harvested) {
        uint256 currentValue = vault.convertToAssets(vaultShares);

        if (currentValue > totalDeposited) {
            harvested = currentValue - totalDeposited;
            totalDeposited = currentValue;
            emit Harvested(harvested);
        }
    }

    /// @notice
    function totalAssets() public view returns (uint256) {
        return vault.convertToAssets(vaultShares);
    }

    /// @notice
    function currentAPY() external view returns (uint256) {
        // Calculate weighted average APY across all markets in the vault
        uint256 totalAPY = 0;
        uint256 totalAllocation = 0;

        uint256 queueLen = vault.supplyQueueLength();

        for (uint256 i = 0; i < queueLen; i++) {
            bytes32 mktId = vault.supplyQueue(i);
            (uint184 cap, bool enabled,) = vault.config(mktId);

            if (!enabled || cap == 0) continue;

            // Get market data
            IMorpho.Market memory mkt = IMorpho(MORPHO).market(mktId);
            IMorpho.MarketParams memory params = IMorpho(MORPHO).idToMarketParams(mktId);

            if (mkt.totalSupplyAssets == 0) continue;

            // Calculate this market's supply APY
            uint256 borrowRate = IIrm(params.irm).borrowRateView(params, mkt);
            uint256 utilization = (uint256(mkt.totalBorrowAssets) * WAD) / uint256(mkt.totalSupplyAssets);
            uint256 supplyRate = (borrowRate * utilization * (WAD - mkt.fee)) / (WAD * WAD);

            // Weight by allocation (simplified: use cap as proxy)
            uint256 weight = uint256(cap);
            totalAPY += (supplyRate * weight);
            totalAllocation += weight;
        }

        if (totalAllocation == 0) return 0;

        // Annualize and convert to basis points
        uint256 weightedRate = totalAPY / totalAllocation;
        uint256 apy = (weightedRate * SECONDS_PER_YEAR * 10000) / WAD;

        // Subtract vault fee
        uint256 vaultFee = vault.fee();
        uint256 netAPY = (apy * (WAD - vaultFee)) / WAD;

        return netAPY;
    }

    /// @notice
    function underlying() external view returns (address) {
        return address(underlyingAsset);
    }

    /// @notice
    function yieldToken() external view returns (address) {
        return address(vault);
    }

    /// @notice
    function isActive() external view returns (bool) {
        return !isPaused && vaultShares > 0;
    }

    /// @notice
    function name() external view returns (string memory) {
        return _name;
    }

    // =========================================================================
    // METAMORPHO-SPECIFIC FUNCTIONS
    // =========================================================================

    /// @notice Get vault curator
    function getCurator() external view returns (address) {
        return vault.curator();
    }

    /// @notice Get vault performance fee
    function getVaultFee() external view returns (uint96) {
        return vault.fee();
    }

    /// @notice Get idle assets in vault
    function getIdleAssets() external view returns (uint256) {
        return vault.idle();
    }

    /// @notice Get number of markets in supply queue
    function getSupplyQueueLength() external view returns (uint256) {
        return vault.supplyQueueLength();
    }

    /// @notice Get market IDs in supply queue
    function getSupplyQueue() external view returns (bytes32[] memory) {
        uint256 len = vault.supplyQueueLength();
        bytes32[] memory queue = new bytes32[](len);
        for (uint256 i = 0; i < len; i++) {
            queue[i] = vault.supplyQueue(i);
        }
        return queue;
    }

    /// @notice Get market configuration
    function getMarketConfig(bytes32 mktId) external view returns (uint184 cap, bool enabled, uint64 removableAt) {
        return vault.config(mktId);
    }

    /// @notice Get max withdrawable amount
    function maxWithdrawable() external view returns (uint256) {
        return vault.maxRedeem(address(this));
    }

    /// @notice Preview deposit
    function previewDeposit(uint256 assets) external view returns (uint256) {
        return vault.previewDeposit(assets);
    }

    /// @notice Preview redeem
    function previewRedeem(uint256 shares) external view returns (uint256) {
        return vault.previewRedeem(shares);
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
        if (vaultShares > 0) {
            uint256 assets = vault.redeem(vaultShares, owner(), address(this));
            vaultShares = 0;
            totalDeposited = 0;
            emit Withdrawn(owner(), assets, 0);
        }
    }

    /// @notice Rescue stuck tokens (not the strategy tokens)
    function rescueTokens(address token, uint256 amount) external onlyOwner {
        require(token != address(underlyingAsset), "Cannot rescue underlying");
        require(token != address(vault), "Cannot rescue vault shares");
        IERC20(token).safeTransfer(owner(), amount);
    }
}

// =============================================================================
// FACTORY
// =============================================================================

/// @title Morpho Strategy Factory
/// @notice Factory for deploying Morpho yield strategies
contract MorphoStrategyFactory is Ownable {

    // =========================================================================
    // EVENTS
    // =========================================================================

    event MorphoBlueStrategyDeployed(
        address indexed strategy,
        bytes32 indexed mktId,
        string strategyName
    );

    event MetaMorphoStrategyDeployed(
        address indexed strategy,
        address indexed vaultAddr,
        string strategyName
    );

    // =========================================================================
    // CONSTRUCTOR
    // =========================================================================

    constructor() Ownable(msg.sender) {}

    // =========================================================================
    // DEPLOYMENT FUNCTIONS
    // =========================================================================

    /// @notice Deploy Morpho Blue strategy for a specific market
    /// @param morphoMarketParams Market parameters
    /// @param controller Controller address
    /// @param strategyName Strategy name
    function deployMorphoBlueStrategy(
        IMorpho.MarketParams memory morphoMarketParams,
        address controller,
        string calldata strategyName
    ) external onlyOwner returns (address) {
        MorphoBlueStrategy strategy = new MorphoBlueStrategy(
            morphoMarketParams,
            controller,
            strategyName,
            msg.sender
        );

        emit MorphoBlueStrategyDeployed(
            address(strategy),
            strategy.marketId(),
            strategyName
        );

        return address(strategy);
    }

    /// @notice Deploy MetaMorpho strategy for a vault
    /// @param metaMorphoVault MetaMorpho vault address
    /// @param controller Controller address
    /// @param strategyName Strategy name
    function deployMetaMorphoStrategy(
        address metaMorphoVault,
        address controller,
        string calldata strategyName
    ) external onlyOwner returns (address) {
        MetaMorphoStrategy strategy = new MetaMorphoStrategy(
            metaMorphoVault,
            controller,
            strategyName,
            msg.sender
        );

        emit MetaMorphoStrategyDeployed(
            address(strategy),
            metaMorphoVault,
            strategyName
        );

        return address(strategy);
    }
}

// =============================================================================
// POPULAR METAMORPHO VAULTS (MAINNET)
// =============================================================================

/// @title MetaMorpho USDC Strategy
/// @notice Strategy for Steakhouse USDC MetaMorpho vault
/// @dev Steakhouse USDC vault: 0xBEEF01735c132Ada46AA9aA4c54623cAA92A64CB
contract MetaMorphoUSDCStrategy is MetaMorphoStrategy {

    /// @notice Steakhouse USDC MetaMorpho vault (mainnet)
    address public constant STEAKHOUSE_USDC = 0xBEEF01735c132Ada46AA9aA4c54623cAA92A64CB;

    constructor(address _controller, address _owner)
        MetaMorphoStrategy(STEAKHOUSE_USDC, _controller, "MetaMorpho Steakhouse USDC", _owner)
    {}
}

/// @title MetaMorpho WETH Strategy
/// @notice Strategy for Steakhouse WETH MetaMorpho vault
/// @dev Steakhouse WETH vault: 0xBeEf020372F0bA93E43fB68E0F98edEc3f5e50d2
contract MetaMorphoWETHStrategy is MetaMorphoStrategy {

    /// @notice Steakhouse WETH MetaMorpho vault (mainnet)
    address public constant STEAKHOUSE_WETH = 0xBeEf020372F0bA93E43fB68E0F98edEc3f5e50d2;

    constructor(address _controller, address _owner)
        MetaMorphoStrategy(STEAKHOUSE_WETH, _controller, "MetaMorpho Steakhouse WETH", _owner)
    {}
}

/// @title MetaMorpho USDT Strategy
/// @notice Strategy for Flagship USDT MetaMorpho vault
/// @dev Flagship USDT vault: 0x8CB3649114051cA5119141a34C200D65dc0Faa73
contract MetaMorphoUSDTStrategy is MetaMorphoStrategy {

    /// @notice Flagship USDT MetaMorpho vault (mainnet)
    address public constant FLAGSHIP_USDT = 0x8CB3649114051cA5119141a34C200D65dc0Faa73;

    constructor(address _controller, address _owner)
        MetaMorphoStrategy(FLAGSHIP_USDT, _controller, "MetaMorpho Flagship USDT", _owner)
    {}
}
