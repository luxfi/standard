// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import "../IYieldStrategy.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/// @title Euler V2 Yield Strategies
/// @notice Yield strategies for Euler V2 modular lending protocol
/// @dev Euler V2 is a modular lending platform with:
///      - EVC (Ethereum Vault Connector) for cross-vault collateralization
///      - EVault: ERC4626-compliant lending vaults
///      - Isolated and cross-collateral modes
///      - Programmable risk management via governors
///      - Oracle-agnostic price feeds
///
/// Key Features:
/// - ERC4626 standard vaults (composable with other DeFi)
/// - Sub-accounts for position isolation
/// - Batch operations via EVC
/// - Customizable liquidation flows
///
/// Mainnet Addresses:
/// - EVC: 0x0C9a3dd6b8F28529d72d7f9cE918D493519EE383
/// - EVault Factory: 0x29a56a1b8214D9Cf7c5561811750D5cBDb45CC8e

// =============================================================================
// EULER V2 INTERFACES
// =============================================================================

/// @notice Ethereum Vault Connector - orchestrates cross-vault operations
interface IEVC {
    /// @notice Enables a vault as collateral for the account
    function enableCollateral(address account, address vault) external;
    
    /// @notice Disables a vault as collateral
    function disableCollateral(address account, address vault) external;
    
    /// @notice Enables a controller vault that can borrow against collateral
    function enableController(address account, address controller) external;
    
    /// @notice Disables a controller
    function disableController(address account) external;
    
    /// @notice Get the collaterals enabled for an account
    function getCollaterals(address account) external view returns (address[] memory);
    
    /// @notice Get the controller for an account
    function getControllers(address account) external view returns (address[] memory);
    
    /// @notice Check if collateral is enabled
    function isCollateralEnabled(address account, address vault) external view returns (bool);
    
    /// @notice Check if controller is enabled
    function isControllerEnabled(address account, address controller) external view returns (bool);
    
    /// @notice Execute batch operations
    function batch(BatchItem[] calldata items) external;
    
    /// @notice Call a target with EVC context
    function call(
        address targetContract,
        address onBehalfOfAccount,
        uint256 value,
        bytes calldata data
    ) external payable returns (bytes memory);
    
    /// @notice Get sub-account address
    function getSubAccountAddress(address primary, uint256 subAccountId) external pure returns (address);
    
    struct BatchItem {
        address targetContract;
        address onBehalfOfAccount;
        uint256 value;
        bytes data;
    }
}

/// @notice Euler V2 Vault (EVault) - ERC4626 compliant lending vault
interface IEVault {
    // ==========================================================================
    // ERC4626 STANDARD
    // ==========================================================================
    
    /// @notice Deposit assets and receive shares
    function deposit(uint256 assets, address receiver) external returns (uint256 shares);
    
    /// @notice Mint exact shares by depositing assets
    function mint(uint256 shares, address receiver) external returns (uint256 assets);
    
    /// @notice Withdraw assets by burning shares
    function withdraw(uint256 assets, address receiver, address owner) external returns (uint256 shares);
    
    /// @notice Redeem shares for assets
    function redeem(uint256 shares, address receiver, address owner) external returns (uint256 assets);
    
    /// @notice Total assets in the vault
    function totalAssets() external view returns (uint256);
    
    /// @notice Convert assets to shares
    function convertToShares(uint256 assets) external view returns (uint256);
    
    /// @notice Convert shares to assets
    function convertToAssets(uint256 shares) external view returns (uint256);
    
    /// @notice Preview deposit
    function previewDeposit(uint256 assets) external view returns (uint256);
    
    /// @notice Preview mint
    function previewMint(uint256 shares) external view returns (uint256);
    
    /// @notice Preview withdraw
    function previewWithdraw(uint256 assets) external view returns (uint256);
    
    /// @notice Preview redeem
    function previewRedeem(uint256 shares) external view returns (uint256);
    
    /// @notice Max deposit for receiver
    function maxDeposit(address receiver) external view returns (uint256);
    
    /// @notice Max mint for receiver
    function maxMint(address receiver) external view returns (uint256);
    
