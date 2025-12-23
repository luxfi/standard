// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {AlchemicCredit, CreditPosition} from "./AlchemicCredit.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Monotonicity} from "../../interfaces/IObligation.sol";

/**
 * ╔═══════════════════════════════════════════════════════════════════════════════╗
 * ║                        SELF-REPAYING CREDIT CARD                              ║
 * ╠═══════════════════════════════════════════════════════════════════════════════╣
 * ║                                                                               ║
 * ║  The world's first credit card where TIME pays off your balance.             ║
 * ║                                                                               ║
 * ║  ┌─────────────────────────────────────────────────────────────────────┐     ║
 * ║  │   Traditional Credit Card          │  Self-Repaying Credit Card    │     ║
 * ║  │   ─────────────────────────────────│──────────────────────────────│     ║
 * ║  │   Balance: $1,000                  │  Balance: $1,000             │     ║
 * ║  │   After 1 year at 20% APR:         │  After 1 year at 5% yield:   │     ║
 * ║  │   Balance: $1,200 (+$200)          │  Balance: $500 (-$500)       │     ║
 * ║  │                                    │                              │     ║
 * ║  │   TIME WORKS AGAINST YOU           │  TIME WORKS FOR YOU          │     ║
 * ║  │   ↑ INCREASING (riba)              │  ↓ DECREASING (halal)        │     ║
 * ║  └─────────────────────────────────────────────────────────────────────┘     ║
 * ║                                                                               ║
 * ║  How it works:                                                               ║
 * ║    1. Deposit collateral (stablecoins, ETH, etc.)                           ║
 * ║    2. Your collateral earns yield (DeFi strategies)                         ║
 * ║    3. Spend using your credit card (virtual or physical)                    ║
 * ║    4. Yield automatically pays off your spending                            ║
 * ║    5. No interest. No fees. No debt spiral.                                 ║
 * ║                                                                               ║
 * ║  Who this is for:                                                           ║
 * ║    • Anyone who wants interest-free credit                                  ║
 * ║    • Muslims seeking Shariah-compliant banking                              ║
 * ║    • The unbanked (no credit score needed)                                  ║
 * ║    • Anyone who believes TIME should work FOR them                          ║
 * ║                                                                               ║
 * ╚═══════════════════════════════════════════════════════════════════════════════╝
 */

/// @notice Card status
enum CardStatus {
    INACTIVE,   // Not yet activated
    ACTIVE,     // Card is active and can spend
    FROZEN,     // Temporarily frozen by user
    CANCELLED   // Permanently cancelled
}

/// @notice Transaction type
enum TransactionType {
    PURCHASE,   // Regular purchase
    WITHDRAWAL, // Cash withdrawal
    REFUND,     // Merchant refund
    REWARD      // Reward credit
}

/// @notice Card configuration
struct CardConfig {
    uint256 dailyLimit;          // Max spend per day
    uint256 transactionLimit;    // Max per transaction
    uint256 monthlyLimit;        // Max spend per month
    bool onlineEnabled;          // Allow online purchases
    bool internationalEnabled;   // Allow international
    bool contactlessEnabled;     // Allow contactless
}

/// @notice Card holder data
struct CardHolder {
    address owner;              // Card owner
    bytes32 cardHash;           // Hash of card number (privacy)
    CardStatus status;          // Card status
    CardConfig config;          // Card configuration
    uint256 spentToday;         // Spent today
    uint256 spentThisMonth;     // Spent this month
    uint256 lastSpendDate;      // Last spend timestamp
    uint256 lastSpendMonth;     // Last spend month
    uint256 totalSpent;         // Lifetime spend
    uint256 totalRepaid;        // Total auto-repaid
}

/// @notice Transaction record
struct Transaction {
    uint256 amount;             // Transaction amount
    uint256 timestamp;          // When it happened
    bytes32 merchantId;         // Merchant identifier
    TransactionType txType;     // Type of transaction
    bool settled;               // Has been settled by yield
}

/// @notice Card errors
error CardNotActive();
error CardFrozen();
error DailyLimitExceeded();
error TransactionLimitExceeded();
error MonthlyLimitExceeded();
error OnlinePurchasesDisabled();
error InternationalDisabled();
error InsufficientCredit();
error NotCardOwner();
error CardAlreadyExists();
error InvalidCardConfig();

/**
 * @title CreditCard
 * @notice Self-repaying credit card powered by AlchemicCredit
 * @dev User-facing interface for ethical credit
 */
