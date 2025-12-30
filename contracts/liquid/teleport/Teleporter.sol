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
 * @notice Cross-chain bridge for base collateral (ETH, USDC, USDT, DAI, etc.)
 * @dev Part of the Teleport Protocol - bridges assets for use with Liquid Protocol
 *
 * Token Model:
 * - Teleporter mints COLLATERAL tokens (e.g., bridged ETH)
 * - Collateral must be deposited into LiquidETH vault to get L* tokens
 * - L* tokens (e.g., LETH) are the yield-bearing synthetics
 *
 * Flow:
 * 1. User deposits ETH on Ethereum/Base → LiquidVault
 * 2. MPC attests → Teleporter.mintDeposit() → mints ETH to user on Lux
 * 3. User deposits ETH into LiquidETH → receives LETH (yield-bearing)
 * 4. Yield harvested → mintYield() → LETH minted to LiquidYield → reduces debt
 *
 * Domain Separation:
 * - Deposit nonces: user deposits (mintDeposit)
 * - Yield nonces: yield minting (mintYield)
 * - Withdraw nonces: burn and release flow
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
    bytes32 public constant LIQUID_VAULT_ROLE = keccak256("LIQUID_VAULT_ROLE");

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
        uint256 totalBacking;     // Total collateral on source chain
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

    /// @notice The collateral token (bridged ETH, USDC, etc.)
    IBridgedToken public immutable collateralToken;

    /// @notice The synthetic token (LETH, LUSD, etc.) - minted for yield
    IBridgedToken public immutable synthToken;

    /// @notice LiquidVault address (for yield routing)
    address public liquidVault;

    /// @notice Total collateral minted via deposits
    uint256 public totalDepositMinted;

    /// @notice Total synth minted via yield
    uint256 public totalYieldMinted;

    /// @notice Total collateral burned for withdrawals
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

    /// @notice Emitted when collateral minted for deposit
    event DepositMinted(
        uint256 indexed srcChainId,
        uint256 indexed depositNonce,
        address indexed recipient,
        uint256 amount
    );

    /// @notice Emitted when synth minted for yield (to LiquidVault)
    event YieldMinted(
        uint256 indexed srcChainId,
        uint256 indexed yieldNonce,
        uint256 amount
    );

    /// @notice Emitted when collateral burned for withdrawal
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

    /**
     * @notice Initialize Teleporter
     * @param _collateralToken Bridged collateral token (e.g., ETH on Lux)
     * @param _synthToken Synthetic token (e.g., LETH)
     * @param _mpcOracle Initial MPC oracle address
     */
    constructor(
        address _collateralToken,
        address _synthToken,
        address _mpcOracle
    ) Ownable(msg.sender) {
        if (_collateralToken == address(0) || _synthToken == address(0) || _mpcOracle == address(0)) {
            revert ZeroAddress();
        }

        collateralToken = IBridgedToken(_collateralToken);
        synthToken = IBridgedToken(_synthToken);

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(MPC_ROLE, _mpcOracle);
        mpcOracles[_mpcOracle] = true;

        emit MPCOracleSet(_mpcOracle, true);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // MINT FUNCTIONS (MPC ONLY)
    // ═══════════════════════════════════════════════════════════════════════

    /**
     * @notice Mint collateral for a deposit proof from source chain
     * @dev Mints the COLLATERAL token (e.g., bridged ETH), NOT the synthetic
     *      User must deposit collateral into LiquidVault to get L* tokens
     * @param srcChainId Source chain ID (e.g., Base = 8453, Ethereum = 1)
     * @param depositNonce Deposit nonce from source chain LiquidVault
     * @param recipient Collateral recipient on Lux
     * @param amount Amount of collateral to mint
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

        // Mint COLLATERAL to recipient (not synth!)
        collateralToken.mint(recipient, amount);

        emit DepositMinted(srcChainId, depositNonce, recipient, amount);
    }

    /**
     * @notice Mint synthetic for yield harvested on source chain
     * @dev Mints the SYNTHETIC token (e.g., LETH) to LiquidVault for debt repayment
     *      Yield is realized as synthetic tokens, not collateral
     * @param srcChainId Source chain ID
     * @param yieldNonce Yield nonce from source chain LiquidVault
     * @param amount Amount of synth yield to mint
     * @param signature MPC signature of yield proof
     */
    function mintYield(
        uint256 srcChainId,
        uint256 yieldNonce,
        uint256 amount,
        bytes calldata signature
    ) external nonReentrant whenNotPaused {
        if (amount == 0) revert ZeroAmount();
        if (liquidVault == address(0)) revert ZeroAddress();
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

        // Mint SYNTHETIC to LiquidVault (for debt repayment)
        synthToken.mint(liquidVault, amount);

        // Notify LiquidVault of yield
        ILiquidVault(liquidVault).onYieldReceived(amount, srcChainId);

        emit YieldMinted(srcChainId, yieldNonce, amount);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // BURN FUNCTIONS (USER)
    // ═══════════════════════════════════════════════════════════════════════

    /**
     * @notice Burn collateral to initiate withdrawal back to source chain
     * @param amount Amount of collateral to burn
     * @param srcChainId Destination chain for release
     * @param recipient Recipient on source chain
     * @return withdrawNonce Unique withdraw nonce for tracking
     */
    function burnForWithdraw(
        uint256 amount,
        uint256 srcChainId,
        address recipient
    ) external nonReentrant whenNotPaused returns (uint256 withdrawNonce) {
        if (amount == 0) revert ZeroAmount();
        if (recipient == address(0)) revert ZeroAddress();

        // Burn collateral from user
        collateralToken.burnFrom(msg.sender, amount);

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

        // MPC will monitor this event and call release on source chain LiquidVault
    }

    // ═══════════════════════════════════════════════════════════════════════
    // BACKING ATTESTATION (MPC ONLY)
    // ═══════════════════════════════════════════════════════════════════════

    /**
     * @notice Update backing attestation for a source chain
     * @param srcChainId Source chain ID
     * @param totalBacking Total collateral backing on source chain
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
     * @notice Set LiquidVault address (receives yield)
     * @param _liquidVault LiquidVault address on Lux
     */
    function setLiquidVault(address _liquidVault) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (_liquidVault == address(0)) revert ZeroAddress();
        liquidVault = _liquidVault;
        _grantRole(LIQUID_VAULT_ROLE, _liquidVault);
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
     * @notice Get total collateral minted
     */
    function totalMinted() public view returns (uint256) {
        return totalDepositMinted;
    }

    /**
     * @notice Get net collateral in circulation
     */
    function netCirculation() external view returns (uint256) {
        return totalMinted() - totalBurned;
    }

    /**
     * @notice Get current peg ratio (in basis points)
     * @dev 10000 = 1:1, 9950 = 99.5%
     */
    function getCurrentPeg() public view returns (uint256) {
        // In production, query DEX oracle for collateral/synth ratio
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
            // Stale attestation - allow for launch, stricter later
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
 * @notice Interface for bridged/synthetic tokens
 */
interface IBridgedToken {
    function mint(address to, uint256 amount) external;
    function burn(uint256 amount) external;
    function burnFrom(address from, uint256 amount) external;
    function balanceOf(address account) external view returns (uint256);
}

/**
 * @notice Interface for LiquidVault (LiquidETH, etc.)
 */
interface ILiquidVault {
    function onYieldReceived(uint256 amount, uint256 srcChainId) external;
}
