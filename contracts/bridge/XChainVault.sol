// SPDX-License-Identifier: BSD-3-Clause
// Copyright (c) 2025 Lux Industries Inc.
pragma solidity ^0.8.31;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import {IWarp} from "./interfaces/IWarpMessenger.sol";
import "./interfaces/IBridge.sol";

/**
 * @title XChainVault
 * @dev Manages token vaults for X-Chain bridging with support for ERC20, ERC721, and ERC1155
 */
contract XChainVault is Ownable {
    using SafeERC20 for IERC20;

    // Warp precompile address (official)
    address constant WARP_PRECOMPILE = 0x0200000000000000000000000000000000000005;
    
    // Token types
    enum TokenType {
        ERC20,
        ERC721,
        ERC1155
    }
    
    // Vault entry structure
    struct VaultEntry {
        address originalToken;
        uint32 originalChainId;
        TokenType tokenType;
        address depositor;
        uint256 amount; // For ERC20
        uint256 tokenId; // For ERC721
        uint256[] tokenIds; // For ERC1155
        uint256[] amounts; // For ERC1155
        bool isActive;
        uint256 mintedAmount; // Track minted wrapped tokens
    }
    
    // Events
    event TokenVaulted(
        bytes32 indexed vaultId,
        address indexed originalToken,
        uint32 originalChainId,
        TokenType tokenType,
        address indexed depositor,
        uint256 amount,
        uint256 tokenId
    );
    
    event TokenReleased(
        bytes32 indexed vaultId,
        address indexed recipient,
        uint256 amount,
        uint256 tokenId
    );
    
    event WrappedTokenMinted(
        bytes32 indexed vaultId,
        uint32 destinationChainId,
        address recipient,
        uint256 amount
    );

    event MpcOracleUpdated(address indexed oracle, bool authorized);
    event MpcThresholdUpdated(uint256 newThreshold);
    event BurnProofVerified(bytes32 indexed vaultId, uint256 amount, uint256 burnNonce);
    
    // State variables
    mapping(bytes32 => VaultEntry) public vaults;
    mapping(address => mapping(uint32 => address)) public wrappedTokens; // originalToken => chainId => wrappedToken
    mapping(address => bool) public supportedTokens;
    mapping(uint32 => bool) public supportedChains;
    mapping(bytes32 => bool) public trustedSourceChains; // sourceChainID => trusted

    /// @notice Authorized MPC signers for burn proof verification
    mapping(address => bool) public isMpcOracle;

    /// @notice Minimum number of MPC signatures required
    uint256 public mpcThreshold;

    /// @notice Nonce to prevent replay attacks on burn proofs
    mapping(bytes32 => bool) public usedBurnNonces;

    uint256 private nonce;
    address public bridge;
    
    modifier onlyBridge() {
        require(msg.sender == bridge, "Only bridge can call");
        _;
    }
    
    constructor(address _bridge) Ownable(msg.sender) {
        bridge = _bridge;
        mpcThreshold = 2; // Default: require at least 2 MPC signatures
    }
    
    /**
     * @dev Vault ERC20 tokens
     */
    function vaultERC20(
        address token,
        uint256 amount,
        uint32 destinationChainId,
        address recipient
    ) external returns (bytes32 vaultId) {
        require(supportedTokens[token], "Token not supported");
        require(supportedChains[destinationChainId], "Chain not supported");
        require(amount > 0, "Amount must be greater than 0");
        
        // Transfer tokens to vault (SafeERC20 handles non-standard return values)
        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
        
        // Generate vault ID
        vaultId = keccak256(abi.encodePacked(
            block.chainid,
            token,
            msg.sender,
            nonce++
        ));
        
        // Create vault entry
        vaults[vaultId] = VaultEntry({
            originalToken: token,
            originalChainId: uint32(block.chainid),
            tokenType: TokenType.ERC20,
            depositor: msg.sender,
            amount: amount,
            tokenId: 0,
            tokenIds: new uint256[](0),
            amounts: new uint256[](0),
            isActive: true,
            mintedAmount: 0
        });
        
        // Send Warp message to destination chain
        _sendVaultMessage(vaultId, destinationChainId, recipient);
        
        emit TokenVaulted(vaultId, token, uint32(block.chainid), TokenType.ERC20, msg.sender, amount, 0);
    }
    
    /**
     * @dev Vault ERC721 token
     */
    function vaultERC721(
        address token,
        uint256 tokenId,
        uint32 destinationChainId,
        address recipient
    ) external returns (bytes32 vaultId) {
        require(supportedTokens[token], "Token not supported");
        require(supportedChains[destinationChainId], "Chain not supported");
        
        // Transfer NFT to vault
        IERC721(token).transferFrom(msg.sender, address(this), tokenId);
        
        // Generate vault ID
        vaultId = keccak256(abi.encodePacked(
            block.chainid,
            token,
            tokenId,
            msg.sender,
            nonce++
        ));
        
        // Create vault entry
        vaults[vaultId] = VaultEntry({
            originalToken: token,
            originalChainId: uint32(block.chainid),
            tokenType: TokenType.ERC721,
            depositor: msg.sender,
            amount: 0,
            tokenId: tokenId,
            tokenIds: new uint256[](0),
            amounts: new uint256[](0),
            isActive: true,
            mintedAmount: 0
        });
        
        // Send Warp message to destination chain
        _sendVaultMessage(vaultId, destinationChainId, recipient);
        
        emit TokenVaulted(vaultId, token, uint32(block.chainid), TokenType.ERC721, msg.sender, 0, tokenId);
    }
    
    /**
     * @dev Vault ERC1155 tokens
     */
    function vaultERC1155(
        address token,
        uint256[] calldata tokenIds,
        uint256[] calldata amounts,
        uint32 destinationChainId,
        address recipient
    ) external returns (bytes32 vaultId) {
        require(supportedTokens[token], "Token not supported");
        require(supportedChains[destinationChainId], "Chain not supported");
        require(tokenIds.length == amounts.length, "Arrays length mismatch");
        require(tokenIds.length > 0, "Empty arrays");
        
        // Transfer tokens to vault
        IERC1155(token).safeBatchTransferFrom(
            msg.sender,
            address(this),
            tokenIds,
            amounts,
            ""
        );
        
        // Generate vault ID
        vaultId = keccak256(abi.encodePacked(
            block.chainid,
            token,
            keccak256(abi.encode(tokenIds, amounts)),
            msg.sender,
            nonce++
        ));
        
        // Create vault entry
        vaults[vaultId] = VaultEntry({
            originalToken: token,
            originalChainId: uint32(block.chainid),
            tokenType: TokenType.ERC1155,
            depositor: msg.sender,
            amount: 0,
            tokenId: 0,
            tokenIds: tokenIds,
            amounts: amounts,
            isActive: true,
            mintedAmount: 0
        });
        
        // Send Warp message to destination chain
        _sendVaultMessage(vaultId, destinationChainId, recipient);
        
        emit TokenVaulted(vaultId, token, uint32(block.chainid), TokenType.ERC1155, msg.sender, 0, 0);
    }
    
    /**
     * @dev Release tokens from vault (called by bridge after wrapped tokens are burned)
     */
    function releaseFromVault(
        bytes32 vaultId,
        address recipient,
        uint256 amount,
        bytes calldata warpProof
    ) external onlyBridge {
        VaultEntry storage vault = vaults[vaultId];
        require(vault.isActive, "Vault not active");
        
        // Verify Warp message proving burn on destination chain
        require(_verifyBurnProof(vaultId, amount, warpProof), "Invalid burn proof");
        
        if (vault.tokenType == TokenType.ERC20) {
            require(vault.amount >= amount, "Insufficient vault balance");
            vault.amount -= amount;
            IERC20(vault.originalToken).safeTransfer(recipient, amount);
        } else if (vault.tokenType == TokenType.ERC721) {
            require(amount == 1, "Invalid amount for NFT");
            vault.isActive = false;
            IERC721(vault.originalToken).transferFrom(address(this), recipient, vault.tokenId);
        } else if (vault.tokenType == TokenType.ERC1155) {
            // For ERC1155, amount represents the index in the arrays
            uint256 index = amount;
            require(index < vault.tokenIds.length, "Invalid token index");
            
            uint256[] memory tokenId = new uint256[](1);
            uint256[] memory tokenAmount = new uint256[](1);
            tokenId[0] = vault.tokenIds[index];
            tokenAmount[0] = vault.amounts[index];
            
            IERC1155(vault.originalToken).safeBatchTransferFrom(
                address(this),
                recipient,
                tokenId,
                tokenAmount,
                ""
            );
        }
        
        emit TokenReleased(vaultId, recipient, amount, vault.tokenId);
    }
    
    /**
     * @dev Send vault message via Warp
     */
    function _sendVaultMessage(
        bytes32 vaultId,
        uint32 destinationChainId,
        address recipient
    ) private {
        // Include destination chain in payload (Warp precompile takes only payload)
        bytes memory message = abi.encode(
            uint8(1), // Message type: VAULT_CREATED
            destinationChainId, // Destination chain encoded in payload
            vaultId,
            vaults[vaultId].originalToken,
            vaults[vaultId].originalChainId,
            vaults[vaultId].tokenType,
            recipient,
            vaults[vaultId].amount,
            vaults[vaultId].tokenId,
            vaults[vaultId].tokenIds,
            vaults[vaultId].amounts
        );
        
        // Destination chain ID is encoded in the payload
        // The Warp precompile takes only the payload bytes
        IWarp(WARP_PRECOMPILE).sendWarpMessage(message);
    }
    
    /**
     * @dev Verify burn proof using MPC threshold signatures
     * @param vaultId The vault identifier
     * @param amount The amount being released
     * @param proof Encoded MPC signatures: (uint256 burnNonce, uint32 sourceChainId, bytes[] signatures)
     * @return True if the proof has sufficient valid MPC signatures
     */
    function _verifyBurnProof(
        bytes32 vaultId,
        uint256 amount,
        bytes calldata proof
    ) private returns (bool) {
        if (proof.length == 0) return false;

        // Decode MPC proof: nonce, source chain, and array of signatures
        (uint256 burnNonce, uint32 sourceChainId, bytes[] memory signatures) = abi.decode(
            proof,
            (uint256, uint32, bytes[])
        );

        // Verify minimum threshold of signatures provided
        if (signatures.length < mpcThreshold) return false;

        // Create the burn message hash that MPC signers should have signed
        // Message format: BURN | sourceChainId | vaultId | amount | burnNonce
        bytes32 messageHash = keccak256(abi.encode(
            bytes4(0x4255524e), // "BURN" magic bytes
            sourceChainId,
            vaultId,
            amount,
            burnNonce
        ));

        // Convert to Ethereum signed message hash (EIP-191)
        bytes32 ethSignedHash = MessageHashUtils.toEthSignedMessageHash(messageHash);

        // Verify nonce hasn't been used (replay protection)
        bytes32 nonceKey = keccak256(abi.encode(vaultId, burnNonce));
        if (usedBurnNonces[nonceKey]) return false;

        // Count valid MPC signatures (track signers to prevent duplicate signatures)
        uint256 validSignatures = 0;
        address[] memory usedSigners = new address[](signatures.length);

        for (uint256 i = 0; i < signatures.length; i++) {
            // Recover signer from signature
            address signer = ECDSA.recover(ethSignedHash, signatures[i]);

            // Verify signer is authorized MPC oracle
            if (!isMpcOracle[signer]) continue;

            // Check signer hasn't been counted already (prevent signature reuse)
            bool isDuplicate = false;
            for (uint256 j = 0; j < validSignatures; j++) {
                if (usedSigners[j] == signer) {
                    isDuplicate = true;
                    break;
                }
            }
            if (isDuplicate) continue;

            usedSigners[validSignatures] = signer;
            validSignatures++;

            // Early exit if threshold reached
            if (validSignatures >= mpcThreshold) break;
        }

        // Verify threshold met
        if (validSignatures < mpcThreshold) return false;

        // Mark nonce as used
        usedBurnNonces[nonceKey] = true;

        return true;
    }
    
    /**
     * @dev Update supported tokens
     */
    function setSupportedToken(address token, bool supported) external onlyOwner {
        supportedTokens[token] = supported;
    }
    
    /**
     * @dev Update supported chains
     */
    function setSupportedChain(uint32 chainId, bool supported) external onlyOwner {
        supportedChains[chainId] = supported;
    }
    
    /**
     * @dev Update bridge address
     */
    function setBridge(address _bridge) external onlyOwner {
        bridge = _bridge;
    }

    /**
     * @dev Set trusted source chain for Warp message verification
     * @param chainId The source chain ID (bytes32 from Warp)
     * @param trusted Whether the chain is trusted
     */
    function setTrustedSourceChain(bytes32 chainId, bool trusted) external onlyOwner {
        trustedSourceChains[chainId] = trusted;
    }

    /**
     * @dev Add or remove an MPC oracle for burn proof verification
     * @param oracle The oracle address
     * @param authorized Whether to authorize or revoke
     */
    function setMpcOracle(address oracle, bool authorized) external onlyOwner {
        require(oracle != address(0), "Invalid oracle address");
        isMpcOracle[oracle] = authorized;
        emit MpcOracleUpdated(oracle, authorized);
    }

    /**
     * @dev Set the minimum number of MPC signatures required
     * @param threshold The new threshold (must be > 0)
     */
    function setMpcThreshold(uint256 threshold) external onlyOwner {
        require(threshold > 0, "Threshold must be > 0");
        mpcThreshold = threshold;
        emit MpcThresholdUpdated(threshold);
    }

    /**
     * @dev Batch add MPC oracles
     * @param oracles Array of oracle addresses to add
     */
    function addMpcOracles(address[] calldata oracles) external onlyOwner {
        for (uint256 i = 0; i < oracles.length; i++) {
            require(oracles[i] != address(0), "Invalid oracle address");
            isMpcOracle[oracles[i]] = true;
            emit MpcOracleUpdated(oracles[i], true);
        }
    }

    /**
     * @dev ERC1155 receiver
     */
    function onERC1155Received(
        address,
        address,
        uint256,
        uint256,
        bytes calldata
    ) external pure returns (bytes4) {
        return this.onERC1155Received.selector;
    }
    
    function onERC1155BatchReceived(
        address,
        address,
        uint256[] calldata,
        uint256[] calldata,
        bytes calldata
    ) external pure returns (bytes4) {
        return this.onERC1155BatchReceived.selector;
    }
}