// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "../synths/adapters/IYieldAdapter.sol";

/// @title Vault
/// @notice Lux yield vault - deposit collateral, earn yield, mint synths
/// @dev Multi-strategy vault with yield adapter support (AAVE, Compound, Yearn, etc.)
contract Vault is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // ═══════════════════════════════════════════════════════════════════════
    // TYPES
    // ═══════════════════════════════════════════════════════════════════════

    struct Strategy {
        IYieldAdapter adapter;      // Yield adapter contract
        uint256 allocation;         // Allocation weight (basis points)
        uint256 deposited;          // Amount deposited
        uint256 lastHarvest;        // Last harvest timestamp
        bool active;                // Strategy active flag
    }

    struct UserDeposit {
        uint256 shares;             // Vault shares
        uint256 debt;               // Synth debt owed
        uint256 depositTime;        // Deposit timestamp
    }

    // ═══════════════════════════════════════════════════════════════════════
    // CONSTANTS
    // ═══════════════════════════════════════════════════════════════════════

    uint256 public constant BASIS_POINTS = 10000;
    uint256 public constant MINIMUM_COLLATERAL_RATIO = 15000; // 150%
    uint256 public constant LIQUIDATION_RATIO = 11000;        // 110%
    uint256 public constant MAX_STRATEGIES = 10;

    // ═══════════════════════════════════════════════════════════════════════
    // STATE
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice Underlying collateral token (e.g., USDC, WETH)
    IERC20 public immutable underlying;

    /// @notice Synthetic token that can be minted (e.g., xUSD)
    address public synth;

    /// @notice Treasury for fees
    address public treasury;

    /// @notice Total vault shares
    uint256 public totalShares;

    /// @notice Total debt minted
    uint256 public totalDebt;

    /// @notice Deposit fee in basis points
    uint256 public depositFee = 0;

    /// @notice Withdrawal fee in basis points
    uint256 public withdrawalFee = 0;

    /// @notice Performance fee in basis points (on yield)
    uint256 public performanceFee = 1000; // 10%

    /// @notice Yield strategies
    Strategy[] public strategies;

    /// @notice User deposits
    mapping(address => UserDeposit) public deposits;

    // ═══════════════════════════════════════════════════════════════════════
    // EVENTS
    // ═══════════════════════════════════════════════════════════════════════

    event Deposited(address indexed user, uint256 amount, uint256 shares);
    event Withdrawn(address indexed user, uint256 amount, uint256 shares);
    event Minted(address indexed user, uint256 amount);
    event Burned(address indexed user, uint256 amount);
    event Liquidated(address indexed user, address indexed liquidator, uint256 debt, uint256 collateral);
    event StrategyAdded(uint256 indexed index, address adapter);
    event StrategyRemoved(uint256 indexed index);
    event Harvested(uint256 indexed strategyIndex, uint256 yield);
    event Rebalanced(uint256 totalDeposited);

    // ═══════════════════════════════════════════════════════════════════════
    // ERRORS
    // ═══════════════════════════════════════════════════════════════════════

    error ZeroAmount();
    error InsufficientShares();
    error InsufficientCollateral();
    error ExceedsMaxStrategies();
    error StrategyNotActive();
    error NotLiquidatable();
    error UnauthorizedMinter();

    // ═══════════════════════════════════════════════════════════════════════
    // CONSTRUCTOR
    // ═══════════════════════════════════════════════════════════════════════

    constructor(
        address _underlying,
        address _synth,
        address _treasury
    ) Ownable(msg.sender) {
        underlying = IERC20(_underlying);
        synth = _synth;
        treasury = _treasury;
    }

    // ═══════════════════════════════════════════════════════════════════════
    // DEPOSIT/WITHDRAW
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice Deposit collateral into the vault
    /// @param amount Amount of underlying to deposit
    /// @return shares Vault shares received
    function deposit(uint256 amount) external nonReentrant returns (uint256 shares) {
        if (amount == 0) revert ZeroAmount();

        // Calculate fee
        uint256 fee = amount * depositFee / BASIS_POINTS;
        uint256 netAmount = amount - fee;

        // Calculate shares
        shares = _calculateShares(netAmount);

        // Transfer tokens
        underlying.safeTransferFrom(msg.sender, address(this), amount);

        // Transfer fee to treasury
        if (fee > 0) {
            underlying.safeTransfer(treasury, fee);
        }

        // Update state
        deposits[msg.sender].shares += shares;
        deposits[msg.sender].depositTime = block.timestamp;
        totalShares += shares;

        // Deploy to strategies
        _deployToStrategies(netAmount);

        emit Deposited(msg.sender, amount, shares);
    }

    /// @notice Withdraw collateral from the vault
    /// @param shares Amount of shares to burn
    /// @return amount Underlying tokens received
    function withdraw(uint256 shares) external nonReentrant returns (uint256 amount) {
        if (shares == 0) revert ZeroAmount();
        if (deposits[msg.sender].shares < shares) revert InsufficientShares();

        // Check collateral ratio after withdrawal
        uint256 remainingShares = deposits[msg.sender].shares - shares;
        if (deposits[msg.sender].debt > 0) {
            uint256 remainingValue = _sharesToUnderlying(remainingShares);
            uint256 requiredCollateral = deposits[msg.sender].debt * MINIMUM_COLLATERAL_RATIO / BASIS_POINTS;
            if (remainingValue < requiredCollateral) revert InsufficientCollateral();
        }

        // Calculate amount
        amount = _sharesToUnderlying(shares);

        // Withdraw from strategies
        _withdrawFromStrategies(amount);

        // Calculate fee
        uint256 fee = amount * withdrawalFee / BASIS_POINTS;
        uint256 netAmount = amount - fee;

        // Update state
        deposits[msg.sender].shares -= shares;
        totalShares -= shares;

        // Transfer
        underlying.safeTransfer(msg.sender, netAmount);
        if (fee > 0) {
            underlying.safeTransfer(treasury, fee);
        }

        emit Withdrawn(msg.sender, amount, shares);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // SYNTH MINTING
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice Mint synthetic tokens against collateral
    /// @param amount Amount of synths to mint
    function mint(uint256 amount) external nonReentrant {
        if (amount == 0) revert ZeroAmount();

        // Check collateral ratio
        uint256 collateralValue = _sharesToUnderlying(deposits[msg.sender].shares);
        uint256 newDebt = deposits[msg.sender].debt + amount;
        uint256 requiredCollateral = newDebt * MINIMUM_COLLATERAL_RATIO / BASIS_POINTS;

        if (collateralValue < requiredCollateral) revert InsufficientCollateral();

        // Update debt
        deposits[msg.sender].debt = newDebt;
        totalDebt += amount;

        // Mint synths
        ISynthMinter(synth).mint(msg.sender, amount);

        emit Minted(msg.sender, amount);
    }

    /// @notice Burn synthetic tokens to reduce debt
    /// @param amount Amount of synths to burn
    function burn(uint256 amount) external nonReentrant {
        if (amount == 0) revert ZeroAmount();
        if (deposits[msg.sender].debt < amount) {
            amount = deposits[msg.sender].debt;
        }

        // Burn synths
        ISynthMinter(synth).burnFrom(msg.sender, amount);

        // Update debt
        deposits[msg.sender].debt -= amount;
        totalDebt -= amount;

        emit Burned(msg.sender, amount);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // LIQUIDATION
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice Liquidate an undercollateralized position
    /// @param user Position owner
    function liquidate(address user) external nonReentrant {
        UserDeposit storage userDeposit = deposits[user];
        
        if (userDeposit.debt == 0) revert NotLiquidatable();

        // Check if liquidatable
        uint256 collateralValue = _sharesToUnderlying(userDeposit.shares);
        uint256 minCollateral = userDeposit.debt * LIQUIDATION_RATIO / BASIS_POINTS;

        if (collateralValue >= minCollateral) revert NotLiquidatable();

        uint256 debt = userDeposit.debt;
        uint256 shares = userDeposit.shares;

        // Burn synths from liquidator
        ISynthMinter(synth).burnFrom(msg.sender, debt);

        // Calculate collateral to give liquidator (debt value + 10% bonus)
        uint256 collateralReward = debt * 11000 / BASIS_POINTS;
        if (collateralReward > collateralValue) {
            collateralReward = collateralValue;
        }

        // Withdraw from strategies
        _withdrawFromStrategies(collateralReward);

        // Clear user position
        uint256 remainingCollateral = collateralValue - collateralReward;
        if (remainingCollateral > 0) {
            // Convert remaining to shares
            deposits[user].shares = remainingCollateral * totalShares / _totalAssets();
        } else {
            deposits[user].shares = 0;
        }
        deposits[user].debt = 0;

        // Update totals
        totalDebt -= debt;
        totalShares -= shares - deposits[user].shares;

        // Transfer to liquidator
        underlying.safeTransfer(msg.sender, collateralReward);

        emit Liquidated(user, msg.sender, debt, collateralReward);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // STRATEGY MANAGEMENT
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice Add a new yield strategy
    /// @param adapter Yield adapter address
    /// @param allocation Allocation weight in basis points
    function addStrategy(address adapter, uint256 allocation) external onlyOwner {
        if (strategies.length >= MAX_STRATEGIES) revert ExceedsMaxStrategies();

        strategies.push(Strategy({
            adapter: IYieldAdapter(adapter),
            allocation: allocation,
            deposited: 0,
            lastHarvest: block.timestamp,
            active: true
        }));

        // Approve adapter
        underlying.forceApprove(adapter, type(uint256).max);

        emit StrategyAdded(strategies.length - 1, adapter);
    }

    /// @notice Remove a strategy
    /// @param index Strategy index
    function removeStrategy(uint256 index) external onlyOwner {
        Strategy storage strategy = strategies[index];
        
        // Withdraw all from strategy
        if (strategy.deposited > 0) {
            strategy.adapter.unwrap(strategy.deposited, address(this));
        }

        strategy.active = false;
        strategy.allocation = 0;

        emit StrategyRemoved(index);
    }

    /// @notice Update strategy allocation
    /// @param index Strategy index
    /// @param allocation New allocation
    function setAllocation(uint256 index, uint256 allocation) external onlyOwner {
        strategies[index].allocation = allocation;
    }

    /// @notice Harvest yield from a strategy
    /// @param index Strategy index
    function harvest(uint256 index) external returns (uint256 harvested) {
        Strategy storage strategy = strategies[index];
        if (!strategy.active) revert StrategyNotActive();

        harvested = strategy.adapter.harvest();

        // Take performance fee
        if (harvested > 0) {
            uint256 fee = harvested * performanceFee / BASIS_POINTS;
            underlying.safeTransfer(treasury, fee);
        }

        strategy.lastHarvest = block.timestamp;

        emit Harvested(index, harvested);
    }

    /// @notice Harvest all strategies
    function harvestAll() external returns (uint256 totalHarvested) {
        for (uint256 i = 0; i < strategies.length; i++) {
            if (strategies[i].active) {
                totalHarvested += strategies[i].adapter.harvest();
            }
        }

        if (totalHarvested > 0) {
            uint256 fee = totalHarvested * performanceFee / BASIS_POINTS;
            underlying.safeTransfer(treasury, fee);
        }
    }

    /// @notice Rebalance funds across strategies
    function rebalance() external onlyOwner {
        uint256 total = _totalAssets();
        uint256 totalAllocation = _totalAllocation();

        for (uint256 i = 0; i < strategies.length; i++) {
            Strategy storage strategy = strategies[i];
            if (!strategy.active) continue;

            uint256 targetAmount = total * strategy.allocation / totalAllocation;

            if (strategy.deposited > targetAmount) {
                // Withdraw excess
                uint256 excess = strategy.deposited - targetAmount;
                strategy.adapter.unwrap(excess, address(this));
                strategy.deposited -= excess;
            } else if (strategy.deposited < targetAmount) {
                // Deposit more
                uint256 needed = targetAmount - strategy.deposited;
                strategy.adapter.wrap(needed, address(this));
                strategy.deposited += needed;
            }
        }

        emit Rebalanced(total);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // VIEW FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice Get user's collateral value in underlying
    function getCollateralValue(address user) external view returns (uint256) {
        return _sharesToUnderlying(deposits[user].shares);
    }

    /// @notice Get user's health factor (collateral ratio)
    function getHealthFactor(address user) external view returns (uint256) {
        if (deposits[user].debt == 0) return type(uint256).max;
        
        uint256 collateralValue = _sharesToUnderlying(deposits[user].shares);
        return collateralValue * BASIS_POINTS / deposits[user].debt;
    }

    /// @notice Get max mintable synths for user
    function getMaxMintable(address user) external view returns (uint256) {
        uint256 collateralValue = _sharesToUnderlying(deposits[user].shares);
        uint256 maxDebt = collateralValue * BASIS_POINTS / MINIMUM_COLLATERAL_RATIO;
        
        if (maxDebt <= deposits[user].debt) return 0;
        return maxDebt - deposits[user].debt;
    }

    /// @notice Get total assets under management
    function totalAssets() external view returns (uint256) {
        return _totalAssets();
    }

    /// @notice Get share price
    function sharePrice() external view returns (uint256) {
        if (totalShares == 0) return 1e18;
        return _totalAssets() * 1e18 / totalShares;
    }

    /// @notice Get number of strategies
    function strategyCount() external view returns (uint256) {
        return strategies.length;
    }

    // ═══════════════════════════════════════════════════════════════════════
    // ADMIN FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════

    function setFees(
        uint256 _depositFee,
        uint256 _withdrawalFee,
        uint256 _performanceFee
    ) external onlyOwner {
        require(_depositFee <= 500, "Max 5%");
        require(_withdrawalFee <= 500, "Max 5%");
        require(_performanceFee <= 3000, "Max 30%");
        
        depositFee = _depositFee;
        withdrawalFee = _withdrawalFee;
        performanceFee = _performanceFee;
    }

    function setTreasury(address _treasury) external onlyOwner {
        treasury = _treasury;
    }

    // ═══════════════════════════════════════════════════════════════════════
    // INTERNAL FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════

    function _calculateShares(uint256 amount) internal view returns (uint256) {
        if (totalShares == 0) return amount;
        return amount * totalShares / _totalAssets();
    }

    function _sharesToUnderlying(uint256 shares) internal view returns (uint256) {
        if (totalShares == 0) return 0;
        return shares * _totalAssets() / totalShares;
    }

    function _totalAssets() internal view returns (uint256 total) {
        total = underlying.balanceOf(address(this));
        for (uint256 i = 0; i < strategies.length; i++) {
            if (strategies[i].active) {
                total += strategies[i].deposited;
            }
        }
    }

    function _totalAllocation() internal view returns (uint256 total) {
        for (uint256 i = 0; i < strategies.length; i++) {
            if (strategies[i].active) {
                total += strategies[i].allocation;
            }
        }
    }

    function _deployToStrategies(uint256 amount) internal {
        uint256 totalAllocation = _totalAllocation();
        if (totalAllocation == 0) return;

        for (uint256 i = 0; i < strategies.length; i++) {
            Strategy storage strategy = strategies[i];
            if (!strategy.active) continue;

            uint256 strategyAmount = amount * strategy.allocation / totalAllocation;
            if (strategyAmount > 0) {
                underlying.forceApprove(address(strategy.adapter), strategyAmount);
                strategy.adapter.wrap(strategyAmount, address(this));
                strategy.deposited += strategyAmount;
            }
        }
    }

    function _withdrawFromStrategies(uint256 amount) internal {
        uint256 idle = underlying.balanceOf(address(this));
        
        if (idle >= amount) return;

        uint256 needed = amount - idle;

        // Withdraw proportionally from strategies
        for (uint256 i = 0; i < strategies.length && needed > 0; i++) {
            Strategy storage strategy = strategies[i];
            if (!strategy.active || strategy.deposited == 0) continue;

            uint256 withdrawAmount = needed > strategy.deposited ? strategy.deposited : needed;
            strategy.adapter.unwrap(withdrawAmount, address(this));
            strategy.deposited -= withdrawAmount;
            needed -= withdrawAmount;
        }
    }
}

/// @notice Interface for synth minting
interface ISynthMinter {
    function mint(address to, uint256 amount) external;
    function burnFrom(address from, uint256 amount) external;
}
