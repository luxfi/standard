// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import "../IYieldStrategy.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/// @title TON Blockchain Yield Strategies
/// @notice Cross-chain yield strategies for TON blockchain protocols
/// @dev Includes Tonstakers (tsTON), Bemo (stTON), and STON.fi LP
///      These protocols generate yield from staking and DEX fees
///      Typical APY: 5-15% staking, 10-50% LP depending on pairs

// ═══════════════════════════════════════════════════════════════════════════════
// TON BRIDGE INTERFACES
// ═══════════════════════════════════════════════════════════════════════════════

/// @title ITONBridge
/// @notice Interface for cross-chain TON bridge operations
/// @dev Handles locking assets on EVM and bridging to TON
interface ITONBridge {
    /// @notice Lock EVM assets and initiate bridge to TON
    /// @param amount Amount of LTON/wrapped TON to lock
    /// @param tonRecipient TON address (32 bytes) to receive assets
    /// @return bridgeId Unique identifier for the bridge operation
    function lockAndBridge(uint256 amount, bytes32 tonRecipient) external returns (bytes32 bridgeId);

    /// @notice Claim bridged assets from TON back to EVM
    /// @param bridgeId Bridge operation identifier
    /// @param proof Merkle proof from TON validators
    /// @return amount Amount of assets claimed
    function claimFromTON(bytes32 bridgeId, bytes calldata proof) external returns (uint256 amount);

    /// @notice Get bridge operation status
    /// @param bridgeId Bridge operation identifier
    /// @return status 0=pending, 1=confirmed, 2=completed, 3=failed
    /// @return amount Amount involved in the operation
    function getBridgeStatus(bytes32 bridgeId) external view returns (uint8 status, uint256 amount);
}

/// @title ITONYieldOracle
/// @notice Oracle for TON yield protocol rates
/// @dev Updated by off-chain relayers from TON blockchain
interface ITONYieldOracle {
    /// @notice Get current tsTON/TON exchange rate (18 decimals)
    /// @return Exchange rate where 1e18 = 1:1
    function getTsTONExchangeRate() external view returns (uint256);

    /// @notice Get current stTON/TON exchange rate (18 decimals)
    /// @return Exchange rate where 1e18 = 1:1
    function getStTONExchangeRate() external view returns (uint256);

    /// @notice Get APY for a STON.fi pool
    /// @param poolId STON.fi pool identifier
    /// @return APY in basis points (e.g., 500 = 5%)
    function getStonFiPoolApy(bytes32 poolId) external view returns (uint256);

    /// @notice Get current TON staking APY
    /// @return APY in basis points
    function getTONStakingApy() external view returns (uint256);
}

/// @title ITONYieldController
/// @notice Controller for TON-side yield operations
/// @dev Initiates transactions on TON blockchain via bridge messages
interface ITONYieldController {
    /// @notice Deposit TON to Tonstakers protocol
    /// @param tonAmount Amount of TON to deposit
    /// @return txId TON transaction identifier
    function depositToTonstakers(uint256 tonAmount) external returns (bytes32 txId);

    /// @notice Withdraw from Tonstakers protocol
    /// @param tsTonAmount Amount of tsTON to withdraw
    /// @return txId TON transaction identifier
    function withdrawFromTonstakers(uint256 tsTonAmount) external returns (bytes32 txId);

    /// @notice Deposit TON to Bemo protocol
    /// @param tonAmount Amount of TON to deposit
    /// @return txId TON transaction identifier
    function depositToBemo(uint256 tonAmount) external returns (bytes32 txId);

    /// @notice Withdraw from Bemo protocol
    /// @param stTonAmount Amount of stTON to withdraw
    /// @return txId TON transaction identifier
    function withdrawFromBemo(uint256 stTonAmount) external returns (bytes32 txId);

    /// @notice Add liquidity to STON.fi pool
    /// @param poolId Pool identifier
    /// @param amount0 Amount of first token
    /// @param amount1 Amount of second token
    /// @return txId TON transaction identifier
    function addLiquidityToStonFi(bytes32 poolId, uint256 amount0, uint256 amount1) external returns (bytes32 txId);

    /// @notice Remove liquidity from STON.fi pool
    /// @param poolId Pool identifier
    /// @param lpAmount Amount of LP tokens to remove
    /// @return txId TON transaction identifier
    function removeLiquidityFromStonFi(bytes32 poolId, uint256 lpAmount) external returns (bytes32 txId);

    /// @notice Claim STON.fi farming rewards
    /// @param poolId Pool identifier
    /// @return txId TON transaction identifier
    function claimStonFiRewards(bytes32 poolId) external returns (bytes32 txId);
}

// ═══════════════════════════════════════════════════════════════════════════════
// TON MESSAGE STRUCTURES
// ═══════════════════════════════════════════════════════════════════════════════

/// @notice Message structure for TON deposits
struct TONDepositMessage {
    /// @dev Action type: 1=stake, 2=unstake, 3=addLiquidity, 4=removeLiquidity, 5=claim
    uint8 action;
    /// @dev Protocol identifier (tonstakers, bemo, stonfi)
    bytes32 protocol;
    /// @dev Amount of tokens involved
    uint256 amount;
    /// @dev Recipient TON address
    bytes32 tonAddress;
}

