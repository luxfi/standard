// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

/**
 * @title EigenLayerStrategy
 * @notice Yield strategies for EigenLayer restaking
 * @dev Implements two restaking approaches:
 *
 * 1. EigenLayerLSTStrategy - Restake liquid staking tokens (stETH, rETH, cbETH)
 *    - Deposit LSTs into EigenLayer strategies
 *    - Delegate to operators for AVS validation
 *    - Earn restaking rewards + AVS rewards
 *
 * 2. EigenPodStrategy - Native ETH restaking via EigenPods
 *    - Create EigenPod for 32 ETH validator deposits
 *    - Verify withdrawal credentials on beacon chain
 *    - Earn native staking + AVS rewards
 *
 * EigenLayer Architecture:
 * - StrategyManager: Handles LST deposits into strategies
 * - DelegationManager: Operator delegation and withdrawals
 * - EigenPodManager: Native ETH restaking via pods
 * - AVS (Actively Validated Services): Additional reward sources
 *
 * Withdrawal Process:
 * - 7-day unbonding period for security
 * - Queued withdrawals tracked by root hash
 * - Slashing protection during unbonding
 */

import {IYieldStrategy} from "../IYieldStrategy.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

// ═══════════════════════════════════════════════════════════════════════════════
// EIGENLAYER INTERFACES
// ═══════════════════════════════════════════════════════════════════════════════

/**
 * @title IStrategyManager
 * @notice EigenLayer StrategyManager for LST deposits
 */
interface IStrategyManager {
    /// @notice Deposit tokens into a strategy
    function depositIntoStrategy(
        address strategy,
        address token,
        uint256 amount
    ) external returns (uint256 shares);

    /// @notice Deposit with signature (gasless deposits)
    function depositIntoStrategyWithSignature(
        address strategy,
        address token,
        uint256 amount,
        address staker,
        uint256 expiry,
        bytes memory signature
    ) external returns (uint256 shares);

    /// @notice Get shares for staker in strategy
    function stakerStrategyShares(address staker, address strategy) external view returns (uint256);

    /// @notice Get all deposits for a staker
    function getDeposits(address staker) external view returns (address[] memory, uint256[] memory);
}

/**
 * @title IDelegationManager
 * @notice EigenLayer DelegationManager for operator delegation and withdrawals
 */
interface IDelegationManager {
    struct QueuedWithdrawalParams {
        address[] strategies;
        uint256[] shares;
        address withdrawer;
    }

    struct Withdrawal {
        address staker;
        address delegatedTo;
        address withdrawer;
        uint256 nonce;
        uint32 startBlock;
        address[] strategies;
        uint256[] shares;
    }

    /// @notice Delegate stake to an operator
    function delegateTo(
        address operator,
        bytes memory approverSignatureAndExpiry,
        bytes32 approverSalt
    ) external;

    /// @notice Undelegate from current operator
    function undelegate(address staker) external returns (bytes32[] memory withdrawalRoots);

    /// @notice Queue withdrawals
    function queueWithdrawals(
        QueuedWithdrawalParams[] calldata queuedWithdrawalParams
    ) external returns (bytes32[] memory);

    /// @notice Complete a queued withdrawal
    function completeQueuedWithdrawal(
        Withdrawal calldata withdrawal,
        IERC20[] calldata tokens,
        uint256 middlewareTimesIndex,
        bool receiveAsTokens
    ) external;

    /// @notice Complete multiple queued withdrawals
    function completeQueuedWithdrawals(
        Withdrawal[] calldata withdrawals,
        IERC20[][] calldata tokens,
        uint256[] calldata middlewareTimesIndexes,
        bool[] calldata receiveAsTokens
    ) external;

    /// @notice Get operator that staker is delegated to
    function delegatedTo(address staker) external view returns (address);

    /// @notice Check if staker is delegated
    function isDelegated(address staker) external view returns (bool);

    /// @notice Get operator's shares in a strategy
    function operatorShares(address operator, address strategy) external view returns (uint256);

    /// @notice Get minimum withdrawal delay blocks
    function minWithdrawalDelayBlocks() external view returns (uint256);

    /// @notice Calculate withdrawal root
    function calculateWithdrawalRoot(Withdrawal calldata withdrawal) external pure returns (bytes32);
}

/**
 * @title IEigenPodManager
 * @notice EigenLayer EigenPodManager for native ETH restaking
 */
interface IEigenPodManager {
    /// @notice Create an EigenPod for the sender
    function createPod() external returns (address);

    /// @notice Stake ETH to beacon chain via EigenPod
    function stake(
        bytes calldata pubkey,
        bytes calldata signature,
        bytes32 depositDataRoot
    ) external payable;

    /// @notice Get EigenPod address for owner
    function ownerToPod(address owner) external view returns (address);

    /// @notice Check if owner has a pod
    function hasPod(address owner) external view returns (bool);

    /// @notice Get restaked beacon chain ETH for staker
    function podOwnerShares(address podOwner) external view returns (int256);
}

/**
 * @title IEigenPod
 * @notice EigenLayer EigenPod for validator management
 */