    /// @notice Max withdraw for owner
    function maxWithdraw(address owner) external view returns (uint256);
    
    /// @notice Max redeem for owner
    function maxRedeem(address owner) external view returns (uint256);
    
    /// @notice Get underlying asset
    function asset() external view returns (address);
    
    /// @notice Share balance
    function balanceOf(address account) external view returns (uint256);
    
    /// @notice Total supply of shares
    function totalSupply() external view returns (uint256);
    
    // ==========================================================================
    // EULER V2 SPECIFIC
    // ==========================================================================
    
    /// @notice Borrow assets from the vault
    function borrow(uint256 assets, address receiver) external returns (uint256 shares);
    
    /// @notice Repay borrowed assets
    function repay(uint256 assets, address receiver) external returns (uint256 shares);
    
    /// @notice Pull debt from another account (requires authorization)
    function pullDebt(uint256 assets, address from) external returns (uint256 shares);
    
    /// @notice Get debt owed by account
    function debtOf(address account) external view returns (uint256);
    
    /// @notice Get total borrows
    function totalBorrows() external view returns (uint256);
    
    /// @notice Get interest rate (per second, scaled by 1e27)
    function interestRate() external view returns (uint256);
    
    /// @notice Get supply APY (annualized, scaled by 1e27)
    function interestAccumulator() external view returns (uint256);
    
    /// @notice Get vault's EVC address
    function EVC() external view returns (address);
    
    /// @notice Get vault's oracle
    function oracle() external view returns (address);
    
    /// @notice Get vault's unit of account
    function unitOfAccount() external view returns (address);
    
    /// @notice Get vault governor
    function governorAdmin() external view returns (address);
    
    /// @notice Get LTV configuration for a collateral
    function LTVFull(address collateral) external view returns (
        uint16 borrowLTV,
        uint16 liquidationLTV,
        uint16 initialLiquidationLTV,
        uint48 targetTimestamp,
        uint32 rampDuration
    );
    
    /// @notice Check if vault is in operation
    function vaultStatus() external view returns (uint256);
    
    /// @notice Get account liquidity
    function accountLiquidity(address account, bool liquidation) external view returns (
        uint256 collateralValue,
        uint256 liabilityValue
    );
    
    /// @notice Check account health
    function checkAccountStatus(address account, address[] calldata collaterals) external view returns (bool);
    
    /// @notice Vault name
    function name() external view virtual returns (string memory);
    
    /// @notice Vault symbol
    function symbol() external view returns (string memory);
    
    /// @notice Decimals
    function decimals() external view returns (uint8);
}

/// @notice Euler V2 Oracle interface
interface IEulerOracle {
    /// @notice Get quote for amount of base in terms of quote asset
    function getQuote(uint256 amount, address base, address quote) external view returns (uint256);
    
    /// @notice Get quotes for multiple amounts
    function getQuotes(uint256[] calldata amounts, address base, address quote) external view returns (uint256[] memory);
}

/// @notice Interest Rate Model interface
interface IIRM {
    /// @notice Compute interest rate based on utilization
    function computeInterestRate(address vault, uint256 cash, uint256 borrows) external view returns (uint256);
    
    /// @notice Compute interest rate with full vault context
    function computeInterestRateView(address vault, uint256 cash, uint256 borrows) external view returns (uint256);
}

/// @notice Wrapped ETH interface
interface IWETH {
    function deposit() external payable;
    function withdraw(uint256 wad) external;
    function approve(address spender, uint256 amount) external returns (bool);
}

/// @notice Wrapped stETH interface
interface IWstETH {
    function wrap(uint256 stETHAmount) external returns (uint256);
    function unwrap(uint256 wstETHAmount) external returns (uint256);
    function getStETHByWstETH(uint256 wstETHAmount) external view returns (uint256);
    function getWstETHByStETH(uint256 stETHAmount) external view returns (uint256);
}

/// @notice EVault Factory for deploying new vaults
interface IEVaultFactory {
    /// @notice Create a new EVault
    function createProxy(address implementation, bool upgradeable, bytes memory trailingData) 
        external returns (address);
    
    /// @notice Get implementation for an asset
    function getImplementation(address asset) external view returns (address);
}

