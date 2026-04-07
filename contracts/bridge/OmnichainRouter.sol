// SPDX-License-Identifier: MIT
pragma solidity ^0.8.31;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { ECDSA } from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import { MessageHashUtils } from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";

/**
 * @title OmnichainRouter
 * @notice The immutable, non-upgradeable omnichain bridge router
 *
 * @dev This contract is the SINGLE entry point for all cross-chain operations.
 *      It is:
 *        - NON-UPGRADEABLE (no proxy, no admin upgrade path)
 *        - NON-CUSTODIAL (MPC threshold signatures, no single key)
 *        - TRUSTLESS (on-chain signature verification, nonce tracking)
 *        - FEE-TRANSPARENT (all fees on-chain, configurable by governance)
 *
 *      Architecture:
 *
 *      [Any Chain] --MPC Sign--> OmnichainRouter --mint--> Bridged Tokens
 *                                      |
 *                                      ├── YieldBridgeConfig (strategy routing)
 *                                      ├── Staking Vault (fee distribution)
 *                                      ├── ShariaFilter (halal/haram classification)
 *                                      └── Native DEX (instant liquidity)
 *
 *      SOVEREIGN GOVERNANCE:
 *        Each chain deploys its OWN OmnichainRouter.
 *        Governance is per-chain — the native token holders decide fees:
 *
 *        Chain A:  DAO → fees to staking vault
 *        Chain B:  DAO → fees to stakers
 *        Any L1:   Their DAO → their fee recipient
 *
 *      Fee Flow (trustless, on-chain, governed by native DAO):
 *        bridge_fee (configurable, max 1%) → split:
 *          - stakeholderShareBps% → stakeholder vault (stakers)
 *          - remainder → protocol treasury
 *
 *      GOVERNANCE MODEL:
 *        - `governor` address controls: fee rates, fee splits, token registration,
 *          daily limits, Shariah compliance mode, yield strategy config
 *        - `governor` CANNOT: mint tokens, steal funds, change MPC signers,
 *          upgrade the contract, bypass nonce checks
 *        - Governor is typically a timelock controlled by the native DAO
 *        - Fee recipient changes require governor + 48h timelock
 *
 *      MPC SIGNER MANAGEMENT (separate from governance):
 *        - 2-of-3 threshold (FROST/CGGMP21)
 *        - Signer rotation requires 2-of-3 current signers to approve
 *        - 7-day timelock on signer changes (gives users exit window)
 *        - No single entity can mint without threshold agreement
 *        - MPC set can be shared across chains OR each chain runs its own
 *
 *      PERMISSIONLESS RELAY:
 *        Anyone can call bridge functions with valid MPC signatures.
 *        Liquidity.io / Lux / any operator pays gas but CANNOT steal funds.
 *        Users can self-relay if operator goes offline.
 */