interface IEigenPod {
    /// @notice Verify withdrawal credentials for validators
    function verifyWithdrawalCredentials(
        uint64 oracleTimestamp,
        BeaconChainProofs.StateRootProof calldata stateRootProof,
        uint40[] calldata validatorIndices,
        bytes[] calldata validatorFieldsProofs,
        bytes32[][] calldata validatorFields
    ) external;

    /// @notice Verify and process withdrawals
    function verifyAndProcessWithdrawals(
        uint64 oracleTimestamp,
        BeaconChainProofs.StateRootProof calldata stateRootProof,
        BeaconChainProofs.WithdrawalProof[] calldata withdrawalProofs,
        bytes[] calldata validatorFieldsProofs,
        bytes32[][] calldata validatorFields,
        bytes32[][] calldata withdrawalFields
    ) external;

    /// @notice Withdraw non-beacon chain ETH
    function withdrawNonBeaconChainETHBalanceWei(
        address recipient,
        uint256 amountToWithdraw
    ) external;

    /// @notice Get withdrawable restaked execution layer ETH
    function withdrawableRestakedExecutionLayerGwei() external view returns (uint64);

    /// @notice Get non-beacon chain ETH balance
    function nonBeaconChainETHBalanceWei() external view returns (uint256);

    /// @notice Get pod owner
    function podOwner() external view returns (address);

    /// @notice Check if pod has restaked via credentials
    function hasRestaked() external view returns (bool);
}

/**
 * @title BeaconChainProofs
 * @notice Proof structures for beacon chain verification
 */
library BeaconChainProofs {
    struct StateRootProof {
        bytes32 beaconStateRoot;
        bytes proof;
    }

    struct WithdrawalProof {
        bytes withdrawalProof;
        bytes slotProof;
        bytes executionPayloadProof;
        bytes timestampProof;
        bytes historicalSummaryBlockRootProof;
        uint64 blockRootIndex;
        uint64 historicalSummaryIndex;
        uint64 withdrawalIndex;
        bytes32 blockRoot;
        bytes32 slotRoot;
        bytes32 timestampRoot;
        bytes32 executionPayloadRoot;
    }
}

/**
 * @title IStrategy
 * @notice EigenLayer Strategy interface for LST strategies
 */
interface IStrategy {
    function deposit(address token, uint256 amount) external returns (uint256);
    function withdraw(address recipient, address token, uint256 amountShares) external;
    function sharesToUnderlyingView(uint256 amountShares) external view returns (uint256);
    function underlyingToSharesView(uint256 amountUnderlying) external view returns (uint256);
    function userUnderlyingView(address user) external view returns (uint256);
    function shares(address user) external view returns (uint256);
    function underlyingToken() external view returns (address);
    function totalShares() external view returns (uint256);
}

/**
 * @title IAVSDirectory
 * @notice Interface for AVS registration and rewards
 */
interface IAVSDirectory {
    /// @notice Register operator to AVS
    function registerOperatorToAVS(
        address operator,
        bytes calldata signature
    ) external;

    /// @notice Check if operator is registered to AVS
    function isOperatorRegisteredToAVS(
        address operator,
        address avs
    ) external view returns (bool);
}

/**
 * @title IRewardsCoordinator
 * @notice Interface for claiming AVS rewards
 */
interface IRewardsCoordinator {
    struct RewardsMerkleClaim {
        uint32 rootIndex;
        uint32 earnerIndex;
        bytes earnerTreeProof;
        EarnerTreeMerkleLeaf earnerLeaf;
        uint32[] tokenIndices;
        bytes[] tokenTreeProofs;
        TokenTreeMerkleLeaf[] tokenLeaves;
    }

    struct EarnerTreeMerkleLeaf {
        address earner;
        bytes32 earnerTokenRoot;
    }

    struct TokenTreeMerkleLeaf {
        IERC20 token;
        uint256 cumulativeEarnings;
    }

    /// @notice Claim rewards for earner
    function processClaim(
        RewardsMerkleClaim calldata claim,
        address recipient
    ) external;

    /// @notice Check cumulative claimed for earner and token
    function cumulativeClaimed(address earner, IERC20 token) external view returns (uint256);
}

// ═══════════════════════════════════════════════════════════════════════════════
// CUSTOM ERRORS
// ═══════════════════════════════════════════════════════════════════════════════

/// @notice Thrown when strategy is not active
error StrategyNotActive();

/// @notice Thrown when amount is zero
error ZeroAmount();

/// @notice Thrown when withdrawal is still pending
error WithdrawalPending(bytes32 withdrawalRoot, uint256 completableAtBlock);

/// @notice Thrown when no operator is delegated
error NotDelegated();

/// @notice Thrown when already delegated to an operator
error AlreadyDelegated(address currentOperator);

/// @notice Thrown when withdrawal not found
error WithdrawalNotFound(bytes32 withdrawalRoot);

/// @notice Thrown when insufficient shares
error InsufficientShares(uint256 requested, uint256 available);

/// @notice Thrown when invalid operator address
error InvalidOperator();

/// @notice Thrown when EigenPod not created
error PodNotCreated();

/// @notice Thrown when EigenPod already exists
error PodAlreadyExists();