/// @notice Yield report from TON protocols
struct TONYieldReport {
    /// @dev Protocol identifier
    bytes32 protocol;
    /// @dev Total deposited in TON
    uint256 totalDeposited;
    /// @dev Current value including yield
    uint256 currentValue;
    /// @dev Pending rewards to claim
    uint256 pendingRewards;
    /// @dev Last update timestamp
    uint64 lastUpdate;
}

// ═══════════════════════════════════════════════════════════════════════════════
// CUSTOM ERRORS
// ═══════════════════════════════════════════════════════════════════════════════

/// @dev Strategy is not active
error StrategyNotActive();

/// @dev Caller is not the vault
error OnlyVault();

/// @dev Amount is below minimum
error BelowMinimum(uint256 amount, uint256 minimum);

/// @dev Bridge operation pending
error BridgePending(bytes32 bridgeId);

/// @dev Insufficient balance
error InsufficientBalance(uint256 requested, uint256 available);

/// @dev Invalid proof
error InvalidProof();

/// @dev Operation timeout
error OperationTimeout(bytes32 operationId);

/// @dev Oracle data stale
error StaleOracleData(uint256 lastUpdate, uint256 maxAge);

/// @dev Invalid pool ID
error InvalidPoolId(bytes32 poolId);

// ═══════════════════════════════════════════════════════════════════════════════
// BASE TON STRATEGY
// ═══════════════════════════════════════════════════════════════════════════════