// =============================================================================
// EULER V2 BASE STRATEGY
// =============================================================================

/// @title Euler V2 Base Strategy
/// @notice Abstract base for Euler V2 yield strategies
/// @dev Implements common EVC and EVault integration logic
abstract contract EulerV2BaseStrategy is Ownable, ReentrancyGuard{
    using SafeERC20 for IERC20;

    // =========================================================================
    // CONSTANTS
    // =========================================================================

    /// @notice Ethereum Vault Connector (Mainnet)
    address public constant EVC = 0x0C9a3dd6b8F28529d72d7f9cE918D493519EE383;
    
    /// @notice EVault Factory (Mainnet)
    address public constant EVAULT_FACTORY = 0x29a56a1b8214D9Cf7c5561811750D5cBDb45CC8e;
    
    /// @notice Seconds per year for APY calculation
    uint256 internal constant SECONDS_PER_YEAR = 365.25 days;
    
    /// @notice RAY (1e27) for interest rate scaling
    uint256 internal constant RAY = 1e27;

    // =========================================================================
    // STATE
    // =========================================================================

    /// @notice EVault address
    IEVault public immutable vault;
    
    /// @notice Underlying asset
    IERC20 public immutable underlyingAsset;
    
    /// @notice Vault that controls this strategy
    address public controller;
    
    /// @notice Strategy shares held in EVault
    uint256 public vaultShares;
    
    /// @notice Total deposited (for yield tracking)
    uint256 public totalDeposited;
    
    /// @notice Whether strategy is paused
    bool public isPaused;
    
    /// @notice Sub-account ID for position isolation (0 = primary)
    uint256 public subAccountId;

    // =========================================================================
    // EVENTS
    // =========================================================================

    event Deposited(address indexed depositor, uint256 assets, uint256 shares);
    event Withdrawn(address indexed recipient, uint256 assets, uint256 shares);
    event Harvested(uint256 yield);
    event ControllerUpdated(address indexed oldController, address indexed newController);
    event SubAccountUpdated(uint256 indexed oldId, uint256 indexed newId);

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
        address _vault,
        address _controller,
        address _owner
    ) Ownable(_owner) {
        if (_vault == address(0)) revert InvalidVault();
        
        vault = IEVault(_vault);
        underlyingAsset = IERC20(vault.asset());
        controller = _controller;
        
        // Approve vault to spend underlying
        underlyingAsset.approve(_vault, type(uint256).max);
    }

    // =========================================================================
    // YIELD STRATEGY INTERFACE
    // =========================================================================

    /// @notice
    function deposit(uint256 amount) external onlyController whenNotPaused nonReentrant returns (uint256 shares) {
        if (amount == 0) revert ZeroAmount();
        
        // Transfer assets from controller
        underlyingAsset.safeTransferFrom(msg.sender, address(this), amount);
        
        // Deposit to EVault
        shares = vault.deposit(amount, address(this));
        
        vaultShares += shares;
        totalDeposited += amount;
        
        emit Deposited(msg.sender, amount, shares);
    }

    /// @notice
    function withdraw(uint256 shares) external onlyController nonReentrant returns (uint256 assets) {
        if (shares == 0) revert ZeroAmount();
        if (shares > vaultShares) revert InsufficientShares();
        
        // Redeem from EVault
        assets = vault.redeem(shares, msg.sender, address(this));
        
        vaultShares -= shares;
        if (assets <= totalDeposited) {
            totalDeposited -= assets;
        } else {
            totalDeposited = 0;
        }
        
        emit Withdrawn(msg.sender, assets, shares);
    }

    /// @notice
    function harvest() external returns (uint256 harvested) {
        uint256 currentValue = vault.convertToAssets(vaultShares);
        
        if (currentValue > totalDeposited) {
            harvested = currentValue - totalDeposited;
            // Update deposited to reflect harvested yield
            totalDeposited = currentValue;
            emit Harvested(harvested);
        }
    }

    /// @notice
    function totalAssets() external view returns (uint256) {
        return vault.convertToAssets(vaultShares);
    }

    /// @notice
    function currentAPY() external view returns (uint256) {
        // Get interest rate (per second, scaled by 1e27)
        uint256 ratePerSecond = vault.interestRate();
        
        if (ratePerSecond == 0) return 0;
        
        // Calculate utilization for supply APY
        uint256 totalSupply = vault.totalAssets();
        uint256 totalBorrows = vault.totalBorrows();
        
        if (totalSupply == 0) return 0;
        
        uint256 utilization = (totalBorrows * 1e18) / totalSupply;
        
        // Supply APY = Borrow rate * utilization
        // Annualize: rate * seconds_per_year
        uint256 borrowAPY = (ratePerSecond * SECONDS_PER_YEAR * 10000) / RAY;
        uint256 supplyAPY = (borrowAPY * utilization) / 1e18;
        
        return supplyAPY; // In basis points
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

    function asset() external view returns (address) {
        return address(underlyingAsset);
    }

    /// @notice
    function name() external view virtual returns (string memory);

    // =========================================================================
    // EVC INTEGRATION
    // =========================================================================

    /// @notice Get sub-account address for this strategy
    function getSubAccount() public view returns (address) {
        if (subAccountId == 0) return address(this);
        return IEVC(EVC).getSubAccountAddress(address(this), subAccountId);
    }

    /// @notice Enable this vault as collateral via EVC
    function enableAsCollateral(address collateralVault) external onlyOwner {
        IEVC(EVC).enableCollateral(getSubAccount(), collateralVault);
    }

    /// @notice Disable collateral
    function disableAsCollateral(address collateralVault) external onlyOwner {
        IEVC(EVC).disableCollateral(getSubAccount(), collateralVault);
    }

    /// @notice Execute batch operations via EVC
    function batchViaEVC(IEVC.BatchItem[] calldata items) external onlyOwner {
        IEVC(EVC).batch(items);
    }

    // =========================================================================
    // VIEW FUNCTIONS
    // =========================================================================

    /// @notice Get current utilization rate
    function getUtilization() external view returns (uint256) {
        uint256 totalSupply = vault.totalAssets();
        if (totalSupply == 0) return 0;
        return (vault.totalBorrows() * 1e18) / totalSupply;
    }

    /// @notice Get max withdrawable amount
    function maxWithdrawable() external view returns (uint256) {
        return vault.maxRedeem(address(this));
    }

    /// @notice Get vault health metrics
    function getVaultMetrics() external view returns (
        uint256 totalSupply,
        uint256 totalBorrows,
        uint256 interestRate,
        uint256 utilization
    ) {
        totalSupply = vault.totalAssets();
        totalBorrows = vault.totalBorrows();
        interestRate = vault.interestRate();
        utilization = totalSupply > 0 ? (totalBorrows * 1e18) / totalSupply : 0;
    }

    // =========================================================================
    // ADMIN FUNCTIONS
    // =========================================================================

    /// @notice Set controller address
    function setController(address _controller) external onlyOwner {
        emit ControllerUpdated(controller, _controller);
        controller = _controller;
    }

    /// @notice Set sub-account ID for position isolation
    function setSubAccountId(uint256 _subAccountId) external onlyOwner {
        emit SubAccountUpdated(subAccountId, _subAccountId);
        subAccountId = _subAccountId;
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
            emit Withdrawn(owner(), assets, vaultShares);
        }
    }

    /// @notice Rescue stuck tokens (not the strategy token)
    function rescueTokens(address token, uint256 amount) external onlyOwner {
        require(token != address(underlyingAsset), "Cannot rescue underlying");
        require(token != address(vault), "Cannot rescue vault shares");
        IERC20(token).safeTransfer(owner(), amount);
    }
}

