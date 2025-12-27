// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./IBridgeToken.sol";

/**
 * @title Bridge
 * @notice Secure cross-chain bridge using EIP-712 typed signatures and MPC oracles
 * @dev Implements proper replay protection, token whitelisting, and role separation
 */
contract Bridge is AccessControl, ReentrancyGuard, Pausable, EIP712 {
    using ECDSA for bytes32;
    using SafeERC20 for IERC20;

    // ============ Roles ============
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant ORACLE_ROLE = keccak256("ORACLE_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    // ============ EIP-712 Type Hash ============
    bytes32 public constant CLAIM_TYPEHASH = keccak256(
        "Claim(bytes32 burnTxHash,uint256 logIndex,address token,uint256 amount,uint256 toChainId,address recipient,bool vault,uint256 nonce,uint256 deadline)"
    );

    // ============ Constants ============
    uint256 public constant MAX_FEE_RATE = 1e17; // 10% max fee
    uint256 public constant FEE_DENOMINATOR = 1e18;

    // ============ State ============
    uint256 public feeRate;
    address public feeRecipient;
    uint256 public burnNonce;

    // Replay protection: claimId => used
    mapping(bytes32 => bool) public usedClaims;

    // Token whitelist: token => allowed
    mapping(address => bool) public allowedTokens;

    // Oracle active status
    mapping(address => bool) public oracleActive;

    // ============ Structs ============
    struct BurnData {
        address token;
        address sender;
        uint256 amount;
        uint256 toChainId;
        address recipient;
        bool vault;
        uint256 nonce;
    }

    struct ClaimData {
        bytes32 burnTxHash;
        uint256 logIndex;
        address token;
        uint256 amount;
        uint256 toChainId;
        address recipient;
        bool vault;
        uint256 nonce;
        uint256 deadline;
    }

    // ============ Events ============
    event BridgeBurned(
        bytes32 indexed burnId,
        address indexed token,
        address indexed sender,
        uint256 amount,
        uint256 toChainId,
        address recipient,
        bool vault,
        uint256 nonce
    );

    event BridgeMinted(
        bytes32 indexed claimId,
        address indexed token,
        address indexed recipient,
        uint256 amount,
        uint256 fee
    );

    event TokenAllowlistUpdated(address indexed token, bool allowed);
    event OracleUpdated(address indexed oracle, bool active);
    event FeeConfigUpdated(address indexed recipient, uint256 rate);
    event EmergencyWithdraw(address indexed token, address indexed to, uint256 amount);

    // ============ Errors ============
    error TokenNotAllowed(address token);
    error InvalidAmount();
    error InvalidRecipient();
    error InvalidChainId();
    error InvalidSignature();
    error InvalidOracle();
    error ClaimAlreadyUsed(bytes32 claimId);
    error ClaimExpired();
    error InvalidFeeRate();
    error InvalidFeeRecipient();
    error InsufficientBalance();
    error TransferFailed();

    // ============ Constructor ============
    constructor(
        string memory name,
        string memory version,
        address admin,
        address _feeRecipient,
        uint256 _feeRate
    ) EIP712(name, version) {
        if (admin == address(0)) revert InvalidRecipient();
        if (_feeRecipient == address(0)) revert InvalidFeeRecipient();
        if (_feeRate > MAX_FEE_RATE) revert InvalidFeeRate();

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(ADMIN_ROLE, admin);
        _grantRole(PAUSER_ROLE, admin);

        feeRecipient = _feeRecipient;
        feeRate = _feeRate;

        emit FeeConfigUpdated(_feeRecipient, _feeRate);
    }

    // ============ External Functions ============

    /**
     * @notice Burns tokens for cross-chain transfer with committed destination
     * @param token Token address to burn
     * @param amount Amount to burn
     * @param toChainId Destination chain ID
     * @param recipient Recipient address on destination chain
     * @param vault Whether to vault (lock) or burn tokens
     */
    function bridgeBurn(
        address token,
        uint256 amount,
        uint256 toChainId,
        address recipient,
        bool vault
    ) external nonReentrant whenNotPaused returns (bytes32 burnId) {
        if (!allowedTokens[token]) revert TokenNotAllowed(token);
        if (amount == 0) revert InvalidAmount();
        if (recipient == address(0)) revert InvalidRecipient();
        if (toChainId == 0 || toChainId == block.chainid) revert InvalidChainId();

        // Increment nonce
        uint256 currentNonce = burnNonce++;

        // Calculate burnId for canonical reference
        burnId = keccak256(abi.encode(
            block.chainid,
            address(this),
            token,
            msg.sender,
            amount,
            toChainId,
            recipient,
            vault,
            currentNonce
        ));

        // Burn or transfer tokens
        IBridgeToken bridgeToken = IBridgeToken(token);
        if (vault) {
            // Transfer to this contract for vaulting
            IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
        } else {
            // Burn tokens
            bridgeToken.bridgeBurn(msg.sender, amount);
        }

        emit BridgeBurned(
            burnId,
            token,
            msg.sender,
            amount,
            toChainId,
            recipient,
            vault,
            currentNonce
        );
    }

    /**
     * @notice Mints tokens based on verified burn on source chain
     * @param claim Claim data from source chain burn
     * @param signature MPC oracle signature
     */
    function bridgeMint(
        ClaimData calldata claim,
        bytes calldata signature
    ) external nonReentrant whenNotPaused returns (bytes32 claimId) {
        // Validate deadline
        if (block.timestamp > claim.deadline) revert ClaimExpired();

        // Validate token
        if (!allowedTokens[claim.token]) revert TokenNotAllowed(claim.token);

        // Validate amounts
        if (claim.amount == 0) revert InvalidAmount();
        if (claim.recipient == address(0)) revert InvalidRecipient();

        // Calculate claimId for replay protection
        claimId = keccak256(abi.encode(
            claim.burnTxHash,
            claim.logIndex,
            claim.token,
            claim.amount,
            claim.toChainId,
            claim.recipient,
            claim.vault,
            claim.nonce,
            claim.deadline
        ));

        // Check replay protection
        if (usedClaims[claimId]) revert ClaimAlreadyUsed(claimId);

        // Verify EIP-712 signature
        bytes32 structHash = keccak256(abi.encode(
            CLAIM_TYPEHASH,
            claim.burnTxHash,
            claim.logIndex,
            claim.token,
            claim.amount,
            claim.toChainId,
            claim.recipient,
            claim.vault,
            claim.nonce,
            claim.deadline
        ));

        bytes32 digest = _hashTypedDataV4(structHash);
        address signer = ECDSA.recover(digest, signature);

        // Verify signer is active oracle
        if (!oracleActive[signer]) revert InvalidOracle();

        // Mark claim as used
        usedClaims[claimId] = true;

        // Calculate fee
        uint256 fee = (claim.amount * feeRate) / FEE_DENOMINATOR;
        uint256 amountAfterFee = claim.amount - fee;

        // Mint or release tokens
        IBridgeToken bridgeToken = IBridgeToken(claim.token);
        if (claim.vault) {
            // Release from vault
            if (fee > 0) {
                IERC20(claim.token).safeTransfer(feeRecipient, fee);
            }
            IERC20(claim.token).safeTransfer(claim.recipient, amountAfterFee);
        } else {
            // Mint tokens
            if (fee > 0) {
                bridgeToken.bridgeMint(feeRecipient, fee);
            }
            bridgeToken.bridgeMint(claim.recipient, amountAfterFee);
        }

        emit BridgeMinted(claimId, claim.token, claim.recipient, amountAfterFee, fee);
    }

    // ============ View Functions ============

    /**
     * @notice Get the EIP-712 domain separator
     */
    function domainSeparator() external view returns (bytes32) {
        return _domainSeparatorV4();
    }

    /**
     * @notice Calculate claimId for a given claim
     */
    function calculateClaimId(ClaimData calldata claim) external pure returns (bytes32) {
        return keccak256(abi.encode(
            claim.burnTxHash,
            claim.logIndex,
            claim.token,
            claim.amount,
            claim.toChainId,
            claim.recipient,
            claim.vault,
            claim.nonce,
            claim.deadline
        ));
    }

    /**
     * @notice Get the digest to sign for a claim
     */
    function getClaimDigest(ClaimData calldata claim) external view returns (bytes32) {
        bytes32 structHash = keccak256(abi.encode(
            CLAIM_TYPEHASH,
            claim.burnTxHash,
            claim.logIndex,
            claim.token,
            claim.amount,
            claim.toChainId,
            claim.recipient,
            claim.vault,
            claim.nonce,
            claim.deadline
        ));
        return _hashTypedDataV4(structHash);
    }

    // ============ Admin Functions ============

    /**
     * @notice Update token allowlist
     */
    function setTokenAllowed(address token, bool allowed) external onlyRole(ADMIN_ROLE) {
        allowedTokens[token] = allowed;
        emit TokenAllowlistUpdated(token, allowed);
    }

    /**
     * @notice Add or update oracle
     */
    function setOracle(address oracle, bool active) external onlyRole(ADMIN_ROLE) {
        if (oracle == address(0)) revert InvalidOracle();
        
        if (active) {
            _grantRole(ORACLE_ROLE, oracle);
        } else {
            _revokeRole(ORACLE_ROLE, oracle);
        }
        
        oracleActive[oracle] = active;
        emit OracleUpdated(oracle, active);
    }

    /**
     * @notice Update fee configuration
     */
    function setFeeConfig(address _feeRecipient, uint256 _feeRate) external onlyRole(ADMIN_ROLE) {
        if (_feeRecipient == address(0)) revert InvalidFeeRecipient();
        if (_feeRate > MAX_FEE_RATE) revert InvalidFeeRate();

        feeRecipient = _feeRecipient;
        feeRate = _feeRate;

        emit FeeConfigUpdated(_feeRecipient, _feeRate);
    }

    /**
     * @notice Pause the bridge
     */
    function pause() external onlyRole(PAUSER_ROLE) {
        _pause();
    }

    /**
     * @notice Unpause the bridge
     */
    function unpause() external onlyRole(PAUSER_ROLE) {
        _unpause();
    }

    /**
     * @notice Emergency withdraw stuck tokens (admin only)
     */
    function emergencyWithdraw(
        address token,
        address to,
        uint256 amount
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (to == address(0)) revert InvalidRecipient();
        IERC20(token).safeTransfer(to, amount);
        emit EmergencyWithdraw(token, to, amount);
    }
}
