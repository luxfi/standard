// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

/**
 * @title SolanaStrategies
 * @notice Cross-chain yield strategies for Solana DeFi protocols via Wormhole
 * @dev Implements IYieldStrategy for Marinade (mSOL), Jito (JitoSOL), and Kamino Finance
 *
 * Architecture:
 * ┌─────────────────────────────────────────────────────────────────────────────┐
 * │  Lux EVM (Source Chain)                                                     │
 * │  ┌─────────────┐    ┌─────────────┐    ┌─────────────┐                     │
 * │  │ Deposit     │ -> │ Wormhole    │ -> │ Track       │                     │
 * │  │ wSOL/wstSOL │    │ Relayer     │    │ Pending     │                     │
 * │  └─────────────┘    └─────────────┘    └─────────────┘                     │
 * └──────────────────────────────────────────┼──────────────────────────────────┘
 *                                            │ Wormhole Message
 * ┌──────────────────────────────────────────┼──────────────────────────────────┐
 * │  Solana (Destination)                    ▼                                  │
 * │  ┌─────────────┐    ┌─────────────┐    ┌─────────────┐                     │
 * │  │ Bridge      │ -> │ Protocol    │ -> │ Yield       │                     │
 * │  │ Receiver    │    │ Deposit     │    │ Accrues     │                     │
 * │  └─────────────┘    └─────────────┘    └─────────────┘                     │
 * └─────────────────────────────────────────────────────────────────────────────┘
 *
 * Supported Protocols:
 * - Marinade Finance: mSOL liquid staking (6-8% APY)
 * - Jito: JitoSOL MEV-boosted staking (7-10% APY)
 * - Kamino Finance: Automated liquidity and lending
 *
 * Cross-chain considerations:
 * - All deposits/withdrawals are asynchronous via Wormhole
 * - Exchange rates fetched from on-chain oracle
 * - Pending transactions tracked until confirmation
 */

import {IYieldStrategy} from "../IYieldStrategy.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

// ═══════════════════════════════════════════════════════════════════════════════
// WORMHOLE INTERFACES
// ═══════════════════════════════════════════════════════════════════════════════

/// @notice Wormhole Relayer for cross-chain messaging
interface IWormholeRelayer {
    /// @notice Send payload to target chain via Wormhole
    /// @param targetChain Wormhole chain ID (1=Solana)
    /// @param targetAddress Contract address on target chain
    /// @param payload Encoded message payload
    /// @param receiverValue Native tokens to send to receiver
    /// @param gasLimit Gas limit for execution on target
    /// @return sequence Message sequence number
    function sendPayloadToEvm(
        uint16 targetChain,
        address targetAddress,
        bytes memory payload,
        uint256 receiverValue,
        uint256 gasLimit
    ) external payable returns (uint64 sequence);

    /// @notice Quote delivery price
    /// @param targetChain Wormhole chain ID
    /// @param receiverValue Native tokens for receiver
    /// @param gasLimit Gas limit for execution
    /// @return nativePriceQuote Cost in native tokens
    /// @return targetChainRefundPerGasUnused Refund rate for unused gas
    function quoteEVMDeliveryPrice(
        uint16 targetChain,
        uint256 receiverValue,
        uint256 gasLimit
    ) external view returns (uint256 nativePriceQuote, uint256 targetChainRefundPerGasUnused);
}

/// @notice Oracle for Solana yield protocol exchange rates
interface ISolanaYieldOracle {
    /// @notice Get mSOL/SOL exchange rate (18 decimals)
    function getMsolExchangeRate() external view returns (uint256);

    /// @notice Get JitoSOL/SOL exchange rate (18 decimals)
    function getJitosolExchangeRate() external view returns (uint256);

    /// @notice Get Kamino market APY (basis points)
    /// @param market Kamino market identifier
    function getKaminoApy(bytes32 market) external view returns (uint256);

    /// @notice Get staking rewards rate (basis points)
    /// @param validatorSet Validator set identifier
    function getStakingRewards(bytes32 validatorSet) external view returns (uint256);
}

/// @notice Solana-side bridge receiver interface
interface ISolanaBridgeReceiver {
    /// @notice Deposit SOL to Marinade for mSOL
    function depositToMarinade(uint256 solAmount) external returns (bytes32 txId);

    /// @notice Withdraw mSOL from Marinade
    function withdrawFromMarinade(uint256 msolAmount) external returns (bytes32 txId);

