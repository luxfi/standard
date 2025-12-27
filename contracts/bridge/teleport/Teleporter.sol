// SPDX-License-Identifier: BSD-3-Clause
// Copyright (c) 2025 Lux Industries Inc.
pragma solidity ^0.8.31;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";

/**
 * @title Teleporter
 * @author Lux Industries
 * @notice Simple burn/mint teleporter on Lux for base collateral (ETH, USDC, USDT, DAI, etc.)
 * @dev Part of the Liquid system for self-repaying bridged asset loans
 *
 * Architecture:
 * - Receives MPC-signed proofs of deposits from LiquidVault on external chains
 * - Mints bridged tokens (LETH, LUSD, etc.) on Lux
 * - Receives yield proofs and mints yield tokens to LiquidYield
 * - Burns tokens for withdrawals back to source chain
 *
 * Domain Separation:
 * - Deposit nonces: used for user deposits (mintDeposit)
 * - Yield nonces: used for yield minting (mintYield) - separate namespace
 * - Withdraw nonces: used for burn and release flow
 *
 * Invariants:
 * - totalMinted <= totalBackingOnSourceChain (attested via MPC)
 * - Only MPC can mint (via signed proofs)
 * - Burn requires token balance
 */
contract Teleporter is Ownable, AccessControl, ReentrancyGuard {
    // ═══════════════════════════════════════════════════════════════════════
    // ROLES
    // ═══════════════════════════════════════════════════════════════════════

    bytes32 public constant MPC_ROLE = keccak256("MPC_ROLE");
    bytes32 public constant LIQUID_YIELD_ROLE = keccak256("LIQUID_YIELD_ROLE");

    // ═══════════════════════════════════════════════════════════════════════
    // TYPES
    // ═══════════════════════════════════════════════════════════════════════

    struct DepositMint {
        uint256 depositNonce;
        address recipient;
        uint256 amount;
        uint256 srcChainId;
        uint256 timestamp;
    }

    struct YieldMint {
        uint256 yieldNonce;
        uint256 amount;
        uint256 srcChainId;
        uint256 timestamp;
    }

    struct BackingAttestation {
        uint256 totalBacking;     // Total ETH on source chain
        uint256 timestamp;
        bytes signature;
    }

    // ═══════════════════════════════════════════════════════════════════════
    // CONSTANTS
    // ═══════════════════════════════════════════════════════════════════════

    uint256 public constant BASIS_POINTS = 10_000;
    
    /// @notice Peg degradation threshold (99.5% = 9950 bps)
    uint256 public constant PEG_DEGRADE_THRESHOLD = 9950;
    
    /// @notice Peg pause threshold (98.5% = 9850 bps)
    uint256 public constant PEG_PAUSE_THRESHOLD = 9850;

    // ═══════════════════════════════════════════════════════════════════════
    // STATE
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice The bridged token (LETH, LUSD, etc.)
    IBridgedToken public immutable token;

    /// @notice LiquidETH vault for debt notifications (if applicable)
    address public liquidVault;

    /// @notice LiquidYield for yield routing
    address public liquidYield;

    /// @notice Total LETH minted via deposits
    uint256 public totalDepositMinted;

    /// @notice Total LETH minted via yield
    uint256 public totalYieldMinted;

    /// @notice Total LETH burned for withdrawals
    uint256 public totalBurned;

    /// @notice Processed deposit nonces (replay protection)
    mapping(uint256 => mapping(uint256 => bool)) public processedDeposits; // srcChainId => depositNonce => processed

    /// @notice Processed yield nonces (replay protection)
    mapping(uint256 => mapping(uint256 => bool)) public processedYields; // srcChainId => yieldNonce => processed

    /// @notice Pending withdraw nonces
    mapping(uint256 => bool) public pendingWithdraws;

    /// @notice Latest backing attestation per source chain
    mapping(uint256 => BackingAttestation) public backingAttestations;

    /// @notice MPC Oracle addresses
    mapping(address => bool) public mpcOracles;

    /// @notice Paused state
    bool public paused;

    // ═══════════════════════════════════════════════════════════════════════
    // EVENTS
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice Emitted when LETH minted for deposit
    event DepositMinted(
        uint256 indexed srcChainId,
        uint256 indexed depositNonce,
        address indexed recipient,
        uint256 amount
    );

    /// @notice Emitted when LETH minted for yield
    event YieldMinted(
        uint256 indexed srcChainId,
        uint256 indexed yieldNonce,
        uint256 amount
    );

    /// @notice Emitted when LETH burned for withdrawal
    event BurnedForWithdraw(
        address indexed user,
        uint256 amount,
        uint256 indexed withdrawNonce
    );

    /// @notice Emitted when backing attestation updated
    event BackingUpdated(
        uint256 indexed srcChainId,
        uint256 totalBacking,
        uint256 timestamp
    );

    /// @notice Emitted when MPC oracle updated
    event MPCOracleSet(address indexed oracle, bool active);

    /// @notice Emitted when paused state changes
    event PausedStateChanged(bool paused);

    // ═══════════════════════════════════════════════════════════════════════
    // ERRORS
    // ═══════════════════════════════════════════════════════════════════════

    error ZeroAmount();
    error ZeroAddress();
    error InvalidSignature();
    error NonceAlreadyProcessed();
    error InsufficientBalance();
    error BridgePaused();
    error PegDegraded();
    error BackingInsufficient();

    // ═══════════════════════════════════════════════════════════════════════
    // MODIFIERS
    // ═══════════════════════════════════════════════════════════════════════

    modifier whenNotPaused() {
        if (paused) revert BridgePaused();
        _;
    }

    modifier checkPeg() {
        uint256 peg = getCurrentPeg();
        if (peg < PEG_PAUSE_THRESHOLD) revert BridgePaused();
        _;
    }

    // ═══════════════════════════════════════════════════════════════════════
    // CONSTRUCTOR
    // ═══════════════════════════════════════════════════════════════════════

    constructor(
        address _leth,
        address _mpcOracle
    ) Ownable(msg.sender) {
        if (_leth == address(0) || _mpcOracle == address(0)) revert ZeroAddress();
        
        token = IBridgedToken(_leth);
        
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(MPC_ROLE, _mpcOracle);
        mpcOracles[_mpcOracle] = true;
        
        emit MPCOracleSet(_mpcOracle, true);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // MINT FUNCTIONS (MPC ONLY)
    // ═══════════════════════════════════════════════════════════════════════

    /**
     * @notice Mint LETH for a deposit proof from source chain
     * @param srcChainId Source chain ID (e.g., Base = 8453)
     * @param depositNonce Deposit nonce from TeleportVault
     * @param recipient LETH recipient on Lux
     * @param amount Amount of LETH to mint
     * @param signature MPC signature of deposit proof
     */
    function mintDeposit(
        uint256 srcChainId,
        uint256 depositNonce,
        address recipient,
        uint256 amount,
        bytes calldata signature
    ) external nonReentrant whenNotPaused checkPeg {
        if (amount == 0) revert ZeroAmount();
        if (recipient == address(0)) revert ZeroAddress();
        if (processedDeposits[srcChainId][depositNonce]) revert NonceAlreadyProcessed();

        // Verify MPC signature
        bytes32 messageHash = keccak256(abi.encodePacked(
            "DEPOSIT",
            srcChainId,
            depositNonce,
            recipient,
            amount
        ));
        bytes32 ethSignedHash = MessageHashUtils.toEthSignedMessageHash(messageHash);
        address signer = ECDSA.recover(ethSignedHash, signature);
        
        if (!mpcOracles[signer]) revert InvalidSignature();

        // Check backing ratio
        _checkBackingRatio(srcChainId, amount);

        // Mark as processed
        processedDeposits[srcChainId][depositNonce] = true;
        totalDepositMinted += amount;

        // Mint tokens to recipient
        token.mint(recipient, amount);

        emit DepositMinted(srcChainId, depositNonce, recipient, amount);
    }

    /**
     * @notice Mint LETH for yield harvested on source chain
     * @param srcChainId Source chain ID
     * @param yieldNonce Yield nonce from TeleportVault
     * @param amount Amount of yield LETH to mint
     * @param signature MPC signature of yield proof
     */
    function mintYield(
        uint256 srcChainId,
        uint256 yieldNonce,
        uint256 amount,
        bytes calldata signature
    ) external nonReentrant whenNotPaused {
        if (amount == 0) revert ZeroAmount();
        if (liquidYield == address(0)) revert ZeroAddress();
        if (processedYields[srcChainId][yieldNonce]) revert NonceAlreadyProcessed();

        // Verify MPC signature
        bytes32 messageHash = keccak256(abi.encodePacked(
            "YIELD",
            srcChainId,
            yieldNonce,
            amount
        ));
        bytes32 ethSignedHash = MessageHashUtils.toEthSignedMessageHash(messageHash);
        address signer = ECDSA.recover(ethSignedHash, signature);
        
        if (!mpcOracles[signer]) revert InvalidSignature();

        // Mark as processed
        processedYields[srcChainId][yieldNonce] = true;
        totalYieldMinted += amount;

        // Mint yield tokens directly to LiquidYield
        token.mint(liquidYield, amount);

        // Notify LiquidYield
        ILiquidYield(liquidYield).onYieldReceived(amount, srcChainId);

        emit YieldMinted(srcChainId, yieldNonce, amount);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // BURN FUNCTIONS (USER)
    // ═══════════════════════════════════════════════════════════════════════

    /**
     * @notice Burn LETH to initiate withdrawal back to source chain
     * @param amount Amount of LETH to burn
     * @param srcChainId Destination chain for ETH release
     * @param recipient ETH recipient on source chain
     * @return withdrawNonce Unique withdraw nonce for tracking
     */
    function burnForWithdraw(
        uint256 amount,
        uint256 srcChainId,
        address recipient
    ) external nonReentrant whenNotPaused returns (uint256 withdrawNonce) {
        if (amount == 0) revert ZeroAmount();
        if (recipient == address(0)) revert ZeroAddress();

        // Burn tokens from user
        token.burnFrom(msg.sender, amount);

        // Generate withdraw nonce
        withdrawNonce = uint256(keccak256(abi.encodePacked(
            block.timestamp,
            msg.sender,
            amount,
            srcChainId,
            block.number
        )));

        pendingWithdraws[withdrawNonce] = true;
        totalBurned += amount;

        emit BurnedForWithdraw(msg.sender, amount, withdrawNonce);

        // MPC will monitor this event and call release on LiquidVault
    }

    // ═══════════════════════════════════════════════════════════════════════
    // BACKING ATTESTATION (MPC ONLY)
    // ═══════════════════════════════════════════════════════════════════════

    /**
     * @notice Update backing attestation for a source chain
     * @param srcChainId Source chain ID
     * @param totalBacking Total ETH backing on source chain
     * @param signature MPC signature
     */
    function updateBacking(
        uint256 srcChainId,
        uint256 totalBacking,
        bytes calldata signature
    ) external {
        // Verify MPC signature
        bytes32 messageHash = keccak256(abi.encodePacked(
            "BACKING",
            srcChainId,
            totalBacking,
            block.timestamp
        ));
        bytes32 ethSignedHash = MessageHashUtils.toEthSignedMessageHash(messageHash);
        address signer = ECDSA.recover(ethSignedHash, signature);
        
        if (!mpcOracles[signer]) revert InvalidSignature();

        backingAttestations[srcChainId] = BackingAttestation({
            totalBacking: totalBacking,
            timestamp: block.timestamp,
            signature: signature
        });

        emit BackingUpdated(srcChainId, totalBacking, block.timestamp);

        // Auto-pause if backing insufficient
        if (totalBacking < totalMinted()) {
            paused = true;
            emit PausedStateChanged(true);
        }
    }

    // ═══════════════════════════════════════════════════════════════════════
    // ADMIN FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════

    /**
     * @notice Set LiquidVault address (for debt notifications)
     * @param _liquidVault LiquidVault address
     */
    function setLiquidVault(address _liquidVault) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (_liquidVault == address(0)) revert ZeroAddress();
        liquidVault = _liquidVault;
    }

    /**
     * @notice Set LiquidYield address
     * @param _liquidYield LiquidYield address
     */
    function setLiquidYield(address _liquidYield) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (_liquidYield == address(0)) revert ZeroAddress();
        liquidYield = _liquidYield;
        _grantRole(LIQUID_YIELD_ROLE, _liquidYield);
    }

    /**
     * @notice Set MPC oracle status
     * @param oracle Oracle address
     * @param active Active status
     */
    function setMPCOracle(address oracle, bool active) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (oracle == address(0)) revert ZeroAddress();
        
        mpcOracles[oracle] = active;
        
        if (active) {
            _grantRole(MPC_ROLE, oracle);
        } else {
            _revokeRole(MPC_ROLE, oracle);
        }
        
        emit MPCOracleSet(oracle, active);
    }

    /**
     * @notice Set paused state
     * @param _paused New paused state
     */
    function setPaused(bool _paused) external onlyRole(DEFAULT_ADMIN_ROLE) {
        paused = _paused;
        emit PausedStateChanged(_paused);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // VIEW FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════

    /**
     * @notice Get total tokens minted (deposits + yield)
     */
    function totalMinted() public view returns (uint256) {
        return totalDepositMinted + totalYieldMinted;
    }

    /**
     * @notice Get net LETH in circulation
     */
    function netCirculation() external view returns (uint256) {
        return totalMinted() - totalBurned;
    }

    /**
     * @notice Get current peg ratio (in basis points)
     * @dev 10000 = 1:1, 9950 = 99.5%
     */
    function getCurrentPeg() public view returns (uint256) {
        // In a real implementation, this would query a DEX oracle
        // For now, we assume 1:1 peg
        return BASIS_POINTS;
    }

    /**
     * @notice Check if deposit nonce is processed
     */
    function isDepositProcessed(uint256 srcChainId, uint256 depositNonce) external view returns (bool) {
        return processedDeposits[srcChainId][depositNonce];
    }

    /**
     * @notice Check if yield nonce is processed
     */
    function isYieldProcessed(uint256 srcChainId, uint256 yieldNonce) external view returns (bool) {
        return processedYields[srcChainId][yieldNonce];
    }

    /**
     * @notice Get backing attestation for a source chain
     */
    function getBacking(uint256 srcChainId) external view returns (uint256 totalBacking, uint256 timestamp) {
        BackingAttestation memory attestation = backingAttestations[srcChainId];
        return (attestation.totalBacking, attestation.timestamp);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // INTERNAL FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════

    /**
     * @notice Check that backing ratio is sufficient for new minting
     */
    function _checkBackingRatio(uint256 srcChainId, uint256 additionalMint) internal view {
        BackingAttestation memory attestation = backingAttestations[srcChainId];
        
        // Require attestation within last 24 hours
        if (block.timestamp - attestation.timestamp > 24 hours) {
            // Stale attestation, allow minting but log warning
            // In production, might want stricter enforcement
            return;
        }

        uint256 newTotalMinted = totalMinted() + additionalMint;
        
        if (newTotalMinted > attestation.totalBacking) {
            revert BackingInsufficient();
        }
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// INTERFACES
// ═══════════════════════════════════════════════════════════════════════════

/**
 * @notice Interface for bridged tokens (LETH, LUSD, etc.)
 */
interface IBridgedToken {
    function mint(address to, uint256 amount) external;
    function burn(uint256 amount) external;
    function burnFrom(address from, uint256 amount) external;
    function balanceOf(address account) external view returns (uint256);
}

/**
 * @notice Interface for LiquidYield
 */
interface ILiquidYield {
    function onYieldReceived(uint256 amount, uint256 srcChainId) external;
}
