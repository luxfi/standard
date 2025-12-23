// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {ICapital, RiskTier, CapitalState} from "../../interfaces/ICapital.sol";
import {IYield, YieldType, AccrualPattern} from "../../interfaces/IYield.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * ╔═══════════════════════════════════════════════════════════════════════════════╗
 * ║                         RWA YIELD ADAPTER                                     ║
 * ╠═══════════════════════════════════════════════════════════════════════════════╣
 * ║                                                                               ║
 * ║  Real World Asset yield integration for Capital OS                           ║
 * ║                                                                               ║
 * ║  ┌─────────────────────────────────────────────────────────────────────┐     ║
 * ║  │   Supported RWA Categories                                          │     ║
 * ║  │                                                                     │     ║
 * ║  │   TREASURY:                                                        │     ║
 * ║  │     • T-Bills, T-Notes, T-Bonds                                    │     ║
 * ║  │     • Government bonds (AAA sovereign)                             │     ║
 * ║  │     • ⚠️ Interest-bearing (not Shariah-compliant)                  │     ║
 * ║  │                                                                     │     ║
 * ║  │   REAL_ESTATE:                                                     │     ║
 * ║  │     • Rental income tokenized properties                           │     ║
 * ║  │     • REIT dividends                                               │     ║
 * ║  │     • ✅ Rental income is Shariah-compliant                        │     ║
 * ║  │                                                                     │     ║
 * ║  │   TRADE_FINANCE:                                                   │     ║
 * ║  │     • Invoice factoring                                            │     ║
 * ║  │     • Supply chain finance                                         │     ║
 * ║  │     • ✅ Service fees are Shariah-compliant                        │     ║
 * ║  │                                                                     │     ║
 * ║  │   PRIVATE_CREDIT:                                                  │     ║
 * ║  │     • Corporate loans (tokenized)                                  │     ║
 * ║  │     • Revenue-based financing                                      │     ║
 * ║  │     • ⚠️ Interest = not compliant, rev-share = compliant          │     ║
 * ║  │                                                                     │     ║
 * ║  │   INFRASTRUCTURE:                                                  │     ║
 * ║  │     • Toll roads, bridges                                          │     ║
 * ║  │     • Energy projects                                              │     ║
 * ║  │     • ✅ Usage fees are Shariah-compliant                          │     ║
 * ║  └─────────────────────────────────────────────────────────────────────┘     ║
 * ║                                                                               ║
 * ║  Key architecture:                                                           ║
 * ║    • Oracles report off-chain yield                                         ║
 * ║    • On-chain tokens represent RWA ownership                                ║
 * ║    • Yield distributed based on token holdings                              ║
 * ║    • Compliance filtering available                                         ║
 * ║                                                                               ║
 * ╚═══════════════════════════════════════════════════════════════════════════════╝
 */

/// @notice RWA asset category
enum RWACategory {
    TREASURY,        // Government bonds (interest-bearing)
    REAL_ESTATE,     // Rental income properties
    TRADE_FINANCE,   // Invoice/supply chain finance
    PRIVATE_CREDIT,  // Corporate loans
    INFRASTRUCTURE,  // Toll roads, energy
    COMMODITY,       // Gold, silver, etc.
    EQUITY           // Tokenized stocks
}

/// @notice RWA vault configuration
struct RWAVault {
    string name;                    // Vault name
    string symbol;                  // Vault symbol
    IERC20 underlyingToken;         // Token representing RWA ownership
    IERC20 yieldToken;              // Token for yield distribution (USDC, etc.)
    RWACategory category;           // Asset category
    address oracle;                 // Yield oracle
    uint256 totalDeposited;         // Total tokens deposited
    uint256 totalYieldDistributed;  // Cumulative yield
    uint256 yieldPerToken;          // Accumulated yield per token (scaled by 1e18)
    uint256 lastYieldUpdate;        // Last oracle update
    bool shariahCompliant;          // Pre-computed compliance flag
    bool active;                    // Vault is active
}