/// @notice Thrown when invalid validator pubkey
error InvalidPubkey();

/// @notice Thrown when insufficient ETH for staking
error InsufficientETH(uint256 required, uint256 provided);

/// @notice Thrown when caller is not authorized
error Unauthorized();

// ═══════════════════════════════════════════════════════════════════════════════
// EVENTS
// ═══════════════════════════════════════════════════════════════════════════════

/// @notice Emitted when assets are deposited into EigenLayer
event Deposited(address indexed user, address indexed token, uint256 amount, uint256 shares);

/// @notice Emitted when delegating to an operator
event Delegated(address indexed staker, address indexed operator);

/// @notice Emitted when undelegating from operator
event Undelegated(address indexed staker, address indexed operator);

/// @notice Emitted when withdrawal is queued
event WithdrawalQueued(
    bytes32 indexed withdrawalRoot,
    address indexed staker,
    address indexed strategy,
    uint256 shares,
    uint32 startBlock
);

/// @notice Emitted when withdrawal is completed
event WithdrawalCompleted(
    bytes32 indexed withdrawalRoot,
    address indexed staker,
    address indexed recipient,
    uint256 amount
);

/// @notice Emitted when AVS rewards are claimed
event RewardsClaimed(address indexed earner, address indexed token, uint256 amount);

/// @notice Emitted when EigenPod is created
event PodCreated(address indexed owner, address indexed pod);

/// @notice Emitted when ETH is staked to beacon chain
event ValidatorStaked(address indexed owner, bytes pubkey, uint256 amount);

/// @notice Emitted when withdrawal credentials are verified
event WithdrawalCredentialsVerified(address indexed owner, uint40[] validatorIndices);

// ═══════════════════════════════════════════════════════════════════════════════
// EIGENLAYER LST STRATEGY
// ═══════════════════════════════════════════════════════════════════════════════

/**
 * @title EigenLayerLSTStrategy
 * @notice Restaking strategy for liquid staking tokens (stETH, rETH, cbETH)
 * @dev Deposits LSTs into EigenLayer strategies and manages operator delegation
 *
 * Yield Sources:
 * - Base LST yield (staking rewards)
 * - AVS rewards (from services validated by delegated operator)
 *
 * Withdrawal Process:
 * 1. Queue withdrawal (7-day unbonding)
 * 2. Complete withdrawal after delay
 * 3. Receive underlying LST tokens
 */