    /// @notice Deposit SOL to Jito for JitoSOL
    function depositToJito(uint256 solAmount) external returns (bytes32 txId);

    /// @notice Withdraw JitoSOL from Jito
    function withdrawFromJito(uint256 jitosolAmount) external returns (bytes32 txId);

    /// @notice Deposit to Kamino market
    function depositToKamino(bytes32 market, uint256 amount) external returns (bytes32 txId);

    /// @notice Withdraw from Kamino market
    function withdrawFromKamino(bytes32 market, uint256 shares) external returns (bytes32 txId);

    /// @notice Claim rewards from protocol
    function claimRewards(bytes32 protocol) external returns (bytes32 txId);
}

// ═══════════════════════════════════════════════════════════════════════════════
// CROSS-CHAIN MESSAGE TYPES
// ═══════════════════════════════════════════════════════════════════════════════

/// @notice Action types for cross-chain messages
enum SolanaAction {
    DEPOSIT,
    WITHDRAW,
    CLAIM
}

/// @notice Cross-chain deposit/withdraw message
struct SolanaDepositMessage {
    uint8 action;          // 0=deposit, 1=withdraw, 2=claim
    bytes32 protocol;      // marinade, jito, kamino
    uint256 amount;        // Amount in lamports/shares
    bytes32 recipient;     // Solana pubkey (32 bytes)
}

/// @notice Yield report from Solana
struct SolanaYieldReport {
    bytes32 protocol;      // Protocol identifier
    uint256 deposited;     // Total SOL deposited
    uint256 currentValue;  // Current value in SOL
    uint256 pendingRewards;// Unclaimed rewards
    uint64 lastUpdate;     // Timestamp of last update
}

/// @notice Pending cross-chain transaction
struct PendingTransaction {
    uint64 sequence;       // Wormhole sequence number
    SolanaAction action;   // Action type
    uint256 amount;        // Amount involved
    uint256 timestamp;     // When sent
    bool completed;        // Whether confirmed
}

// ═══════════════════════════════════════════════════════════════════════════════
// ERRORS
// ═══════════════════════════════════════════════════════════════════════════════

error NotActive();
error OnlyVault();
error InsufficientBalance();
error InvalidAmount();
error InvalidRecipient();
error MessageFailed();
error PendingTransactionExists();
error TransactionNotFound();
error TransactionAlreadyCompleted();
error InsufficientFee();
error OracleStale();
error InvalidExchangeRate();

// ═══════════════════════════════════════════════════════════════════════════════
// EVENTS
// ═══════════════════════════════════════════════════════════════════════════════

/// @notice Emitted when cross-chain deposit is initiated
event CrossChainDeposit(
    bytes32 indexed protocol,
    uint256 amount,
    bytes32 solanaRecipient,
    uint64 sequence
);

/// @notice Emitted when cross-chain withdrawal is initiated
event CrossChainWithdraw(
    bytes32 indexed protocol,
    uint256 shares,
    bytes32 solanaRecipient,
    uint64 sequence
);

/// @notice Emitted when yield report is received
event YieldReported(
    bytes32 indexed protocol,
    uint256 deposited,
    uint256 currentValue,
    uint256 pendingRewards
);

/// @notice Emitted when Wormhole message is sent
event MessageSent(
    uint16 targetChain,
    uint64 sequence,
    bytes payload
);

/// @notice Emitted when pending transaction is confirmed
event TransactionConfirmed(
    uint64 indexed sequence,
    bool success
);

// ═══════════════════════════════════════════════════════════════════════════════
// SOLANA STRATEGY BASE
// ═══════════════════════════════════════════════════════════════════════════════

/**
 * @title SolanaStrategyBase
 * @notice Abstract base for Solana cross-chain yield strategies
 * @dev Handles Wormhole messaging, pending transaction tracking, and oracle queries
 */