// =============================================================================
// CONCRETE IMPLEMENTATIONS
// =============================================================================

/// @title Euler V2 USDC Strategy
/// @notice Supplies USDC to Euler V2 for yield
/// @dev Uses the primary USDC EVault on mainnet
contract EulerV2USDCStrategy is EulerV2BaseStrategy {
    
    /// @notice USDC address (Ethereum mainnet)
    address public constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    
    /// @notice Euler V2 USDC EVault (mainnet)
    /// @dev This is the primary USDC lending vault
    address public constant USDC_EVAULT = 0x797DD80692c3b2dAdabCe8e30C07fDE5307D48a9;

    constructor(address _controller, address _owner)
        EulerV2BaseStrategy(USDC_EVAULT, _controller, _owner)
    {}

    /// @notice
    function name() external pure override returns (string memory) {
        return "Euler V2 USDC";
    }
}

/// @title Euler V2 WETH Strategy
/// @notice Supplies WETH to Euler V2 for yield
contract EulerV2WETHStrategy is EulerV2BaseStrategy {
    
    /// @notice WETH address (Ethereum mainnet)
    address public constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    
    /// @notice Euler V2 WETH EVault (mainnet)
    address public constant WETH_EVAULT = 0xD8b27CF359b7D15710a5BE299AF6e7Bf904984C2;

    constructor(address _controller, address _owner)
        EulerV2BaseStrategy(WETH_EVAULT, _controller, _owner)
    {}

    /// @notice
    function name() external pure override returns (string memory) {
        return "Euler V2 WETH";
    }

    /// @notice Deposit native ETH (wraps to WETH first)
    function depositETH() external payable onlyController whenNotPaused nonReentrant returns (uint256 shares) {
        if (msg.value == 0) revert ZeroAmount();
        
        // Wrap ETH to WETH
        IWETH(WETH).deposit{value: msg.value}();
        
        // Deposit to EVault
        shares = vault.deposit(msg.value, address(this));
        
        vaultShares += shares;
        totalDeposited += msg.value;
        
        emit Deposited(msg.sender, msg.value, shares);
    }

    /// @notice Withdraw as native ETH
    function withdrawETH(uint256 shares) external onlyController nonReentrant returns (uint256 assets) {
        if (shares == 0) revert ZeroAmount();
        if (shares > vaultShares) revert InsufficientShares();
        
        // Redeem from EVault
        assets = vault.redeem(shares, address(this), address(this));
        
        // Unwrap WETH to ETH
        IWETH(WETH).withdraw(assets);
        
        // Send ETH to controller
        (bool success, ) = msg.sender.call{value: assets}("");
        require(success, "ETH transfer failed");
        
        vaultShares -= shares;
        if (assets <= totalDeposited) {
            totalDeposited -= assets;
        } else {
            totalDeposited = 0;
        }
        
        emit Withdrawn(msg.sender, assets, shares);
    }

    receive() external payable {}
}