contract CreditCard is ReentrancyGuard {
    using SafeERC20 for IERC20;

    // ═══════════════════════════════════════════════════════════════════════════
    // STATE
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice The underlying credit engine
    AlchemicCredit public immutable creditEngine;

    /// @notice Card holder data by address
    mapping(address => CardHolder) public cardHolders;

    /// @notice Transaction history by user
    mapping(address => Transaction[]) public transactionHistory;

    /// @notice Authorized payment processors
    mapping(address => bool) public authorizedProcessors;

    /// @notice Card number hash to owner (for processor lookups)
    mapping(bytes32 => address) public cardToOwner;

    /// @notice Total cards issued
    uint256 public totalCardsIssued;

    /// @notice Total volume processed
    uint256 public totalVolumeProcessed;

    // ═══════════════════════════════════════════════════════════════════════════
    // EVENTS
    // ═══════════════════════════════════════════════════════════════════════════

    event CardIssued(address indexed holder, bytes32 cardHash);
    event CardActivated(address indexed holder);
    event CardFrozenEvent(address indexed holder);
    event CardUnfrozen(address indexed holder);
    event CardCancelled(address indexed holder);
    event Purchase(
        address indexed holder,
        uint256 amount,
        bytes32 merchantId,
        uint256 newObligation
    );
    event Refund(
        address indexed holder,
        uint256 amount,
        bytes32 merchantId
    );
    event AutoRepayment(
        address indexed holder,
        uint256 amount,
        uint256 remainingObligation
    );
    event LimitsUpdated(
        address indexed holder,
        uint256 daily,
        uint256 transaction,
        uint256 monthly
    );

    // ═══════════════════════════════════════════════════════════════════════════
    // CONSTRUCTOR
    // ═══════════════════════════════════════════════════════════════════════════

    constructor(address _creditEngine) {
        creditEngine = AlchemicCredit(_creditEngine);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // CARD MANAGEMENT
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Issue a new credit card to a user
     * @param cardHash Hash of the card number (16 digits)
     * @param config Initial card configuration
     */
    function issueCard(
        bytes32 cardHash,
        CardConfig calldata config
    ) external nonReentrant {
        if (cardHolders[msg.sender].owner != address(0)) revert CardAlreadyExists();
        if (config.dailyLimit == 0 || config.transactionLimit == 0) revert InvalidCardConfig();

        cardHolders[msg.sender] = CardHolder({
            owner: msg.sender,
            cardHash: cardHash,
            status: CardStatus.ACTIVE,
            config: config,
            spentToday: 0,
            spentThisMonth: 0,
            lastSpendDate: 0,
            lastSpendMonth: 0,
            totalSpent: 0,
            totalRepaid: 0
        });

        cardToOwner[cardHash] = msg.sender;
        totalCardsIssued++;

        emit CardIssued(msg.sender, cardHash);
        emit CardActivated(msg.sender);
    }

    /**
     * @notice Freeze card (temporary suspension)
     */
    function freezeCard() external {
        CardHolder storage card = cardHolders[msg.sender];
        if (card.owner != msg.sender) revert NotCardOwner();
        if (card.status != CardStatus.ACTIVE) revert CardNotActive();

        card.status = CardStatus.FROZEN;
        emit CardFrozenEvent(msg.sender);
    }

    /**
     * @notice Unfreeze card
     */
    function unfreezeCard() external {
        CardHolder storage card = cardHolders[msg.sender];
        if (card.owner != msg.sender) revert NotCardOwner();
        if (card.status != CardStatus.FROZEN) revert CardFrozen();

        card.status = CardStatus.ACTIVE;
        emit CardUnfrozen(msg.sender);
    }

    /**
     * @notice Cancel card permanently
     */
    function cancelCard() external {
        CardHolder storage card = cardHolders[msg.sender];
        if (card.owner != msg.sender) revert NotCardOwner();

        card.status = CardStatus.CANCELLED;
        delete cardToOwner[card.cardHash];
        emit CardCancelled(msg.sender);
    }

    /**
     * @notice Update card spending limits
     */
    function updateLimits(
        uint256 dailyLimit,
        uint256 transactionLimit,
        uint256 monthlyLimit
    ) external {
        CardHolder storage card = cardHolders[msg.sender];
        if (card.owner != msg.sender) revert NotCardOwner();

        card.config.dailyLimit = dailyLimit;
        card.config.transactionLimit = transactionLimit;
        card.config.monthlyLimit = monthlyLimit;

        emit LimitsUpdated(msg.sender, dailyLimit, transactionLimit, monthlyLimit);
    }

    /**
     * @notice Toggle online purchases
     */
    function setOnlineEnabled(bool enabled) external {
        CardHolder storage card = cardHolders[msg.sender];
        if (card.owner != msg.sender) revert NotCardOwner();
        card.config.onlineEnabled = enabled;
    }

    /**
     * @notice Toggle international purchases
     */
    function setInternationalEnabled(bool enabled) external {
        CardHolder storage card = cardHolders[msg.sender];
        if (card.owner != msg.sender) revert NotCardOwner();
        card.config.internationalEnabled = enabled;
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // PAYMENT PROCESSING
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Process a purchase (called by authorized processor)
     * @param cardHash Card identifier hash
     * @param amount Purchase amount
     * @param merchantId Merchant identifier
     * @param isOnline Is this an online purchase
     * @param isInternational Is this an international purchase
     */
    function processPurchase(
        bytes32 cardHash,
        uint256 amount,
        bytes32 merchantId,
        bool isOnline,
        bool isInternational
    ) external nonReentrant returns (bool) {
        if (!authorizedProcessors[msg.sender]) revert NotCardOwner();

        address holder = cardToOwner[cardHash];
        CardHolder storage card = cardHolders[holder];

        // Check card status
        if (card.status != CardStatus.ACTIVE) revert CardNotActive();
        if (card.status == CardStatus.FROZEN) revert CardFrozen();

        // Check restrictions
        if (isOnline && !card.config.onlineEnabled) revert OnlinePurchasesDisabled();
        if (isInternational && !card.config.internationalEnabled) revert InternationalDisabled();

        // Reset daily/monthly counters if needed
        _resetCountersIfNeeded(card);

        // Check limits
        if (amount > card.config.transactionLimit) revert TransactionLimitExceeded();
        if (card.spentToday + amount > card.config.dailyLimit) revert DailyLimitExceeded();
        if (card.spentThisMonth + amount > card.config.monthlyLimit) revert MonthlyLimitExceeded();

        // Check available credit from engine
        (,,, uint256 availableCredit,,) = creditEngine.getPosition(holder);
        if (amount > availableCredit) revert InsufficientCredit();

        // Execute advance from credit engine
        // Note: In production, this would be called through a meta-transaction
        // or authorized operator pattern
        // creditEngine.takeAdvanceFor(holder, amount);

        // Update card state
        card.spentToday += amount;
        card.spentThisMonth += amount;
        card.totalSpent += amount;
        totalVolumeProcessed += amount;

        // Record transaction
        transactionHistory[holder].push(Transaction({
            amount: amount,
            timestamp: block.timestamp,
            merchantId: merchantId,
            txType: TransactionType.PURCHASE,
            settled: false
        }));

        emit Purchase(holder, amount, merchantId, 0); // TODO: Get actual obligation

        return true;
    }

    /**
     * @notice Process a refund
     * @param cardHash Card identifier hash
     * @param amount Refund amount
     * @param merchantId Merchant identifier
     */
    function processRefund(
        bytes32 cardHash,
        uint256 amount,
        bytes32 merchantId
    ) external nonReentrant returns (bool) {
        if (!authorizedProcessors[msg.sender]) revert NotCardOwner();

        address holder = cardToOwner[cardHash];
        CardHolder storage card = cardHolders[holder];

        // Refunds don't require active card
        if (card.owner == address(0)) revert NotCardOwner();

        // Update state (reduce obligation)
        card.spentToday = card.spentToday > amount ? card.spentToday - amount : 0;
        card.spentThisMonth = card.spentThisMonth > amount ? card.spentThisMonth - amount : 0;

        // Record transaction
        transactionHistory[holder].push(Transaction({
            amount: amount,
            timestamp: block.timestamp,
            merchantId: merchantId,
            txType: TransactionType.REFUND,
            settled: true
        }));

        emit Refund(holder, amount, merchantId);

        return true;
    }

    /**
     * @notice Trigger yield harvest and auto-repayment
     * @dev Anyone can call this to trigger settlement
     */
    function triggerAutoRepayment(address holder) external nonReentrant {
        // Settle position in credit engine
        creditEngine.settle();

        // Get updated position
        (, uint256 obligation,,,,) = creditEngine.getPosition(holder);

        // Calculate repayment
        CardHolder storage card = cardHolders[holder];
        uint256 prevTotal = card.totalSpent - card.totalRepaid;
        uint256 repaid = prevTotal > obligation ? prevTotal - obligation : 0;

        if (repaid > 0) {
            card.totalRepaid += repaid;
            emit AutoRepayment(holder, repaid, obligation);
        }
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // INTERNAL
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Reset daily/monthly counters if in new period
     */
    function _resetCountersIfNeeded(CardHolder storage card) internal {
        uint256 today = block.timestamp / 1 days;
        uint256 thisMonth = block.timestamp / 30 days;

        if (card.lastSpendDate < today) {
            card.spentToday = 0;
            card.lastSpendDate = today;
        }

        if (card.lastSpendMonth < thisMonth) {
            card.spentThisMonth = 0;
            card.lastSpendMonth = thisMonth;
        }
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // VIEW FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Get card summary for user
     */
    function getCardSummary(address holder) external view returns (
        CardStatus status,
        uint256 availableCredit,
        uint256 currentObligation,
        uint256 spentToday,
        uint256 spentThisMonth,
        uint256 dailyRemaining,
        uint256 monthlyRemaining,
        uint256 timeToFullRepayment
    ) {
        CardHolder storage card = cardHolders[holder];
        status = card.status;
        spentToday = card.spentToday;
        spentThisMonth = card.spentThisMonth;

        // Get credit engine position
        (, currentObligation,, availableCredit,, timeToFullRepayment) =
            creditEngine.getPosition(holder);

        // Calculate remaining limits
        dailyRemaining = card.config.dailyLimit > spentToday
            ? card.config.dailyLimit - spentToday
            : 0;
        monthlyRemaining = card.config.monthlyLimit > spentThisMonth
            ? card.config.monthlyLimit - spentThisMonth
            : 0;
    }

    /**
     * @notice Get transaction history
     */
    function getTransactions(
        address holder,
        uint256 offset,
        uint256 limit
    ) external view returns (Transaction[] memory) {
        Transaction[] storage allTx = transactionHistory[holder];
        uint256 total = allTx.length;

        if (offset >= total) {
            return new Transaction[](0);
        }

        uint256 end = offset + limit > total ? total : offset + limit;
        uint256 count = end - offset;

        Transaction[] memory result = new Transaction[](count);
        for (uint256 i = 0; i < count; i++) {
            result[i] = allTx[total - 1 - offset - i]; // Most recent first
        }

        return result;
    }

    /**
     * @notice Get repayment projection
     * @dev Shows how balance will decrease over time
     */
    function getRepaymentProjection(address holder) external view returns (
        uint256 currentObligation,
        uint256 in30Days,
        uint256 in90Days,
        uint256 in180Days,
        uint256 in365Days,
        uint256 daysToZero
    ) {
        uint256 timeToZero;
        (, currentObligation,,,, timeToZero) = creditEngine.getPosition(holder);

        // Simplified projection (real impl would use actual APY)
        uint256 monthlyRate = currentObligation * 500 / (10000 * 12); // ~5% APY / 12

        in30Days = currentObligation > monthlyRate ? currentObligation - monthlyRate : 0;
        in90Days = currentObligation > monthlyRate * 3 ? currentObligation - monthlyRate * 3 : 0;
        in180Days = currentObligation > monthlyRate * 6 ? currentObligation - monthlyRate * 6 : 0;
        in365Days = currentObligation > monthlyRate * 12 ? currentObligation - monthlyRate * 12 : 0;

        daysToZero = timeToZero / 1 days;
    }

    /**
     * @notice Check if credit card is Shariah-compliant
     * @dev Delegates to underlying engine - always true for AlchemicCredit
     */
    function isShariahCompliant() external view returns (bool) {
        return creditEngine.isShariahCompliant();
    }

    /**
     * @notice Get obligation direction
     * @dev Always DECREASING for this card
     */
    function obligationDirection() external view returns (Monotonicity) {
        return creditEngine.obligationDirection();
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // ADMIN
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Authorize a payment processor
     */
    function authorizeProcessor(address processor, bool authorized) external {
        // TODO: Add access control
        authorizedProcessors[processor] = authorized;
    }
}

/**
 * ╔═══════════════════════════════════════════════════════════════════════════════╗
 * ║                              FACTORY                                         ║
 * ╚═══════════════════════════════════════════════════════════════════════════════╝
 */

contract CreditCardFactory {
    event CreditCardCreated(address indexed card, address indexed creditEngine);

    function create(address creditEngine) external returns (address) {
        CreditCard card = new CreditCard(creditEngine);
        emit CreditCardCreated(address(card), creditEngine);
        return address(card);
    }
}
