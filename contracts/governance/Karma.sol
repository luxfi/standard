// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.31;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

import {IDIDRegistry} from "../identity/interfaces/IDID.sol";

/**
 * @title Karma (K) - Soul-Bound Reputation Token
 * @notice Non-transferable reputation score bound to decentralized identifiers (DIDs)
 * @dev Implements LP-3002 Governance Token Stack
 *
 * K TOKENOMICS:
 * ┌─────────────────────────────────────────────────────────────────────────────┐
 * │  K (Karma) is a soul-bound token representing human legitimacy              │
 * │                                                                             │
 * │  Properties:                                                                │
 * │  - Non-transferable (soul-bound to address/DID)                             │
 * │  - Minted by approved attestation providers                                 │
 * │  - Burned as governance penalty (slashing)                                  │
 * │  - Max 1000 K per account (soft cap)                                        │
 * │                                                                             │
 * │  Earning K:                                                                 │
 * │  - Identity verification: +100 K                                            │
 * │  - Proof of Humanity: +200 K                                                │
 * │  - Governance participation: +1-50 K                                        │
 * │  - Community contribution: +10-100 K                                        │
 * │                                                                             │
 * │  Losing K:                                                                  │
 * │  - Governance penalty: -50 to -500 K                                        │
 * │  - Failed malicious proposal: -100 K                                        │
 * │  - Slashing event: -25% of K                                                │
 * │  - Activity-driven decay:                                                   │
 * │    • 1% per year if active (≥1 tx/month)                                    │
 * │    • 10% per year if inactive (0 tx)                                        │
 * └─────────────────────────────────────────────────────────────────────────────┘
 */