abstract contract SolanaStrategyBase is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // ═══════════════════════════════════════════════════════════════════════
    // CONSTANTS
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice Wormhole chain ID for Solana
    uint16 public constant SOLANA_CHAIN_ID = 1;

    /// @notice Default gas limit for Solana execution
    uint256 public constant SOLANA_GAS_LIMIT = 500_000;

    /// @notice Maximum staleness for oracle data (1 hour)
    uint256 public constant MAX_ORACLE_STALENESS = 3600;

    /// @notice Basis points denominator
    uint256 public constant BPS = 10_000;

    /// @notice 1e18 for exchange rate calculations
    uint256 public constant RATE_PRECISION = 1e18;

    // ═══════════════════════════════════════════════════════════════════════
    // STATE
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice Wormhole relayer contract
    IWormholeRelayer public immutable wormholeRelayer;

    /// @notice Solana yield oracle
    ISolanaYieldOracle public immutable oracle;

    /// @notice Wrapped SOL token on EVM (wSOL from Wormhole)
    address public immutable wSOL;

    /// @notice Solana bridge receiver address (32-byte pubkey)
    bytes32 public solanaReceiver;

    /// @notice Vault that controls this strategy
    address public vault;

    /// @notice Protocol identifier (marinade, jito, kamino)
    bytes32 public immutable protocolId;

    /// @notice Total shares tracked on EVM side
    uint256 public totalShares;

    /// @notice Total SOL deposited (tracked locally)
    uint256 public totalDeposited;

    /// @notice Latest yield report from Solana
    SolanaYieldReport public latestReport;

    /// @notice Strategy active status
    bool public active = true;

    /// @notice Pending transactions by sequence number
    mapping(uint64 => PendingTransaction) public pendingTransactions;

    /// @notice Active pending transaction sequences
    uint64[] public pendingSequences;

    /// @notice Last harvest timestamp
    uint256 public lastHarvest;

    // ═══════════════════════════════════════════════════════════════════════
    // MODIFIERS
    // ═══════════════════════════════════════════════════════════════════════

    modifier onlyVault() {
        if (msg.sender != vault) revert OnlyVault();
        _;
    }

    modifier whenActive() {
        if (!active) revert NotActive();
        _;
    }

    // ═══════════════════════════════════════════════════════════════════════
    // CONSTRUCTOR
    // ═══════════════════════════════════════════════════════════════════════

    /**
     * @notice Construct Solana strategy base
     * @param _vault Vault that controls this strategy
     * @param _wormholeRelayer Wormhole relayer address
     * @param _oracle Solana yield oracle address
     * @param _wSOL Wrapped SOL token address
     * @param _solanaReceiver Solana receiver pubkey (32 bytes)
     * @param _protocolId Protocol identifier
     */
    constructor(
        address _vault,
        address _wormholeRelayer,
        address _oracle,
        address _wSOL,
        bytes32 _solanaReceiver,
        bytes32 _protocolId
    ) Ownable(msg.sender) {
        vault = _vault;
        wormholeRelayer = IWormholeRelayer(_wormholeRelayer);
        oracle = ISolanaYieldOracle(_oracle);
        wSOL = _wSOL;
        solanaReceiver = _solanaReceiver;
        protocolId = _protocolId;

        // Approve wormhole relayer to transfer wSOL
        IERC20(_wSOL).approve(_wormholeRelayer, type(uint256).max);

        lastHarvest = block.timestamp;
    }

    // ═══════════════════════════════════════════════════════════════════════
    // YIELD STRATEGY INTERFACE
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice
    function deposit(uint256 amount) external virtual onlyVault whenActive nonReentrant returns (uint256 shares) {
        if (amount == 0) revert InvalidAmount();

        // Transfer wSOL from vault
        IERC20(wSOL).safeTransferFrom(msg.sender, address(this), amount);

        // Calculate shares based on current exchange rate
        uint256 exchangeRate = _getExchangeRate();
        shares = (amount * RATE_PRECISION) / exchangeRate;

        // Encode deposit message
        SolanaDepositMessage memory message = SolanaDepositMessage({
            action: uint8(SolanaAction.DEPOSIT),
            protocol: protocolId,
            amount: amount,
            recipient: solanaReceiver
        });

        // Get Wormhole fee
        (uint256 fee,) = wormholeRelayer.quoteEVMDeliveryPrice(
            SOLANA_CHAIN_ID,
            0,
            SOLANA_GAS_LIMIT
        );

        // Send via Wormhole
        uint64 sequence = _sendWormholeMessage(abi.encode(message), fee);

        // Track pending transaction
        _addPendingTransaction(sequence, SolanaAction.DEPOSIT, amount);

        // Update local tracking
        totalShares += shares;
        totalDeposited += amount;

        emit CrossChainDeposit(protocolId, amount, solanaReceiver, sequence);
    }

    /// @notice
    function withdraw(uint256 shares) external onlyVault nonReentrant returns (uint256 amount) {
        if (shares > totalShares) revert InsufficientBalance();

        // Calculate amount based on current exchange rate
        uint256 exchangeRate = _getExchangeRate();
        amount = (shares * exchangeRate) / RATE_PRECISION;

        // Encode withdraw message
        SolanaDepositMessage memory message = SolanaDepositMessage({
            action: uint8(SolanaAction.WITHDRAW),
            protocol: protocolId,
            amount: shares,
            recipient: solanaReceiver
        });

        // Get Wormhole quote
        (uint256 fee,) = wormholeRelayer.quoteEVMDeliveryPrice(
            SOLANA_CHAIN_ID,
            0,
            SOLANA_GAS_LIMIT
        );

        // Send via Wormhole (requires ETH for fee)
        uint64 sequence = _sendWormholeMessage(abi.encode(message), fee);

        // Track pending transaction
        _addPendingTransaction(sequence, SolanaAction.WITHDRAW, shares);

        // Update local tracking
        totalShares -= shares;
        // Note: totalDeposited updated when confirmation received

        emit CrossChainWithdraw(protocolId, shares, solanaReceiver, sequence);
    }

    /// @notice
    function harvest() external returns (uint256 harvested) {
        // Encode claim message
        SolanaDepositMessage memory message = SolanaDepositMessage({
            action: uint8(SolanaAction.CLAIM),
            protocol: protocolId,
            amount: 0,
            recipient: solanaReceiver
        });

        // Get Wormhole quote
        (uint256 fee,) = wormholeRelayer.quoteEVMDeliveryPrice(
            SOLANA_CHAIN_ID,
            0,
            SOLANA_GAS_LIMIT
        );

        // Send via Wormhole
        uint64 sequence = _sendWormholeMessage(abi.encode(message), fee);

        // Track pending transaction
        _addPendingTransaction(sequence, SolanaAction.CLAIM, 0);

        // Return pending rewards from last report
        harvested = latestReport.pendingRewards;
        lastHarvest = block.timestamp;
    }

    /// @notice
    function totalAssets() external view returns (uint256) {
        if (latestReport.lastUpdate == 0) {
            return totalDeposited;
        }
        return latestReport.currentValue;
    }

    /// @notice
    function currentAPY() external view virtual returns (uint256);

    /// @notice
    function underlying() external view returns (address) {
        return wSOL;
    }

    /// @notice
    function yieldToken() external view virtual returns (address);

    /// @notice
    function isActive() external view returns (bool) {
        return active;
    }

    /// @notice
    function name() external view virtual returns (string memory);

    // ═══════════════════════════════════════════════════════════════════════
    // WORMHOLE MESSAGING
    // ═══════════════════════════════════════════════════════════════════════

    /**
     * @notice Send message via Wormhole relayer
     * @param payload Encoded message payload
     * @param fee Native fee for Wormhole delivery
     * @return sequence Wormhole sequence number
     */
    function _sendWormholeMessage(bytes memory payload, uint256 fee) internal returns (uint64 sequence) {
        (uint256 requiredFee,) = wormholeRelayer.quoteEVMDeliveryPrice(
            SOLANA_CHAIN_ID,
            0,
            SOLANA_GAS_LIMIT
        );

        if (fee < requiredFee) revert InsufficientFee();

        sequence = wormholeRelayer.sendPayloadToEvm{value: fee}(
            SOLANA_CHAIN_ID,
            address(0), // Target address encoded in payload for Solana
            payload,
            0,
            SOLANA_GAS_LIMIT
        );

        emit MessageSent(SOLANA_CHAIN_ID, sequence, payload);
    }

    /**
     * @notice Quote Wormhole delivery price
     * @return fee Native token fee required
     */
    function quoteDeliveryFee() external view returns (uint256 fee) {
        (fee,) = wormholeRelayer.quoteEVMDeliveryPrice(
            SOLANA_CHAIN_ID,
            0,
            SOLANA_GAS_LIMIT
        );
    }

    // ═══════════════════════════════════════════════════════════════════════
    // PENDING TRANSACTION MANAGEMENT
    // ═══════════════════════════════════════════════════════════════════════

    /**
     * @notice Add pending transaction
     */
    function _addPendingTransaction(uint64 sequence, SolanaAction action, uint256 amount) internal {
        pendingTransactions[sequence] = PendingTransaction({
            sequence: sequence,
            action: action,
            amount: amount,
            timestamp: block.timestamp,
            completed: false
        });
        pendingSequences.push(sequence);
    }

    /**
     * @notice Confirm pending transaction (called by oracle/relayer)
     * @param sequence Wormhole sequence number
     * @param success Whether transaction succeeded on Solana
     */
    function confirmTransaction(uint64 sequence, bool success) external onlyOwner {
        PendingTransaction storage pending = pendingTransactions[sequence];
        if (pending.timestamp == 0) revert TransactionNotFound();
        if (pending.completed) revert TransactionAlreadyCompleted();

        pending.completed = true;

        if (!success) {
            // Revert local state on failure
            if (pending.action == SolanaAction.DEPOSIT) {
                totalShares -= (pending.amount * RATE_PRECISION) / _getExchangeRate();
                totalDeposited -= pending.amount;
            } else if (pending.action == SolanaAction.WITHDRAW) {
                totalShares += (pending.amount * _getExchangeRate()) / RATE_PRECISION;
            }
        }

        emit TransactionConfirmed(sequence, success);
    }

    /**
     * @notice Get all pending transactions
     */
    function getPendingTransactions() external view returns (PendingTransaction[] memory pending) {
        uint256 count = 0;
        for (uint256 i = 0; i < pendingSequences.length; i++) {
            if (!pendingTransactions[pendingSequences[i]].completed) {
                count++;
            }
        }

        pending = new PendingTransaction[](count);
        uint256 index = 0;
        for (uint256 i = 0; i < pendingSequences.length; i++) {
            PendingTransaction storage tx_ = pendingTransactions[pendingSequences[i]];
            if (!tx_.completed) {
                pending[index++] = tx_;
            }
        }
    }

    // ═══════════════════════════════════════════════════════════════════════
    // ORACLE UPDATES
    // ═══════════════════════════════════════════════════════════════════════

    /**
     * @notice Update yield report from Solana oracle
     * @param report New yield report
     */
    function updateYieldReport(SolanaYieldReport calldata report) external onlyOwner {
        if (report.protocol != protocolId) revert InvalidRecipient();

        latestReport = report;

        emit YieldReported(
            report.protocol,
            report.deposited,
            report.currentValue,
            report.pendingRewards
        );
    }

    /**
     * @notice Get exchange rate from oracle
     */
    function _getExchangeRate() internal view virtual returns (uint256);

    // ═══════════════════════════════════════════════════════════════════════
    // ADMIN FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice Set strategy active status
    function setActive(bool _active) external onlyOwner {
        active = _active;
    }

    /// @notice Set vault address
    function setVault(address _vault) external onlyOwner {
        vault = _vault;
    }

    /// @notice Set Solana receiver address
    function setSolanaReceiver(bytes32 _solanaReceiver) external onlyOwner {
        solanaReceiver = _solanaReceiver;
    }

    /// @notice Emergency withdraw (returns wSOL on EVM side only)
    function emergencyWithdraw() external onlyOwner {
        uint256 balance = IERC20(wSOL).balanceOf(address(this));
        if (balance > 0) {
            IERC20(wSOL).safeTransfer(owner(), balance);
        }
        active = false;
    }

    /// @notice Rescue stuck tokens
    function rescueToken(address token, uint256 amount) external onlyOwner {
        IERC20(token).safeTransfer(owner(), amount);
    }

    /// @notice Receive ETH for Wormhole fees
    receive() external payable {}
}