/// @title Euler V2 wstETH Strategy
/// @notice Supplies wstETH to Euler V2 for yield
/// @dev wstETH earns staking yield + lending yield (double dip)
contract EulerV2WstETHStrategy is EulerV2BaseStrategy {
    using SafeERC20 for IERC20;
    
    /// @notice wstETH address (Ethereum mainnet)
    address public constant WSTETH = 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0;
    
    /// @notice Euler V2 wstETH EVault (mainnet)
    address public constant WSTETH_EVAULT = 0xbC4B4AC47582c3E38Ce5940B80Da65401F4628f1;
    
    /// @notice stETH address for wrapping
    address public constant STETH = 0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84;

    constructor(address _controller, address _owner)
        EulerV2BaseStrategy(WSTETH_EVAULT, _controller, _owner)
    {}

    /// @notice
    function name() external pure override returns (string memory) {
        return "Euler V2 wstETH";
    }

    /// @notice Get combined APY (staking + lending)
    function combinedAPY() external view returns (uint256 stakingAPY, uint256 lendingAPY, uint256 total) {
        // Lido staking APY is roughly 3-4%
        stakingAPY = 350; // ~3.5% in basis points
        
        // Get lending APY from vault
        lendingAPY = this.currentAPY();
        
        total = stakingAPY + lendingAPY;
    }

    /// @notice Deposit stETH (wraps to wstETH first)
    function depositStETH(uint256 stETHAmount) external onlyController whenNotPaused nonReentrant returns (uint256 shares) {
        if (stETHAmount == 0) revert ZeroAmount();
        
        // Transfer stETH
        IERC20(STETH).safeTransferFrom(msg.sender, address(this), stETHAmount);
        
        // Approve and wrap to wstETH
        IERC20(STETH).approve(WSTETH, stETHAmount);
        uint256 wstETHAmount = IWstETH(WSTETH).wrap(stETHAmount);
        
        // Deposit to EVault
        shares = vault.deposit(wstETHAmount, address(this));
        
        vaultShares += shares;
        totalDeposited += wstETHAmount;
        
        emit Deposited(msg.sender, wstETHAmount, shares);
    }
}

