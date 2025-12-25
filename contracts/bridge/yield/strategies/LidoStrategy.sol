// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import "../IYieldStrategy.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/// @title Lido stETH Yield Strategies
/// @notice Yield strategies for Lido liquid staking and Curve LP staking
/// @dev Provides three strategy variants:
///      - StETHStrategy: Direct stETH staking (rebasing)
///      - WstETHStrategy: Wrapped stETH (non-rebasing, better for DeFi)
///      - LidoCurveStrategy: stETH/ETH Curve pool with gauge rewards
///
/// Yield Sources:
/// - ETH staking yield (~3.5-4.5% APY)
/// - Curve LP trading fees (variable)
/// - CRV/LDO gauge emissions (variable)

// =============================================================================
// LIDO INTERFACES
// =============================================================================

/// @notice Lido stETH interface
interface ILido {
    function submit(address _referral) external payable returns (uint256);
    function getSharesByPooledEth(uint256 _ethAmount) external view returns (uint256);
    function getPooledEthByShares(uint256 _sharesAmount) external view returns (uint256);
    function getTotalPooledEther() external view returns (uint256);
    function getTotalShares() external view returns (uint256);
    function balanceOf(address _account) external view returns (uint256);
    function sharesOf(address _account) external view returns (uint256);
    function transferShares(address _recipient, uint256 _sharesAmount) external returns (uint256);
    function transferSharesFrom(address _sender, address _recipient, uint256 _sharesAmount) external returns (uint256);
    function approve(address _spender, uint256 _amount) external returns (bool);
    function allowance(address _owner, address _spender) external view returns (uint256);
    function getCurrentStakeLimit() external view returns (uint256);
    function isStakingPaused() external view returns (bool);
}

/// @notice Wrapped stETH (wstETH) interface
interface IWstETH {
    function wrap(uint256 _stETHAmount) external returns (uint256);
    function unwrap(uint256 _wstETHAmount) external returns (uint256);
    function getWstETHByStETH(uint256 _stETHAmount) external view returns (uint256);
    function getStETHByWstETH(uint256 _wstETHAmount) external view returns (uint256);
    function stEthPerToken() external view returns (uint256);
    function tokensPerStEth() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address recipient, uint256 amount) external returns (bool);
    function approve(address spender, uint256 amount) external returns (bool);
    function stETH() external view returns (address);
}

/// @notice Lido Withdrawal Queue interface
interface ILidoWithdrawalQueue {
    struct WithdrawalRequestStatus {
        uint256 amountOfStETH;
        uint256 amountOfShares;
        address owner;
        uint256 timestamp;
        bool isFinalized;
        bool isClaimed;
    }
    function requestWithdrawals(uint256[] calldata _amounts, address _owner) external returns (uint256[] memory requestIds);
    function requestWithdrawalsWstETH(uint256[] calldata _amounts, address _owner) external returns (uint256[] memory requestIds);
    function claimWithdrawals(uint256[] calldata _requestIds, uint256[] calldata _hints) external;
    function claimWithdrawal(uint256 _requestId) external;
    function getWithdrawalStatus(uint256[] calldata _requestIds) external view returns (WithdrawalRequestStatus[] memory statuses);
    function getLastFinalizedRequestId() external view returns (uint256);
    function getLastRequestId() external view returns (uint256);
    function findCheckpointHints(uint256[] calldata _requestIds, uint256 _firstIndex, uint256 _lastIndex) external view returns (uint256[] memory hintIds);
    function getClaimableEther(uint256[] calldata _requestIds, uint256[] calldata _hints) external view returns (uint256[] memory claimableEth);
    function MIN_STETH_WITHDRAWAL_AMOUNT() external view returns (uint256);
    function MAX_STETH_WITHDRAWAL_AMOUNT() external view returns (uint256);
}

/// @notice Curve stETH/ETH pool interface
interface ICurveStETHPool {
    function exchange(int128 i, int128 j, uint256 dx, uint256 min_dy) external payable returns (uint256);
    function add_liquidity(uint256[2] memory amounts, uint256 min_mint_amount) external payable returns (uint256);
    function remove_liquidity(uint256 _amount, uint256[2] memory min_amounts) external returns (uint256[2] memory);
    function remove_liquidity_one_coin(uint256 _token_amount, int128 i, uint256 _min_amount) external returns (uint256);
    function get_virtual_price() external view returns (uint256);
    function calc_token_amount(uint256[2] memory amounts, bool is_deposit) external view returns (uint256);
    function calc_withdraw_one_coin(uint256 _token_amount, int128 i) external view returns (uint256);
    function balances(uint256 i) external view returns (uint256);
    function coins(uint256 i) external view returns (address);
}

/// @notice Curve Gauge interface for staking LP tokens
interface ICurveGauge {
    function deposit(uint256 _value) external;
    function withdraw(uint256 _value) external;
    function claim_rewards() external;
    function claimable_reward(address _addr, address _token) external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function reward_tokens(uint256 index) external view returns (address);
    function reward_count() external view returns (uint256);
    function integrate_fraction(address user) external view returns (uint256);
}

/// @notice Curve Minter for claiming CRV rewards
interface ICurveMinter {
    function mint(address gauge_addr) external;
    function minted(address user, address gauge) external view returns (uint256);
}

// =============================================================================
// STETH STRATEGY - Direct Rebasing stETH
// =============================================================================