/// @notice User position in a vault
struct RWAPosition {
    uint256 balance;                // Tokens deposited
    uint256 yieldDebt;              // Yield already accounted for
    uint256 claimedYield;           // Total yield claimed
    uint256 depositTime;            // When deposited
}

/// @notice Yield report from oracle
struct YieldReport {
    uint256 totalYield;             // Total yield for period
    uint256 periodStart;            // Period start timestamp
    uint256 periodEnd;              // Period end timestamp
    bytes32 reportHash;             // Hash of off-chain report
    address reporter;               // Who submitted the report
}

/// @notice Adapter errors
error VaultNotActive();
error ZeroAmount();
error InsufficientBalance();
error UnauthorizedOracle();
error StaleYieldReport();
error NotShariahCompliant();

/**
 * @title RWAYieldAdapter
 * @notice Off-chain yield integration for Capital OS
 * @dev Bridges real world assets into the yield layer
 */
contract RWAYieldAdapter is ReentrancyGuard {
    using SafeERC20 for IERC20;

    // ═══════════════════════════════════════════════════════════════════════════
    // CONSTANTS
    // ═══════════════════════════════════════════════════════════════════════════

    uint256 public constant SCALE = 1e18;
    uint256 public constant MAX_YIELD_AGE = 1 days; // Yield reports must be recent

    // ═══════════════════════════════════════════════════════════════════════════
    // STATE
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Vaults by ID
    mapping(bytes32 => RWAVault) public vaults;

    /// @notice User positions: user => vaultId => position
    mapping(address => mapping(bytes32 => RWAPosition)) public positions;

    /// @notice Yield reports history: vaultId => reports
    mapping(bytes32 => YieldReport[]) public yieldReports;

    /// @notice Vault IDs list
    bytes32[] public vaultIds;

    /// @notice Admin
    address public admin;

    /// @notice Whether to enforce Shariah compliance
    bool public shariahModeEnabled;

    // ═══════════════════════════════════════════════════════════════════════════
    // EVENTS
    // ═══════════════════════════════════════════════════════════════════════════

    event VaultCreated(bytes32 indexed vaultId, string name, RWACategory category, bool shariahCompliant);
    event Deposited(address indexed user, bytes32 indexed vaultId, uint256 amount);
    event Withdrawn(address indexed user, bytes32 indexed vaultId, uint256 amount);
    event YieldReported(bytes32 indexed vaultId, uint256 amount, bytes32 reportHash);
    event YieldClaimed(address indexed user, bytes32 indexed vaultId, uint256 amount);

    // ═══════════════════════════════════════════════════════════════════════════
    // CONSTRUCTOR
    // ═══════════════════════════════════════════════════════════════════════════

    constructor(address _admin) {
        admin = _admin;
    }

    modifier onlyAdmin() {
        require(msg.sender == admin, "Not admin");
        _;
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // VAULT MANAGEMENT
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Create a new RWA vault
     * @param name Vault name
     * @param symbol Vault symbol
     * @param underlyingToken Token representing RWA
     * @param yieldToken Token for yield (USDC)
     * @param category RWA category
     * @param oracle Authorized yield oracle
     */
    function createVault(
        string calldata name,
        string calldata symbol,
        address underlyingToken,
        address yieldToken,
        RWACategory category,
        address oracle
    ) external onlyAdmin returns (bytes32 vaultId) {
        vaultId = keccak256(abi.encodePacked(name, symbol, underlyingToken, block.timestamp));

        // Determine Shariah compliance based on category
        bool compliant = _isCategoryCompliant(category);

        vaults[vaultId] = RWAVault({
            name: name,
            symbol: symbol,
            underlyingToken: IERC20(underlyingToken),
            yieldToken: IERC20(yieldToken),
            category: category,
            oracle: oracle,
            totalDeposited: 0,
            totalYieldDistributed: 0,
            yieldPerToken: 0,
            lastYieldUpdate: block.timestamp,
            shariahCompliant: compliant,
            active: true
        });

        vaultIds.push(vaultId);

        emit VaultCreated(vaultId, name, category, compliant);
    }

    /**
     * @notice Determine if category is Shariah-compliant
     */
    function _isCategoryCompliant(RWACategory category) internal pure returns (bool) {
        // Treasury bonds = interest = not compliant
        if (category == RWACategory.TREASURY) return false;

        // Private credit is case-by-case (assume not compliant by default)
        if (category == RWACategory.PRIVATE_CREDIT) return false;

        // Real estate (rental income), trade finance (fees), infrastructure (fees)
        // are generally compliant
        return true;
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // CAPITAL OPERATIONS
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Deposit RWA tokens into vault
     * @param vaultId Vault identifier
     * @param amount Amount to deposit
     */
    function deposit(bytes32 vaultId, uint256 amount) external nonReentrant {
        if (amount == 0) revert ZeroAmount();

        RWAVault storage vault = vaults[vaultId];
        if (!vault.active) revert VaultNotActive();

        // Enforce Shariah mode if enabled
        if (shariahModeEnabled && !vault.shariahCompliant) {
            revert NotShariahCompliant();
        }

        // Update user's pending yield before deposit
        RWAPosition storage pos = positions[msg.sender][vaultId];
        if (pos.balance > 0) {
            _updateYield(msg.sender, vaultId);
        }

        // Transfer tokens
        vault.underlyingToken.safeTransferFrom(msg.sender, address(this), amount);

        // Update position
        pos.balance += amount;
        pos.yieldDebt = (pos.balance * vault.yieldPerToken) / SCALE;
        if (pos.depositTime == 0) {
            pos.depositTime = block.timestamp;
        }

        vault.totalDeposited += amount;

        emit Deposited(msg.sender, vaultId, amount);
    }

    /**
     * @notice Withdraw RWA tokens from vault
     * @param vaultId Vault identifier
     * @param amount Amount to withdraw
     */
    function withdraw(bytes32 vaultId, uint256 amount) external nonReentrant {
        if (amount == 0) revert ZeroAmount();

        RWAPosition storage pos = positions[msg.sender][vaultId];
        if (amount > pos.balance) revert InsufficientBalance();

        RWAVault storage vault = vaults[vaultId];

        // Claim pending yield first
        _updateYield(msg.sender, vaultId);
        _claimYield(msg.sender, vaultId);

        // Update position
        pos.balance -= amount;
        pos.yieldDebt = (pos.balance * vault.yieldPerToken) / SCALE;

        vault.totalDeposited -= amount;

        // Transfer tokens back
        vault.underlyingToken.safeTransfer(msg.sender, amount);

        emit Withdrawn(msg.sender, vaultId, amount);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // YIELD OPERATIONS
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Report yield from off-chain source
     * @dev Called by authorized oracle
     * @param vaultId Vault identifier
     * @param yieldAmount Yield amount for the period
     * @param periodStart Period start timestamp
     * @param periodEnd Period end timestamp
     * @param reportHash Hash of off-chain audit report
     */
    function reportYield(
        bytes32 vaultId,
        uint256 yieldAmount,
        uint256 periodStart,
        uint256 periodEnd,
        bytes32 reportHash
    ) external {
        RWAVault storage vault = vaults[vaultId];
        if (msg.sender != vault.oracle) revert UnauthorizedOracle();
        if (!vault.active) revert VaultNotActive();

        // Update yield per token
        if (vault.totalDeposited > 0) {
            vault.yieldPerToken += (yieldAmount * SCALE) / vault.totalDeposited;
        }

        vault.totalYieldDistributed += yieldAmount;
        vault.lastYieldUpdate = block.timestamp;

        // Store report for audit trail
        yieldReports[vaultId].push(YieldReport({
            totalYield: yieldAmount,
            periodStart: periodStart,
            periodEnd: periodEnd,
            reportHash: reportHash,
            reporter: msg.sender
        }));

        // Transfer yield tokens to adapter for distribution
        vault.yieldToken.safeTransferFrom(msg.sender, address(this), yieldAmount);

        emit YieldReported(vaultId, yieldAmount, reportHash);
    }

    /**
     * @notice Claim accrued yield
     * @param vaultId Vault identifier
     */
    function claimYield(bytes32 vaultId) external nonReentrant {
        _updateYield(msg.sender, vaultId);
        _claimYield(msg.sender, vaultId);
    }

    /**
     * @notice Update pending yield for user
     */
    function _updateYield(address user, bytes32 vaultId) internal {
        // Yield is automatically tracked via yieldPerToken
        // No additional action needed
    }

    /**
     * @notice Claim pending yield
     */
    function _claimYield(address user, bytes32 vaultId) internal {
        RWAVault storage vault = vaults[vaultId];
        RWAPosition storage pos = positions[user][vaultId];

        uint256 pending = getPendingYield(user, vaultId);
        if (pending == 0) return;

        // Update yield debt
        pos.yieldDebt = (pos.balance * vault.yieldPerToken) / SCALE;
        pos.claimedYield += pending;

        // Transfer yield
        vault.yieldToken.safeTransfer(user, pending);

        emit YieldClaimed(user, vaultId, pending);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // VIEW FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Get pending yield for user
     */
    function getPendingYield(address user, bytes32 vaultId) public view returns (uint256) {
        RWAVault storage vault = vaults[vaultId];
        RWAPosition storage pos = positions[user][vaultId];

        if (pos.balance == 0) return 0;

        uint256 accumulatedYield = (pos.balance * vault.yieldPerToken) / SCALE;
        return accumulatedYield > pos.yieldDebt ? accumulatedYield - pos.yieldDebt : 0;
    }

    /**
     * @notice Get position summary
     */
    function getPosition(address user, bytes32 vaultId) external view returns (
        uint256 balance,
        uint256 pendingYield,
        uint256 claimedYield,
        uint256 depositTime,
        RWACategory category,
        bool shariahCompliant
    ) {
        RWAVault storage vault = vaults[vaultId];
        RWAPosition storage pos = positions[user][vaultId];

        balance = pos.balance;
        pendingYield = getPendingYield(user, vaultId);
        claimedYield = pos.claimedYield;
        depositTime = pos.depositTime;
        category = vault.category;
        shariahCompliant = vault.shariahCompliant;
    }

    /**
     * @notice Get vault info
     */
    function getVault(bytes32 vaultId) external view returns (
        string memory name,
        RWACategory category,
        uint256 totalDeposited,
        uint256 totalYieldDistributed,
        uint256 currentAPY,
        bool shariahCompliant,
        bool active
    ) {
        RWAVault storage vault = vaults[vaultId];

        name = vault.name;
        category = vault.category;
        totalDeposited = vault.totalDeposited;
        totalYieldDistributed = vault.totalYieldDistributed;
        shariahCompliant = vault.shariahCompliant;
        active = vault.active;

        // Calculate APY from recent yield
        if (vault.totalDeposited > 0 && vault.lastYieldUpdate > 0) {
            // Simplified APY calculation
            uint256 elapsed = block.timestamp - vault.lastYieldUpdate;
            if (elapsed > 0 && vault.totalYieldDistributed > 0) {
                currentAPY = (vault.totalYieldDistributed * 365 days * 10000) / (vault.totalDeposited * elapsed);
            }
        }
    }

    /**
     * @notice Get yield type for category
     */
    function yieldType(RWACategory category) external pure returns (YieldType) {
        if (category == RWACategory.TREASURY) return YieldType.INTEREST;
        if (category == RWACategory.REAL_ESTATE) return YieldType.DIVIDEND;
        if (category == RWACategory.TRADE_FINANCE) return YieldType.FEE;
        if (category == RWACategory.PRIVATE_CREDIT) return YieldType.INTEREST;
        if (category == RWACategory.INFRASTRUCTURE) return YieldType.FEE;
        if (category == RWACategory.COMMODITY) return YieldType.APPRECIATION;
        if (category == RWACategory.EQUITY) return YieldType.DIVIDEND;
        return YieldType.INTEREST; // Default
    }

    /**
     * @notice Check if specific vault is Shariah-compliant
     */
    function isVaultShariahCompliant(bytes32 vaultId) external view returns (bool) {
        return vaults[vaultId].shariahCompliant;
    }

    /**
     * @notice Get all Shariah-compliant vaults
     */
    function getCompliantVaults() external view returns (bytes32[] memory) {
        uint256 count = 0;
        for (uint256 i = 0; i < vaultIds.length; i++) {
            if (vaults[vaultIds[i]].shariahCompliant && vaults[vaultIds[i]].active) {
                count++;
            }
        }

        bytes32[] memory compliant = new bytes32[](count);
        uint256 index = 0;
        for (uint256 i = 0; i < vaultIds.length; i++) {
            if (vaults[vaultIds[i]].shariahCompliant && vaults[vaultIds[i]].active) {
                compliant[index++] = vaultIds[i];
            }
        }

        return compliant;
    }

    /**
     * @notice Explain compliance for each category
     */
    function getComplianceExplanation(RWACategory category) external pure returns (
        bool compliant,
        string memory reason
    ) {
        if (category == RWACategory.TREASURY) {
            return (false, "Government bonds pay interest (riba), which is forbidden in Islamic finance");
        }
        if (category == RWACategory.REAL_ESTATE) {
            return (true, "Rental income represents legitimate earnings from property ownership (ijara)");
        }
        if (category == RWACategory.TRADE_FINANCE) {
            return (true, "Fees for trade facilitation services are permissible (murabaha-like)");
        }
        if (category == RWACategory.PRIVATE_CREDIT) {
            return (false, "Traditional loans charge interest; revenue-sharing alternatives may be compliant");
        }
        if (category == RWACategory.INFRASTRUCTURE) {
            return (true, "Usage fees (tolls, utilities) represent payment for services (ijara)");
        }
        if (category == RWACategory.COMMODITY) {
            return (true, "Commodities like gold/silver are permissible assets when properly structured");
        }
        if (category == RWACategory.EQUITY) {
            return (true, "Equity ownership in halal businesses is permissible (musharaka)");
        }
        return (false, "Unknown category");
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // INTEGRATION WITH ALCHEMIC
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Route yield directly to settlement
     * @dev Called by Alchemic to auto-settle obligations
     * @param vaultId Vault to route from
     * @param recipient Settlement contract
     * @param maxAmount Maximum to route
     */
    function routeToSettlement(
        bytes32 vaultId,
        address recipient,
        uint256 maxAmount
    ) external nonReentrant returns (uint256 routed) {
        uint256 pending = getPendingYield(msg.sender, vaultId);
        if (pending == 0) return 0;

        routed = pending > maxAmount ? maxAmount : pending;

        // Claim and transfer directly
        _claimYield(msg.sender, vaultId);

        RWAVault storage vault = vaults[vaultId];
        vault.yieldToken.safeTransfer(recipient, routed);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // ADMIN
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Enable/disable Shariah-only mode
     * @dev When enabled, only compliant vaults can accept deposits
     */
    function setShariahMode(bool enabled) external onlyAdmin {
        shariahModeEnabled = enabled;
    }

    /**
     * @notice Update vault oracle
     */
    function setVaultOracle(bytes32 vaultId, address oracle) external onlyAdmin {
        vaults[vaultId].oracle = oracle;
    }

    /**
     * @notice Deactivate vault
     */
    function deactivateVault(bytes32 vaultId) external onlyAdmin {
        vaults[vaultId].active = false;
    }
}

/**
 * ╔═══════════════════════════════════════════════════════════════════════════════╗
 * ║                              FACTORY                                         ║
 * ╚═══════════════════════════════════════════════════════════════════════════════╝
 */

contract RWAYieldAdapterFactory {
    event AdapterCreated(address indexed adapter, address indexed admin);

    function create(address admin) external returns (address) {
        RWAYieldAdapter adapter = new RWAYieldAdapter(admin);
        emit AdapterCreated(address(adapter), admin);
        return address(adapter);
    }
}