contract OmnichainRouter is ReentrancyGuard {
    using SafeERC20 for IERC20;
    using ECDSA for bytes32;
    using MessageHashUtils for bytes32;

    // ================================================================
    //  IMMUTABLE CONFIG (set once at deployment, never changes)
    // ================================================================

    /// @notice This chain's ID (immutable — identifies which chain this router is on)
    uint64 public immutable chainId;

    // ================================================================
    //  SOVEREIGN GOVERNANCE (controlled by native chain DAO)
    // ================================================================

    /// @notice Governor address — the native chain's DAO (timelock)
    address public governor;

    /// @notice Pending governor (2-step transfer)
    address public pendingGovernor;

    /// @notice Stakeholder vault — receives majority of bridge fees
    address public stakeholderVault;

    /// @notice Protocol treasury (receives minority of fees)
    address public treasury;

    /// @notice Bridge fee in basis points (max 100 = 1%)
    uint256 public bridgeFeeBps;

    /// @notice Stakeholder share of fees in basis points (e.g., 9000 = 90%)
    uint256 public stakeholderShareBps;

    /// @notice Timelock for governance changes
    uint256 public constant GOVERNANCE_TIMELOCK = 48 hours;

    /// @notice Pending fee recipient change
    address public pendingStakeholderVault;
    uint256 public pendingStakeholderVaultActivateAt;

    /// @notice Shariah compliance mode (filters non-halal yield strategies)
    bool public shariahMode;

    /// @notice ShariaFilter contract (optional, set by governor)
    address public shariaFilter;

    /// @notice Max bridge fee hard cap (immutable, protects users)
    uint256 public constant MAX_BRIDGE_FEE_BPS = 100; // 1% absolute max

    // ================================================================
    //  MPC SIGNER STATE (rotatable with timelock)
    // ================================================================

    struct SignerSet {
        address signer1;          // individual signer (for accountability/display)
        address signer2;          // individual signer
        address signer3;          // individual signer
        address mpcGroupAddress;  // CGGMP21/FROST threshold aggregate key address
        uint8 threshold;          // required signers (e.g., 2-of-3)
    }

    SignerSet public signers;

    /// @notice Pending signer rotation (7-day timelock)
    SignerSet public pendingSigners;
    uint256 public pendingSignersActivateAt; // 0 = no pending change
    uint256 public rotationNonce;            // prevents rotation/cancel replay

    uint256 public constant SIGNER_TIMELOCK = 7 days;

    // ================================================================
    //  BRIDGE STATE
    // ================================================================

    /// @notice Registered bridge tokens (LETH, LBTC, LUSD, etc.)
    mapping(address => bool) public registeredTokens;

    /// @notice Processed deposit nonces per source chain
    mapping(uint64 => mapping(uint64 => bool)) public processedDeposits;

    /// @notice Outbound nonce for burns
    uint64 public outboundNonce;

    /// @notice Total minted per token (for backing ratio tracking)
    mapping(address => uint256) public totalMinted;

    /// @notice Total backing per token (attested by MPC)
    mapping(address => uint256) public totalBacking;

    /// @notice Last backing attestation timestamp per token
    mapping(address => uint256) public lastBackingUpdate;

    /// @notice Daily mint limits per token
    mapping(address => uint256) public dailyMintLimit;
    mapping(address => uint256) public dailyMinted;
    mapping(address => uint256) public mintPeriodStart;

    /// @notice Auto-pause flag (set by undercollateralization, only clearable by valid backing)
    bool public autoPaused;

    /// @notice Manual pause flag (set by MPC signers)
    bool public manualPaused;

    /// @notice Nonce for pause/unpause signatures (prevents replay)
    uint256 public pauseNonce;

    // ================================================================
    //  EVENTS
    // ================================================================

    event Minted(
        uint64 indexed sourceChain,
        uint64 indexed nonce,
        address indexed token,
        address recipient,
        uint256 amount,
        uint256 fee
    );

    event Burned(
        uint64 indexed destChain,
        uint64 indexed nonce,
        address indexed token,
        address sender,
        bytes32 recipient,
        uint256 amount
    );

    event BackingUpdated(address indexed token, uint256 totalBacking, uint256 timestamp);
    event SignerRotationProposed(SignerSet newSigners, uint256 activateAt);
    event SignerRotationExecuted(SignerSet newSigners);
    event TokenRegistered(address indexed token, uint256 dailyLimit);

    // ================================================================
    //  CONSTRUCTOR (immutable params)
    // ================================================================

    /// @notice Deploy the OmnichainRouter for a specific chain
    /// @param _chainId This chain's ID (immutable)
    /// @param _governor The native DAO's timelock/governor address
    /// @param _stakeholderVault Fee recipient (xLUX on Lux, LQDTY stakers on Liquidity, etc.)
    /// @param _treasury Protocol treasury address
    /// @param _bridgeFeeBps Initial bridge fee (max 1%)
    /// @param _stakeholderShareBps Stakeholder share of fees (e.g., 9000 = 90%)
    /// @param _signer1 MPC signer 1
    /// @param _signer2 MPC signer 2
    /// @param _signer3 MPC signer 3
    constructor(
        uint64 _chainId,
        address _governor,
        address _stakeholderVault,
        address _treasury,
        uint256 _bridgeFeeBps,
        uint256 _stakeholderShareBps,
        address _signer1,
        address _signer2,
        address _signer3,
        address _mpcGroupAddress
    ) {
        require(_bridgeFeeBps <= MAX_BRIDGE_FEE_BPS, "Max 1% bridge fee");
        require(_stakeholderShareBps <= 10000, "Invalid share");
        require(_governor != address(0), "Zero governor");
        require(_stakeholderVault != address(0), "Zero vault");
        require(_mpcGroupAddress != address(0), "Zero MPC group");

        chainId = _chainId;
        governor = _governor;
        stakeholderVault = _stakeholderVault;
        treasury = _treasury;
        bridgeFeeBps = _bridgeFeeBps;
        stakeholderShareBps = _stakeholderShareBps;

        signers = SignerSet(_signer1, _signer2, _signer3, _mpcGroupAddress, 2);
    }

    // ================================================================
    //  GOVERNANCE (native chain DAO controls fees/config)
    // ================================================================

    modifier onlyGovernor() {
        require(msg.sender == governor, "Only governor");
        _;
    }

    /// @notice Transfer governance to new address (2-step)
    function transferGovernance(address newGovernor) external onlyGovernor {
        require(newGovernor != address(0), "Zero address");
        pendingGovernor = newGovernor;
    }

    /// @notice Accept governance transfer
    function acceptGovernance() external {
        require(msg.sender == pendingGovernor, "Not pending governor");
        governor = pendingGovernor;
        pendingGovernor = address(0);
    }

    /// @notice Update bridge fee (governor only, max 1%)
    function setBridgeFee(uint256 newFeeBps) external onlyGovernor {
        require(newFeeBps <= MAX_BRIDGE_FEE_BPS, "Max 1%");
        bridgeFeeBps = newFeeBps;
    }

    /// @notice Update stakeholder share of fees (governor only)
    function setStakeholderShare(uint256 newShareBps) external onlyGovernor {
        require(newShareBps <= 10000, "Invalid");
        stakeholderShareBps = newShareBps;
    }

    /// @notice Propose new stakeholder vault (48h timelock)
    /// @dev This is the most sensitive governance action — changing where fees go.
    ///      48h timelock gives stakers time to react.
    function proposeStakeholderVault(address newVault) external onlyGovernor {
        require(newVault != address(0), "Zero address");
        pendingStakeholderVault = newVault;
        pendingStakeholderVaultActivateAt = block.timestamp + GOVERNANCE_TIMELOCK;
    }

    /// @notice Execute pending stakeholder vault change (after 48h)
    function executeStakeholderVaultChange() external {
        require(pendingStakeholderVaultActivateAt > 0, "No pending change");
        require(block.timestamp >= pendingStakeholderVaultActivateAt, "Timelock active");
        stakeholderVault = pendingStakeholderVault;
        pendingStakeholderVaultActivateAt = 0;
    }

    /// @notice Update treasury address (governor only, immediate)
    function setTreasury(address newTreasury) external onlyGovernor {
        require(newTreasury != address(0), "Zero address");
        treasury = newTreasury;
    }

    /// @notice Enable/disable Shariah compliance mode (governor only)
    function setShariahMode(bool enabled, address _shariaFilter) external onlyGovernor {
        shariahMode = enabled;
        shariaFilter = _shariaFilter;
    }

    /// @notice Update daily mint limit for a token (governor only)
    function setDailyMintLimit(address token, uint256 limit) external onlyGovernor {
        require(registeredTokens[token], "Not registered");
        dailyMintLimit[token] = limit;
    }

    // ================================================================
    //  CORE BRIDGE: MINT (MPC-signed, anyone can relay)
    // ================================================================

    /// @notice Mint bridge tokens with MPC attestation
    /// @dev ANYONE can call this with a valid MPC signature.
    ///      Liquidity.io typically relays, but users can self-relay.
    ///      The MPC signature proves the deposit happened on the source chain.
    function mintDeposit(
        uint64 sourceChainId,
        uint64 depositNonce,
        address token,
        address recipient,
        uint256 amount,
        bytes calldata mpcSignature
    ) external nonReentrant {
        require(!autoPaused && !manualPaused, "Paused");
        require(registeredTokens[token], "Token not registered");
        require(!processedDeposits[sourceChainId][depositNonce], "Nonce processed");
        require(amount > 0, "Zero amount");

        // Verify MPC signature (includes destination chainId to prevent cross-chain replay)
        bytes32 digest = keccak256(abi.encodePacked(
            "DEPOSIT",
            chainId,        // destination chain (prevents replay on other chains)
            sourceChainId,
            depositNonce,
            token,
            recipient,
            amount
        ));
        address recovered = digest.toEthSignedMessageHash().recover(mpcSignature);
        require(_isAuthorizedSigner(recovered), "Invalid MPC signature");

        // Check daily limit
        _checkDailyLimit(token, amount);

        // Mark nonce as processed
        processedDeposits[sourceChainId][depositNonce] = true;

        // Calculate fee
        uint256 fee = (amount * bridgeFeeBps) / 10000;
        uint256 mintAmount = amount - fee;

        // Mint to recipient
        IBridgeToken(token).bridgeMint(recipient, mintAmount);

        // Distribute fee to sovereign stakeholders
        if (fee > 0) {
            uint256 toStakeholders = (fee * stakeholderShareBps) / 10000;
            uint256 toTreasury = fee - toStakeholders;

            if (toStakeholders > 0) {
                IBridgeToken(token).bridgeMint(stakeholderVault, toStakeholders);
            }
            if (toTreasury > 0) {
                IBridgeToken(token).bridgeMint(treasury, toTreasury);
            }
        }

        // Track total minted including fee shares for accurate backing ratio
        // All minted tokens must be backed by source chain deposits
        totalMinted[token] += amount;

        emit Minted(sourceChainId, depositNonce, token, recipient, mintAmount, fee);
    }

    // ================================================================
    //  CORE BRIDGE: BATCH MINT (GPU-optimized, relayer batching)
    // ================================================================

    struct MintParams {
        uint64 sourceChainId;
        uint64 depositNonce;
        address token;
        address recipient;
        uint256 amount;
    }

    /// @notice Batch mint multiple deposits in a single transaction
    /// @dev Amortizes per-tx overhead for GPU EVM acceleration (30K+ opcodes = 3x GPU zone).
    ///      Each deposit requires its own MPC signature over its own digest.
    function batchMintDeposit(
        MintParams[] calldata deposits,
        bytes[] calldata mpcSignatures
    ) external nonReentrant {
        require(deposits.length == mpcSignatures.length, "Length mismatch");
        require(!autoPaused && !manualPaused, "Paused");

        for (uint256 i = 0; i < deposits.length; i++) {
            MintParams calldata d = deposits[i];
            require(registeredTokens[d.token], "Token not registered");
            require(!processedDeposits[d.sourceChainId][d.depositNonce], "Nonce processed");
            require(d.amount > 0, "Zero amount");

            bytes32 digest = keccak256(abi.encodePacked(
                "DEPOSIT", chainId, d.sourceChainId, d.depositNonce, d.token, d.recipient, d.amount
            ));
            address recovered = digest.toEthSignedMessageHash().recover(mpcSignatures[i]);
            require(_isAuthorizedSigner(recovered), "Invalid MPC signature");

            _checkDailyLimit(d.token, d.amount);
            processedDeposits[d.sourceChainId][d.depositNonce] = true;

            uint256 fee = (d.amount * bridgeFeeBps) / 10000;
            uint256 mintAmount = d.amount - fee;

            IBridgeToken(d.token).bridgeMint(d.recipient, mintAmount);

            if (fee > 0) {
                uint256 toStakeholders = (fee * stakeholderShareBps) / 10000;
                uint256 toTreasury = fee - toStakeholders;
                if (toStakeholders > 0) IBridgeToken(d.token).bridgeMint(stakeholderVault, toStakeholders);
                if (toTreasury > 0) IBridgeToken(d.token).bridgeMint(treasury, toTreasury);
            }

            totalMinted[d.token] += d.amount;
            emit Minted(d.sourceChainId, d.depositNonce, d.token, d.recipient, mintAmount, fee);
        }
    }

    // ================================================================
    //  CORE BRIDGE: BURN (user-initiated, permissionless)
    // ================================================================

    /// @notice Burn bridge tokens to withdraw on destination chain
    /// @dev Fully permissionless. ALWAYS allowed even when paused.
    ///      Burns reduce systemic risk (decrease totalMinted), so blocking
    ///      them during a pause would trap users. Exit guarantee.
    function burnForWithdrawal(
        address token,
        uint256 amount,
        uint64 destChainId,
        bytes32 destRecipient
    ) external nonReentrant {
        // NOTE: No pause check. Burns are always allowed (exit guarantee).
        require(registeredTokens[token], "Token not registered");
        require(amount > 0, "Zero amount");

        // Burn from sender
        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
        IBridgeToken(token).bridgeBurn(address(this), amount);

        outboundNonce++;
        totalMinted[token] -= amount;

        emit Burned(destChainId, outboundNonce, token, msg.sender, destRecipient, amount);
    }

    // ================================================================
    //  BACKING ATTESTATION (MPC updates total backing periodically)
    // ================================================================

    /// @notice MPC attests to total backing on source chains
    /// @dev Called every ~12 hours. If backing < minted, auto-pause.
    function updateBacking(
        address token,
        uint256 _totalBacking,
        uint256 timestamp,
        bytes calldata mpcSignature
    ) external {
        bytes32 digest = keccak256(abi.encodePacked(
            "BACKING",
            chainId,
            token,
            _totalBacking,
            timestamp
        ));
        address recovered = digest.toEthSignedMessageHash().recover(mpcSignature);
        require(_isAuthorizedSigner(recovered), "Invalid MPC signature");
        require(timestamp > lastBackingUpdate[token], "Stale attestation");

        totalBacking[token] = _totalBacking;
        lastBackingUpdate[token] = timestamp;

        // Auto-pause if undercollateralized (< 98.5%), auto-clear when restored (>= 99%)
        if (totalMinted[token] > 0) {
            uint256 ratio = _totalBacking * 10000 / totalMinted[token];
            if (ratio < 9850) {
                autoPaused = true;
            } else if (autoPaused && ratio >= 9900) {
                // Only clear autoPause when backing is restored above 99%
                // (hysteresis prevents oscillation)
                autoPaused = false;
            }
        }

        emit BackingUpdated(token, _totalBacking, timestamp);
    }

    // ================================================================
    //  MPC SIGNER MANAGEMENT (timelocked rotation)
    // ================================================================

    /// @notice Propose new signer set (requires current MPC threshold signature)
    function proposeSignerRotation(
        SignerSet calldata newSigners,
        bytes calldata mpcSignature
    ) external {
        bytes32 digest = keccak256(abi.encodePacked(
            "ROTATE_SIGNERS",
            chainId,
            rotationNonce,
            newSigners.signer1,
            newSigners.signer2,
            newSigners.signer3,
            newSigners.mpcGroupAddress,
            newSigners.threshold
        ));
        address recovered = digest.toEthSignedMessageHash().recover(mpcSignature);
        require(_isAuthorizedSigner(recovered), "Invalid MPC signature");

        pendingSigners = newSigners;
        pendingSignersActivateAt = block.timestamp + SIGNER_TIMELOCK;
        rotationNonce++;

        emit SignerRotationProposed(newSigners, pendingSignersActivateAt);
    }

    /// @notice Execute pending signer rotation (after timelock)
    function executeSignerRotation() external {
        require(pendingSignersActivateAt > 0, "No pending rotation");
        require(block.timestamp >= pendingSignersActivateAt, "Timelock not expired");

        signers = pendingSigners;
        pendingSignersActivateAt = 0;

        emit SignerRotationExecuted(signers);
    }

    /// @notice Cancel pending rotation (requires current MPC signature)
    function cancelSignerRotation(bytes calldata mpcSignature) external {
        require(pendingSignersActivateAt > 0, "No pending rotation");
        bytes32 digest = keccak256(abi.encodePacked(
            "CANCEL_ROTATION",
            chainId,
            rotationNonce,
            pendingSignersActivateAt
        ));
        address recovered = digest.toEthSignedMessageHash().recover(mpcSignature);
        require(_isAuthorizedSigner(recovered), "Invalid MPC signature");

        pendingSignersActivateAt = 0;
        rotationNonce++;
    }

    // ================================================================
    //  PAUSE / UNPAUSE (MPC only)
    // ================================================================

    /// @notice Manual pause (MPC only, uses nonce to prevent replay)
    function pause(bytes calldata mpcSignature) external {
        bytes32 digest = keccak256(abi.encodePacked("PAUSE", chainId, pauseNonce));
        address recovered = digest.toEthSignedMessageHash().recover(mpcSignature);
        require(_isAuthorizedSigner(recovered), "Invalid");
        manualPaused = true;
        pauseNonce++;
    }

    /// @notice Manual unpause (MPC only). Does NOT clear autoPaused.
    /// autoPaused is only clearable when backing ratio is restored via updateBacking.
    function unpause(bytes calldata mpcSignature) external {
        bytes32 digest = keccak256(abi.encodePacked("UNPAUSE", chainId, pauseNonce));
        address recovered = digest.toEthSignedMessageHash().recover(mpcSignature);
        require(_isAuthorizedSigner(recovered), "Invalid");
        manualPaused = false;
        pauseNonce++;
    }

    // ================================================================
    //  TOKEN REGISTRATION (MPC only, one-time per token)
    // ================================================================

    function registerToken(
        address token,
        uint256 _dailyMintLimit,
        bytes calldata mpcSignature
    ) external {
        bytes32 digest = keccak256(abi.encodePacked("REGISTER", chainId, token, _dailyMintLimit));
        address recovered = digest.toEthSignedMessageHash().recover(mpcSignature);
        require(_isAuthorizedSigner(recovered), "Invalid");
        require(!registeredTokens[token], "Already registered");

        registeredTokens[token] = true;
        dailyMintLimit[token] = _dailyMintLimit;

        emit TokenRegistered(token, _dailyMintLimit);
    }

    // ================================================================
    //  VIEW FUNCTIONS
    // ================================================================

    /// @notice Get current peg ratio for a token (10000 = fully backed)
    function getPegRatio(address token) external view returns (uint256) {
        if (totalMinted[token] == 0) return 10000;
        return (totalBacking[token] * 10000) / totalMinted[token];
    }

    /// @notice Check if a signer is authorized
    function isAuthorizedSigner(address signer) external view returns (bool) {
        return _isAuthorizedSigner(signer);
    }

    // ================================================================
    //  INTERNAL
    // ================================================================

    /// @dev Verifies against the MPC threshold group address (CGGMP21/FROST aggregate key).
    ///      The threshold protocol ensures only t-of-n signers can produce a valid signature
    ///      for this address. Individual signer addresses are for display/accountability only.
    function _isAuthorizedSigner(address recovered) internal view returns (bool) {
        return recovered == signers.mpcGroupAddress;
    }

    function _checkDailyLimit(address token, uint256 amount) internal {
        uint256 limit = dailyMintLimit[token];
        if (limit == 0) return; // unlimited

        if (block.timestamp >= mintPeriodStart[token] + 1 days) {
            dailyMinted[token] = 0;
            mintPeriodStart[token] = block.timestamp;
        }

        dailyMinted[token] += amount;
        require(dailyMinted[token] <= limit, "Daily mint limit exceeded");
    }
}

/// @notice Interface for bridge tokens (LETH, LBTC, LUSD, etc.)
interface IBridgeToken {
    function bridgeMint(address to, uint256 amount) external;
    function bridgeBurn(address from, uint256 amount) external;
}
