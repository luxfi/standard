// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import "../IYieldStrategy.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/// @title Perpetual DEX Yield Strategies
/// @notice High-yield strategies from perpetual futures liquidity provision
/// @dev Includes GMX V2 (GM tokens), Hyperliquid HLP, Vertex, Gains Network
///      These protocols generate yield from trading fees + funding rates
///      Typical APY: 20-80% depending on market conditions

// ═══════════════════════════════════════════════════════════════════════════════
// GMX V2 INTERFACES (Arbitrum)
// ═══════════════════════════════════════════════════════════════════════════════

interface IGMXExchangeRouter {
    struct CreateDepositParams {
        address receiver;
        address callbackContract;
        address uiFeeReceiver;
        address market;
        address initialLongToken;
        address initialShortToken;
        address[] longTokenSwapPath;
        address[] shortTokenSwapPath;
        uint256 minMarketTokens;
        bool shouldUnwrapNativeToken;
        uint256 executionFee;
        uint256 callbackGasLimit;
    }

    struct CreateWithdrawalParams {
        address receiver;
        address callbackContract;
        address uiFeeReceiver;
        address market;
        address[] longTokenSwapPath;
        address[] shortTokenSwapPath;
        uint256 minLongTokenAmount;
        uint256 minShortTokenAmount;
        bool shouldUnwrapNativeToken;
        uint256 executionFee;
        uint256 callbackGasLimit;
    }

    function createDeposit(CreateDepositParams calldata params) external payable returns (bytes32);
    function createWithdrawal(CreateWithdrawalParams calldata params) external payable returns (bytes32);
    function sendWnt(address receiver, uint256 amount) external payable;
    function sendTokens(address token, address receiver, uint256 amount) external;
}

interface IGMXReader {
    function getMarketTokenPrice(
        address dataStore,
        MarketProps memory market,
        PriceProps memory indexTokenPrice,
        PriceProps memory longTokenPrice,
        PriceProps memory shortTokenPrice,
        bytes32 pnlFactorType,
        bool maximize
    ) external view returns (int256, MarketPoolValueInfoProps memory);

    function getMarket(address dataStore, address market) external view returns (MarketProps memory);
}

struct MarketProps {
    address marketToken;
    address indexToken;
    address longToken;
    address shortToken;
}

struct PriceProps {
    uint256 min;
    uint256 max;
}

struct MarketPoolValueInfoProps {
    int256 poolValue;
    int256 longPnl;
    int256 shortPnl;
    int256 netPnl;
    uint256 longTokenAmount;
    uint256 shortTokenAmount;
    uint256 longTokenUsd;
    uint256 shortTokenUsd;
    uint256 totalBorrowingFees;
    uint256 borrowingFeePoolFactor;
    uint256 impactPoolAmount;
}

interface IGMXDepositVault {
    function recordTransferIn(address token) external returns (uint256);
}

// ═══════════════════════════════════════════════════════════════════════════════
// HYPERLIQUID INTERFACES
// ═══════════════════════════════════════════════════════════════════════════════

interface IHyperliquidVault {
    /// @notice Deposit USDC into HLP vault
    function deposit(uint256 amount) external returns (uint256 shares);
    
    /// @notice Withdraw from HLP vault
    function withdraw(uint256 shares) external returns (uint256 amount);
    
    /// @notice Get total HLP supply
    function totalSupply() external view returns (uint256);
    
    /// @notice Get HLP balance
    function balanceOf(address account) external view returns (uint256);
    
    /// @notice Get underlying assets value
    function totalAssets() external view returns (uint256);
    
    /// @notice Get pending rewards
    function pendingRewards(address account) external view returns (uint256);
    
    /// @notice Claim rewards
    function claimRewards() external returns (uint256);
}

interface IHyperliquidBridge {
    /// @notice Bridge USDC from L1 to Hyperliquid L1
    function deposit(address token, uint256 amount, address recipient) external;
    
    /// @notice Initiate withdrawal from Hyperliquid to L1
    function initiateWithdrawal(address token, uint256 amount) external returns (bytes32);
}

// ═══════════════════════════════════════════════════════════════════════════════
// VERTEX PROTOCOL INTERFACES
// ═══════════════════════════════════════════════════════════════════════════════

interface IVertexEndpoint {
    struct DepositCollateral {
        bytes32 sender;
        uint32 productId;
        uint128 amount;
    }

    function depositCollateral(DepositCollateral calldata txn, bytes calldata signature) external;
    function withdrawCollateral(bytes32 sender, uint32 productId, uint128 amount, uint64 nonce) external;
}

interface IVertexClearinghouse {
    function getHealth(bytes32 subaccount, uint32 healthType) external view returns (int128);
    function getSpotBalance(bytes32 subaccount, uint32 productId) external view returns (int128);
}

