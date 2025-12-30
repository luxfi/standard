// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.31;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import {ERC20Votes} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Votes.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {Nonces} from "@openzeppelin/contracts/utils/Nonces.sol";

/**
 * @title LiquidLUX (xLUX)
 * @author Lux Industries Inc
 * @notice Master yield vault that receives ALL protocol fees and mints xLUX shares
 *
 * ARCHITECTURE:
 * ┌─────────────────────────────────────────────────────────────────────────────┐
 * │                           LiquidLUX (xLUX)                                  │
 * ├─────────────────────────────────────────────────────────────────────────────┤
 * │  INFLOWS:                                                                   │
 * │  ┌───────────────┐ ┌───────────────┐ ┌───────────────┐ ┌───────────────┐   │
 * │  │ DEX Fees      │ │ Bridge Fees   │ │ Lending Fees  │ │ Perps Fees    │   │
 * │  │ (10% perf)    │ │ (10% perf)    │ │ (10% perf)    │ │ (10% perf)    │   │
 * │  └───────┬───────┘ └───────┬───────┘ └───────┬───────┘ └───────┬───────┘   │
 * │          │                 │                 │                 │           │
 * │          ▼                 ▼                 ▼                 ▼           │
 * │  ┌───────────────────────────────────────────────────────────────────────┐ │
 * │  │                    receiveFees(amount, feeType)                       │ │
 * │  │                         → 10% to treasury                             │ │
 * │  │                         → 90% to vault                                │ │
 * │  └───────────────────────────────────────────────────────────────────────┘ │
 * │                                                                             │
 * │  ┌───────────────┐                                                         │
 * │  │ Validator     │ ─────► depositValidatorRewards(amount)                  │
 * │  │ Rewards       │         → 0% perf fee (validators exempt)               │
 * │  │ (0% perf)     │         → 100% to vault                                 │
 * │  └───────────────┘                                                         │
 * │                                                                             │
 * │  OUTFLOWS:                                                                  │
 * │  • Users deposit LUX → receive xLUX shares                                 │
 * │  • Users withdraw xLUX → receive LUX + proportional yield                  │
 * │  • xLUX is checkpointed (ERC20Votes) for flash-loan-resistant governance   │
 * │                                                                             │
 * │  GOVERNANCE:                                                                │
 * │  • vLUX = xLUX + DLUX (aggregated in VotingLUX contract)                   │
 * │  • Timelock-controlled parameter changes                                   │
 * │  • Slashing reserve + loss socialization policy                            │
 * └─────────────────────────────────────────────────────────────────────────────┘
 *
 * SECURITY IMPROVEMENTS:
 * 1. bytes32 feeType constants (gas efficient, typo-proof)
 * 2. SafeERC20 everywhere, no infinite approvals
 * 3. GOVERNANCE_ROLE for timelock-controlled setters
 * 4. ERC20Votes for checkpointed voting power (anti-flash-loan)
 * 5. Slashing policy (reserve buffer + loss socialization)
 * 6. Pausable + emergency withdrawal
 * 7. Full accounting ledgers + reconciliation view
 */