/// @title StETH Strategy
/// @notice Direct ETH staking via Lido to receive rebasing stETH
/// @dev stETH balance increases over time as staking rewards accrue
///      Best for: Simple exposure to Lido staking yield
///      Considerations: Rebasing may cause issues with some DeFi protocols
contract StETHStrategy is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // =========================================================================
    // CONSTANTS
    // =========================================================================

    /// @notice Lido stETH contract (Mainnet)
    address public constant STETH = 0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84;

    /// @notice Lido Withdrawal Queue (Mainnet)
    address public constant WITHDRAWAL_QUEUE = 0x889edC2eDab5f40e902b864aD4d7AdE8E412F9B1;

    /// @notice Basis points denominator
    uint256 public constant BPS = 10_000;

    /// @notice Approximate annual staking APY (updated periodically)
    uint256 public constant DEFAULT_APY_BPS = 400; // 4.0%

    // =========================================================================
    // STATE
    // =========================================================================

    /// @notice Vault that controls this strategy
    address public vault;

    /// @notice stETH shares tracked (for accurate accounting despite rebasing)
    uint256 public stethShares;

    /// @notice Total deposited ETH (for accounting)
    uint256 public _totalDeposited;

    /// @notice Pending withdrawal request IDs
    uint256[] public pendingWithdrawals;

    /// @notice Referral address for Lido submissions
    address public referral;

    /// @notice Whether strategy is accepting deposits
    bool public active;

    /// @notice Last recorded total pooled ether (for APY calculation)
    uint256 public lastTotalPooled;

    /// @notice Timestamp of last APY snapshot
    uint256 public lastSnapshotTime;

    /// @notice Calculated APY in basis points
    uint256 public calculatedAPY;

    // =========================================================================
    // EVENTS
    // =========================================================================

    /// @notice Emitted when ETH is staked for stETH
    event Staked(address indexed user, uint256 ethAmount, uint256 stethReceived, uint256 sharesReceived);

    /// @notice Emitted when withdrawal is requested
    event WithdrawalRequested(uint256 indexed requestId, uint256 stethAmount, uint256 sharesAmount);

    /// @notice Emitted when withdrawal is claimed
    event Claimed(uint256 indexed requestId, uint256 ethAmount);

    /// @notice Emitted when vault is updated
    event VaultUpdated(address indexed oldVault, address indexed newVault);

    /// @notice Emitted when referral is updated
    event ReferralUpdated(address indexed oldReferral, address indexed newReferral);

    /// @notice Emitted when strategy is activated/deactivated
    event ActiveStatusChanged(bool active);

    /// @notice Emitted when APY is updated
    event APYUpdated(uint256 oldAPY, uint256 newAPY);

    // =========================================================================
    // ERRORS
    // =========================================================================

    /// @notice Caller is not the vault
    error OnlyVault();

    /// @notice Strategy is not active
    error StrategyNotActive();

    /// @notice Lido staking is paused
    error StakingPaused();

    /// @notice Amount exceeds stake limit
    error ExceedsStakeLimit(uint256 amount, uint256 limit);

    /// @notice Zero amount not allowed
    error ZeroAmount();

    /// @notice Withdrawal not finalized
    error WithdrawalNotFinalized(uint256 requestId);

    /// @notice Invalid withdrawal request
    error InvalidWithdrawalRequest(uint256 requestId);

    // =========================================================================
    // MODIFIERS
    // =========================================================================

    modifier onlyVault() {
        if (msg.sender != vault) revert OnlyVault();
        _;
    }

    modifier whenActive() {
        if (!active) revert StrategyNotActive();
        _;
    }

    // =========================================================================
    // CONSTRUCTOR
    // =========================================================================

    /// @notice Deploy stETH strategy
    /// @param _vault Initial vault address
    /// @param _referral Lido referral address
    constructor(address _vault, address _referral) Ownable(msg.sender) {
        vault = _vault;
        referral = _referral;
        active = true;
        calculatedAPY = DEFAULT_APY_BPS;
        lastSnapshotTime = block.timestamp;
        lastTotalPooled = ILido(STETH).getTotalPooledEther();
    }

    // =========================================================================
    // IYIELDSTRATEGY IMPLEMENTATION
    // =========================================================================

    /// @notice
    function deposit(uint256 amount, bytes calldata /* data */) external onlyVault whenActive nonReentrant returns (uint256 shares) {
        if (amount == 0) revert ZeroAmount();

        ILido steth = ILido(STETH);

        // Check staking limits
        if (steth.isStakingPaused()) revert StakingPaused();
        uint256 stakeLimit = steth.getCurrentStakeLimit();
        if (amount > stakeLimit) revert ExceedsStakeLimit(amount, stakeLimit);

        // Transfer ETH from vault (vault must send ETH with call)
        // Get shares before deposit
        uint256 sharesBefore = steth.sharesOf(address(this));

        // Submit ETH to Lido
        uint256 stethReceived = steth.submit{value: amount}(referral);

        // Calculate actual shares received
        uint256 sharesAfter = steth.sharesOf(address(this));
        shares = sharesAfter - sharesBefore;
        stethShares += shares;
        _totalDeposited += amount;

        emit Staked(msg.sender, amount, stethReceived, shares);
    }

    /// @notice
    function withdraw(uint256 amount, address recipient, bytes calldata /* data */) external onlyVault nonReentrant returns (uint256 assets) {
        if (amount == 0) revert ZeroAmount();
        
        ILido steth = ILido(STETH);
        
        // Convert amount to shares if needed
        uint256 sharesToWithdraw = steth.getSharesByPooledEth(amount);
        if (sharesToWithdraw > stethShares) sharesToWithdraw = stethShares;
        
        assets = steth.getPooledEthByShares(sharesToWithdraw);

        ILidoWithdrawalQueue queue = ILidoWithdrawalQueue(WITHDRAWAL_QUEUE);

        // Check withdrawal limits
        uint256 minAmount = queue.MIN_STETH_WITHDRAWAL_AMOUNT();
        uint256 maxAmount = queue.MAX_STETH_WITHDRAWAL_AMOUNT();

        // Handle amount splitting if needed
        uint256[] memory amounts = _splitWithdrawalAmounts(assets, minAmount, maxAmount);

        // Approve withdrawal queue
        steth.approve(WITHDRAWAL_QUEUE, assets);

        // Request withdrawals - recipient will claim later
        uint256[] memory requestIds = queue.requestWithdrawals(amounts, recipient);

        // Track pending withdrawals
        for (uint256 i = 0; i < requestIds.length; i++) {
            pendingWithdrawals.push(requestIds[i]);
            emit WithdrawalRequested(requestIds[i], amounts[i], steth.getSharesByPooledEth(amounts[i]));
        }

        // Update shares tracking
        stethShares -= sharesToWithdraw;
        if (_totalDeposited >= assets) {
            _totalDeposited -= assets;
        } else {
            _totalDeposited = 0;
        }
    }

    /// @notice
    function totalAssets() external view returns (uint256) {
        ILido steth = ILido(STETH);
        return steth.getPooledEthByShares(stethShares);
    }

    /// @notice
    function totalDeposited() external view returns (uint256) {
        return _totalDeposited;
    }

    /// @notice
    function currentAPY() external view returns (uint256) {
        return calculatedAPY;
    }

    /// @notice
    function asset() external pure returns (address) {
        return address(0); // Native ETH
    }

    /// @notice
    function harvest() external onlyVault returns (uint256 harvested) {
        // For stETH, yield is automatically captured via rebasing
        // This function updates APY calculation and claims any finalized withdrawals
        _updateAPY();
        harvested = _claimFinalizedWithdrawals();
    }

    /// @notice
    function isActive() external view returns (bool) {
        return active && !ILido(STETH).isStakingPaused();
    }

    /// @notice
    function name() external pure returns (string memory) {
        return "Lido stETH Strategy";
    }

    // =========================================================================
    // ADDITIONAL VIEW FUNCTIONS
    // =========================================================================

    /// @notice Get the yield token address (stETH)
    /// @return stETH address
    function yieldToken() external pure returns (address) {
        return STETH;
    }

    // =========================================================================
    // WITHDRAWAL MANAGEMENT
    // =========================================================================

    /// @notice Claim finalized withdrawals
    /// @return claimed Total ETH claimed
    function claimWithdrawals() external nonReentrant returns (uint256 claimed) {
        claimed = _claimFinalizedWithdrawals();
    }

    /// @notice Get pending withdrawal status
    /// @return statuses Array of withdrawal statuses
    function getPendingWithdrawals() external view returns (ILidoWithdrawalQueue.WithdrawalRequestStatus[] memory statuses) {
        if (pendingWithdrawals.length == 0) {
            return new ILidoWithdrawalQueue.WithdrawalRequestStatus[](0);
        }
        return ILidoWithdrawalQueue(WITHDRAWAL_QUEUE).getWithdrawalStatus(pendingWithdrawals);
    }

    /// @notice Get number of pending withdrawals
    /// @return Number of pending withdrawal requests
    function pendingWithdrawalCount() external view returns (uint256) {
        return pendingWithdrawals.length;
    }

    // =========================================================================
    // ADMIN FUNCTIONS
    // =========================================================================

    /// @notice Update vault address
    /// @param _vault New vault address
    function setVault(address _vault) external onlyOwner {
        emit VaultUpdated(vault, _vault);
        vault = _vault;
    }

    /// @notice Update referral address
    /// @param _referral New referral address
    function setReferral(address _referral) external onlyOwner {
        emit ReferralUpdated(referral, _referral);
        referral = _referral;
    }

    /// @notice Set strategy active status
    /// @param _active Whether strategy is active
    function setActive(bool _active) external onlyOwner {
        active = _active;
        emit ActiveStatusChanged(_active);
    }

    /// @notice Emergency withdraw all assets
    /// @param recipient Address to receive assets
    function emergencyWithdraw(address recipient) external onlyOwner {
        ILido steth = ILido(STETH);
        uint256 balance = steth.balanceOf(address(this));
        if (balance > 0) {
            IERC20(STETH).safeTransfer(vault, balance);
        }
        stethShares = 0;
        _totalDeposited = 0;
    }

    // =========================================================================
    // INTERNAL FUNCTIONS
    // =========================================================================

    /// @notice Split amount into valid withdrawal chunks
    function _splitWithdrawalAmounts(
        uint256 amount,
        uint256 minAmount,
        uint256 maxAmount
    ) internal pure returns (uint256[] memory amounts) {
        if (amount < minAmount) {
            amounts = new uint256[](1);
            amounts[0] = minAmount;
            return amounts;
        }

        uint256 numChunks = (amount + maxAmount - 1) / maxAmount;
        amounts = new uint256[](numChunks);

        uint256 remaining = amount;
        for (uint256 i = 0; i < numChunks; i++) {
            amounts[i] = remaining > maxAmount ? maxAmount : remaining;
            remaining -= amounts[i];
        }
    }

    /// @notice Claim finalized withdrawals
    function _claimFinalizedWithdrawals() internal returns (uint256 claimed) {
        if (pendingWithdrawals.length == 0) return 0;

        ILidoWithdrawalQueue queue = ILidoWithdrawalQueue(WITHDRAWAL_QUEUE);
        ILidoWithdrawalQueue.WithdrawalRequestStatus[] memory statuses = 
            queue.getWithdrawalStatus(pendingWithdrawals);

        uint256 balanceBefore = address(this).balance;

        // Process finalized withdrawals
        uint256 writeIndex = 0;
        for (uint256 i = 0; i < pendingWithdrawals.length; i++) {
            if (statuses[i].isFinalized && !statuses[i].isClaimed) {
                queue.claimWithdrawal(pendingWithdrawals[i]);
                emit Claimed(pendingWithdrawals[i], statuses[i].amountOfStETH);
            } else if (!statuses[i].isClaimed) {
                // Keep unfinalized/unclaimed requests
                pendingWithdrawals[writeIndex++] = pendingWithdrawals[i];
            }
        }

        // Resize array
        while (pendingWithdrawals.length > writeIndex) {
            pendingWithdrawals.pop();
        }

        claimed = address(this).balance - balanceBefore;

        // Forward claimed ETH to vault
        if (claimed > 0 && vault != address(0)) {
            (bool success, ) = vault.call{value: claimed}("");
            require(success, "ETH transfer failed");
        }
    }

    /// @notice Update APY calculation
    function _updateAPY() internal {
        ILido steth = ILido(STETH);
        uint256 currentTotal = steth.getTotalPooledEther();
        uint256 timeDelta = block.timestamp - lastSnapshotTime;

        if (timeDelta >= 1 days && lastTotalPooled > 0) {
            // Calculate rate of increase
            uint256 increase = currentTotal > lastTotalPooled ? currentTotal - lastTotalPooled : 0;
            uint256 ratePerSecond = (increase * 1e18) / (lastTotalPooled * timeDelta);
            uint256 annualRate = ratePerSecond * 365 days;
            uint256 newAPY = (annualRate * BPS) / 1e18;

            if (newAPY != calculatedAPY) {
                emit APYUpdated(calculatedAPY, newAPY);
                calculatedAPY = newAPY;
            }

            lastTotalPooled = currentTotal;
            lastSnapshotTime = block.timestamp;
        }
    }

    /// @notice Receive ETH from withdrawal claims
    receive() external payable {}
}