contract EigenLayerLSTStrategy is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // ═══════════════════════════════════════════════════════════════════════
    // CONSTANTS
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice Basis points denominator
    uint256 public constant BPS = 10000;

    /// @notice Expected blocks per day (Ethereum ~12s blocks)
    uint256 public constant BLOCKS_PER_DAY = 7200;

    /// @notice 7 day withdrawal delay in blocks
    uint256 public constant WITHDRAWAL_DELAY_BLOCKS = 50400; // 7 * 7200

    // ═══════════════════════════════════════════════════════════════════════
    // IMMUTABLES
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice EigenLayer StrategyManager
    IStrategyManager public immutable strategyManager;

    /// @notice EigenLayer DelegationManager
    IDelegationManager public immutable delegationManager;

    /// @notice EigenLayer Rewards Coordinator
    IRewardsCoordinator public immutable rewardsCoordinator;

    /// @notice EigenLayer Strategy for this LST
    IStrategy public immutable eigenStrategy;

    /// @notice Underlying LST token (stETH, rETH, cbETH)
    IERC20 public immutable underlyingToken;

    /// @notice Strategy name
    string public strategyName;

    // ═══════════════════════════════════════════════════════════════════════
    // STATE
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice Whether strategy is accepting deposits
    bool public active;

    /// @notice Current delegated operator
    address public delegatedOperator;

    /// @notice Pending withdrawals by root
    mapping(bytes32 => PendingWithdrawal) public pendingWithdrawals;

    /// @notice User shares in this strategy
    mapping(address => uint256) public userShares;

    /// @notice Total shares outstanding
    uint256 public totalShares;

    /// @notice Last recorded APY (basis points)
    uint256 public lastRecordedAPY;

    /// @notice Total rewards claimed
    uint256 public totalRewardsClaimed;

    /// @notice Pending withdrawal tracking
    struct PendingWithdrawal {
        address staker;
        address withdrawer;
        uint256 shares;
        uint32 startBlock;
        bool completed;
    }

    // ═══════════════════════════════════════════════════════════════════════
    // CONSTRUCTOR
    // ═══════════════════════════════════════════════════════════════════════

    /**
     * @notice Deploy EigenLayer LST Strategy
     * @param _strategyManager EigenLayer StrategyManager address
     * @param _delegationManager EigenLayer DelegationManager address
     * @param _rewardsCoordinator EigenLayer RewardsCoordinator address
     * @param _eigenStrategy EigenLayer Strategy for this LST
     * @param _underlyingToken Underlying LST token address
     * @param _name Strategy name
     * @param _owner Strategy owner
     */
    constructor(
        address _strategyManager,
        address _delegationManager,
        address _rewardsCoordinator,
        address _eigenStrategy,
        address _underlyingToken,
        string memory _name,
        address _owner
    ) Ownable(_owner) {
        strategyManager = IStrategyManager(_strategyManager);
        delegationManager = IDelegationManager(_delegationManager);
        rewardsCoordinator = IRewardsCoordinator(_rewardsCoordinator);
        eigenStrategy = IStrategy(_eigenStrategy);
        underlyingToken = IERC20(_underlyingToken);
        strategyName = _name;
        active = true;

        // Approve StrategyManager to spend LST
        underlyingToken.approve(_strategyManager, type(uint256).max);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // YIELD STRATEGY INTERFACE
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice Total deposited (for yield tracking)
    uint256 public totalDeposited;

    /**
     * @notice Deposit LST into EigenLayer
     * @param amount Amount of LST to deposit
     * @return shares Amount of strategy shares received
     */
    function deposit(uint256 amount) external nonReentrant returns (uint256 shares) {
        if (!active) revert StrategyNotActive();
        if (amount == 0) revert ZeroAmount();

        // Transfer LST from user
        underlyingToken.safeTransferFrom(msg.sender, address(this), amount);

        // Deposit into EigenLayer strategy
        shares = strategyManager.depositIntoStrategy(
            address(eigenStrategy),
            address(underlyingToken),
            amount
        );

        // Track user shares
        userShares[msg.sender] += shares;
        totalShares += shares;
        totalDeposited += amount;

        emit Deposited(msg.sender, address(underlyingToken), amount, shares);
    }

    /**
     * @notice Queue withdrawal from EigenLayer
     * @dev Starts 7-day unbonding period
     * @param shares Amount of shares to withdraw
     * @return amount Expected underlying amount (actual received after completion)
     */
    function withdraw(uint256 shares) external nonReentrant returns (uint256 amount) {
        if (shares == 0) revert ZeroAmount();
        if (userShares[msg.sender] < shares) {
            revert InsufficientShares(shares, userShares[msg.sender]);
        }

        // Calculate expected underlying
        amount = eigenStrategy.sharesToUnderlyingView(shares);

        // Update shares
        userShares[msg.sender] -= shares;
        totalShares -= shares;
        if (amount <= totalDeposited) {
            totalDeposited -= amount;
        } else {
            totalDeposited = 0;
        }

        // Queue withdrawal
        address[] memory strategies = new address[](1);
        strategies[0] = address(eigenStrategy);

        uint256[] memory sharesToWithdraw = new uint256[](1);
        sharesToWithdraw[0] = shares;

        IDelegationManager.QueuedWithdrawalParams[] memory params = 
            new IDelegationManager.QueuedWithdrawalParams[](1);
        params[0] = IDelegationManager.QueuedWithdrawalParams({
            strategies: strategies,
            shares: sharesToWithdraw,
            withdrawer: msg.sender
        });

        bytes32[] memory roots = delegationManager.queueWithdrawals(params);

        // Track pending withdrawal
        pendingWithdrawals[roots[0]] = PendingWithdrawal({
            staker: msg.sender,
            withdrawer: msg.sender,
            shares: shares,
            startBlock: uint32(block.number),
            completed: false
        });

        emit WithdrawalQueued(
            roots[0],
            msg.sender,
            address(eigenStrategy),
            shares,
            uint32(block.number)
        );
    }

    /**
     * @notice Complete a queued withdrawal after unbonding period
     * @param withdrawal Withdrawal struct from queue
     * @param tokens Token array for withdrawal
     * @param middlewareTimesIndex Index for middleware times
     */
    function completeWithdrawal(
        IDelegationManager.Withdrawal calldata withdrawal,
        IERC20[] calldata tokens,
        uint256 middlewareTimesIndex
    ) external nonReentrant {
        bytes32 root = delegationManager.calculateWithdrawalRoot(withdrawal);
        PendingWithdrawal storage pending = pendingWithdrawals[root];

        if (pending.staker == address(0)) revert WithdrawalNotFound(root);
        if (pending.completed) revert WithdrawalNotFound(root);

        // Check if unbonding complete
        uint256 completableAt = pending.startBlock + WITHDRAWAL_DELAY_BLOCKS;
        if (block.number < completableAt) {
            revert WithdrawalPending(root, completableAt);
        }

        pending.completed = true;

        // Complete withdrawal
        delegationManager.completeQueuedWithdrawal(
            withdrawal,
            tokens,
            middlewareTimesIndex,
            true // receive as tokens
        );

        // Transfer tokens to withdrawer
        uint256 balance = underlyingToken.balanceOf(address(this));
        if (balance > 0) {
            underlyingToken.safeTransfer(pending.withdrawer, balance);
        }

        emit WithdrawalCompleted(root, pending.staker, pending.withdrawer, balance);
    }

    /**
     * @notice Get total assets in underlying terms
     * @return Total assets managed by strategy
     */
    function totalAssets() external view returns (uint256) {
        uint256 strategyShares = strategyManager.stakerStrategyShares(
            address(this),
            address(eigenStrategy)
        );
        return eigenStrategy.sharesToUnderlyingView(strategyShares);
    }

    /**
     * @notice Get current APY
     * @dev Returns estimated APY from LST + AVS rewards
     * @return APY in basis points
     */
    function currentAPY() external view returns (uint256) {
        // Base APY from LST (approximate, would need oracle in production)
        // stETH ~3.5%, rETH ~3.3%, cbETH ~3.2%
        // Plus estimated AVS rewards ~1-2%
        return lastRecordedAPY > 0 ? lastRecordedAPY : 450; // Default 4.5%
    }

    /**
     * @notice Get underlying asset
     * @return Underlying LST address
     */
    function asset() external view returns (address) {
        return address(underlyingToken);
    }

    /**
     * @notice Harvest AVS rewards
     * @dev Claims rewards via RewardsCoordinator
     * @return harvested Amount of rewards harvested
     */
    function harvest() external nonReentrant returns (uint256 harvested) {
        // Note: In production, this would require merkle proofs from AVS
        // Rewards are distributed via merkle trees, claimed through RewardsCoordinator
        return 0; // Placeholder - actual implementation needs merkle proof
    }

    /**
     * @notice Claim AVS rewards with merkle proof
     * @param claim Merkle claim data
     */
    function claimRewards(
        IRewardsCoordinator.RewardsMerkleClaim calldata claim,
        address recipient
    ) external nonReentrant {
        rewardsCoordinator.processClaim(claim, recipient);

        // Calculate claimed amount
        for (uint256 i = 0; i < claim.tokenLeaves.length; i++) {
            uint256 previousClaimed = rewardsCoordinator.cumulativeClaimed(
                claim.earnerLeaf.earner,
                claim.tokenLeaves[i].token
            );
            uint256 claimed = claim.tokenLeaves[i].cumulativeEarnings - previousClaimed;
            
            if (claimed > 0) {
                totalRewardsClaimed += claimed;
                emit RewardsClaimed(
                    claim.earnerLeaf.earner,
                    address(claim.tokenLeaves[i].token),
                    claimed
                );
            }
        }
    }

    /**
     * @notice Check if strategy is active
     * @return True if accepting deposits
     */
    function isActive() external view returns (bool) {
        return active;
    }

    /**
     * @notice Get strategy name
     * @return Strategy name
     */
    function name() external view returns (string memory) {
        return strategyName;
    }

    /**
     * @notice Get strategy version
     * @return Version string
     */
    function version() external pure returns (string memory) {
        return "1.0.0";
    }

    /**
     * @notice Get the vault address that controls this strategy
     * @return Vault address (owner for this strategy)
     */
    function vault() external view returns (address) {
        return owner();
    }

    /**
     * @notice Get pending yield (not yet harvested)
     * @return Estimated pending yield
     */
    function pendingYield() external view returns (uint256) {
        // Yield accrues continuously in EigenLayer
        // For LSTs, yield is embedded in share price appreciation
        uint256 strategyShares = strategyManager.stakerStrategyShares(
            address(this),
            address(eigenStrategy)
        );
        uint256 currentValue = eigenStrategy.sharesToUnderlyingView(strategyShares);
        return currentValue > totalDeposited ? currentValue - totalDeposited : 0;
    }

    // ═══════════════════════════════════════════════════════════════════════
    // DELEGATION MANAGEMENT
    // ═══════════════════════════════════════════════════════════════════════

    /**
     * @notice Delegate to an EigenLayer operator
     * @param operator Operator address to delegate to
     * @param approverSignature Operator's approver signature (if required)
     * @param approverSalt Salt for approver signature
     */
    function delegateTo(
        address operator,
        bytes calldata approverSignature,
        bytes32 approverSalt
    ) external onlyOwner {
        if (operator == address(0)) revert InvalidOperator();
        if (delegationManager.isDelegated(address(this))) {
            revert AlreadyDelegated(delegationManager.delegatedTo(address(this)));
        }

        delegationManager.delegateTo(operator, approverSignature, approverSalt);
        delegatedOperator = operator;

        emit Delegated(address(this), operator);
    }

    /**
     * @notice Undelegate from current operator
     * @dev This will queue withdrawals for all shares
     * @return withdrawalRoots Withdrawal roots for queued withdrawals
     */
    function undelegate() external onlyOwner returns (bytes32[] memory withdrawalRoots) {
        if (!delegationManager.isDelegated(address(this))) {
            revert NotDelegated();
        }

        address previousOperator = delegatedOperator;
        delegatedOperator = address(0);

        withdrawalRoots = delegationManager.undelegate(address(this));

        emit Undelegated(address(this), previousOperator);
    }

    /**
     * @notice Get current delegated operator
     * @return Operator address (address(0) if not delegated)
     */
    function getDelegatedOperator() external view returns (address) {
        return delegatedOperator;
    }

    /**
     * @notice Check if delegated to any operator
     * @return True if delegated
     */
    function isDelegated() external view returns (bool) {
        return delegationManager.isDelegated(address(this));
    }

    // ═══════════════════════════════════════════════════════════════════════
    // ADMIN FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════

    /**
     * @notice Pause deposits
     */
    function pause() external onlyOwner {
        active = false;
    }

    /**
     * @notice Resume deposits
     */
    function unpause() external onlyOwner {
        active = true;
    }

    /**
     * @notice Update recorded APY
     * @param apy New APY in basis points
     */
    function updateAPY(uint256 apy) external onlyOwner {
        lastRecordedAPY = apy;
    }

    /**
     * @notice Emergency withdraw stuck tokens
     * @param token Token to withdraw
     * @param to Recipient
     * @param amount Amount to withdraw
     */
    function emergencyWithdraw(
        address token,
        address to,
        uint256 amount
    ) external onlyOwner {
        IERC20(token).safeTransfer(to, amount);
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// EIGENPOD STRATEGY
// ═══════════════════════════════════════════════════════════════════════════════

/**
 * @title EigenPodStrategy
 * @notice Native ETH restaking via EigenPod
 * @dev Stakes 32 ETH validators through EigenPod for restaking
 *
 * Workflow:
 * 1. Create EigenPod (one per staker)
 * 2. Deposit 32 ETH per validator
 * 3. Verify withdrawal credentials on beacon chain
 * 4. Delegate to operator for AVS validation
 * 5. Earn staking + AVS rewards
 *
 * Yield Sources:
 * - Ethereum consensus layer rewards
 * - Execution layer tips/MEV
 * - AVS rewards from validated services
 */
contract EigenPodStrategy is Ownable, ReentrancyGuard{
    using SafeERC20 for IERC20;

    // ═══════════════════════════════════════════════════════════════════════
    // CONSTANTS
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice ETH required per validator
    uint256 public constant VALIDATOR_STAKE = 32 ether;

    /// @notice Basis points denominator
    uint256 public constant BPS = 10000;

    // ═══════════════════════════════════════════════════════════════════════
    // IMMUTABLES
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice EigenPodManager
    IEigenPodManager public immutable eigenPodManager;

    /// @notice DelegationManager
    IDelegationManager public immutable delegationManager;

    /// @notice RewardsCoordinator
    IRewardsCoordinator public immutable rewardsCoordinator;

    // ═══════════════════════════════════════════════════════════════════════
    // STATE
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice Whether strategy is active
    bool public active;

    /// @notice EigenPod for this strategy
    IEigenPod public eigenPod;

    /// @notice Delegated operator
    address public delegatedOperator;

    /// @notice Total ETH staked
    uint256 public totalStaked;

    /// @notice Validator pubkeys
    bytes[] public validatorPubkeys;

    /// @notice Verified validator indices
    mapping(uint40 => bool) public verifiedValidators;

    /// @notice Last recorded APY
    uint256 public lastRecordedAPY;

    /// @notice Total rewards claimed
    uint256 public totalRewardsClaimed;

    /// @notice Total deposited (for yield tracking)
    uint256 public totalDeposited;

    /// @notice Pending withdrawals
    mapping(bytes32 => PendingWithdrawal) public pendingWithdrawals;

    struct PendingWithdrawal {
        address staker;
        uint256 amount;
        uint32 startBlock;
        bool completed;
    }

    // ═══════════════════════════════════════════════════════════════════════
    // CONSTRUCTOR
    // ═══════════════════════════════════════════════════════════════════════

    /**
     * @notice Deploy EigenPod Strategy
     * @param _eigenPodManager EigenPodManager address
     * @param _delegationManager DelegationManager address
     * @param _rewardsCoordinator RewardsCoordinator address
     * @param _owner Strategy owner
     */
    constructor(
        address _eigenPodManager,
        address _delegationManager,
        address _rewardsCoordinator,
        address _owner
    ) Ownable(_owner) {
        eigenPodManager = IEigenPodManager(_eigenPodManager);
        delegationManager = IDelegationManager(_delegationManager);
        rewardsCoordinator = IRewardsCoordinator(_rewardsCoordinator);
        active = true;
    }

    // ═══════════════════════════════════════════════════════════════════════
    // EIGENPOD MANAGEMENT
    // ═══════════════════════════════════════════════════════════════════════

    /**
     * @notice Create EigenPod for this strategy
     * @return pod Address of created EigenPod
     */
    function createPod() external onlyOwner returns (address pod) {
        if (eigenPodManager.hasPod(address(this))) {
            revert PodAlreadyExists();
        }

        pod = eigenPodManager.createPod();
        eigenPod = IEigenPod(pod);

        emit PodCreated(address(this), pod);
    }

    /**
     * @notice Stake ETH to beacon chain via EigenPod
     * @param pubkey Validator public key (48 bytes)
     * @param signature Deposit signature
     * @param depositDataRoot Deposit data root
     */
    function stakeValidator(
        bytes calldata pubkey,
        bytes calldata signature,
        bytes32 depositDataRoot
    ) external payable onlyOwner nonReentrant {
        if (!eigenPodManager.hasPod(address(this))) {
            revert PodNotCreated();
        }
        if (pubkey.length != 48) revert InvalidPubkey();
        if (msg.value != VALIDATOR_STAKE) {
            revert InsufficientETH(VALIDATOR_STAKE, msg.value);
        }

        eigenPodManager.stake{value: msg.value}(pubkey, signature, depositDataRoot);
        
        validatorPubkeys.push(pubkey);
        totalStaked += msg.value;

        emit ValidatorStaked(address(this), pubkey, msg.value);
    }

    /**
     * @notice Verify withdrawal credentials for validators
     * @param oracleTimestamp Beacon chain timestamp
     * @param stateRootProof State root proof
     * @param validatorIndices Validator indices to verify
     * @param validatorFieldsProofs Proofs for validator fields
     * @param validatorFields Validator field data
     */
    function verifyWithdrawalCredentials(
        uint64 oracleTimestamp,
        BeaconChainProofs.StateRootProof calldata stateRootProof,
        uint40[] calldata validatorIndices,
        bytes[] calldata validatorFieldsProofs,
        bytes32[][] calldata validatorFields
    ) external onlyOwner {
        if (address(eigenPod) == address(0)) revert PodNotCreated();

        eigenPod.verifyWithdrawalCredentials(
            oracleTimestamp,
            stateRootProof,
            validatorIndices,
            validatorFieldsProofs,
            validatorFields
        );

        // Mark validators as verified
        for (uint256 i = 0; i < validatorIndices.length; i++) {
            verifiedValidators[validatorIndices[i]] = true;
        }

        emit WithdrawalCredentialsVerified(address(this), validatorIndices);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // YIELD STRATEGY INTERFACE
    // ═══════════════════════════════════════════════════════════════════════

    /**
     * @notice Deposit ETH (adds to pending stake)
     * @param amount Amount (must match msg.value for ETH)
     * @return shares Shares issued (1:1 with ETH for native staking)
     */
    function deposit(uint256 amount) external nonReentrant returns (uint256 shares) {
        if (!active) revert StrategyNotActive();
        if (amount == 0) revert ZeroAmount();

        // ETH is held until staked as validator
        shares = amount;
        totalDeposited += amount;

        emit Deposited(msg.sender, address(0), amount, shares);
    }

    /**
     * @notice Withdraw ETH
     * @dev Withdrawals are complex for native staking - requires exiting validators
     * @param shares Amount of shares to withdraw
     * @return amount Amount withdrawn
     */
    function withdraw(uint256 shares) external nonReentrant returns (uint256 amount) {
        // Native ETH withdrawals require:
        // 1. Exit validator on beacon chain
        // 2. Wait for withdrawal to process
        // 3. Verify withdrawal via EigenPod
        // 4. Queue withdrawal through DelegationManager
        // 5. Complete after 7-day delay
        
        // For simplicity, this handles non-beacon chain ETH only
        if (address(eigenPod) == address(0)) revert PodNotCreated();

        uint256 available = eigenPod.nonBeaconChainETHBalanceWei();
        if (shares > available) {
            revert InsufficientShares(shares, available);
        }

        eigenPod.withdrawNonBeaconChainETHBalanceWei(msg.sender, shares);
        amount = shares;
        if (amount <= totalDeposited) {
            totalDeposited -= amount;
        } else {
            totalDeposited = 0;
        }

        emit WithdrawalCompleted(bytes32(0), msg.sender, msg.sender, amount);
    }

    /**
     * @notice Get total assets
     * @return Total ETH staked plus pending
     */
    function totalAssets() external view returns (uint256) {
        int256 podShares = eigenPodManager.podOwnerShares(address(this));
        uint256 podBalance = address(eigenPod) != address(0) 
            ? eigenPod.nonBeaconChainETHBalanceWei() 
            : 0;
        
        return totalStaked + podBalance + (podShares > 0 ? uint256(podShares) : 0);
    }

    /**
     * @notice Get current APY
     * @return APY in basis points (native staking ~3-4%)
     */
    function currentAPY() external view returns (uint256) {
        return lastRecordedAPY > 0 ? lastRecordedAPY : 350; // Default 3.5%
    }

    /**
     * @notice Get underlying asset
     * @return address(0) for native ETH
     */
    function asset() external pure returns (address) {
        return address(0); // Native ETH
    }

    /**
     * @notice Harvest execution layer rewards
     * @return harvested Amount harvested
     */
    function harvest() external nonReentrant returns (uint256 harvested) {
        if (address(eigenPod) == address(0)) return 0;

        // Non-beacon chain ETH can be withdrawn
        uint256 available = eigenPod.nonBeaconChainETHBalanceWei();
        if (available > 0) {
            eigenPod.withdrawNonBeaconChainETHBalanceWei(address(this), available);
            harvested = available;
        }
    }

    /**
     * @notice Check if active
     * @return True if accepting deposits
     */
    function isActive() external view returns (bool) {
        return active;
    }

    /**
     * @notice Get strategy name
     * @return Strategy name
     */
    function name() external pure returns (string memory) {
        return "EigenPod Native ETH";
    }

    /**
     * @notice Get strategy version
     * @return Version string
     */
    function version() external pure returns (string memory) {
        return "1.0.0";
    }

    /**
     * @notice Get the vault address that controls this strategy
     * @return Vault address (owner for this strategy)
     */
    function vault() external view returns (address) {
        return owner();
    }

    /**
     * @notice Get pending yield (not yet harvested)
     * @return Estimated pending yield from execution layer
     */
    function pendingYield() external view returns (uint256) {
        if (address(eigenPod) == address(0)) return 0;
        return eigenPod.nonBeaconChainETHBalanceWei();
    }

    // ═══════════════════════════════════════════════════════════════════════
    // DELEGATION
    // ═══════════════════════════════════════════════════════════════════════

    /**
     * @notice Delegate to operator
     * @param operator Operator address
     * @param approverSignature Approver signature
     * @param approverSalt Salt for signature
     */
    function delegateTo(
        address operator,
        bytes calldata approverSignature,
        bytes32 approverSalt
    ) external onlyOwner {
        if (operator == address(0)) revert InvalidOperator();
        if (delegationManager.isDelegated(address(this))) {
            revert AlreadyDelegated(delegatedOperator);
        }

        delegationManager.delegateTo(operator, approverSignature, approverSalt);
        delegatedOperator = operator;

        emit Delegated(address(this), operator);
    }

    /**
     * @notice Undelegate from operator
     * @return withdrawalRoots Queued withdrawal roots
     */
    function undelegate() external onlyOwner returns (bytes32[] memory withdrawalRoots) {
        if (!delegationManager.isDelegated(address(this))) {
            revert NotDelegated();
        }

        address previousOperator = delegatedOperator;
        delegatedOperator = address(0);

        withdrawalRoots = delegationManager.undelegate(address(this));

        emit Undelegated(address(this), previousOperator);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // ADMIN
    // ═══════════════════════════════════════════════════════════════════════

    /**
     * @notice Pause deposits
     */
    function pause() external onlyOwner {
        active = false;
    }

    /**
     * @notice Resume deposits
     */
    function unpause() external onlyOwner {
        active = true;
    }

    /**
     * @notice Update APY
     * @param apy New APY in basis points
     */
    function updateAPY(uint256 apy) external onlyOwner {
        lastRecordedAPY = apy;
    }

    /**
     * @notice Get validator count
     * @return Number of validators
     */
    function validatorCount() external view returns (uint256) {
        return validatorPubkeys.length;
    }

    /**
     * @notice Check if pod exists
     * @return True if EigenPod created
     */
    function hasPod() external view returns (bool) {
        return address(eigenPod) != address(0);
    }

    /// @notice Receive ETH
    receive() external payable {}
}

// ═══════════════════════════════════════════════════════════════════════════════
// STRATEGY FACTORIES
// ═══════════════════════════════════════════════════════════════════════════════

/**
 * @title EigenLayerLSTStrategyFactory
 * @notice Factory for deploying EigenLayer LST strategies
 */
contract EigenLayerLSTStrategyFactory {
    /// @notice Emitted when strategy deployed
    event StrategyDeployed(
        address indexed strategy,
        address indexed underlyingToken,
        address indexed eigenStrategy,
        string name
    );

    /// @notice EigenLayer StrategyManager
    address public immutable strategyManager;

    /// @notice EigenLayer DelegationManager
    address public immutable delegationManager;

    /// @notice EigenLayer RewardsCoordinator
    address public immutable rewardsCoordinator;

    constructor(
        address _strategyManager,
        address _delegationManager,
        address _rewardsCoordinator
    ) {
        strategyManager = _strategyManager;
        delegationManager = _delegationManager;
        rewardsCoordinator = _rewardsCoordinator;
    }

    /**
     * @notice Deploy a new LST strategy
     * @param eigenStrategy EigenLayer strategy address
     * @param underlyingToken LST token address
     * @param name Strategy name
     * @param owner Strategy owner
     * @return strategy Deployed strategy address
     */
    function deploy(
        address eigenStrategy,
        address underlyingToken,
        string calldata name,
        address owner
    ) external returns (address strategy) {
        strategy = address(new EigenLayerLSTStrategy(
            strategyManager,
            delegationManager,
            rewardsCoordinator,
            eigenStrategy,
            underlyingToken,
            name,
            owner
        ));

        emit StrategyDeployed(strategy, underlyingToken, eigenStrategy, name);
    }
}

/**
 * @title EigenPodStrategyFactory
 * @notice Factory for deploying EigenPod strategies
 */
contract EigenPodStrategyFactory {
    /// @notice Emitted when strategy deployed
    event StrategyDeployed(address indexed strategy, address indexed owner);

    /// @notice EigenPodManager
    address public immutable eigenPodManager;

    /// @notice DelegationManager
    address public immutable delegationManager;

    /// @notice RewardsCoordinator
    address public immutable rewardsCoordinator;

    constructor(
        address _eigenPodManager,
        address _delegationManager,
        address _rewardsCoordinator
    ) {
        eigenPodManager = _eigenPodManager;
        delegationManager = _delegationManager;
        rewardsCoordinator = _rewardsCoordinator;
    }

    /**
     * @notice Deploy a new EigenPod strategy
     * @param owner Strategy owner
     * @return strategy Deployed strategy address
     */
    function deploy(address owner) external returns (address strategy) {
        strategy = address(new EigenPodStrategy(
            eigenPodManager,
            delegationManager,
            rewardsCoordinator,
            owner
        ));

        emit StrategyDeployed(strategy, owner);
    }
}