contract Karma is AccessControl {
    // ============ Constants ============

    /// @notice Role for attestation providers who can mint K
    bytes32 public constant ATTESTOR_ROLE = keccak256("ATTESTOR_ROLE");

    /// @notice Role for governance to slash K
    bytes32 public constant SLASHER_ROLE = keccak256("SLASHER_ROLE");

    /// @notice Soft cap per account
    uint256 public constant MAX_KARMA = 1000e18;

    /// @notice Activity period for monthly tracking
    uint256 public constant ACTIVITY_PERIOD = 30 days;

    /// @notice Decay rate per year if ACTIVE (1% - at least 1 tx/month)
    uint256 public constant ACTIVE_DECAY_RATE = 100; // basis points (1%)

    /// @notice Decay rate per year if INACTIVE (10% - 0 tx/month)
    uint256 public constant INACTIVE_DECAY_RATE = 1000; // basis points (10%)

    /// @notice Minimum Karma floor for verified DID holders (prevents total decay)
    /// @dev Ensures verified community members always retain voting power for 1000+ years
    uint256 public constant MIN_VERIFIED_KARMA = 50e18;

    // ============ State ============

    /// @notice K balance per account
    mapping(address => uint256) private _balances;

    /// @notice DID bound to account
    mapping(address => bytes32) public didOf;

    /// @notice Account bound to DID (reverse lookup)
    mapping(bytes32 => address) public accountOf;

    /// @notice Whether account is human-verified
    mapping(address => bool) public isVerified;

    /// @notice Last activity timestamp per account
    mapping(address => uint256) public lastActivity;

    /// @notice Transaction count in current month (account => month => count)
    /// @dev Month = block.timestamp / 30 days. Only current and previous month are used for decay.
    /// Historical entries are ignored but not cleaned up (gas optimization).
    mapping(address => mapping(uint256 => uint256)) public monthlyTxCount;

    /// @notice Whether account was active last month (had ≥1 tx)
    /// @dev Updated on each recordActivity() call
    mapping(address => bool) public wasActiveLastMonth;

    /// @notice Total K in circulation
    uint256 public totalSupply;

    /// @notice DID Registry for on-chain DID verification
    IDIDRegistry public didRegistry;

    /// @notice Full DID string storage (optional, for display)
    mapping(address => string) public didStringOf;

    /// @notice Token metadata
    string public constant name = "Karma";
    string public constant symbol = "K";
    uint8 public constant decimals = 18;

    // ============ Events ============

    event KarmaMinted(address indexed to, uint256 amount, bytes32 reason);
    event KarmaSlashed(address indexed from, uint256 amount, bytes32 reason);
    event KarmaDecayed(address indexed account, uint256 amount, bool wasActive);
    event ActivityRecorded(address indexed account, uint256 month, uint256 txCount);
    event DIDLinked(address indexed account, bytes32 indexed did);
    event Verified(address indexed account, bool status);

    // ============ Errors ============

    error NotTransferable();
    error NotAttestor();
    error NotSlasher();
    error ExceedsMaxKarma();
    error InsufficientKarma();
    error DIDAlreadyLinked();
    error AccountAlreadyHasDID();
    error ZeroAddress();
    error ZeroAmount();
    error DIDNotVerified();
    error NotDIDController();

    // ============ Constructor ============

    constructor(address admin) {
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(ATTESTOR_ROLE, admin);
        _grantRole(SLASHER_ROLE, admin);
    }

    // ============ View Functions ============

    /// @notice Get K balance for account (with decay applied)
    /// @param account Address to query
    /// @return Current K balance after decay
    function balanceOf(address account) public view returns (uint256) {
        return karmaOf(account);
    }

    /// @notice Get K balance with activity-driven decay calculation
    /// @param account Address to query
    /// @return K balance after applying decay (1% if active, 10% if inactive)
    /// @dev Verified DID holders have a MIN_VERIFIED_KARMA floor to ensure 1000+ year sustainability
    function karmaOf(address account) public view returns (uint256) {
        uint256 balance = _balances[account];
        if (balance == 0) return 0;

        uint256 lastActive = lastActivity[account];
        if (lastActive == 0) return balance;

        // Calculate elapsed time since last activity
        uint256 elapsedTime = block.timestamp - lastActive;
        if (elapsedTime < ACTIVITY_PERIOD) return balance;

        // Determine decay rate based on activity status
        // Active = at least 1 tx in the last month = 1% decay
        // Inactive = 0 tx in the last month = 10% decay
        uint256 decayRate = wasActiveLastMonth[account] ? ACTIVE_DECAY_RATE : INACTIVE_DECAY_RATE;

        // Calculate number of years (or fractions) for decay
        uint256 decayPeriods = elapsedTime / 365 days;
        if (decayPeriods == 0) {
            // Apply fractional decay for partial year
            uint256 fraction = (elapsedTime * 10000) / 365 days;
            uint256 decayAmount = (balance * decayRate * fraction) / (10000 * 10000);
            balance = balance > decayAmount ? balance - decayAmount : 0;
        } else {
            // Apply compound decay for full years (capped at 10 iterations)
            for (uint256 i = 0; i < decayPeriods && i < 10; i++) {
                balance = (balance * (10000 - decayRate)) / 10000;
            }
        }

        // Verified DID holders have a minimum floor to ensure long-term voting power
        // This prevents total decay even after 1000+ years of inactivity
        if (isVerified[account] && balance < MIN_VERIFIED_KARMA) {
            return MIN_VERIFIED_KARMA;
        }

        return balance;
    }

    /// @notice Get current month number for activity tracking
    /// @return Current month (timestamp / 30 days)
    function currentMonth() public view returns (uint256) {
        return block.timestamp / ACTIVITY_PERIOD;
    }

    /// @notice Check if account is currently active (has tx this month)
    /// @param account Address to check
    /// @return isActive Whether account has at least 1 tx this month
    function isActive(address account) public view returns (bool) {
        return monthlyTxCount[account][currentMonth()] > 0;
    }

    // ============ Attestor Functions ============

    /// @notice Mint K to account (only attestation providers)
    /// @param to Recipient address
    /// @param amount Amount of K to mint
    /// @param reason Reason code for minting
    function mint(address to, uint256 amount, bytes32 reason) external {
        if (!hasRole(ATTESTOR_ROLE, msg.sender)) revert NotAttestor();
        if (to == address(0)) revert ZeroAddress();
        if (amount == 0) revert ZeroAmount();

        uint256 newBalance = _balances[to] + amount;
        if (newBalance > MAX_KARMA) revert ExceedsMaxKarma();

        _balances[to] = newBalance;
        totalSupply += amount;
        lastActivity[to] = block.timestamp;

        emit KarmaMinted(to, amount, reason);
    }

    /// @notice Verify an account as human
    /// @param account Address to verify
    function verify(address account) external {
        if (!hasRole(ATTESTOR_ROLE, msg.sender)) revert NotAttestor();
        isVerified[account] = true;
        lastActivity[account] = block.timestamp;
        emit Verified(account, true);
    }

    /// @notice Link DID to account
    /// @param account Address to link
    /// @param did Decentralized Identifier
    function linkDID(address account, bytes32 did) external {
        if (!hasRole(ATTESTOR_ROLE, msg.sender)) revert NotAttestor();
        if (didOf[account] != bytes32(0)) revert AccountAlreadyHasDID();
        if (accountOf[did] != address(0)) revert DIDAlreadyLinked();

        didOf[account] = did;
        accountOf[did] = account;
        lastActivity[account] = block.timestamp;

        emit DIDLinked(account, did);
    }

    // ============ Slasher Functions ============

    /// @notice Slash K from account (governance penalty)
    /// @param account Address to slash
    /// @param amount Amount of K to burn
    /// @param reason Reason code for slashing
    function slash(address account, uint256 amount, bytes32 reason) external {
        if (!hasRole(SLASHER_ROLE, msg.sender)) revert NotSlasher();
        
        uint256 balance = _balances[account];
        if (amount > balance) {
            amount = balance; // Slash entire balance if amount exceeds
        }

        _balances[account] = balance - amount;
        totalSupply -= amount;

        emit KarmaSlashed(account, amount, reason);
    }

    /// @notice Slash percentage of K (for slashing events)
    /// @param account Address to slash
    /// @param bps Basis points to slash (e.g., 2500 = 25%)
    /// @param reason Reason code
    function slashPercentage(address account, uint256 bps, bytes32 reason) external {
        if (!hasRole(SLASHER_ROLE, msg.sender)) revert NotSlasher();
        if (bps > 10000) bps = 10000;

        uint256 balance = _balances[account];
        uint256 amount = (balance * bps) / 10000;

        _balances[account] = balance - amount;
        totalSupply -= amount;

        emit KarmaSlashed(account, amount, reason);
    }

    /// @notice Burn K from account (called by KarmaMinter for community moderation)
    /// @dev Can be called by ATTESTOR_ROLE (for strike mechanism) or SLASHER_ROLE
    /// @param account Address to burn from
    /// @param amount Amount of K to burn
    /// @param reason Reason code for burning
    function burn(address account, uint256 amount, bytes32 reason) external {
        // Allow both attestors (KarmaMinter) and slashers to burn
        if (!hasRole(ATTESTOR_ROLE, msg.sender) && !hasRole(SLASHER_ROLE, msg.sender)) {
            revert NotSlasher();
        }

        uint256 balance = _balances[account];
        if (amount > balance) {
            amount = balance;
        }

        _balances[account] = balance - amount;
        totalSupply -= amount;

        emit KarmaSlashed(account, amount, reason);
    }

    // ============ User Functions ============

    /// @notice Record activity to track monthly tx count and reset decay timer
    /// @dev Called by anyone for their own account, or by attestors for others
    function recordActivity(address account) external {
        // Can be called by anyone to update their own activity
        // Or by authorized contracts for governance participation
        if (msg.sender == account || hasRole(ATTESTOR_ROLE, msg.sender)) {
            uint256 month = currentMonth();
            uint256 prevMonth = month > 0 ? month - 1 : 0;

            // Update activity status from previous month before recording new activity
            wasActiveLastMonth[account] = monthlyTxCount[account][prevMonth] > 0;

            // Increment tx count for current month
            monthlyTxCount[account][month]++;
            lastActivity[account] = block.timestamp;

            emit ActivityRecorded(account, month, monthlyTxCount[account][month]);
        }
    }

    /// @notice Batch record activity for multiple accounts (keeper function)
    /// @param accounts Addresses to record activity for
    function batchRecordActivity(address[] calldata accounts) external {
        if (!hasRole(ATTESTOR_ROLE, msg.sender)) revert NotAttestor();

        uint256 month = currentMonth();
        uint256 prevMonth = month > 0 ? month - 1 : 0;

        for (uint256 i = 0; i < accounts.length; i++) {
            address account = accounts[i];
            wasActiveLastMonth[account] = monthlyTxCount[account][prevMonth] > 0;
            monthlyTxCount[account][month]++;
            lastActivity[account] = block.timestamp;
            emit ActivityRecorded(account, month, monthlyTxCount[account][month]);
        }
    }

    /// @notice Apply decay to an account (called by keepers)
    /// @param account Address to apply decay
    /// @dev Emits KarmaDecayed with wasActive status for transparency
    function applyDecay(address account) external {
        uint256 currentBalance = _balances[account];
        uint256 decayedBalance = karmaOf(account);

        if (decayedBalance < currentBalance) {
            uint256 decayAmount = currentBalance - decayedBalance;
            _balances[account] = decayedBalance;
            totalSupply -= decayAmount;

            // Update wasActiveLastMonth before emitting
            uint256 prevMonth = currentMonth() > 0 ? currentMonth() - 1 : 0;
            bool wasActive = monthlyTxCount[account][prevMonth] > 0;
            wasActiveLastMonth[account] = wasActive;

            emit KarmaDecayed(account, decayAmount, wasActive);
        }
    }

    /// @notice Get monthly transaction count for an account
    /// @param account Address to query
    /// @param month Month number to query
    /// @return Transaction count for that month
    function getTxCountForMonth(address account, uint256 month) external view returns (uint256) {
        return monthlyTxCount[account][month];
    }

    /// @notice Get decay rate that would apply to an account
    /// @param account Address to check
    /// @return decayRate Decay rate in basis points (100 = 1%, 1000 = 10%)
    function getDecayRate(address account) external view returns (uint256 decayRate) {
        return wasActiveLastMonth[account] ? ACTIVE_DECAY_RATE : INACTIVE_DECAY_RATE;
    }

    /// @notice Get full activity status for an account (for UI/analytics)
    /// @param account Address to check
    /// @return karma Current Karma balance (with decay applied)
    /// @return verified Whether account has verified DID
    /// @return activeThisMonth Whether account has recorded activity this month
    /// @return activeLastMonth Whether account was active last month
    /// @return currentDecayRate Current decay rate in basis points
    /// @return hasKarmaFloor Whether account qualifies for MIN_VERIFIED_KARMA floor
    function getActivityStatus(address account) external view returns (
        uint256 karma,
        bool verified,
        bool activeThisMonth,
        bool activeLastMonth,
        uint256 currentDecayRate,
        bool hasKarmaFloor
    ) {
        karma = karmaOf(account);
        verified = isVerified[account];
        activeThisMonth = monthlyTxCount[account][currentMonth()] > 0;
        activeLastMonth = wasActiveLastMonth[account];
        currentDecayRate = activeLastMonth ? ACTIVE_DECAY_RATE : INACTIVE_DECAY_RATE;
        hasKarmaFloor = verified && _balances[account] > 0;
    }

    // ============ DID Registry Integration ============

    /// @notice Set DID Registry contract
    /// @param registry Address of DIDRegistry contract
    function setDIDRegistry(address registry) external {
        if (!hasRole(DEFAULT_ADMIN_ROLE, msg.sender)) revert NotAttestor();
        didRegistry = IDIDRegistry(registry);
    }

    /// @notice Link DID from registry (self-service with on-chain verification)
    /// @param did Full DID string (e.g., "did:lux:alice")
    /// @dev Caller must be the controller of the DID in the registry
    function linkDIDFromRegistry(string calldata did) external {
        if (address(didRegistry) == address(0)) revert ZeroAddress();
        
        // Verify DID exists and caller is controller
        if (!didRegistry.didExists(did)) revert DIDNotVerified();
        if (didRegistry.controllerOf(did) != msg.sender) revert NotDIDController();

        bytes32 didHash = keccak256(bytes(did));
        
        if (didOf[msg.sender] != bytes32(0)) revert AccountAlreadyHasDID();
        if (accountOf[didHash] != address(0)) revert DIDAlreadyLinked();

        didOf[msg.sender] = didHash;
        accountOf[didHash] = msg.sender;
        didStringOf[msg.sender] = did;
        lastActivity[msg.sender] = block.timestamp;

        emit DIDLinked(msg.sender, didHash);
    }

    /// @notice Get DID string for account
    /// @param account Address to query
    /// @return did The full DID string if linked
    function getDIDString(address account) external view returns (string memory did) {
        return didStringOf[account];
    }

    /// @notice Check if account has verified DID from registry
    /// @param account Address to check
    /// @return hasVerifiedDID Whether account has a verified DID
    function hasVerifiedDID(address account) external view returns (bool) {
        if (address(didRegistry) == address(0)) return false;
        
        bytes32 didHash = didOf[account];
        if (didHash == bytes32(0)) return false;

        string memory did = didStringOf[account];
        if (bytes(did).length == 0) return false;

        return didRegistry.didExists(did);
    }

    // ============ Disabled Transfer Functions ============

    /// @notice Transfer is disabled (soul-bound)
    function transfer(address, uint256) external pure returns (bool) {
        revert NotTransferable();
    }

    /// @notice TransferFrom is disabled (soul-bound)
    function transferFrom(address, address, uint256) external pure returns (bool) {
        revert NotTransferable();
    }

    /// @notice Approve is disabled (soul-bound)
    function approve(address, uint256) external pure returns (bool) {
        revert NotTransferable();
    }

    /// @notice Allowance is always zero (soul-bound)
    function allowance(address, address) external pure returns (uint256) {
        return 0;
    }
}