// =============================================================================
// WSTETH STRATEGY - Wrapped Non-Rebasing stETH
// =============================================================================

/// @title WstETH Strategy
/// @notice Wrapped stETH strategy for non-rebasing yield exposure
/// @dev wstETH wraps stETH in a non-rebasing token:
///      - Balance stays constant, share value increases
///      - Better for DeFi integrations (no rebase accounting issues)
///      - Same underlying yield as stETH
contract WstETHStrategy is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // =========================================================================
    // CONSTANTS
    // =========================================================================

    /// @notice Lido stETH contract (Mainnet)
    address public constant STETH = 0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84;

    /// @notice Wrapped stETH contract (Mainnet)
    address public constant WSTETH = 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0;

    /// @notice Lido Withdrawal Queue (Mainnet)
    address public constant WITHDRAWAL_QUEUE = 0x889edC2eDab5f40e902b864aD4d7AdE8E412F9B1;

    /// @notice Basis points denominator
    uint256 public constant BPS = 10_000;

    /// @notice Default APY (same as stETH)
    uint256 public constant DEFAULT_APY_BPS = 400;

    // =========================================================================
    // STATE
    // =========================================================================

    /// @notice Vault that controls this strategy
    address public vault;

    /// @notice wstETH balance held
    uint256 public wstethBalance;

    /// @notice Total deposited ETH (for accounting)
    uint256 public _totalDeposited;

    /// @notice Pending withdrawal request IDs
    uint256[] public pendingWithdrawals;

    /// @notice Referral address for Lido submissions
    address public referral;

    /// @notice Whether strategy is active
    bool public active;

    /// @notice Calculated APY in basis points
    uint256 public calculatedAPY;

    // =========================================================================
    // EVENTS
    // =========================================================================

    /// @notice Emitted when ETH is staked and wrapped
    event Staked(address indexed user, uint256 ethAmount, uint256 stethReceived);

    /// @notice Emitted when stETH is wrapped to wstETH
    event Wrapped(uint256 stethAmount, uint256 wstethReceived);

    /// @notice Emitted when wstETH is unwrapped
    event Unwrapped(uint256 wstethAmount, uint256 stethReceived);

    /// @notice Emitted when withdrawal is requested
    event WithdrawalRequested(uint256 indexed requestId, uint256 wstethAmount);

    /// @notice Emitted when withdrawal is claimed
    event Claimed(uint256 indexed requestId, uint256 ethAmount);

    /// @notice Emitted when vault is updated
    event VaultUpdated(address indexed oldVault, address indexed newVault);

    /// @notice Emitted when strategy is activated/deactivated
    event ActiveStatusChanged(bool active);

    // =========================================================================
    // ERRORS
    // =========================================================================

    /// @notice Caller is not the vault
    error OnlyVault();

    /// @notice Strategy is not active
    error StrategyNotActive();

    /// @notice Lido staking is paused
    error StakingPaused();

    /// @notice Zero amount not allowed
    error ZeroAmount();

    /// @notice Insufficient balance
    error InsufficientBalance(uint256 requested, uint256 available);

    // =========================================================================
    // MODIFIERS
    // =========================================================================

    modifier onlyVault() {
        if (msg.sender != vault) revert OnlyVault();
        _;
    }

    modifier whenActive() {
        if (!active) revert StrategyNotActive();
        _;
    }

    // =========================================================================
    // CONSTRUCTOR
    // =========================================================================

    /// @notice Deploy wstETH strategy
    /// @param _vault Initial vault address
    /// @param _referral Lido referral address
    constructor(address _vault, address _referral) Ownable(msg.sender) {
        vault = _vault;
        referral = _referral;
        active = true;
        calculatedAPY = DEFAULT_APY_BPS;
    }

    // =========================================================================
    // IYIELDSTRATEGY IMPLEMENTATION
    // =========================================================================

    /// @notice
    function deposit(uint256 amount, bytes calldata /* data */) external onlyVault whenActive nonReentrant returns (uint256 shares) {
        if (amount == 0) revert ZeroAmount();

        ILido steth = ILido(STETH);
        IWstETH wsteth = IWstETH(WSTETH);

        if (steth.isStakingPaused()) revert StakingPaused();

        // Submit ETH to Lido
        uint256 stethReceived = steth.submit{value: amount}(referral);
        emit Staked(msg.sender, amount, stethReceived);

        // Approve and wrap to wstETH
        steth.approve(WSTETH, stethReceived);
        shares = wsteth.wrap(stethReceived);
        wstethBalance += shares;
        _totalDeposited += amount;

        emit Wrapped(stethReceived, shares);
    }

    /// @notice
    function withdraw(uint256 amount, address recipient, bytes calldata /* data */) external onlyVault nonReentrant returns (uint256 assets) {
        if (amount == 0) revert ZeroAmount();

        IWstETH wsteth = IWstETH(WSTETH);
        
        // Convert ETH amount to wstETH shares
        uint256 wstethAmount = wsteth.getWstETHByStETH(amount);
        if (wstethAmount > wstethBalance) revert InsufficientBalance(wstethAmount, wstethBalance);

        ILidoWithdrawalQueue queue = ILidoWithdrawalQueue(WITHDRAWAL_QUEUE);

        // Unwrap wstETH to stETH
        uint256 stethAmount = wsteth.unwrap(wstethAmount);
        emit Unwrapped(wstethAmount, stethAmount);

        // Request withdrawal - recipient will claim
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = stethAmount;

        IERC20(STETH).safeIncreaseAllowance(WITHDRAWAL_QUEUE, stethAmount);
        uint256[] memory requestIds = queue.requestWithdrawals(amounts, recipient);

        pendingWithdrawals.push(requestIds[0]);
        wstethBalance -= wstethAmount;

        emit WithdrawalRequested(requestIds[0], wstethAmount);

        // Return expected ETH amount
        assets = stethAmount;
        if (_totalDeposited >= assets) {
            _totalDeposited -= assets;
        } else {
            _totalDeposited = 0;
        }
    }

    /// @notice
    function totalAssets() external view returns (uint256) {
        IWstETH wsteth = IWstETH(WSTETH);
        uint256 stethAmount = wsteth.getStETHByWstETH(wstethBalance);
        return stethAmount;
    }

    /// @notice
    function totalDeposited() external view returns (uint256) {
        return _totalDeposited;
    }

    /// @notice
    function currentAPY() external view returns (uint256) {
        return calculatedAPY;
    }

    /// @notice
    function asset() external pure returns (address) {
        return address(0); // Native ETH
    }

    /// @notice
    function harvest() external onlyVault returns (uint256 harvested) {
        // wstETH is non-rebasing, so no explicit harvest needed
        // Just claim any finalized withdrawals
        harvested = _claimFinalizedWithdrawals();
    }

    /// @notice
    function isActive() external view returns (bool) {
        return active && !ILido(STETH).isStakingPaused();
    }

    /// @notice
    function name() external pure returns (string memory) {
        return "Lido wstETH Strategy";
    }

    // =========================================================================
    // VIEW FUNCTIONS
    // =========================================================================

    /// @notice Get the yield token address (wstETH)
    /// @return wstETH address
    function yieldToken() external pure returns (address) {
        return WSTETH;
    }

    /// @notice Get wstETH to stETH exchange rate
    /// @return stETH amount per wstETH
    function stEthPerWstEth() external view returns (uint256) {
        return IWstETH(WSTETH).stEthPerToken();
    }

    /// @notice Get pending withdrawal count
    /// @return Number of pending withdrawals
    function pendingWithdrawalCount() external view returns (uint256) {
        return pendingWithdrawals.length;
    }

    // =========================================================================
    // ADMIN FUNCTIONS
    // =========================================================================

    /// @notice Update vault address
    /// @param _vault New vault address
    function setVault(address _vault) external onlyOwner {
        emit VaultUpdated(vault, _vault);
        vault = _vault;
    }

    /// @notice Set strategy active status
    /// @param _active Whether strategy is active
    function setActive(bool _active) external onlyOwner {
        active = _active;
        emit ActiveStatusChanged(_active);
    }

    /// @notice Emergency withdraw all assets
    /// @param recipient Address to receive assets
    function emergencyWithdraw(address recipient) external onlyOwner {
        uint256 balance = IERC20(WSTETH).balanceOf(address(this));
        if (balance > 0) {
            IERC20(WSTETH).safeTransfer(vault, balance);
        }
        wstethBalance = 0;
        _totalDeposited = 0;
    }

    // =========================================================================
    // INTERNAL FUNCTIONS
    // =========================================================================

    /// @notice Claim finalized withdrawals
    function _claimFinalizedWithdrawals() internal returns (uint256 claimed) {
        if (pendingWithdrawals.length == 0) return 0;

        ILidoWithdrawalQueue queue = ILidoWithdrawalQueue(WITHDRAWAL_QUEUE);
        ILidoWithdrawalQueue.WithdrawalRequestStatus[] memory statuses = 
            queue.getWithdrawalStatus(pendingWithdrawals);

        uint256 balanceBefore = address(this).balance;

        uint256 writeIndex = 0;
        for (uint256 i = 0; i < pendingWithdrawals.length; i++) {
            if (statuses[i].isFinalized && !statuses[i].isClaimed) {
                queue.claimWithdrawal(pendingWithdrawals[i]);
                emit Claimed(pendingWithdrawals[i], statuses[i].amountOfStETH);
            } else if (!statuses[i].isClaimed) {
                pendingWithdrawals[writeIndex++] = pendingWithdrawals[i];
            }
        }

        while (pendingWithdrawals.length > writeIndex) {
            pendingWithdrawals.pop();
        }

        claimed = address(this).balance - balanceBefore;

        if (claimed > 0 && vault != address(0)) {
            (bool success, ) = vault.call{value: claimed}("");
            require(success, "ETH transfer failed");
        }
    }

    /// @notice Receive ETH from withdrawal claims
    receive() external payable {}
}