// ═══════════════════════════════════════════════════════════════════════════════
// MARINADE STRATEGY
// ═══════════════════════════════════════════════════════════════════════════════

/**
 * @title MarinadeStrategy
 * @notice Cross-chain strategy for Marinade Finance mSOL liquid staking
 * @dev Deposits SOL to Marinade via Wormhole, receives mSOL yield
 *
 * Marinade Finance:
 * - Largest Solana liquid staking protocol
 * - mSOL = yield-bearing SOL token
 * - Decentralized validator delegation
 * - ~6-8% APY from Solana staking rewards
 * - Instant unstaking available (with fee)
 *
 * Exchange rate: mSOL/SOL appreciates over time as staking rewards accrue
 */
contract MarinadeStrategy is SolanaStrategyBase {
    // Protocol identifiers
    bytes32 public constant MARINADE_PROTOCOL = keccak256("marinade");
    bytes32 public constant MARINADE_VALIDATORS = keccak256("marinade_validators");

    /// @notice mSOL token representation on EVM (Wormhole wrapped)
    address public immutable wMSOL;

    /**
     * @notice Construct Marinade strategy
     * @param _vault Vault that controls this strategy
     * @param _wormholeRelayer Wormhole relayer address
     * @param _oracle Solana yield oracle address
     * @param _wSOL Wrapped SOL token address
     * @param _wMSOL Wrapped mSOL token address
     * @param _solanaReceiver Solana receiver pubkey
     */
    constructor(
        address _vault,
        address _wormholeRelayer,
        address _oracle,
        address _wSOL,
        address _wMSOL,
        bytes32 _solanaReceiver
    ) SolanaStrategyBase(
        _vault,
        _wormholeRelayer,
        _oracle,
        _wSOL,
        _solanaReceiver,
        MARINADE_PROTOCOL
    ) {
        wMSOL = _wMSOL;
    }

    /// @notice
    function currentAPY() external view override returns (uint256) {
        // Get staking rewards from oracle (basis points)
        return oracle.getStakingRewards(MARINADE_VALIDATORS);
    }

    /// @notice
    function yieldToken() external view override returns (address) {
        return wMSOL;
    }

    /// @notice
    function name() external pure override returns (string memory) {
        return "Marinade mSOL Strategy";
    }

    /// @notice Get mSOL/SOL exchange rate
    function _getExchangeRate() internal view override returns (uint256) {
        uint256 rate = oracle.getMsolExchangeRate();
        if (rate == 0) revert InvalidExchangeRate();
        return rate;
    }

    /// @notice Get current mSOL exchange rate
    function getMsolRate() external view returns (uint256) {
        return oracle.getMsolExchangeRate();
    }

    /// @notice Calculate mSOL received for SOL deposit
    function previewDeposit(uint256 solAmount) external view returns (uint256 msolAmount) {
        uint256 rate = oracle.getMsolExchangeRate();
        msolAmount = (solAmount * RATE_PRECISION) / rate;
    }

    /// @notice Calculate SOL received for mSOL withdrawal
    function previewWithdraw(uint256 msolAmount) external view returns (uint256 solAmount) {
        uint256 rate = oracle.getMsolExchangeRate();
        solAmount = (msolAmount * rate) / RATE_PRECISION;
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// JITO STRATEGY
// ═══════════════════════════════════════════════════════════════════════════════

/**
 * @title JitoStrategy
 * @notice Cross-chain strategy for Jito JitoSOL MEV-boosted staking
 * @dev Deposits SOL to Jito via Wormhole, receives JitoSOL yield
 *
 * Jito:
 * - MEV-boosted liquid staking
 * - JitoSOL = yield-bearing SOL + MEV rewards
 * - Runs Jito-Solana validator client with MEV extraction
 * - ~7-10% APY (staking + MEV)
 * - Higher yield than plain staking due to MEV capture
 *
 * Exchange rate: JitoSOL/SOL appreciates faster due to MEV rewards
 */
contract JitoStrategy is SolanaStrategyBase {
    // Protocol identifiers
    bytes32 public constant JITO_PROTOCOL = keccak256("jito");
    bytes32 public constant JITO_VALIDATORS = keccak256("jito_validators");

    /// @notice JitoSOL token representation on EVM (Wormhole wrapped)
    address public immutable wJitoSOL;

    /**
     * @notice Construct Jito strategy
     * @param _vault Vault that controls this strategy
     * @param _wormholeRelayer Wormhole relayer address
     * @param _oracle Solana yield oracle address
     * @param _wSOL Wrapped SOL token address
     * @param _wJitoSOL Wrapped JitoSOL token address
     * @param _solanaReceiver Solana receiver pubkey
     */
    constructor(
        address _vault,
        address _wormholeRelayer,
        address _oracle,
        address _wSOL,
        address _wJitoSOL,
        bytes32 _solanaReceiver
    ) SolanaStrategyBase(
        _vault,
        _wormholeRelayer,
        _oracle,
        _wSOL,
        _solanaReceiver,
        JITO_PROTOCOL
    ) {
        wJitoSOL = _wJitoSOL;
    }

    /// @notice
    function currentAPY() external view override returns (uint256) {
        // Get staking + MEV rewards from oracle
        return oracle.getStakingRewards(JITO_VALIDATORS);
    }

    /// @notice
    function yieldToken() external view override returns (address) {
        return wJitoSOL;
    }

    /// @notice
    function name() external pure override returns (string memory) {
        return "Jito JitoSOL MEV Strategy";
    }

    /// @notice Get JitoSOL/SOL exchange rate
    function _getExchangeRate() internal view override returns (uint256) {
        uint256 rate = oracle.getJitosolExchangeRate();
        if (rate == 0) revert InvalidExchangeRate();
        return rate;
    }

    /// @notice Get current JitoSOL exchange rate
    function getJitosolRate() external view returns (uint256) {
        return oracle.getJitosolExchangeRate();
    }

    /// @notice Calculate JitoSOL received for SOL deposit
    function previewDeposit(uint256 solAmount) external view returns (uint256 jitosolAmount) {
        uint256 rate = oracle.getJitosolExchangeRate();
        jitosolAmount = (solAmount * RATE_PRECISION) / rate;
    }

    /// @notice Calculate SOL received for JitoSOL withdrawal
    function previewWithdraw(uint256 jitosolAmount) external view returns (uint256 solAmount) {
        uint256 rate = oracle.getJitosolExchangeRate();
        solAmount = (jitosolAmount * rate) / RATE_PRECISION;
    }

    /// @notice Get estimated MEV boost over base staking
    function getMevBoost() external view returns (uint256 boostBps) {
        uint256 jitoApy = oracle.getStakingRewards(JITO_VALIDATORS);
        uint256 baseApy = oracle.getStakingRewards(keccak256("solana_base"));

        if (jitoApy > baseApy) {
            boostBps = jitoApy - baseApy;
        }
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// KAMINO STRATEGY
// ═══════════════════════════════════════════════════════════════════════════════

/**
 * @title KaminoStrategy
 * @notice Cross-chain strategy for Kamino Finance lending and liquidity
 * @dev Deposits to Kamino markets via Wormhole for lending/LP yield
 *
 * Kamino Finance:
 * - Automated liquidity management on Solana
 * - Lending markets (USDC, SOL, etc.)
 * - Concentrated liquidity vaults
 * - ~5-20% APY depending on market
 * - Auto-compounding strategies
 *
 * Supports multiple markets via market ID
 */
contract KaminoStrategy is SolanaStrategyBase {
    using SafeERC20 for IERC20;

    // Protocol identifier
    bytes32 public constant KAMINO_PROTOCOL = keccak256("kamino");

    // Common Kamino market IDs
    bytes32 public constant KAMINO_SOL_LENDING = keccak256("kamino_sol_lending");
    bytes32 public constant KAMINO_USDC_LENDING = keccak256("kamino_usdc_lending");
    bytes32 public constant KAMINO_SOL_USDC_LP = keccak256("kamino_sol_usdc_lp");

    /// @notice Current Kamino market
    bytes32 public market;

    /// @notice kToken (Kamino share token) representation on EVM
    address public immutable kToken;

    /// @notice Market-specific share balance
    uint256 public kTokenBalance;

    /**
     * @notice Construct Kamino strategy
     * @param _vault Vault that controls this strategy
     * @param _wormholeRelayer Wormhole relayer address
     * @param _oracle Solana yield oracle address
     * @param _wSOL Wrapped SOL token address
     * @param _kToken Kamino kToken address
     * @param _solanaReceiver Solana receiver pubkey
     * @param _market Initial Kamino market
     */
    constructor(
        address _vault,
        address _wormholeRelayer,
        address _oracle,
        address _wSOL,
        address _kToken,
        bytes32 _solanaReceiver,
        bytes32 _market
    ) SolanaStrategyBase(
        _vault,
        _wormholeRelayer,
        _oracle,
        _wSOL,
        _solanaReceiver,
        KAMINO_PROTOCOL
    ) {
        kToken = _kToken;
        market = _market;
    }

    /// @notice
    function currentAPY() external view override returns (uint256) {
        return oracle.getKaminoApy(market);
    }

    /// @notice
    function yieldToken() external view override returns (address) {
        return kToken;
    }

    /// @notice
    function name() external view override returns (string memory) {
        return string(abi.encodePacked("Kamino ", _marketName(), " Strategy"));
    }

    /// @notice Get exchange rate (1:1 for share-based accounting)
    function _getExchangeRate() internal pure override returns (uint256) {
        // Kamino uses share-based accounting, rate tracked via oracle reports
        return RATE_PRECISION;
    }

    /// @notice Get market name for display
    function _marketName() internal view returns (string memory) {
        if (market == KAMINO_SOL_LENDING) return "SOL Lending";
        if (market == KAMINO_USDC_LENDING) return "USDC Lending";
        if (market == KAMINO_SOL_USDC_LP) return "SOL-USDC LP";
        return "Custom";
    }

    /// @notice Set Kamino market (admin only)
    function setMarket(bytes32 _market) external onlyOwner {
        market = _market;
    }

    /// @notice Get current market APY
    function getMarketApy() external view returns (uint256) {
        return oracle.getKaminoApy(market);
    }

    /// @notice Check if market is lending or LP
    function isLendingMarket() external view returns (bool) {
        return market == KAMINO_SOL_LENDING || market == KAMINO_USDC_LENDING;
    }

    /// @notice Override deposit to include market in message
    function deposit(uint256 amount) external override onlyVault whenActive nonReentrant returns (uint256 shares) {
        if (amount == 0) revert InvalidAmount();

        // Transfer wSOL from vault
        IERC20(wSOL).safeTransferFrom(msg.sender, address(this), amount);

        // For Kamino, shares = amount (1:1 initially, value tracked via oracle)
        shares = amount;

        // Encode deposit message with market
        bytes memory payload = abi.encode(
            SolanaDepositMessage({
                action: uint8(SolanaAction.DEPOSIT),
                protocol: protocolId,
                amount: amount,
                recipient: solanaReceiver
            }),
            market // Include market ID
        );

        // Get Wormhole fee
        (uint256 fee,) = wormholeRelayer.quoteEVMDeliveryPrice(
            SOLANA_CHAIN_ID,
            0,
            SOLANA_GAS_LIMIT
        );

        // Send via Wormhole
        uint64 sequence = _sendWormholeMessage(payload, fee);

        // Track pending transaction
        _addPendingTransaction(sequence, SolanaAction.DEPOSIT, amount);

        // Update local tracking
        totalShares += shares;
        totalDeposited += amount;
        kTokenBalance += shares;

        emit CrossChainDeposit(protocolId, amount, solanaReceiver, sequence);
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// FACTORY
// ═══════════════════════════════════════════════════════════════════════════════

/**
 * @title SolanaStrategyFactory
 * @notice Factory for deploying Solana cross-chain yield strategies
 */
contract SolanaStrategyFactory {
    // ═══════════════════════════════════════════════════════════════════════
    // EVENTS
    // ═══════════════════════════════════════════════════════════════════════

    event MarinadeStrategyDeployed(address indexed strategy, address vault);
    event JitoStrategyDeployed(address indexed strategy, address vault);
    event KaminoStrategyDeployed(address indexed strategy, address vault, bytes32 market);

    // ═══════════════════════════════════════════════════════════════════════
    // DEPLOY FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════

    /**
     * @notice Deploy Marinade mSOL strategy
     */
    function deployMarinade(
        address vault,
        address wormholeRelayer,
        address oracle,
        address wSOL,
        address wMSOL,
        bytes32 solanaReceiver
    ) external returns (address strategy) {
        strategy = address(new MarinadeStrategy(
            vault,
            wormholeRelayer,
            oracle,
            wSOL,
            wMSOL,
            solanaReceiver
        ));
        emit MarinadeStrategyDeployed(strategy, vault);
    }

    /**
     * @notice Deploy Jito JitoSOL strategy
     */
    function deployJito(
        address vault,
        address wormholeRelayer,
        address oracle,
        address wSOL,
        address wJitoSOL,
        bytes32 solanaReceiver
    ) external returns (address strategy) {
        strategy = address(new JitoStrategy(
            vault,
            wormholeRelayer,
            oracle,
            wSOL,
            wJitoSOL,
            solanaReceiver
        ));
        emit JitoStrategyDeployed(strategy, vault);
    }

    /**
     * @notice Deploy Kamino lending/LP strategy
     */
    function deployKamino(
        address vault,
        address wormholeRelayer,
        address oracle,
        address wSOL,
        address kToken,
        bytes32 solanaReceiver,
        bytes32 market
    ) external returns (address strategy) {
        strategy = address(new KaminoStrategy(
            vault,
            wormholeRelayer,
            oracle,
            wSOL,
            kToken,
            solanaReceiver,
            market
        ));
        emit KaminoStrategyDeployed(strategy, vault, market);
    }
}