/// @title Euler V2 DAI Strategy
/// @notice Supplies DAI to Euler V2 for yield
contract EulerV2DAIStrategy is EulerV2BaseStrategy {
    
    /// @notice DAI address (Ethereum mainnet)
    address public constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    
    /// @notice Euler V2 DAI EVault (mainnet)
    address public constant DAI_EVAULT = 0x61E50b9c39735d3C89F93B97e593a8fFF31A16c2;

    constructor(address _controller, address _owner)
        EulerV2BaseStrategy(DAI_EVAULT, _controller, _owner)
    {}

    /// @notice
    function name() external pure override returns (string memory) {
        return "Euler V2 DAI";
    }
}

/// @title Euler V2 USDT Strategy
/// @notice Supplies USDT to Euler V2 for yield
contract EulerV2USDTStrategy is EulerV2BaseStrategy {
    
    /// @notice USDT address (Ethereum mainnet)
    address public constant USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    
    /// @notice Euler V2 USDT EVault (mainnet)
    address public constant USDT_EVAULT = 0x313603FA690301b0CaeEf8069c065862f9162162;

    constructor(address _controller, address _owner)
        EulerV2BaseStrategy(USDT_EVAULT, _controller, _owner)
    {}

    /// @notice
    function name() external pure override returns (string memory) {
        return "Euler V2 USDT";
    }
}

// =============================================================================
// LEVERAGED STRATEGY
// =============================================================================