// =============================================================================
// LIDO CURVE STRATEGY - stETH/ETH Curve LP + Gauge
// =============================================================================

/// @title Lido Curve Strategy
/// @notice stETH/ETH Curve LP with gauge staking for CRV/LDO rewards
/// @dev Provides triple yield:
///      1. stETH staking rewards (rebasing)
///      2. Curve trading fees
///      3. CRV + LDO gauge emissions
contract LidoCurveStrategy is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // =========================================================================
    // CONSTANTS
    // =========================================================================

    /// @notice Lido stETH contract (Mainnet)
    address public constant STETH = 0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84;

    /// @notice Curve stETH/ETH pool (Mainnet)
    address public constant CURVE_POOL = 0xDC24316b9AE028F1497c275EB9192a3Ea0f67022;

    /// @notice Curve stETH/ETH LP token
    address public constant CURVE_LP = 0x06325440D014e39736583c165C2963BA99fAf14E;

    /// @notice Curve stETH gauge (Mainnet)
    address public constant CURVE_GAUGE = 0x182B723a58739a9c974cFDB385ceaDb237453c28;

    /// @notice Curve CRV token
    address public constant CRV = 0xD533a949740bb3306d119CC777fa900bA034cd52;

    /// @notice Curve Minter for CRV emissions
    address public constant CURVE_MINTER = 0xd061D61a4d941c39E5453435B6345Dc261C2fcE0;

    /// @notice Lido LDO token
    address public constant LDO = 0x5A98FcBEA516Cf06857215779Fd812CA3beF1B32;

    /// @notice Pool coin indices
    int128 public constant ETH_INDEX = 0;
    int128 public constant STETH_INDEX = 1;

    /// @notice Basis points denominator
    uint256 public constant BPS = 10_000;

    // =========================================================================
    // STATE
    // =========================================================================

    /// @notice Vault that controls this strategy
    address public vault;

    /// @notice LP tokens staked in gauge
    uint256 public stakedLP;

    /// @notice Total deposited ETH (for accounting)
    uint256 public _totalDeposited;

    /// @notice Referral address for Lido submissions
    address public referral;

    /// @notice Whether strategy is active
    bool public active;

    /// @notice Reward recipient (defaults to vault)
    address public rewardRecipient;

    /// @notice Accumulated CRV rewards
    uint256 public accumulatedCRV;

    /// @notice Accumulated LDO rewards
    uint256 public accumulatedLDO;

    /// @notice Slippage tolerance for Curve operations (in BPS)
    uint256 public slippageTolerance;

    // =========================================================================
    // EVENTS
    // =========================================================================

    /// @notice Emitted when liquidity is added to Curve
    event LiquidityAdded(uint256 ethAmount, uint256 stethAmount, uint256 lpReceived);

    /// @notice Emitted when liquidity is removed from Curve
    event LiquidityRemoved(uint256 lpBurned, uint256 ethReceived, uint256 stethReceived);

    /// @notice Emitted when LP is staked in gauge
    event Staked(uint256 lpAmount);

    /// @notice Emitted when LP is unstaked from gauge
    event Unstaked(uint256 lpAmount);

    /// @notice Emitted when rewards are claimed
    event RewardsClaimed(uint256 crvAmount, uint256 ldoAmount);

    /// @notice Emitted when vault is updated
    event VaultUpdated(address indexed oldVault, address indexed newVault);

    /// @notice Emitted when strategy is activated/deactivated
    event ActiveStatusChanged(bool active);

    /// @notice Emitted when slippage tolerance is updated
    event SlippageToleranceUpdated(uint256 oldTolerance, uint256 newTolerance);

    // =========================================================================
    // ERRORS
    // =========================================================================

    /// @notice Caller is not the vault
    error OnlyVault();

    /// @notice Strategy is not active
    error StrategyNotActive();

    /// @notice Lido staking is paused
    error StakingPaused();

    /// @notice Zero amount not allowed
    error ZeroAmount();

    /// @notice Slippage exceeded
    error SlippageExceeded(uint256 expected, uint256 received);

    /// @notice Invalid slippage tolerance
    error InvalidSlippageTolerance(uint256 tolerance);

    /// @notice Insufficient LP balance
    error InsufficientLPBalance(uint256 requested, uint256 available);

    // =========================================================================
    // MODIFIERS
    // =========================================================================

    modifier onlyVault() {
        if (msg.sender != vault) revert OnlyVault();
        _;
    }

    modifier whenActive() {
        if (!active) revert StrategyNotActive();
        _;
    }

    // =========================================================================
    // CONSTRUCTOR
    // =========================================================================

    /// @notice Deploy Lido Curve strategy
    /// @param _vault Initial vault address
    /// @param _referral Lido referral address
    /// @param _slippageTolerance Initial slippage tolerance in BPS (e.g., 50 = 0.5%)
    constructor(
        address _vault, 
        address _referral,
        uint256 _slippageTolerance
    ) Ownable(msg.sender) {
        if (_slippageTolerance > 500) revert InvalidSlippageTolerance(_slippageTolerance);
        
        vault = _vault;
        referral = _referral;
        rewardRecipient = _vault;
        slippageTolerance = _slippageTolerance;
        active = true;
    }

    // =========================================================================
    // IYIELDSTRATEGY IMPLEMENTATION
    // =========================================================================

    /// @notice
    function deposit(uint256 amount) external onlyVault whenActive nonReentrant returns (uint256 shares) {
        if (amount == 0) revert ZeroAmount();

        ILido steth = ILido(STETH);
        ICurveStETHPool pool = ICurveStETHPool(CURVE_POOL);
        ICurveGauge gauge = ICurveGauge(CURVE_GAUGE);

        if (steth.isStakingPaused()) revert StakingPaused();

        // Split 50/50 between ETH and stETH for balanced liquidity
        uint256 ethForLP = amount / 2;
        uint256 ethForSteth = amount - ethForLP;

        // Submit half to Lido
        uint256 stethReceived = steth.submit{value: ethForSteth}(referral);

        // Approve stETH for Curve pool
        steth.approve(CURVE_POOL, stethReceived);

        // Calculate minimum LP tokens expected (with slippage)
        uint256[2] memory amounts = [ethForLP, stethReceived];
        uint256 expectedLP = pool.calc_token_amount(amounts, true);
        uint256 minLP = (expectedLP * (BPS - slippageTolerance)) / BPS;

        // Add liquidity to Curve
        uint256 lpReceived = pool.add_liquidity{value: ethForLP}(amounts, minLP);
        emit LiquidityAdded(ethForLP, stethReceived, lpReceived);

        // Approve and stake in gauge
        IERC20(CURVE_LP).safeIncreaseAllowance(CURVE_GAUGE, lpReceived);
        gauge.deposit(lpReceived);
        stakedLP += lpReceived;
        _totalDeposited += amount;
        shares = lpReceived;

        emit Staked(lpReceived);
    }

    /// @notice
    function withdraw(uint256 amount, address recipient, bytes calldata /* data */) external onlyVault nonReentrant returns (uint256 assets) {
        if (amount == 0) revert ZeroAmount();

        ICurveStETHPool pool = ICurveStETHPool(CURVE_POOL);
        ICurveGauge gauge = ICurveGauge(CURVE_GAUGE);

        // Calculate LP tokens to withdraw for the requested ETH amount
        uint256 vPrice = pool.get_virtual_price();
        uint256 lpToWithdraw = (amount * 1e18) / vPrice;
        
        if (lpToWithdraw > stakedLP) revert InsufficientLPBalance(lpToWithdraw, stakedLP);

        // Unstake from gauge
        gauge.withdraw(lpToWithdraw);
        stakedLP -= lpToWithdraw;
        emit Unstaked(lpToWithdraw);

        // Calculate minimum ETH expected (withdraw as single-sided ETH)
        uint256 expectedETH = pool.calc_withdraw_one_coin(lpToWithdraw, ETH_INDEX);
        uint256 minETH = (expectedETH * (BPS - slippageTolerance)) / BPS;

        // Remove liquidity as ETH only
        assets = pool.remove_liquidity_one_coin(lpToWithdraw, ETH_INDEX, minETH);

        // Forward ETH to recipient
        if (assets > 0 && recipient != address(0)) {
            (bool success, ) = recipient.call{value: assets}("");
            require(success, "ETH transfer failed");
        }

        if (_totalDeposited >= assets) {
            _totalDeposited -= assets;
        } else {
            _totalDeposited = 0;
        }

        emit LiquidityRemoved(lpToWithdraw, assets, 0);
    }

    /// @notice
    function totalAssets() external view returns (uint256) {
        if (stakedLP == 0) return 0;

        ICurveStETHPool pool = ICurveStETHPool(CURVE_POOL);
        uint256 vPrice = pool.get_virtual_price();

        // LP value in ETH terms
        return (stakedLP * vPrice) / 1e18;
    }

    /// @notice
    function totalDeposited() external view returns (uint256) {
        return _totalDeposited;
    }

    /// @notice
    function currentAPY() external view returns (uint256) {
        // Curve APY is highly variable, return conservative estimate
        // Real APY = stETH yield + trading fees + CRV emissions + LDO emissions
        // This is a simplified estimate
        return 600; // 6% APY estimate (4% stETH + 2% rewards)
    }

    /// @notice
    function asset() external pure returns (address) {
        return address(0); // Native ETH
    }

    /// @notice
    function harvest() external onlyVault returns (uint256 harvested) {
        harvested = _claimRewards();
    }

    /// @notice
    function isActive() external view returns (bool) {
        return active && !ILido(STETH).isStakingPaused();
    }

    /// @notice
    function name() external pure returns (string memory) {
        return "Lido Curve stETH/ETH Strategy";
    }

    // =========================================================================
    // VIEW FUNCTIONS
    // =========================================================================

    /// @notice Get the yield token address (Curve LP)
    /// @return Curve LP token address
    function yieldToken() external pure returns (address) {
        return CURVE_LP;
    }

    // =========================================================================
    // REWARD FUNCTIONS
    // =========================================================================

    /// @notice Claim all pending rewards (CRV + LDO)
    /// @return totalValue Estimated ETH value of rewards
    function claimRewards() external nonReentrant returns (uint256 totalValue) {
        totalValue = _claimRewards();
    }

    /// @notice Get pending CRV rewards
    /// @return Pending CRV amount
    function pendingCRV() external view returns (uint256) {
        ICurveGauge gauge = ICurveGauge(CURVE_GAUGE);
        return gauge.claimable_reward(address(this), CRV);
    }

    /// @notice Get pending LDO rewards
    /// @return Pending LDO amount
    function pendingLDO() external view returns (uint256) {
        ICurveGauge gauge = ICurveGauge(CURVE_GAUGE);
        return gauge.claimable_reward(address(this), LDO);
    }

    /// @notice Get pool virtual price
    /// @return Virtual price (1e18 scale)
    function getVirtualPrice() external view returns (uint256) {
        return ICurveStETHPool(CURVE_POOL).get_virtual_price();
    }

    // =========================================================================
    // ADMIN FUNCTIONS
    // =========================================================================

    /// @notice Update vault address
    /// @param _vault New vault address
    function setVault(address _vault) external onlyOwner {
        emit VaultUpdated(vault, _vault);
        vault = _vault;
        rewardRecipient = _vault;
    }

    /// @notice Set strategy active status
    /// @param _active Whether strategy is active
    function setActive(bool _active) external onlyOwner {
        active = _active;
        emit ActiveStatusChanged(_active);
    }

    /// @notice Update slippage tolerance
    /// @param _slippageTolerance New tolerance in BPS
    function setSlippageTolerance(uint256 _slippageTolerance) external onlyOwner {
        if (_slippageTolerance > 500) revert InvalidSlippageTolerance(_slippageTolerance);
        emit SlippageToleranceUpdated(slippageTolerance, _slippageTolerance);
        slippageTolerance = _slippageTolerance;
    }

    /// @notice Set reward recipient
    /// @param _recipient New reward recipient
    function setRewardRecipient(address _recipient) external onlyOwner {
        rewardRecipient = _recipient;
    }

    /// @notice Emergency withdraw all assets
    /// @param recipient Address to receive assets
    function emergencyWithdraw(address recipient) external onlyOwner {
        ICurveGauge gauge = ICurveGauge(CURVE_GAUGE);

        // Unstake all from gauge
        if (stakedLP > 0) {
            gauge.withdraw(stakedLP);
            stakedLP = 0;
        }

        // Transfer LP tokens
        uint256 lpBalance = IERC20(CURVE_LP).balanceOf(address(this));
        if (lpBalance > 0) {
            IERC20(CURVE_LP).safeTransfer(vault, lpBalance);
        }

        // Transfer any CRV
        uint256 crvBalance = IERC20(CRV).balanceOf(address(this));
        if (crvBalance > 0) {
            IERC20(CRV).safeTransfer(vault, crvBalance);
        }

        // Transfer any LDO
        uint256 ldoBalance = IERC20(LDO).balanceOf(address(this));
        if (ldoBalance > 0) {
            IERC20(LDO).safeTransfer(vault, ldoBalance);
        }

        // Transfer any ETH
        uint256 ethBalance = address(this).balance;
        if (ethBalance > 0) {
            (bool success, ) = recipient.call{value: ethBalance}("");
            require(success, "ETH transfer failed");
        }

        _totalDeposited = 0;
    }

    // =========================================================================
    // INTERNAL FUNCTIONS
    // =========================================================================

    /// @notice Claim CRV and LDO rewards
    function _claimRewards() internal returns (uint256 totalValue) {
        ICurveGauge gauge = ICurveGauge(CURVE_GAUGE);
        ICurveMinter minter = ICurveMinter(CURVE_MINTER);

        // Claim CRV from minter
        uint256 crvBefore = IERC20(CRV).balanceOf(address(this));
        minter.mint(CURVE_GAUGE);
        uint256 crvClaimed = IERC20(CRV).balanceOf(address(this)) - crvBefore;

        // Claim gauge rewards (LDO)
        uint256 ldoBefore = IERC20(LDO).balanceOf(address(this));
        gauge.claim_rewards();
        uint256 ldoClaimed = IERC20(LDO).balanceOf(address(this)) - ldoBefore;

        accumulatedCRV += crvClaimed;
        accumulatedLDO += ldoClaimed;

        emit RewardsClaimed(crvClaimed, ldoClaimed);

        // Transfer rewards to recipient
        if (rewardRecipient != address(0)) {
            if (crvClaimed > 0) {
                IERC20(CRV).safeTransfer(rewardRecipient, crvClaimed);
            }
            if (ldoClaimed > 0) {
                IERC20(LDO).safeTransfer(rewardRecipient, ldoClaimed);
            }
        }

        // Return placeholder value (actual ETH conversion would need oracle)
        totalValue = crvClaimed + ldoClaimed;
    }

    /// @notice Receive ETH
    receive() external payable {}
}