interface IVertexStaking {
    /// @notice Stake VRTX tokens
    function stake(uint256 amount) external;
    
    /// @notice Unstake VRTX tokens
    function unstake(uint256 amount) external;
    
    /// @notice Claim staking rewards
    function claimRewards() external returns (uint256);
    
    /// @notice Get pending rewards
    function pendingRewards(address account) external view returns (uint256);
    
    /// @notice Get staked balance
    function stakedBalance(address account) external view returns (uint256);
}

// ═══════════════════════════════════════════════════════════════════════════════
// GAINS NETWORK INTERFACES (Polygon/Arbitrum)
// ═══════════════════════════════════════════════════════════════════════════════

interface IGainsVault {
    /// @notice Deposit DAI to receive gDAI
    function deposit(uint256 assets, address receiver) external returns (uint256 shares);
    
    /// @notice Redeem gDAI for DAI
    function redeem(uint256 shares, address receiver, address owner) external returns (uint256 assets);
    
    /// @notice Get current share price
    function shareToAssetsPrice() external view returns (uint256);
    
    /// @notice Get total assets in vault
    function totalAssets() external view returns (uint256);
    
    /// @notice Get gDAI balance
    function balanceOf(address account) external view returns (uint256);
    
    /// @notice Convert assets to shares
    function convertToShares(uint256 assets) external view returns (uint256);
    
    /// @notice Convert shares to assets
    function convertToAssets(uint256 shares) external view returns (uint256);
    
    /// @notice Get current utilization
    function currentEpochPositiveOpenPnl() external view returns (uint256);
    
    /// @notice Maximum deposit amount
    function maxDeposit(address) external view returns (uint256);
    
    /// @notice Get withdraw lock duration
    function withdrawLockDuration() external view returns (uint256);
}

interface IGainsStaking {
    /// @notice Stake GNS tokens
    function stake(uint256 amount) external;
    
    /// @notice Unstake GNS tokens
    function unstake(uint256 amount) external;
    
    /// @notice Harvest pending DAI rewards
    function harvest() external returns (uint256);
    
    /// @notice Get pending rewards
    function pendingRewardsDai(address staker) external view returns (uint256);
    
    /// @notice Get staked GNS balance
    function stakedGns(address staker) external view returns (uint256);
}

// ═══════════════════════════════════════════════════════════════════════════════
// BASE PERPS STRATEGY
// ═══════════════════════════════════════════════════════════════════════════════