/// @title Euler V2 Leveraged Strategy
/// @notice Leveraged yield strategy using EVC cross-collateralization
/// @dev Deposits collateral, borrows against it, and re-deposits for leverage
contract EulerV2LeveragedStrategy is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // =========================================================================
    // CONSTANTS
    // =========================================================================

    address public constant EVC = 0x0C9a3dd6b8F28529d72d7f9cE918D493519EE383;
    uint256 internal constant MAX_LEVERAGE = 5e18; // 5x max
    uint256 internal constant PRECISION = 1e18;

    // =========================================================================
    // STATE
    // =========================================================================

    /// @notice Collateral vault
    IEVault public immutable collateralVault;
    
    /// @notice Borrow vault
    IEVault public immutable borrowVault;
    
    /// @notice Collateral asset
    IERC20 public immutable collateralAsset;
    
    /// @notice Borrow asset
    IERC20 public immutable borrowAsset;
    
    /// @notice Controller address
    address public controller;
    
    /// @notice Target leverage (1e18 = 1x, 2e18 = 2x)
    uint256 public targetLeverage;
    
    /// @notice Total collateral deposited
    uint256 public totalCollateral;
    
    /// @notice Total borrowed
    uint256 public totalBorrowed;
    
    /// @notice Is paused
    bool public isPaused;

    // =========================================================================
    // EVENTS
    // =========================================================================

    event LeverageAdjusted(uint256 oldLeverage, uint256 newLeverage);
    event PositionOpened(uint256 collateral, uint256 borrowed, uint256 leverage);
    event PositionClosed(uint256 collateralReturned);

    // =========================================================================
    // ERRORS
    // =========================================================================

    error ExceedsMaxLeverage();
    error StrategyPaused();
    error OnlyController();
    error InsufficientCollateral();

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
        address _collateralVault,
        address _borrowVault,
        address _controller,
        uint256 _targetLeverage,
        address _owner
    ) Ownable(_owner) {
        if (_targetLeverage > MAX_LEVERAGE) revert ExceedsMaxLeverage();
        
        collateralVault = IEVault(_collateralVault);
        borrowVault = IEVault(_borrowVault);
        collateralAsset = IERC20(collateralVault.asset());
        borrowAsset = IERC20(borrowVault.asset());
        controller = _controller;
        targetLeverage = _targetLeverage;
        
        // Approvals
        collateralAsset.approve(_collateralVault, type(uint256).max);
        borrowAsset.approve(_borrowVault, type(uint256).max);
    }

    // =========================================================================
    // CORE FUNCTIONS
    // =========================================================================

    /// @notice Open leveraged position
    /// @param collateralAmount Initial collateral to deposit
    function openPosition(uint256 collateralAmount) external onlyController whenNotPaused nonReentrant {
        // Transfer collateral
        collateralAsset.safeTransferFrom(msg.sender, address(this), collateralAmount);
        
        // Enable collateral via EVC
        IEVC(EVC).enableCollateral(address(this), address(collateralVault));
        IEVC(EVC).enableController(address(this), address(borrowVault));
        
        // Deposit collateral
        collateralVault.deposit(collateralAmount, address(this));
        
        // Calculate borrow amount for target leverage
        // leverage = totalPosition / collateral
        // totalPosition = collateral * leverage
        // borrowed = totalPosition - collateral = collateral * (leverage - 1)
        uint256 borrowAmount = (collateralAmount * (targetLeverage - PRECISION)) / PRECISION;
        
        // Borrow from vault
        borrowVault.borrow(borrowAmount, address(this));
        
        // If borrow asset == collateral asset, re-deposit for more leverage
        if (address(borrowAsset) == address(collateralAsset)) {
            collateralVault.deposit(borrowAmount, address(this));
        }
        
        totalCollateral = collateralAmount;
        totalBorrowed = borrowAmount;
        
        emit PositionOpened(collateralAmount, borrowAmount, targetLeverage);
    }

    /// @notice Close leveraged position
    function closePosition() external onlyController nonReentrant returns (uint256 returned) {
        // Repay all debt
        if (totalBorrowed > 0) {
            // If we re-deposited borrowed assets, withdraw them first
            if (address(borrowAsset) == address(collateralAsset)) {
                uint256 totalInVault = collateralVault.convertToAssets(
                    collateralVault.balanceOf(address(this))
                );
                uint256 toWithdraw = totalInVault - totalCollateral;
                collateralVault.withdraw(toWithdraw, address(this), address(this));
            }
            
            borrowVault.repay(totalBorrowed, address(this));
        }
        
        // Withdraw all collateral
        uint256 shares = collateralVault.balanceOf(address(this));
        returned = collateralVault.redeem(shares, msg.sender, address(this));
        
        // Disable controller
        IEVC(EVC).disableController(address(this));
        
        totalCollateral = 0;
        totalBorrowed = 0;
        
        emit PositionClosed(returned);
    }

    /// @notice Adjust target leverage
    function setTargetLeverage(uint256 _targetLeverage) external onlyOwner {
        if (_targetLeverage > MAX_LEVERAGE) revert ExceedsMaxLeverage();
        emit LeverageAdjusted(targetLeverage, _targetLeverage);
        targetLeverage = _targetLeverage;
    }

    /// @notice Get current position health
    function getPositionHealth() external view returns (
        uint256 collateralValue,
        uint256 debtValue,
        uint256 healthFactor
    ) {
        (collateralValue, debtValue) = borrowVault.accountLiquidity(address(this), false);
        
        if (debtValue == 0) {
            healthFactor = type(uint256).max;
        } else {
            healthFactor = (collateralValue * PRECISION) / debtValue;
        }
    }

    /// @notice Get effective APY (considering leverage and borrow cost)
    function effectiveAPY() external view returns (int256) {
        // This is simplified - real calculation needs oracle prices
        uint256 supplyAPY = collateralVault.interestRate() * 365 days * 10000 / 1e27;
        uint256 borrowAPY = borrowVault.interestRate() * 365 days * 10000 / 1e27;
        
        // Net APY = supply_apy * leverage - borrow_apy * (leverage - 1)
        int256 netAPY = int256(supplyAPY * targetLeverage / PRECISION) - 
                        int256(borrowAPY * (targetLeverage - PRECISION) / PRECISION);
        
        return netAPY;
    }

    // =========================================================================
    // ADMIN
    // =========================================================================

    function setController(address _controller) external onlyOwner {
        controller = _controller;
    }

    function setPaused(bool _paused) external onlyOwner {
        isPaused = _paused;
    }

    function emergencyRepay() external onlyOwner {
        uint256 debt = borrowVault.debtOf(address(this));
        if (debt > 0) {
            uint256 balance = borrowAsset.balanceOf(address(this));
            if (balance >= debt) {
                borrowVault.repay(debt, address(this));
            }
        }
    }
}