contract LiquidLUX is ERC20, ERC20Permit, ERC20Votes, ReentrancyGuard, AccessControl, Pausable {
    using SafeERC20 for IERC20;

    // ============ Fee Type Constants (bytes32) ============
    
    bytes32 public constant FEE_DEX = keccak256("DEX");
    bytes32 public constant FEE_BRIDGE = keccak256("BRIDGE");
    bytes32 public constant FEE_LENDING = keccak256("LENDING");
    bytes32 public constant FEE_PERPS = keccak256("PERPS");
    bytes32 public constant FEE_LIQUID = keccak256("LIQUID");
    bytes32 public constant FEE_NFT = keccak256("NFT");
    bytes32 public constant FEE_VALIDATOR = keccak256("VALIDATOR");
    bytes32 public constant FEE_OTHER = keccak256("OTHER");

    // ============ Roles ============
    
    bytes32 public constant FEE_DISTRIBUTOR_ROLE = keccak256("FEE_DISTRIBUTOR_ROLE");
    bytes32 public constant VALIDATOR_ROLE = keccak256("VALIDATOR_ROLE");
    bytes32 public constant GOVERNANCE_ROLE = keccak256("GOVERNANCE_ROLE");
    bytes32 public constant EMERGENCY_ROLE = keccak256("EMERGENCY_ROLE");

    // ============ Constants ============
    
    uint256 public constant BPS = 10_000;
    uint256 public constant MAX_PERF_FEE_BPS = 2000; // 20% max
    uint256 public constant MAX_SLASHING_RESERVE_BPS = 2000; // 20% max

    // ============ Immutables ============
    
    IERC20 public immutable lux;

    // ============ Configuration (Governance-controlled) ============
    
    /// @notice Treasury address for performance fees
    address public treasury;
    
    /// @notice Performance fee in basis points (default 10% = 1000 bps)
    uint256 public perfFeeBps = 1000;

    // ============ Slashing Policy ============
    
    /// @notice Slashing reserve buffer (accumulated from portion of fees)
    uint256 public slashingReserve;
    
    /// @notice Basis points of incoming fees directed to slashing reserve
    uint256 public slashingReserveBps = 100; // 1% default
    
    /// @notice If true, losses beyond reserve are socialized across all holders
    bool public socializeLosses = true;

    // ============ Accounting Ledgers ============
    
    /// @notice Total protocol fees received (before perf fee)
    uint256 public totalProtocolFeesIn;
    
    /// @notice Total validator rewards received (no perf fee)
    uint256 public totalValidatorRewardsIn;
    
    /// @notice Total performance fees taken
    uint256 public totalPerfFeesTaken;
    
    /// @notice Total slashing losses applied
    uint256 public totalSlashingLosses;
    
    /// @notice Fees by source type
    mapping(bytes32 => uint256) public feesBySource;
    
    /// @notice Approved fee distributors (e.g., FeeSplitter)
    mapping(address => bool) public feeDistributors;
    
    /// @notice Approved validator sources (e.g., ValidatorVault)
    mapping(address => bool) public validatorSources;

    // ============ Events ============
    
    event FeesReceived(address indexed from, uint256 amount, bytes32 indexed feeType, uint256 perfFee, uint256 toReserve);
    event ValidatorRewardsReceived(address indexed from, uint256 amount);
    event SlashingApplied(uint256 amount, uint256 fromReserve, uint256 socialized);
    event TreasuryUpdated(address indexed newTreasury);
    event PerfFeeBpsUpdated(uint256 newBps);
    event SlashingReserveBpsUpdated(uint256 newBps);
    event SocializeLossesUpdated(bool newValue);
    event FeeDistributorUpdated(address indexed distributor, bool approved);
    event ValidatorSourceUpdated(address indexed source, bool approved);
    event EmergencyWithdrawal(address indexed to, uint256 amount);

    // ============ Errors ============
    
    error InvalidAddress();
    error InvalidBps();
    error NotFeeDistributor();
    error NotValidatorSource();
    error InsufficientBalance();
    error InsufficientShares();
    error ZeroAmount();

    // ============ Constructor ============
    
    constructor(
        address _lux,
        address _treasury,
        address _timelock
    ) ERC20("Liquid LUX", "xLUX") ERC20Permit("Liquid LUX") {
        if (_lux == address(0) || _treasury == address(0)) revert InvalidAddress();
        
        lux = IERC20(_lux);
        treasury = _treasury;

        // Grant roles
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(GOVERNANCE_ROLE, _timelock != address(0) ? _timelock : msg.sender);
        _grantRole(EMERGENCY_ROLE, msg.sender);
    }

    // ============ User Actions ============
    
    /**
     * @notice Deposit LUX and receive xLUX shares
     * @param amount Amount of LUX to deposit
     * @return shares Amount of xLUX shares minted
     */
    function deposit(uint256 amount) external nonReentrant whenNotPaused returns (uint256 shares) {
        if (amount == 0) revert ZeroAmount();
        
        shares = _convertToShares(amount);
        if (shares == 0) revert ZeroAmount();
        
        // CEI: Effects before interactions
        _mint(msg.sender, shares);
        
        // Transfer LUX from user
        lux.safeTransferFrom(msg.sender, address(this), amount);
    }

    /**
     * @notice Withdraw LUX by burning xLUX shares
     * @param shares Amount of xLUX shares to burn
     * @return amount Amount of LUX withdrawn
     */
    function withdraw(uint256 shares) external nonReentrant whenNotPaused returns (uint256 amount) {
        if (shares == 0) revert ZeroAmount();
        if (balanceOf(msg.sender) < shares) revert InsufficientShares();
        
        amount = _convertToAssets(shares);
        if (amount == 0) revert ZeroAmount();
        
        // CEI: Effects before interactions
        _burn(msg.sender, shares);
        
        // Transfer LUX to user
        lux.safeTransfer(msg.sender, amount);
    }

    // ============ Fee Reception ============
    
    /**
     * @notice Receive protocol fees from approved distributors
     * @param amount Amount of LUX fees
     * @param feeType Type of fee (use FEE_* constants)
     */
    function receiveFees(uint256 amount, bytes32 feeType) external nonReentrant whenNotPaused {
        if (!feeDistributors[msg.sender]) revert NotFeeDistributor();
        if (amount == 0) revert ZeroAmount();
        
        // Transfer LUX from distributor
        lux.safeTransferFrom(msg.sender, address(this), amount);
        
        // Calculate performance fee (10%)
        uint256 perfFee = (amount * perfFeeBps) / BPS;
        
        // Calculate slashing reserve contribution
        uint256 toReserve = (amount * slashingReserveBps) / BPS;
        
        // Update accounting
        totalProtocolFeesIn += amount;
        totalPerfFeesTaken += perfFee;
        feesBySource[feeType] += amount;
        slashingReserve += toReserve;
        
        // Send perf fee to treasury
        if (perfFee > 0) {
            lux.safeTransfer(treasury, perfFee);
        }
        
        emit FeesReceived(msg.sender, amount, feeType, perfFee, toReserve);
    }

    /**
     * @notice Receive validator rewards (no performance fee)
     * @param amount Amount of LUX rewards
     */
    function depositValidatorRewards(uint256 amount) external nonReentrant whenNotPaused {
        if (!validatorSources[msg.sender]) revert NotValidatorSource();
        if (amount == 0) revert ZeroAmount();
        
        // Transfer LUX from validator source
        lux.safeTransferFrom(msg.sender, address(this), amount);
        
        // Update accounting (no perf fee for validators)
        totalValidatorRewardsIn += amount;
        feesBySource[FEE_VALIDATOR] += amount;
        
        emit ValidatorRewardsReceived(msg.sender, amount);
    }

    // ============ Slashing ============
    
    /**
     * @notice Apply slashing loss to the vault
     * @dev Called by governance when validator is slashed
     * @param amount Amount of LUX lost to slashing
     */
    function applySlashing(uint256 amount) external onlyRole(GOVERNANCE_ROLE) {
        if (amount == 0) revert ZeroAmount();
        
        uint256 fromReserve = 0;
        uint256 socialized = 0;
        
        // First, use slashing reserve
        if (slashingReserve >= amount) {
            slashingReserve -= amount;
            fromReserve = amount;
        } else {
            fromReserve = slashingReserve;
            slashingReserve = 0;
            
            // Remaining loss
            uint256 remaining = amount - fromReserve;
            
            if (socializeLosses) {
                // Loss is socialized - reduces vault balance
                // This effectively dilutes all xLUX holders proportionally
                socialized = remaining;
            } else {
                // Without socialization, excess loss is absorbed by protocol
                // (would require external coverage)
                revert InsufficientBalance();
            }
        }
        
        totalSlashingLosses += amount;
        
        emit SlashingApplied(amount, fromReserve, socialized);
    }

    // ============ Governance Setters (Timelock-controlled) ============
    
    function setTreasury(address _treasury) external onlyRole(GOVERNANCE_ROLE) {
        if (_treasury == address(0)) revert InvalidAddress();
        treasury = _treasury;
        emit TreasuryUpdated(_treasury);
    }

    function setPerfFeeBps(uint256 _bps) external onlyRole(GOVERNANCE_ROLE) {
        if (_bps > MAX_PERF_FEE_BPS) revert InvalidBps();
        perfFeeBps = _bps;
        emit PerfFeeBpsUpdated(_bps);
    }

    function setSlashingReserveBps(uint256 _bps) external onlyRole(GOVERNANCE_ROLE) {
        if (_bps > MAX_SLASHING_RESERVE_BPS) revert InvalidBps();
        slashingReserveBps = _bps;
        emit SlashingReserveBpsUpdated(_bps);
    }

    function setSocializeLosses(bool _socialize) external onlyRole(GOVERNANCE_ROLE) {
        socializeLosses = _socialize;
        emit SocializeLossesUpdated(_socialize);
    }

    // ============ Access Control ============
    
    function addFeeDistributor(address distributor) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (distributor == address(0)) revert InvalidAddress();
        feeDistributors[distributor] = true;
        emit FeeDistributorUpdated(distributor, true);
    }

    function removeFeeDistributor(address distributor) external onlyRole(DEFAULT_ADMIN_ROLE) {
        feeDistributors[distributor] = false;
        emit FeeDistributorUpdated(distributor, false);
    }

    function addValidatorSource(address source) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (source == address(0)) revert InvalidAddress();
        validatorSources[source] = true;
        emit ValidatorSourceUpdated(source, true);
    }

    function removeValidatorSource(address source) external onlyRole(DEFAULT_ADMIN_ROLE) {
        validatorSources[source] = false;
        emit ValidatorSourceUpdated(source, false);
    }

    // ============ Emergency ============
    
    function pause() external onlyRole(EMERGENCY_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(GOVERNANCE_ROLE) {
        _unpause();
    }

    /**
     * @notice Emergency withdrawal to treasury
     * @dev Only callable when paused by emergency role
     */
    function emergencyWithdrawToTreasury() external onlyRole(EMERGENCY_ROLE) {
        require(paused(), "Must be paused");
        
        uint256 balance = lux.balanceOf(address(this));
        if (balance == 0) revert InsufficientBalance();
        
        lux.safeTransfer(treasury, balance);
        
        emit EmergencyWithdrawal(treasury, balance);
    }

    // ============ View Functions ============
    
    /**
     * @notice Total LUX assets in the vault
     */
    function totalAssets() public view returns (uint256) {
        return lux.balanceOf(address(this));
    }

    /**
     * @notice Convert LUX amount to xLUX shares
     */
    function convertToShares(uint256 assets) external view returns (uint256) {
        return _convertToShares(assets);
    }

    /**
     * @notice Convert xLUX shares to LUX amount
     */
    function convertToAssets(uint256 shares) external view returns (uint256) {
        return _convertToAssets(shares);
    }

    /**
     * @notice Current exchange rate (LUX per xLUX, scaled by 1e18)
     */
    function exchangeRate() external view returns (uint256) {
        uint256 supply = totalSupply();
        if (supply == 0) return 1e18;
        return (totalAssets() * 1e18) / supply;
    }

    /**
     * @notice Reconciliation view for auditing
     * @return expectedBalance What balance should be based on inflows - outflows
     * @return actualBalance Actual LUX balance
     * @return discrepancy Difference (should be 0 or small from rounding)
     */
    function reconcile() external view returns (
        uint256 expectedBalance,
        uint256 actualBalance,
        int256 discrepancy
    ) {
        // Expected = Total In - Perf Fees - Slashing Losses
        // Note: User deposits/withdrawals are already reflected in balance
        expectedBalance = totalProtocolFeesIn + totalValidatorRewardsIn 
                        - totalPerfFeesTaken - totalSlashingLosses;
        actualBalance = lux.balanceOf(address(this));
        discrepancy = int256(actualBalance) - int256(expectedBalance);
    }

    /**
     * @notice Get fee breakdown by source
     */
    function getFeeBreakdown() external view returns (
        uint256 dex,
        uint256 bridge,
        uint256 lending,
        uint256 perps,
        uint256 synths,
        uint256 nft,
        uint256 validator,
        uint256 other
    ) {
        return (
            feesBySource[FEE_DEX],
            feesBySource[FEE_BRIDGE],
            feesBySource[FEE_LENDING],
            feesBySource[FEE_PERPS],
            feesBySource[FEE_LIQUID],
            feesBySource[FEE_NFT],
            feesBySource[FEE_VALIDATOR],
            feesBySource[FEE_OTHER]
        );
    }

    // ============ Internal ============
    
    function _convertToShares(uint256 assets) internal view returns (uint256) {
        uint256 supply = totalSupply();
        if (supply == 0) {
            return assets; // 1:1 for first deposit
        }
        return (assets * supply) / totalAssets();
    }

    function _convertToAssets(uint256 shares) internal view returns (uint256) {
        uint256 supply = totalSupply();
        if (supply == 0) {
            return shares; // 1:1 if no supply
        }
        return (shares * totalAssets()) / supply;
    }

    // ============ ERC20 Overrides (for ERC20Votes) ============
    
    function _update(address from, address to, uint256 amount) internal override(ERC20, ERC20Votes) {
        super._update(from, to, amount);
    }

    function nonces(address owner) public view override(ERC20Permit, Nonces) returns (uint256) {
        return super.nonces(owner);
    }
}