/// @title Base Perpetuals Strategy
/// @notice Common functionality for perps LP strategies
abstract contract BasePerpsStrategy is Ownable, ReentrancyGuard{
    using SafeERC20 for IERC20;

    string public name;
    string public constant protocol = "Perps";
    string public constant version = "1.0.0";

    IERC20 public immutable underlyingAsset;
    uint256 public totalDeposited;
    uint256 public lastHarvest;
    bool public isPaused;

    /// @notice Accumulated yield for tracking
    uint256 public accumulatedYield;

    event Deposited(address indexed user, uint256 amount, uint256 shares);
    event Withdrawn(address indexed user, uint256 amount, uint256 shares);
    event Harvested(uint256 yield);
    event Paused(bool status);

    modifier whenNotPaused() {
        require(!isPaused, "Strategy paused");
        _;
    }

    constructor(
        string memory _name,
        address _underlyingAsset,
        address _owner
    ) Ownable(_owner) {
        name = _name;
        underlyingAsset = IERC20(_underlyingAsset);
        lastHarvest = block.timestamp;
    }

    function asset() external view returns (address) {
        return address(underlyingAsset);
    }

    function isActive() external view returns (bool) {
        return !isPaused && totalDeposited > 0;
    }

    function setPaused(bool _paused) external onlyOwner {
        isPaused = _paused;
        emit Paused(_paused);
    }

    /// @notice Emergency withdraw all funds
    function emergencyWithdraw(address recipient) external virtual onlyOwner {
        // To be overridden by concrete implementations
        revert("Not implemented");
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// GMX V2 STRATEGY (Arbitrum)
// ═══════════════════════════════════════════════════════════════════════════════

/// @title GMX V2 GM Token Strategy
/// @notice Provides liquidity to GMX V2 markets for GM tokens
/// @dev GM tokens earn trading fees + price impact fees
///      Typical APY: 20-50% on major markets (ETH-USD, BTC-USD)
///      Risk: Exposed to trader PnL (vault is counterparty)
contract GMXV2Strategy is BasePerpsStrategy {
    using SafeERC20 for IERC20;

    // GMX V2 Arbitrum Addresses
    address public constant EXCHANGE_ROUTER = 0x7C68C7866A64FA2160F78EEaE12217FFbf871fa8;
    address public constant DEPOSIT_VAULT = 0xF89e77e8Dc11691C9e8757e84aaFbCD8A67d7A55;
    address public constant READER = 0xf60becbba223EEA9495Da3f606753867eC10d139;
    address public constant DATA_STORE = 0xFD70de6b91282D8017aA4E741e9Ae325CAb992d8;
    
    // Wrapped ETH on Arbitrum
    address public constant WETH = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;
    address public constant USDC = 0xaf88d065e77c8cC2239327C5EDb3A432268e5831;

    /// @notice GM market token address
    address public immutable gmToken;

    /// @notice Market configuration
    MarketProps public market;

    /// @notice GM token balance
    uint256 public gmBalance;

    /// @notice Minimum execution fee for deposits/withdrawals
    uint256 public minExecutionFee = 0.001 ether;

    /// @notice Pending deposit keys
    mapping(bytes32 => uint256) public pendingDeposits;

    /// @notice Pending withdrawal keys
    mapping(bytes32 => uint256) public pendingWithdrawals;

    event DepositCreated(bytes32 indexed key, uint256 amount);
    event WithdrawalCreated(bytes32 indexed key, uint256 shares);
    event GMReceived(uint256 amount);

    constructor(
        string memory _name,
        address _gmToken,
        address _underlyingAsset,
        address _owner
    ) BasePerpsStrategy(_name, _underlyingAsset, _owner) {
        gmToken = _gmToken;
        
        // Approve exchange router
        IERC20(_underlyingAsset).approve(EXCHANGE_ROUTER, type(uint256).max);
        IERC20(_underlyingAsset).approve(DEPOSIT_VAULT, type(uint256).max);
    }

    function deposit(uint256 amount)
        external
        nonReentrant
        whenNotPaused
        returns (uint256 shares)
    {
        underlyingAsset.safeTransferFrom(msg.sender, address(this), amount);

        // Send tokens to deposit vault
        IGMXDepositVault(DEPOSIT_VAULT).recordTransferIn(address(underlyingAsset));

        // Create deposit params
        address[] memory emptyPath = new address[](0);
        IGMXExchangeRouter.CreateDepositParams memory params = IGMXExchangeRouter.CreateDepositParams({
            receiver: address(this),
            callbackContract: address(0),
            uiFeeReceiver: address(0),
            market: gmToken,
            initialLongToken: address(underlyingAsset),
            initialShortToken: address(0),
            longTokenSwapPath: emptyPath,
            shortTokenSwapPath: emptyPath,
            minMarketTokens: 0,
            shouldUnwrapNativeToken: false,
            executionFee: minExecutionFee,
            callbackGasLimit: 0
        });

        // Create deposit (async - GM tokens arrive via callback)
        bytes32 key = IGMXExchangeRouter(EXCHANGE_ROUTER).createDeposit{value: minExecutionFee}(params);
        
        pendingDeposits[key] = amount;
        totalDeposited += amount;
        shares = amount; // 1:1 initially, actual shares arrive async

        emit DepositCreated(key, amount);
        emit Deposited(msg.sender, amount, shares);
    }

    function withdraw(uint256 shares)
        external
        nonReentrant
        returns (uint256 assets)
    {
        require(gmBalance >= shares, "Insufficient GM balance");

        // Create withdrawal params
        address[] memory emptyPath = new address[](0);
        IGMXExchangeRouter.CreateWithdrawalParams memory params = IGMXExchangeRouter.CreateWithdrawalParams({
            receiver: msg.sender,
            callbackContract: address(0),
            uiFeeReceiver: address(0),
            market: gmToken,
            longTokenSwapPath: emptyPath,
            shortTokenSwapPath: emptyPath,
            minLongTokenAmount: 0,
            minShortTokenAmount: 0,
            shouldUnwrapNativeToken: false,
            executionFee: minExecutionFee,
            callbackGasLimit: 0
        });

        // Send GM tokens to exchange router
        IERC20(gmToken).safeTransfer(EXCHANGE_ROUTER, shares);

        bytes32 key = IGMXExchangeRouter(EXCHANGE_ROUTER).createWithdrawal{value: minExecutionFee}(params);
        
        pendingWithdrawals[key] = shares;
        gmBalance -= shares;
        
        // Estimate assets based on current GM price
        assets = _estimateGMValue(shares);
        if (assets <= totalDeposited) {
            totalDeposited -= assets;
        } else {
            totalDeposited = 0;
        }

        emit WithdrawalCreated(key, shares);
        emit Withdrawn(msg.sender, assets, shares);
    }

    function harvest() external nonReentrant returns (uint256 yield) {
        // GM tokens automatically compound - yield is embedded in token price
        uint256 currentValue = _estimateGMValue(gmBalance);
        
        if (currentValue > totalDeposited) {
            yield = currentValue - totalDeposited;
            accumulatedYield += yield;
        }
        
        lastHarvest = block.timestamp;
        emit Harvested(yield);
    }

    function totalAssets() external view returns (uint256) {
        return _estimateGMValue(gmBalance) + accumulatedYield;
    }

    function currentAPY() external pure returns (uint256) {
        // GMX V2 typically yields 20-50% APY
        return 3000; // 30% baseline
    }

    /// @notice Called when GM tokens are received from deposits
    function onGMReceived(uint256 amount) external {
        require(msg.sender == EXCHANGE_ROUTER || msg.sender == gmToken, "Unauthorized");
        gmBalance += amount;
        emit GMReceived(amount);
    }

    /// @notice Estimate GM token value in underlying
    function _estimateGMValue(uint256 gmAmount) internal view returns (uint256) {
        if (gmAmount == 0) return 0;
        
        // Simplified - in production use Reader.getMarketTokenPrice()
        uint256 gmTotalSupply = IERC20(gmToken).totalSupply();
        if (gmTotalSupply == 0) return gmAmount;
        
        // Approximate based on deposited ratio
        return (gmAmount * totalDeposited) / gmTotalSupply;
    }

    function setMinExecutionFee(uint256 _fee) external onlyOwner {
        minExecutionFee = _fee;
    }

    function emergencyWithdraw(address recipient) external override onlyOwner {
        uint256 balance = IERC20(gmToken).balanceOf(address(this));
        if (balance > 0) {
            IERC20(gmToken).safeTransfer(msg.sender, balance);
        }
        
        uint256 underlyingBalance = underlyingAsset.balanceOf(address(this));
        if (underlyingBalance > 0) {
            underlyingAsset.safeTransfer(msg.sender, underlyingBalance);
        }
    }

    receive() external payable {}
}

// ═══════════════════════════════════════════════════════════════════════════════
// HYPERLIQUID HLP STRATEGY
// ═══════════════════════════════════════════════════════════════════════════════

/// @title Hyperliquid HLP Strategy
/// @notice Provides liquidity to Hyperliquid perpetuals via HLP vault
/// @dev HLP earns trading fees + funding payments
///      Typical APY: 30-100% (highest among perps LPs)
///      Risk: Counterparty to all Hyperliquid traders
///      Note: Requires bridging to Hyperliquid L1 (separate infra)
contract HyperliquidHLPStrategy is BasePerpsStrategy {
    using SafeERC20 for IERC20;

    /// @notice Hyperliquid vault contract (L1)
    address public hlpVault;

    /// @notice Hyperliquid bridge contract (L1)
    address public hlpBridge;

    /// @notice USDC on mainnet
    address public constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;

    /// @notice HLP shares balance
    uint256 public hlpShares;

    /// @notice Pending bridge deposits
    mapping(bytes32 => uint256) public pendingBridgeDeposits;

    /// @notice Minimum bridge amount
    uint256 public minBridgeAmount = 100e6; // 100 USDC

    event BridgeInitiated(bytes32 indexed depositId, uint256 amount);
    event HLPDeposited(uint256 amount, uint256 shares);
    event HLPWithdrawn(uint256 shares, uint256 amount);

    constructor(
        address _hlpVault,
        address _hlpBridge,
        address _owner
    ) BasePerpsStrategy("Hyperliquid HLP", USDC, _owner) {
        hlpVault = _hlpVault;
        hlpBridge = _hlpBridge;
        
        IERC20(USDC).approve(_hlpBridge, type(uint256).max);
    }

    function deposit(uint256 amount)
        external
        nonReentrant
        whenNotPaused
        returns (uint256 shares)
    {
        require(amount >= minBridgeAmount, "Below minimum");
        
        underlyingAsset.safeTransferFrom(msg.sender, address(this), amount);

        // Bridge USDC to Hyperliquid L1
        IHyperliquidBridge(hlpBridge).deposit(address(underlyingAsset), amount, address(this));

        // Deposit into HLP vault (happens on L1, tracked via events)
        // Note: Actual shares arrive asynchronously
        shares = amount; // 1:1 placeholder
        totalDeposited += amount;

        emit HLPDeposited(amount, shares);
        emit Deposited(msg.sender, amount, shares);
    }

    function withdraw(uint256 shares)
        external
        nonReentrant
        returns (uint256 assets)
    {
        require(hlpShares >= shares, "Insufficient HLP");

        // Initiate withdrawal from HLP vault (L1)
        assets = IHyperliquidVault(hlpVault).withdraw(shares);
        hlpShares -= shares;

        // Bridge back to L1 and transfer
        // Note: This is async, actual transfer happens via bridge callback
        if (assets <= totalDeposited) {
            totalDeposited -= assets;
        } else {
            totalDeposited = 0;
        }

        emit HLPWithdrawn(shares, assets);
        emit Withdrawn(msg.sender, assets, shares);
    }

    function harvest() external nonReentrant returns (uint256 yield) {
        // Claim rewards from HLP vault
        yield = IHyperliquidVault(hlpVault).claimRewards();
        
        if (yield > 0) {
            accumulatedYield += yield;
        }
        
        lastHarvest = block.timestamp;
        emit Harvested(yield);
    }

    function totalAssets() external view returns (uint256) {
        if (hlpShares == 0) return totalDeposited;
        
        // Get current HLP share value
        uint256 totalHLPAssets = IHyperliquidVault(hlpVault).totalAssets();
        uint256 totalHLPSupply = IHyperliquidVault(hlpVault).totalSupply();
        
        if (totalHLPSupply == 0) return totalDeposited;
        
        return (hlpShares * totalHLPAssets) / totalHLPSupply + accumulatedYield;
    }

    function currentAPY() external pure returns (uint256) {
        // Hyperliquid HLP typically yields 30-100% APY
        return 5000; // 50% baseline
    }

    /// @notice Get pending rewards
    function getPendingRewards() external view returns (uint256) {
        return IHyperliquidVault(hlpVault).pendingRewards(address(this));
    }

    /// @notice Update HLP shares after bridge confirmation
    function updateHLPShares(uint256 _shares) external onlyOwner {
        hlpShares = _shares;
    }

    function setMinBridgeAmount(uint256 _amount) external onlyOwner {
        minBridgeAmount = _amount;
    }

    function emergencyWithdraw(address recipient) external override onlyOwner {
        uint256 balance = underlyingAsset.balanceOf(address(this));
        if (balance > 0) {
            underlyingAsset.safeTransfer(msg.sender, balance);
        }
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// VERTEX PROTOCOL STRATEGY
// ═══════════════════════════════════════════════════════════════════════════════

/// @title Vertex Protocol Strategy
/// @notice Provides liquidity to Vertex hybrid DEX (perps + spot)
/// @dev Earns trading fees + VRTX token rewards
///      Typical APY: 15-40%
///      Operates on Arbitrum with sub-millisecond execution
contract VertexStrategy is BasePerpsStrategy {
    using SafeERC20 for IERC20;

    // Vertex Arbitrum Addresses
    address public constant ENDPOINT = 0xbbEE07B3e8121227AfCFe1E2B82772246226128e;
    address public constant CLEARINGHOUSE = 0x77F7b1E3C5E3E5e3C5e3E5e3c5e3E5e3c5e3E5e3;
    address public constant VRTX_TOKEN = 0x95146881b86B3ee99e63705eC87AfE29Fcc044D9;
    address public constant VRTX_STAKING = 0x95146881b86B3ee99e63705eC87AfE29Fcc044D9;

    /// @notice USDC on Arbitrum
    address public constant USDC = 0xaf88d065e77c8cC2239327C5EDb3A432268e5831;

    /// @notice Vertex subaccount ID
    bytes32 public subaccount;

    /// @notice USDC product ID
    uint32 public constant USDC_PRODUCT_ID = 0;

    /// @notice Staked VRTX balance
    uint256 public stakedVRTX;

    /// @notice Collateral deposited
    uint256 public depositedCollateral;

    event CollateralDeposited(uint256 amount);
    event CollateralWithdrawn(uint256 amount);
    event VRTXStaked(uint256 amount);
    event VRTXRewardsClaimed(uint256 amount);

    constructor(
        bytes32 _subaccount,
        address _owner
    ) BasePerpsStrategy("Vertex Protocol", USDC, _owner) {
        subaccount = _subaccount;
        
        IERC20(USDC).approve(ENDPOINT, type(uint256).max);
        IERC20(VRTX_TOKEN).approve(VRTX_STAKING, type(uint256).max);
    }

    function deposit(uint256 amount)
        external
        nonReentrant
        whenNotPaused
        returns (uint256 shares)
    {
        underlyingAsset.safeTransferFrom(msg.sender, address(this), amount);

        // Deposit collateral to Vertex
        IVertexEndpoint.DepositCollateral memory txn = IVertexEndpoint.DepositCollateral({
            sender: subaccount,
            productId: USDC_PRODUCT_ID,
            amount: uint128(amount)
        });

        // Note: signature verification is handled via EOA or approved signer
        IVertexEndpoint(ENDPOINT).depositCollateral(txn, bytes(""));

        depositedCollateral += amount;
        totalDeposited += amount;
        shares = amount;

        emit CollateralDeposited(amount);
        emit Deposited(msg.sender, amount, shares);
    }

    function withdraw(uint256 amount)
        external
        nonReentrant
        returns (uint256 assets)
    {
        require(depositedCollateral >= amount, "Insufficient collateral");

        // Withdraw from Vertex
        IVertexEndpoint(ENDPOINT).withdrawCollateral(
            subaccount,
            USDC_PRODUCT_ID,
            uint128(amount),
            uint64(block.timestamp)
        );

        underlyingAsset.safeTransfer(msg.sender, amount);

        depositedCollateral -= amount;
        totalDeposited -= amount;
        assets = amount;

        emit CollateralWithdrawn(amount);
        emit Withdrawn(msg.sender, amount, amount);
    }

    function harvest() external nonReentrant returns (uint256 yield) {
        // Claim VRTX rewards from staking
        if (stakedVRTX > 0) {
            yield = IVertexStaking(VRTX_STAKING).claimRewards();
            accumulatedYield += yield;
            emit VRTXRewardsClaimed(yield);
        }
        
        lastHarvest = block.timestamp;
        emit Harvested(yield);
    }

    /// @notice Stake VRTX tokens for additional yield
    function stakeVRTX(uint256 amount) external onlyOwner {
        IERC20(VRTX_TOKEN).safeTransferFrom(msg.sender, address(this), amount);
        IVertexStaking(VRTX_STAKING).stake(amount);
        stakedVRTX += amount;
        emit VRTXStaked(amount);
    }

    /// @notice Unstake VRTX tokens
    function unstakeVRTX(uint256 amount) external onlyOwner {
        require(stakedVRTX >= amount, "Insufficient staked");
        IVertexStaking(VRTX_STAKING).unstake(amount);
        stakedVRTX -= amount;
    }

    function totalAssets() external view returns (uint256) {
        // Collateral + pending rewards
        uint256 pending = IVertexStaking(VRTX_STAKING).pendingRewards(address(this));
        return depositedCollateral + accumulatedYield + pending;
    }

    function currentAPY() external pure returns (uint256) {
        // Vertex typically yields 15-40% APY
        return 2500; // 25% baseline
    }

    /// @notice Get subaccount health
    function getHealth() external view returns (int128) {
        return IVertexClearinghouse(CLEARINGHOUSE).getHealth(subaccount, 0);
    }

    function emergencyWithdraw(address recipient) external override onlyOwner {
        uint256 balance = underlyingAsset.balanceOf(address(this));
        if (balance > 0) {
            underlyingAsset.safeTransfer(msg.sender, balance);
        }
        
        uint256 vrtxBalance = IERC20(VRTX_TOKEN).balanceOf(address(this));
        if (vrtxBalance > 0) {
            IERC20(VRTX_TOKEN).safeTransfer(msg.sender, vrtxBalance);
        }
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// GAINS NETWORK STRATEGY
// ═══════════════════════════════════════════════════════════════════════════════

/// @title Gains Network gDAI Strategy
/// @notice Deposits DAI into gDAI vault for trading fee yield
/// @dev gDAI earns fees from leveraged trading on Gains Network
///      Typical APY: 10-30%
///      Available on Polygon and Arbitrum
contract GainsNetworkStrategy is BasePerpsStrategy {
    using SafeERC20 for IERC20;

    /// @notice gDAI vault
    IGainsVault public immutable gDaiVault;

    /// @notice GNS staking contract
    IGainsStaking public immutable gnsStaking;

    /// @notice DAI address
    address public immutable dai;

    /// @notice GNS token address
    address public immutable gnsToken;

    /// @notice gDAI balance
    uint256 public gDaiShares;

    /// @notice Staked GNS balance
    uint256 public stakedGNS;

    /// @notice Lock end timestamp for withdrawals
    uint256 public withdrawLockEnd;

    event GDAIDeposited(uint256 daiAmount, uint256 shares);
    event GDAIWithdrawn(uint256 shares, uint256 daiAmount);
    event GNSStaked(uint256 amount);
    event GNSRewardsClaimed(uint256 amount);

    constructor(
        address _gDaiVault,
        address _gnsStaking,
        address _dai,
        address _gnsToken,
        address _owner
    ) BasePerpsStrategy("Gains Network gDAI", _dai, _owner) {
        gDaiVault = IGainsVault(_gDaiVault);
        gnsStaking = IGainsStaking(_gnsStaking);
        dai = _dai;
        gnsToken = _gnsToken;

        IERC20(_dai).approve(_gDaiVault, type(uint256).max);
        IERC20(_gnsToken).approve(_gnsStaking, type(uint256).max);
    }

    function deposit(uint256 amount)
        external
        nonReentrant
        whenNotPaused
        returns (uint256 shares)
    {
        // Check max deposit
        uint256 maxDeposit = gDaiVault.maxDeposit(address(this));
        require(amount <= maxDeposit, "Exceeds max deposit");

        underlyingAsset.safeTransferFrom(msg.sender, address(this), amount);

        // Deposit to gDAI vault
        shares = gDaiVault.deposit(amount, address(this));
        gDaiShares += shares;
        totalDeposited += amount;

        // Set withdrawal lock
        uint256 lockDuration = gDaiVault.withdrawLockDuration();
        if (block.timestamp + lockDuration > withdrawLockEnd) {
            withdrawLockEnd = block.timestamp + lockDuration;
        }

        emit GDAIDeposited(amount, shares);
        emit Deposited(msg.sender, amount, shares);
    }

    function withdraw(uint256 shares)
        external
        nonReentrant
        returns (uint256 assets)
    {
        require(block.timestamp >= withdrawLockEnd, "Withdrawal locked");
        require(gDaiShares >= shares, "Insufficient gDAI");

        // Redeem gDAI for DAI
        assets = gDaiVault.redeem(shares, msg.sender, address(this));
        gDaiShares -= shares;

        if (assets <= totalDeposited) {
            totalDeposited -= assets;
        } else {
            totalDeposited = 0;
        }

        emit GDAIWithdrawn(shares, assets);
        emit Withdrawn(msg.sender, assets, shares);
    }

    function harvest() external nonReentrant returns (uint256 yield) {
        // gDAI is auto-compounding, but we can track yield
        uint256 currentValue = gDaiVault.convertToAssets(gDaiShares);
        
        if (currentValue > totalDeposited) {
            yield = currentValue - totalDeposited;
        }

        // Harvest GNS staking rewards
        if (stakedGNS > 0) {
            uint256 gnsRewards = gnsStaking.harvest();
            accumulatedYield += gnsRewards;
            emit GNSRewardsClaimed(gnsRewards);
        }
        
        lastHarvest = block.timestamp;
        emit Harvested(yield);
    }

    /// @notice Stake GNS tokens for additional yield
    function stakeGNS(uint256 amount) external onlyOwner {
        IERC20(gnsToken).safeTransferFrom(msg.sender, address(this), amount);
        gnsStaking.stake(amount);
        stakedGNS += amount;
        emit GNSStaked(amount);
    }

    /// @notice Unstake GNS tokens
    function unstakeGNS(uint256 amount) external onlyOwner {
        require(stakedGNS >= amount, "Insufficient staked");
        gnsStaking.unstake(amount);
        stakedGNS -= amount;
    }

    function totalAssets() external view returns (uint256) {
        // gDAI value + staking rewards
        uint256 gDaiValue = gDaiVault.convertToAssets(gDaiShares);
        uint256 pendingRewards = gnsStaking.pendingRewardsDai(address(this));
        return gDaiValue + pendingRewards + accumulatedYield;
    }

    function currentAPY() external pure returns (uint256) {
        // Gains Network typically yields 10-30% APY
        return 2000; // 20% baseline
    }

    /// @notice Get current gDAI share price
    function getSharePrice() external view returns (uint256) {
        return gDaiVault.shareToAssetsPrice();
    }

    /// @notice Get current vault utilization
    function getUtilization() external view returns (uint256) {
        return gDaiVault.currentEpochPositiveOpenPnl();
    }

    /// @notice Check if withdrawals are unlocked
    function isWithdrawUnlocked() external view returns (bool) {
        return block.timestamp >= withdrawLockEnd;
    }

    function emergencyWithdraw(address recipient) external override onlyOwner {
        // Transfer gDAI tokens
        uint256 gDaiBalance = gDaiVault.balanceOf(address(this));
        if (gDaiBalance > 0) {
            IERC20(address(gDaiVault)).safeTransfer(msg.sender, gDaiBalance);
        }

        // Transfer DAI
        uint256 daiBalance = underlyingAsset.balanceOf(address(this));
        if (daiBalance > 0) {
            underlyingAsset.safeTransfer(msg.sender, daiBalance);
        }

        // Transfer GNS
        uint256 gnsBalance = IERC20(gnsToken).balanceOf(address(this));
        if (gnsBalance > 0) {
            IERC20(gnsToken).safeTransfer(msg.sender, gnsBalance);
        }
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// CONCRETE IMPLEMENTATIONS
// ═══════════════════════════════════════════════════════════════════════════════

/// @title GMX V2 ETH-USD Market Strategy
/// @notice Stakes in ETH-USD GM market on Arbitrum
contract GMXV2ETHUSDStrategy is GMXV2Strategy {
    // GM ETH-USD market on Arbitrum
    address public constant GM_ETH_USD = 0x70d95587d40A2caf56bd97485aB3Eec10Bee6336;

    constructor(address _owner)
        GMXV2Strategy(
            "GMX V2 ETH-USD",
            GM_ETH_USD,
            0x82aF49447D8a07e3bd95BD0d56f35241523fBab1, // WETH from parent
            _owner
        )
    {}
}

/// @title GMX V2 BTC-USD Market Strategy
/// @notice Stakes in BTC-USD GM market on Arbitrum
contract GMXV2BTCUSDStrategy is GMXV2Strategy {
    // GM BTC-USD market on Arbitrum
    address public constant GM_BTC_USD = 0x47c031236e19d024b42f8AE6780E44A573170703;
    address public constant WBTC = 0x2f2a2543B76A4166549F7aaB2e75Bef0aefC5B0f;

    constructor(address _owner)
        GMXV2Strategy(
            "GMX V2 BTC-USD",
            GM_BTC_USD,
            WBTC,
            _owner
        )
    {}
}

/// @title Gains Network Polygon Strategy
/// @notice gDAI vault on Polygon
contract GainsPolygonStrategy is GainsNetworkStrategy {
    // Polygon addresses
    address public constant GDAI_VAULT = 0x91993f2101cc758D0dEB7279d41e880F7dEFe827;
    address public constant GNS_STAKING = 0x7b9e962dD8AeD0DB9a1d8a2F9E2bf7c3cac11C5A;
    address public constant POLYGON_DAI = 0x8f3Cf7ad23Cd3CaDbD9735AFf958023239c6A063;
    address public constant POLYGON_GNS = 0xE5417Af564e4bFDA1c483642db72007871397896;

    constructor(address _owner)
        GainsNetworkStrategy(
            GDAI_VAULT,
            GNS_STAKING,
            POLYGON_DAI,
            POLYGON_GNS,
            _owner
        )
    {}
}

/// @title Gains Network Arbitrum Strategy
/// @notice gDAI vault on Arbitrum
contract GainsArbitrumStrategy is GainsNetworkStrategy {
    // Arbitrum addresses
    address public constant GDAI_VAULT = 0xd85E038593d7A098614721EaE955EC2022B9B91B;
    address public constant GNS_STAKING = 0x6B8D3C08072a020aC065c467ce922e3A36D3F9d6;
    address public constant ARBITRUM_DAI = 0xDA10009cBd5D07dd0CeCc66161FC93D7c9000da1;
    address public constant ARBITRUM_GNS = 0x18c11FD286C5EC11c3b683Caa813B77f5163A122;

    constructor(address _owner)
        GainsNetworkStrategy(
            GDAI_VAULT,
            GNS_STAKING,
            ARBITRUM_DAI,
            ARBITRUM_GNS,
            _owner
        )
    {}
}

// ═══════════════════════════════════════════════════════════════════════════════
// PERPS STRATEGY FACTORY
// ═══════════════════════════════════════════════════════════════════════════════

/// @title Perpetual DEX Strategy Factory
/// @notice Deploys perps yield strategies
contract PerpsStrategyFactory is Ownable {
    
    enum StrategyType {
        GMX_V2_ETH_USD,
        GMX_V2_BTC_USD,
        HYPERLIQUID_HLP,
        VERTEX,
        GAINS_POLYGON,
        GAINS_ARBITRUM
    }

    event StrategyDeployed(StrategyType indexed strategyType, address strategy);

    constructor(address _owner) Ownable(_owner) {}

    /// @notice Deploy a perps strategy
    function deploy(StrategyType strategyType) external onlyOwner returns (address strategy) {
        if (strategyType == StrategyType.GMX_V2_ETH_USD) {
            strategy = address(new GMXV2ETHUSDStrategy(owner()));
        } else if (strategyType == StrategyType.GMX_V2_BTC_USD) {
            strategy = address(new GMXV2BTCUSDStrategy(owner()));
        } else if (strategyType == StrategyType.GAINS_POLYGON) {
            strategy = address(new GainsPolygonStrategy(owner()));
        } else if (strategyType == StrategyType.GAINS_ARBITRUM) {
            strategy = address(new GainsArbitrumStrategy(owner()));
        } else {
            revert("Invalid strategy type");
        }

        emit StrategyDeployed(strategyType, strategy);
    }

    /// @notice Deploy Hyperliquid HLP strategy with custom addresses
    function deployHyperliquid(
        address hlpVault,
        address hlpBridge
    ) external onlyOwner returns (address strategy) {
        strategy = address(new HyperliquidHLPStrategy(hlpVault, hlpBridge, owner()));
        emit StrategyDeployed(StrategyType.HYPERLIQUID_HLP, strategy);
    }

    /// @notice Deploy Vertex strategy with custom subaccount
    function deployVertex(bytes32 subaccount) external onlyOwner returns (address strategy) {
        strategy = address(new VertexStrategy(subaccount, owner()));
        emit StrategyDeployed(StrategyType.VERTEX, strategy);
    }
}