// =============================================================================
// FACTORY
// =============================================================================

/// @title Euler V2 Strategy Factory
/// @notice Factory for deploying Euler V2 yield strategies
contract EulerV2StrategyFactory is Ownable {
    
    // =========================================================================
    // EVENTS
    // =========================================================================

    event StrategyDeployed(
        address indexed strategy,
        address indexed vault,
        string strategyType
    );

    // =========================================================================
    // DEPLOYMENT FUNCTIONS
    // =========================================================================

    constructor() Ownable(msg.sender) {}

    /// @notice Deploy USDC strategy
    function deployUSDCStrategy(address controller) external onlyOwner returns (address) {
        EulerV2USDCStrategy strategy = new EulerV2USDCStrategy(controller, msg.sender);
        emit StrategyDeployed(address(strategy), address(strategy.vault()), "USDC");
        return address(strategy);
    }

    /// @notice Deploy WETH strategy
    function deployWETHStrategy(address controller) external onlyOwner returns (address) {
        EulerV2WETHStrategy strategy = new EulerV2WETHStrategy(controller, msg.sender);
        emit StrategyDeployed(address(strategy), address(strategy.vault()), "WETH");
        return address(strategy);
    }

    /// @notice Deploy wstETH strategy
    function deployWstETHStrategy(address controller) external onlyOwner returns (address) {
        EulerV2WstETHStrategy strategy = new EulerV2WstETHStrategy(controller, msg.sender);
        emit StrategyDeployed(address(strategy), address(strategy.vault()), "wstETH");
        return address(strategy);
    }

    /// @notice Deploy DAI strategy
    function deployDAIStrategy(address controller) external onlyOwner returns (address) {
        EulerV2DAIStrategy strategy = new EulerV2DAIStrategy(controller, msg.sender);
        emit StrategyDeployed(address(strategy), address(strategy.vault()), "DAI");
        return address(strategy);
    }

    /// @notice Deploy USDT strategy
    function deployUSDTStrategy(address controller) external onlyOwner returns (address) {
        EulerV2USDTStrategy strategy = new EulerV2USDTStrategy(controller, msg.sender);
        emit StrategyDeployed(address(strategy), address(strategy.vault()), "USDT");
        return address(strategy);
    }

    /// @notice Deploy custom vault strategy
    function deployCustomStrategy(
        address vault,
        address controller,
        string calldata strategyName
    ) external onlyOwner returns (address) {
        CustomEulerV2Strategy strategy = new CustomEulerV2Strategy(
            vault,
            controller,
            strategyName,
            msg.sender
        );
        emit StrategyDeployed(address(strategy), vault, strategyName);
        return address(strategy);
    }

    /// @notice Deploy leveraged strategy
    function deployLeveragedStrategy(
        address collateralVault,
        address borrowVault,
        address controller,
        uint256 targetLeverage
    ) external onlyOwner returns (address) {
        EulerV2LeveragedStrategy strategy = new EulerV2LeveragedStrategy(
            collateralVault,
            borrowVault,
            controller,
            targetLeverage,
            msg.sender
        );
        emit StrategyDeployed(address(strategy), collateralVault, "Leveraged");
        return address(strategy);
    }
}

/// @title Custom Euler V2 Strategy
/// @notice Generic strategy for any Euler V2 vault
contract CustomEulerV2Strategy is EulerV2BaseStrategy {
    
    string private _name;

    constructor(
        address _vault,
        address _controller,
        string memory strategyName,
        address _owner
    ) EulerV2BaseStrategy(_vault, _controller, _owner) {
        _name = strategyName;
    }

    /// @notice
    function name() external view virtual override returns (string memory) {
        return _name;
    }
}
