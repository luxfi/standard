// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title Lux Bridge — TRON TVM native bridge
 * @notice TRON's TVM is EVM-compatible with minor differences:
 *   - Energy/bandwidth instead of gas
 *   - Base58 addresses (T...) but same 20-byte format internally
 *   - TRC-20 = ERC-20 (same interface)
 *   - No EIP-1559 (fixed energy price)
 *   - `msg.sender` works identically
 *
 * This contract is a thin adapter around the standard Teleporter.sol
 * from ~/work/lux/standard/contracts/bridge/teleport/Teleporter.sol.
 *
 * Differences from EVM deployment:
 *   1. TRON_CHAIN_ID constant for bridge messages
 *   2. TRC-20 compatibility (same as ERC-20, no changes needed)
 *   3. Energy-optimized (avoid SLOAD where possible)
 *
 * Deploy with TronBox or TronIDE:
 *   tronbox migrate --network mainnet
 */

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract LuxBridge is ReentrancyGuard {
    using SafeERC20 for IERC20;
    using ECDSA for bytes32;

    // TRON mainnet chain ID in Lux namespace
    uint64 public constant CHAIN_ID = 728126;

    // Bridge state
    address public admin;
    address public mpcSigner; // ECDSA signer (TRON uses secp256k1 like Ethereum)
    uint16 public feeBps;     // 0-500 (0-5%)
    bool public paused;
    uint64 public outboundNonce;
    uint256 public totalLocked;
    uint256 public totalBurned;

    // Nonce tracking: source_chain -> nonce -> processed
    mapping(uint64 => mapping(uint64 => bool)) public processedNonces;

    // Per-token daily limits
    struct TokenConfig {
        uint256 dailyMintLimit;
        uint256 dailyMinted;
        uint256 periodStart;
        bool registered;
    }
    mapping(address => TokenConfig) public tokenConfigs;

    // Events for MPC watchers
    event Lock(
        uint64 indexed sourceChain,
        uint64 indexed destChain,
        uint64 nonce,
        address token,
        address sender,
        bytes32 recipient,
        uint256 amount,
        uint256 fee
    );

    event Mint(
        uint64 indexed sourceChain,
        uint64 nonce,
        address token,
        address recipient,
        uint256 amount
    );

    event Burn(
        uint64 indexed sourceChain,
        uint64 indexed destChain,
        uint64 nonce,
        address token,
        address sender,
        bytes32 recipient,
        uint256 amount
    );

    event Release(
        uint64 indexed sourceChain,
        uint64 nonce,
        address token,
        address recipient,
        uint256 amount
    );

    modifier onlyAdmin() {
        require(msg.sender == admin, "Not admin");
        _;
    }

    modifier whenNotPaused() {
        require(!paused, "Paused");
        _;
    }

    constructor(address _mpcSigner, uint16 _feeBps) {
        require(_feeBps <= 500, "Fee too high");
        admin = msg.sender;
        mpcSigner = _mpcSigner;
        feeBps = _feeBps;
    }

    /// @notice Lock TRC-20 tokens for bridging to another chain
    function lockAndBridge(
        address token,
        uint256 amount,
        uint64 destChainId,
        bytes32 recipient
    ) external whenNotPaused nonReentrant {
        require(amount > 0, "Zero amount");
        require(tokenConfigs[token].registered, "Token not registered");

        uint256 fee = (amount * feeBps) / 10_000;
        uint256 bridgeAmount = amount - fee;

        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);

        totalLocked += bridgeAmount;
        outboundNonce++;

        emit Lock(CHAIN_ID, destChainId, outboundNonce, token, msg.sender, recipient, bridgeAmount, fee);
    }

    /// @notice Mint wrapped tokens with MPC ECDSA signature
    function mintBridged(
        address token,
        uint64 sourceChainId,
        uint64 nonce,
        address recipient,
        uint256 amount,
        bytes calldata signature
    ) external whenNotPaused nonReentrant {
        require(amount > 0, "Zero amount");
        require(!processedNonces[sourceChainId][nonce], "Nonce processed");

        // Verify MPC signature
        bytes32 digest = keccak256(abi.encodePacked(
            "LUX_BRIDGE_MINT",
            sourceChainId,
            nonce,
            recipient,
            token,
            amount
        ));
        address recovered = digest.toEthSignedMessageHash().recover(signature);
        require(recovered == mpcSigner, "Invalid signature");

        // Check daily limit
        _checkDailyLimit(token, amount);

        // Mark nonce
        processedNonces[sourceChainId][nonce] = true;

        // Transfer from vault (locked tokens)
        IERC20(token).safeTransfer(recipient, amount);

        emit Mint(sourceChainId, nonce, token, recipient, amount);
    }

    /// @notice Burn wrapped tokens for withdrawal to another chain
    function burnBridged(
        address token,
        uint256 amount,
        uint64 destChainId,
        bytes32 recipient
    ) external whenNotPaused nonReentrant {
        require(amount > 0, "Zero amount");

        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
        // In production: actual burn via TRC-20 burn function

        totalBurned += amount;
        outboundNonce++;

        emit Burn(CHAIN_ID, destChainId, outboundNonce, token, msg.sender, recipient, amount);
    }

    /// @notice Release locked tokens with MPC signature
    function release(
        address token,
        uint64 sourceChainId,
        uint64 nonce,
        address recipient,
        uint256 amount,
        bytes calldata signature
    ) external whenNotPaused nonReentrant {
        require(!processedNonces[sourceChainId][nonce], "Nonce processed");

        bytes32 digest = keccak256(abi.encodePacked(
            "LUX_BRIDGE_RELEASE",
            sourceChainId,
            nonce,
            recipient,
            token,
            amount
        ));
        address recovered = digest.toEthSignedMessageHash().recover(signature);
        require(recovered == mpcSigner, "Invalid signature");

        processedNonces[sourceChainId][nonce] = true;

        IERC20(token).safeTransfer(recipient, amount);

        emit Release(sourceChainId, nonce, token, recipient, amount);
    }

    // Admin functions
    function registerToken(address token, uint256 dailyLimit) external onlyAdmin {
        tokenConfigs[token] = TokenConfig(dailyLimit, 0, block.timestamp, true);
    }

    function setMpcSigner(address _signer) external onlyAdmin { mpcSigner = _signer; }
    function setFee(uint16 _feeBps) external onlyAdmin { require(_feeBps <= 500); feeBps = _feeBps; }
    function pause() external onlyAdmin { paused = true; }
    function unpause() external onlyAdmin { paused = false; }

    function _checkDailyLimit(address token, uint256 amount) internal {
        TokenConfig storage cfg = tokenConfigs[token];
        if (cfg.dailyMintLimit == 0) return;
        if (block.timestamp >= cfg.periodStart + 1 days) {
            cfg.dailyMinted = 0;
            cfg.periodStart = block.timestamp;
        }
        cfg.dailyMinted += amount;
        require(cfg.dailyMinted <= cfg.dailyMintLimit, "Daily limit exceeded");
    }
}