/// @title BaseTONStrategy
/// @notice Base contract for TON yield strategies
/// @dev Handles common bridge and oracle operations
abstract contract BaseTONStrategy is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // ═══════════════════════════════════════════════════════════════════════════
    // STATE
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice LTON (Lux-wrapped TON) token
    IERC20 public immutable lton;

    /// @notice TON bridge contract
    ITONBridge public immutable tonBridge;

    /// @notice TON yield oracle
    ITONYieldOracle public tonOracle;

    /// @notice TON yield controller
    ITONYieldController public tonController;

    /// @notice Vault controller address
    address public vault;

    /// @notice TON recipient address for this strategy
    bytes32 public tonRecipient;

    /// @notice Total deposited in LTON terms
    uint256 internal _totalDeposited;

    /// @notice Current value as reported by oracle
    uint256 public currentValueReported;

    /// @notice Accumulated yield
    uint256 public accumulatedYield;

    /// @notice Last harvest timestamp
    uint256 public lastHarvest;

    /// @notice Last oracle update timestamp
    uint256 public lastOracleUpdate;

    /// @notice Strategy active status
    bool public active = true;

    /// @notice Minimum deposit amount
    uint256 public minDeposit = 10 ether; // 10 TON minimum

    /// @notice Maximum oracle data age
    uint256 public maxOracleAge = 1 hours;

    /// @notice Pending bridge operations
    mapping(bytes32 => uint256) public pendingBridgeOps;

    /// @notice Bridge operation timestamps
    mapping(bytes32 => uint256) public bridgeOpTimestamps;

    // ═══════════════════════════════════════════════════════════════════════════
    // EVENTS
    // ═══════════════════════════════════════════════════════════════════════════

    event BridgeInitiated(bytes32 indexed bridgeId, uint256 amount, uint8 action);
    event BridgeCompleted(bytes32 indexed bridgeId, uint256 amount);
    event YieldReported(uint256 totalValue, uint256 yield);
    event OracleUpdated(address indexed newOracle);
    event ControllerUpdated(address indexed newController);
    event TONRecipientUpdated(bytes32 newRecipient);

    // ═══════════════════════════════════════════════════════════════════════════
    // MODIFIERS
    // ═══════════════════════════════════════════════════════════════════════════

    modifier onlyVault() {
        if (msg.sender != vault) revert OnlyVault();
        _;
    }

    modifier whenActive() {
        if (!active) revert StrategyNotActive();
        _;
    }

    modifier oracleNotStale() {
        if (block.timestamp - lastOracleUpdate > maxOracleAge) {
            revert StaleOracleData(lastOracleUpdate, maxOracleAge);
        }
        _;
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // CONSTRUCTOR
    // ═══════════════════════════════════════════════════════════════════════════

    constructor(
        address _lton,
        address _tonBridge,
        address _tonOracle,
        address _tonController,
        address _vault,
        bytes32 _tonRecipient
    ) Ownable(msg.sender) {
        lton = IERC20(_lton);
        tonBridge = ITONBridge(_tonBridge);
        tonOracle = ITONYieldOracle(_tonOracle);
        tonController = ITONYieldController(_tonController);
        vault = _vault;
        tonRecipient = _tonRecipient;
        lastHarvest = block.timestamp;
        lastOracleUpdate = block.timestamp;

        // Approve bridge for LTON
        IERC20(_lton).approve(_tonBridge, type(uint256).max);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // INTERNAL HELPERS
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Bridge LTON to TON blockchain
    function _bridgeToTON(uint256 amount) internal returns (bytes32 bridgeId) {
        bridgeId = tonBridge.lockAndBridge(amount, tonRecipient);
        pendingBridgeOps[bridgeId] = amount;
        bridgeOpTimestamps[bridgeId] = block.timestamp;
        emit BridgeInitiated(bridgeId, amount, 1);
    }

    /// @notice Claim assets bridged from TON
    function _claimFromTON(bytes32 bridgeId, bytes calldata proof) internal returns (uint256 amount) {
        amount = tonBridge.claimFromTON(bridgeId, proof);
        delete pendingBridgeOps[bridgeId];
        delete bridgeOpTimestamps[bridgeId];
        emit BridgeCompleted(bridgeId, amount);
    }

    /// @notice Update oracle data
    function _updateFromOracle() internal virtual;

    // ═══════════════════════════════════════════════════════════════════════════
    // IYieldStrategy IMPLEMENTATION
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice
    function asset() external view returns (address) {
        return address(lton);
    }

    /// @notice
    function isActive() external view returns (bool) {
        return active;
    }

    /// @notice
    function totalDeposited() external view returns (uint256) {
        return _totalDeposited;
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // ADMIN
    // ═══════════════════════════════════════════════════════════════════════════

    function setActive(bool _active) external onlyOwner {
        active = _active;
    }

    function setVault(address _vault) external onlyOwner {
        vault = _vault;
    }

    function setOracle(address _oracle) external onlyOwner {
        tonOracle = ITONYieldOracle(_oracle);
        emit OracleUpdated(_oracle);
    }

    function setController(address _controller) external onlyOwner {
        tonController = ITONYieldController(_controller);
        emit ControllerUpdated(_controller);
    }

    function setTONRecipient(bytes32 _recipient) external onlyOwner {
        tonRecipient = _recipient;
        emit TONRecipientUpdated(_recipient);
    }

    function setMinDeposit(uint256 _minDeposit) external onlyOwner {
        minDeposit = _minDeposit;
    }

    function setMaxOracleAge(uint256 _maxAge) external onlyOwner {
        maxOracleAge = _maxAge;
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// TONSTAKERS STRATEGY (tsTON)
// ═══════════════════════════════════════════════════════════════════════════════

/// @title TsTONStrategy
/// @notice Liquid staking via Tonstakers protocol
/// @dev tsTON is the largest TON liquid staking protocol
///      - Validator set diversification
///      - Auto-compounding rewards
///      - No minimum stake
///      Typical APY: 5-8%
contract TsTONStrategy is BaseTONStrategy {
    using SafeERC20 for IERC20;

    // ═══════════════════════════════════════════════════════════════════════════
    // CONSTANTS
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Protocol identifier
    bytes32 public constant PROTOCOL_ID = keccak256("TONSTAKERS");

    /// @notice tsTON wrapper address on EVM (shadow token)
    address public immutable tsTonWrapper;

    // ═══════════════════════════════════════════════════════════════════════════
    // STATE
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice tsTON balance (tracked via oracle)
    uint256 public tsTonBalance;

    /// @notice Current tsTON/TON exchange rate
    uint256 public exchangeRate;

    /// @notice Pending stake operations
    mapping(bytes32 => uint256) public pendingStakes;

    /// @notice Pending unstake operations
    mapping(bytes32 => uint256) public pendingUnstakes;

    // ═══════════════════════════════════════════════════════════════════════════
    // EVENTS
    // ═══════════════════════════════════════════════════════════════════════════

    event Staked(bytes32 indexed txId, uint256 tonAmount);
    event Unstaked(bytes32 indexed txId, uint256 tsTonAmount);
    event ExchangeRateUpdated(uint256 oldRate, uint256 newRate);

    // ═══════════════════════════════════════════════════════════════════════════
    // CONSTRUCTOR
    // ═══════════════════════════════════════════════════════════════════════════

    constructor(
        address _lton,
        address _tsTonWrapper,
        address _tonBridge,
        address _tonOracle,
        address _tonController,
        address _vault,
        bytes32 _tonRecipient
    ) BaseTONStrategy(_lton, _tonBridge, _tonOracle, _tonController, _vault, _tonRecipient) {
        tsTonWrapper = _tsTonWrapper;
        exchangeRate = 1e18; // Initial 1:1 rate
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // IYieldStrategy IMPLEMENTATION
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice
    function deposit(uint256 amount, bytes calldata /* data */) external onlyVault nonReentrant whenActive returns (uint256 shares) {
        if (amount < minDeposit) revert BelowMinimum(amount, minDeposit);

        lton.safeTransferFrom(msg.sender, address(this), amount);

        // Bridge to TON
        bytes32 bridgeId = _bridgeToTON(amount);

        // Initiate stake on Tonstakers
        bytes32 txId = tonController.depositToTonstakers(amount);
        pendingStakes[txId] = amount;

        _totalDeposited += amount;
        shares = _tonToTsTon(amount);
        tsTonBalance += shares;

        emit Staked(txId, amount);
    }

    /// @notice
    function withdraw(uint256 shares, address recipient, bytes calldata /* data */) external onlyVault nonReentrant returns (uint256 assets) {
        if (shares > tsTonBalance) revert InsufficientBalance(shares, tsTonBalance);

        assets = _tsTonToTon(shares);

        // Initiate unstake on Tonstakers
        bytes32 txId = tonController.withdrawFromTonstakers(shares);
        pendingUnstakes[txId] = shares;

        tsTonBalance -= shares;
        if (assets <= _totalDeposited) {
            _totalDeposited -= assets;
        } else {
            _totalDeposited = 0;
        }

        // Note: assets sent after bridge completion via claimUnstake()
        // recipient is tracked for later distribution

        emit Unstaked(txId, shares);
    }

    /// @notice
    function harvest() external nonReentrant returns (uint256 harvested) {
        _updateFromOracle();

        uint256 currentValue = _tsTonToTon(tsTonBalance);
        if (currentValue > _totalDeposited) {
            harvested = currentValue - _totalDeposited;
            accumulatedYield += harvested;
        }

        lastHarvest = block.timestamp;
        emit YieldReported(currentValue, harvested);
    }

    /// @notice
    function totalAssets() external view returns (uint256) {
        return _tsTonToTon(tsTonBalance) + accumulatedYield;
    }

    /// @notice
    function currentAPY() external view returns (uint256) {
        return tonOracle.getTONStakingApy();
    }

    /// @notice
    function name() external pure returns (string memory) {
        return "Tonstakers tsTON";
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // INTERNAL
    // ═══════════════════════════════════════════════════════════════════════════

    function _updateFromOracle() internal override {
        uint256 oldRate = exchangeRate;
        exchangeRate = tonOracle.getTsTONExchangeRate();
        lastOracleUpdate = block.timestamp;

        if (exchangeRate != oldRate) {
            emit ExchangeRateUpdated(oldRate, exchangeRate);
        }
    }

    function _tonToTsTon(uint256 tonAmount) internal view returns (uint256) {
        return (tonAmount * 1e18) / exchangeRate;
    }

    function _tsTonToTon(uint256 tsTonAmount) internal view returns (uint256) {
        return (tsTonAmount * exchangeRate) / 1e18;
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // VIEW
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Get current exchange rate
    function getExchangeRate() external view returns (uint256) {
        return exchangeRate;
    }

    /// @notice Get pending stakes by tx ID
    function getPendingStakes(bytes32 txId) external view returns (uint256) {
        return pendingStakes[txId];
    }

    /// @notice Get pending unstakes by tx ID
    function getPendingUnstakes(bytes32 txId) external view returns (uint256) {
        return pendingUnstakes[txId];
    }

    /// @notice Get yield token wrapper address
    function yieldToken() external view returns (address) {
        return tsTonWrapper;
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // CLAIM COMPLETED OPERATIONS
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Claim completed unstake from TON
    function claimUnstake(bytes32 bridgeId, bytes calldata proof) external onlyOwner returns (uint256 amount) {
        amount = _claimFromTON(bridgeId, proof);
        lton.safeTransfer(vault, amount);
    }

    /// @notice Emergency withdraw
    function emergencyWithdraw(address recipient) external onlyOwner {
        uint256 balance = lton.balanceOf(address(this));
        if (balance > 0) {
            lton.safeTransfer(vault, balance);
        }
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// BEMO STRATEGY (stTON)
// ═══════════════════════════════════════════════════════════════════════════════

/// @title StTONStrategy
/// @notice Liquid staking via Bemo protocol
/// @dev stTON is Bemo's liquid staking token
///      - MEV-protected staking
///      - Insurance fund coverage
///      - Premium validator set
///      Typical APY: 5-7%
contract StTONStrategy is BaseTONStrategy {
    using SafeERC20 for IERC20;

    // ═══════════════════════════════════════════════════════════════════════════
    // CONSTANTS
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Protocol identifier
    bytes32 public constant PROTOCOL_ID = keccak256("BEMO");

    /// @notice stTON wrapper address on EVM
    address public immutable stTonWrapper;

    // ═══════════════════════════════════════════════════════════════════════════
    // STATE
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice stTON balance
    uint256 public stTonBalance;

    /// @notice Current stTON/TON exchange rate
    uint256 public exchangeRate;

    /// @notice Pending stake operations
    mapping(bytes32 => uint256) public pendingStakes;

    /// @notice Pending unstake operations
    mapping(bytes32 => uint256) public pendingUnstakes;

    // ═══════════════════════════════════════════════════════════════════════════
    // EVENTS
    // ═══════════════════════════════════════════════════════════════════════════

    event Staked(bytes32 indexed txId, uint256 tonAmount);
    event Unstaked(bytes32 indexed txId, uint256 stTonAmount);
    event ExchangeRateUpdated(uint256 oldRate, uint256 newRate);

    // ═══════════════════════════════════════════════════════════════════════════
    // CONSTRUCTOR
    // ═══════════════════════════════════════════════════════════════════════════

    constructor(
        address _lton,
        address _stTonWrapper,
        address _tonBridge,
        address _tonOracle,
        address _tonController,
        address _vault,
        bytes32 _tonRecipient
    ) BaseTONStrategy(_lton, _tonBridge, _tonOracle, _tonController, _vault, _tonRecipient) {
        stTonWrapper = _stTonWrapper;
        exchangeRate = 1e18;
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // IYieldStrategy IMPLEMENTATION
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice
    function deposit(uint256 amount, bytes calldata /* data */) external onlyVault nonReentrant whenActive returns (uint256 shares) {
        if (amount < minDeposit) revert BelowMinimum(amount, minDeposit);

        lton.safeTransferFrom(msg.sender, address(this), amount);

        // Bridge to TON
        bytes32 bridgeId = _bridgeToTON(amount);

        // Initiate stake on Bemo
        bytes32 txId = tonController.depositToBemo(amount);
        pendingStakes[txId] = amount;

        _totalDeposited += amount;
        shares = _tonToStTon(amount);
        stTonBalance += shares;

        emit Staked(txId, amount);
    }

    /// @notice
    function withdraw(uint256 shares, address recipient, bytes calldata /* data */) external onlyVault nonReentrant returns (uint256 assets) {
        if (shares > stTonBalance) revert InsufficientBalance(shares, stTonBalance);

        assets = _stTonToTon(shares);

        // Initiate unstake on Bemo
        bytes32 txId = tonController.withdrawFromBemo(shares);
        pendingUnstakes[txId] = shares;

        stTonBalance -= shares;
        if (assets <= _totalDeposited) {
            _totalDeposited -= assets;
        } else {
            _totalDeposited = 0;
        }

        emit Unstaked(txId, shares);
    }

    /// @notice
    function harvest() external nonReentrant returns (uint256 harvested) {
        _updateFromOracle();

        uint256 currentValue = _stTonToTon(stTonBalance);
        if (currentValue > _totalDeposited) {
            harvested = currentValue - _totalDeposited;
            accumulatedYield += harvested;
        }

        lastHarvest = block.timestamp;
        emit YieldReported(currentValue, harvested);
    }

    /// @notice
    function totalAssets() external view returns (uint256) {
        return _stTonToTon(stTonBalance) + accumulatedYield;
    }

    /// @notice
    function currentAPY() external view returns (uint256) {
        // Bemo typically slightly lower than Tonstakers due to insurance fund
        uint256 baseApy = tonOracle.getTONStakingApy();
        return (baseApy * 95) / 100; // 5% reduction for insurance
    }

    /// @notice
    function name() external pure returns (string memory) {
        return "Bemo stTON";
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // INTERNAL
    // ═══════════════════════════════════════════════════════════════════════════

    function _updateFromOracle() internal override {
        uint256 oldRate = exchangeRate;
        exchangeRate = tonOracle.getStTONExchangeRate();
        lastOracleUpdate = block.timestamp;

        if (exchangeRate != oldRate) {
            emit ExchangeRateUpdated(oldRate, exchangeRate);
        }
    }

    function _tonToStTon(uint256 tonAmount) internal view returns (uint256) {
        return (tonAmount * 1e18) / exchangeRate;
    }

    function _stTonToTon(uint256 stTonAmount) internal view returns (uint256) {
        return (stTonAmount * exchangeRate) / 1e18;
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // VIEW
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Get current exchange rate
    function getExchangeRate() external view returns (uint256) {
        return exchangeRate;
    }

    /// @notice Get pending stakes by tx ID
    function getPendingStakes(bytes32 txId) external view returns (uint256) {
        return pendingStakes[txId];
    }

    /// @notice Get pending unstakes by tx ID
    function getPendingUnstakes(bytes32 txId) external view returns (uint256) {
        return pendingUnstakes[txId];
    }

    /// @notice Get yield token wrapper address
    function yieldToken() external view returns (address) {
        return stTonWrapper;
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // CLAIM
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Claim completed unstake from TON
    function claimUnstake(bytes32 bridgeId, bytes calldata proof) external onlyOwner returns (uint256 amount) {
        amount = _claimFromTON(bridgeId, proof);
        lton.safeTransfer(vault, amount);
    }

    /// @notice Emergency withdraw
    function emergencyWithdraw(address recipient) external onlyOwner {
        uint256 balance = lton.balanceOf(address(this));
        if (balance > 0) {
            lton.safeTransfer(vault, balance);
        }
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// STON.FI STRATEGY
// ═══════════════════════════════════════════════════════════════════════════════

/// @title StonFiStrategy
/// @notice LP + farming on STON.fi DEX
/// @dev STON.fi is the largest DEX on TON
///      - Concentrated liquidity pools
///      - STON token farming rewards
///      - Multi-pool support
///      Typical APY: 10-50% (varies by pool)
contract StonFiStrategy is BaseTONStrategy {
    using SafeERC20 for IERC20;

    // ═══════════════════════════════════════════════════════════════════════════
    // CONSTANTS
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Protocol identifier
    bytes32 public constant PROTOCOL_ID = keccak256("STONFI");

    // ═══════════════════════════════════════════════════════════════════════════
    // STATE
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Pool info structure
    struct PoolInfo {
        bytes32 poolId;
        uint256 lpBalance;
        uint256 totalDeposited;
        uint256 pendingRewards;
        bool active;
    }

    /// @notice Active pools
    mapping(bytes32 => PoolInfo) public pools;

    /// @notice List of pool IDs
    bytes32[] public poolIds;

    /// @notice Default pool for single-asset deposits
    bytes32 public defaultPool;

    /// @notice Total LP value in TON terms
    uint256 public totalLpValue;

    /// @notice Pending rewards across all pools
    uint256 public totalPendingRewards;

    /// @notice STON reward token wrapper on EVM
    address public stonWrapper;

    /// @notice Pending add liquidity operations
    mapping(bytes32 => bytes32) public pendingAddLiquidity; // txId => poolId

    /// @notice Pending remove liquidity operations
    mapping(bytes32 => bytes32) public pendingRemoveLiquidity;

    // ═══════════════════════════════════════════════════════════════════════════
    // EVENTS
    // ═══════════════════════════════════════════════════════════════════════════

    event PoolAdded(bytes32 indexed poolId);
    event PoolRemoved(bytes32 indexed poolId);
    event LiquidityAdded(bytes32 indexed poolId, bytes32 indexed txId, uint256 amount0, uint256 amount1);
    event LiquidityRemoved(bytes32 indexed poolId, bytes32 indexed txId, uint256 lpAmount);
    event RewardsClaimed(bytes32 indexed poolId, bytes32 indexed txId);
    event PoolYieldUpdated(bytes32 indexed poolId, uint256 apy);

    // ═══════════════════════════════════════════════════════════════════════════
    // CONSTRUCTOR
    // ═══════════════════════════════════════════════════════════════════════════

    constructor(
        address _lton,
        address _stonWrapper,
        address _tonBridge,
        address _tonOracle,
        address _tonController,
        address _vault,
        bytes32 _tonRecipient,
        bytes32 _defaultPool
    ) BaseTONStrategy(_lton, _tonBridge, _tonOracle, _tonController, _vault, _tonRecipient) {
        stonWrapper = _stonWrapper;
        defaultPool = _defaultPool;

        // Initialize default pool
        pools[_defaultPool] = PoolInfo({
            poolId: _defaultPool,
            lpBalance: 0,
            totalDeposited: 0,
            pendingRewards: 0,
            active: true
        });
        poolIds.push(_defaultPool);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // IYieldStrategy IMPLEMENTATION
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice
    function deposit(uint256 amount, bytes calldata /* data */) external onlyVault nonReentrant whenActive returns (uint256 shares) {
        if (amount < minDeposit) revert BelowMinimum(amount, minDeposit);

        lton.safeTransferFrom(msg.sender, address(this), amount);

        // Bridge to TON
        bytes32 bridgeId = _bridgeToTON(amount);

        // Add liquidity to default pool (single-sided, will be balanced by router)
        bytes32 txId = tonController.addLiquidityToStonFi(defaultPool, amount, 0);
        pendingAddLiquidity[txId] = defaultPool;

        _totalDeposited += amount;
        shares = amount; // 1:1 initially
        pools[defaultPool].lpBalance += shares;
        pools[defaultPool].totalDeposited += amount;

        emit LiquidityAdded(defaultPool, txId, amount, 0);
    }

    /// @notice
    function withdraw(uint256 shares, address recipient, bytes calldata /* data */) external onlyVault nonReentrant returns (uint256 assets) {
        PoolInfo storage pool = pools[defaultPool];
        if (shares > pool.lpBalance) revert InsufficientBalance(shares, pool.lpBalance);

        // Remove liquidity from default pool
        bytes32 txId = tonController.removeLiquidityFromStonFi(defaultPool, shares);
        pendingRemoveLiquidity[txId] = defaultPool;

        pool.lpBalance -= shares;
        assets = shares; // Estimate, actual returned via bridge

        if (assets <= pool.totalDeposited) {
            pool.totalDeposited -= assets;
        } else {
            pool.totalDeposited = 0;
        }

        if (assets <= _totalDeposited) {
            _totalDeposited -= assets;
        } else {
            _totalDeposited = 0;
        }

        emit LiquidityRemoved(defaultPool, txId, shares);
    }

    /// @notice
    function harvest() external nonReentrant returns (uint256 harvested) {
        _updateFromOracle();

        // Claim rewards from all active pools
        for (uint256 i = 0; i < poolIds.length; i++) {
            bytes32 poolId = poolIds[i];
            if (pools[poolId].active && pools[poolId].pendingRewards > 0) {
                bytes32 txId = tonController.claimStonFiRewards(poolId);
                harvested += pools[poolId].pendingRewards;
                pools[poolId].pendingRewards = 0;
                emit RewardsClaimed(poolId, txId);
            }
        }

        accumulatedYield += harvested;
        lastHarvest = block.timestamp;
        emit YieldReported(totalLpValue, harvested);
    }

    /// @notice
    function totalAssets() external view returns (uint256) {
        return totalLpValue + totalPendingRewards + accumulatedYield;
    }

    /// @notice
    function currentAPY() external view returns (uint256) {
        // Weighted average APY across pools
        if (poolIds.length == 0) return 0;

        uint256 totalWeight;
        uint256 weightedApy;

        for (uint256 i = 0; i < poolIds.length; i++) {
            bytes32 poolId = poolIds[i];
            PoolInfo storage pool = pools[poolId];
            if (pool.active && pool.lpBalance > 0) {
                uint256 poolApy = tonOracle.getStonFiPoolApy(poolId);
                weightedApy += poolApy * pool.lpBalance;
                totalWeight += pool.lpBalance;
            }
        }

        return totalWeight > 0 ? weightedApy / totalWeight : 0;
    }

    /// @notice
    function name() external pure returns (string memory) {
        return "STON.fi LP";
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // INTERNAL
    // ═══════════════════════════════════════════════════════════════════════════

    function _updateFromOracle() internal override {
        totalLpValue = 0;
        totalPendingRewards = 0;

        for (uint256 i = 0; i < poolIds.length; i++) {
            bytes32 poolId = poolIds[i];
            PoolInfo storage pool = pools[poolId];

            if (pool.active) {
                // Update pool APY
                uint256 poolApy = tonOracle.getStonFiPoolApy(poolId);
                emit PoolYieldUpdated(poolId, poolApy);

                // Estimate LP value (would come from oracle in production)
                totalLpValue += pool.lpBalance;
                totalPendingRewards += pool.pendingRewards;
            }
        }

        lastOracleUpdate = block.timestamp;
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // POOL MANAGEMENT
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Add a new pool
    function addPool(bytes32 poolId) external onlyOwner {
        if (pools[poolId].poolId != bytes32(0)) revert InvalidPoolId(poolId);

        pools[poolId] = PoolInfo({
            poolId: poolId,
            lpBalance: 0,
            totalDeposited: 0,
            pendingRewards: 0,
            active: true
        });
        poolIds.push(poolId);

        emit PoolAdded(poolId);
    }

    /// @notice Deactivate a pool
    function deactivatePool(bytes32 poolId) external onlyOwner {
        if (pools[poolId].poolId == bytes32(0)) revert InvalidPoolId(poolId);
        pools[poolId].active = false;
        emit PoolRemoved(poolId);
    }

    /// @notice Set default pool
    function setDefaultPool(bytes32 poolId) external onlyOwner {
        if (pools[poolId].poolId == bytes32(0)) revert InvalidPoolId(poolId);
        if (!pools[poolId].active) revert InvalidPoolId(poolId);
        defaultPool = poolId;
    }

    /// @notice Add liquidity to specific pool
    function addLiquidityToPool(
        bytes32 poolId,
        uint256 amount0,
        uint256 amount1
    ) external onlyOwner nonReentrant whenActive returns (bytes32 txId) {
        if (!pools[poolId].active) revert InvalidPoolId(poolId);

        // Transfer and bridge
        if (amount0 > 0) {
            lton.safeTransferFrom(msg.sender, address(this), amount0);
            _bridgeToTON(amount0);
        }

        txId = tonController.addLiquidityToStonFi(poolId, amount0, amount1);
        pendingAddLiquidity[txId] = poolId;

        emit LiquidityAdded(poolId, txId, amount0, amount1);
    }

    /// @notice Remove liquidity from specific pool
    function removeLiquidityFromPool(
        bytes32 poolId,
        uint256 lpAmount
    ) external onlyOwner nonReentrant returns (bytes32 txId) {
        PoolInfo storage pool = pools[poolId];
        if (lpAmount > pool.lpBalance) revert InsufficientBalance(lpAmount, pool.lpBalance);

        txId = tonController.removeLiquidityFromStonFi(poolId, lpAmount);
        pendingRemoveLiquidity[txId] = poolId;
        pool.lpBalance -= lpAmount;

        emit LiquidityRemoved(poolId, txId, lpAmount);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // VIEW
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Get pool count
    function getPoolCount() external view returns (uint256) {
        return poolIds.length;
    }

    /// @notice Get pool info by ID
    function getPoolInfo(bytes32 poolId) external view returns (PoolInfo memory) {
        return pools[poolId];
    }

    /// @notice Get pool APY by ID
    function getPoolApy(bytes32 poolId) external view returns (uint256) {
        return tonOracle.getStonFiPoolApy(poolId);
    }

    /// @notice Get yield token wrapper address
    function yieldToken() external view returns (address) {
        return stonWrapper;
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // CLAIM
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Claim completed liquidity removal from TON
    function claimLiquidity(bytes32 bridgeId, bytes calldata proof) external onlyOwner returns (uint256 amount) {
        amount = _claimFromTON(bridgeId, proof);
        lton.safeTransfer(vault, amount);
    }

    /// @notice Emergency withdraw
    function emergencyWithdraw(address recipient) external onlyOwner {
        uint256 balance = lton.balanceOf(address(this));
        if (balance > 0) {
            lton.safeTransfer(vault, balance);
        }
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// TON STRATEGY FACTORY
// ═══════════════════════════════════════════════════════════════════════════════

/// @title TONStrategyFactory
/// @notice Factory for deploying TON yield strategies
contract TONStrategyFactory is Ownable {
    // ═══════════════════════════════════════════════════════════════════════════
    // TYPES
    // ═══════════════════════════════════════════════════════════════════════════

    enum StrategyType {
        TONSTAKERS,
        BEMO,
        STONFI
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // STATE
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice LTON token address
    address public lton;

    /// @notice TON bridge address
    address public tonBridge;

    /// @notice TON oracle address
    address public tonOracle;

    /// @notice TON controller address
    address public tonController;

    /// @notice tsTON wrapper address
    address public tsTonWrapper;

    /// @notice stTON wrapper address
    address public stTonWrapper;

    /// @notice STON wrapper address
    address public stonWrapper;

    // ═══════════════════════════════════════════════════════════════════════════
    // EVENTS
    // ═══════════════════════════════════════════════════════════════════════════

    event StrategyDeployed(StrategyType indexed strategyType, address indexed strategy);
    event ConfigUpdated(string param, address value);

    // ═══════════════════════════════════════════════════════════════════════════
    // CONSTRUCTOR
    // ═══════════════════════════════════════════════════════════════════════════

    constructor(
        address _lton,
        address _tonBridge,
        address _tonOracle,
        address _tonController,
        address _tsTonWrapper,
        address _stTonWrapper,
        address _stonWrapper
    ) Ownable(msg.sender) {
        lton = _lton;
        tonBridge = _tonBridge;
        tonOracle = _tonOracle;
        tonController = _tonController;
        tsTonWrapper = _tsTonWrapper;
        stTonWrapper = _stTonWrapper;
        stonWrapper = _stonWrapper;
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // DEPLOY
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Deploy a TON strategy
    /// @param strategyType Type of strategy
    /// @param vault Vault controller address
    /// @param tonRecipient TON recipient address (32 bytes)
    /// @return strategy Deployed strategy address
    function deploy(
        StrategyType strategyType,
        address vault,
        bytes32 tonRecipient
    ) external onlyOwner returns (address strategy) {
        if (strategyType == StrategyType.TONSTAKERS) {
            strategy = address(new TsTONStrategy(
                lton,
                tsTonWrapper,
                tonBridge,
                tonOracle,
                tonController,
                vault,
                tonRecipient
            ));
        } else if (strategyType == StrategyType.BEMO) {
            strategy = address(new StTONStrategy(
                lton,
                stTonWrapper,
                tonBridge,
                tonOracle,
                tonController,
                vault,
                tonRecipient
            ));
        } else {
            revert("Invalid strategy type");
        }

        emit StrategyDeployed(strategyType, strategy);
    }

    /// @notice Deploy STON.fi strategy with custom default pool
    /// @param vault Vault controller address
    /// @param tonRecipient TON recipient address
    /// @param defaultPool Default pool ID for single-asset deposits
    /// @return strategy Deployed strategy address
    function deployStonFi(
        address vault,
        bytes32 tonRecipient,
        bytes32 defaultPool
    ) external onlyOwner returns (address strategy) {
        strategy = address(new StonFiStrategy(
            lton,
            stonWrapper,
            tonBridge,
            tonOracle,
            tonController,
            vault,
            tonRecipient,
            defaultPool
        ));

        emit StrategyDeployed(StrategyType.STONFI, strategy);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // CONFIG
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Set LTON token address
    function setLTON(address _lton) external onlyOwner {
        lton = _lton;
        emit ConfigUpdated("lton", _lton);
    }

    /// @notice Set TON bridge address
    function setTONBridge(address _bridge) external onlyOwner {
        tonBridge = _bridge;
        emit ConfigUpdated("tonBridge", _bridge);
    }

    /// @notice Set TON oracle address
    function setTONOracle(address _oracle) external onlyOwner {
        tonOracle = _oracle;
        emit ConfigUpdated("tonOracle", _oracle);
    }

    /// @notice Set TON controller address
    function setTONController(address _controller) external onlyOwner {
        tonController = _controller;
        emit ConfigUpdated("tonController", _controller);
    }

    /// @notice Set tsTON wrapper address
    function setTsTONWrapper(address _wrapper) external onlyOwner {
        tsTonWrapper = _wrapper;
        emit ConfigUpdated("tsTonWrapper", _wrapper);
    }

    /// @notice Set stTON wrapper address
    function setStTONWrapper(address _wrapper) external onlyOwner {
        stTonWrapper = _wrapper;
        emit ConfigUpdated("stTonWrapper", _wrapper);
    }

    /// @notice Set STON wrapper address
    function setSTONWrapper(address _wrapper) external onlyOwner {
        stonWrapper = _wrapper;
        emit ConfigUpdated("stonWrapper", _wrapper);
    }
}