// =============================================================================
// FACTORY
// =============================================================================

/// @title Lido Strategy Factory
/// @notice Factory for deploying Lido yield strategies
contract LidoStrategyFactory {

    /// @notice Strategy type identifiers
    bytes32 public constant STETH = keccak256("LIDO_STETH");
    bytes32 public constant WSTETH = keccak256("LIDO_WSTETH");
    bytes32 public constant CURVE = keccak256("LIDO_CURVE");

    /// @notice Emitted when a strategy is deployed
    event StrategyDeployed(
        bytes32 indexed strategyType,
        address indexed strategy,
        address indexed vault
    );

    /// @notice Deploy a new Lido strategy
    /// @param strategyType Type of strategy (STETH, WSTETH, CURVE)
    /// @param vault Vault address
    /// @param referral Lido referral address
    /// @param slippageTolerance Slippage tolerance for Curve strategy (ignored for others)
    /// @return strategy Address of deployed strategy
    function deploy(
        bytes32 strategyType,
        address vault,
        address referral,
        uint256 slippageTolerance
    ) external returns (address strategy) {
        if (strategyType == STETH) {
            strategy = address(new StETHStrategy(vault, referral));
        } else if (strategyType == WSTETH) {
            strategy = address(new WstETHStrategy(vault, referral));
        } else if (strategyType == CURVE) {
            strategy = address(new LidoCurveStrategy(vault, referral, slippageTolerance));
        } else {
            revert("Invalid strategy type");
        }

        emit StrategyDeployed(strategyType, strategy, vault);
    }
}
