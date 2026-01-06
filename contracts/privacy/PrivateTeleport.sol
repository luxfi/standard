// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./ZNote.sol";
import "./PrivateBridge.sol";
import "../interfaces/IZChainAMM.sol";
import "../interfaces/IShieldedPool.sol";

/**
 * @title PrivateTeleport
 * @notice Cross-chain private teleportation using Warp + Z-Chain privacy layer
 * @dev Enables: XVM UTXO → (Warp) → ZNote (shielded) → Z-Chain AMM (private swap) → C-Chain/XVM
 * 
 * Flow:
 * 1. User initiates atomic swap on XVM (UTXO locked)
 * 2. Warp message sent to Z-Chain with FHE-encrypted amount
 * 3. ZNote created with Pedersen commitment (amount hidden)
 * 4. Optional: Private swap via ZChainAMM (fully homomorphic)
 * 5. Export to destination chain with Bulletproof range proof
 */
contract PrivateTeleport {
    // ═══════════════════════════════════════════════════════════════════════════
    // CONSTANTS
    // ═══════════════════════════════════════════════════════════════════════════
    
    /// @notice Warp precompile address for cross-chain messaging
    address public constant WARP_PRECOMPILE = 0x0200000000000000000000000000000000000005;
    
    /// @notice Atomic bridge precompile on C-Chain
    address public constant ATOMIC_BRIDGE = 0x0000000000000000000000000000000000000410;
    
    /// @notice Minimum blocks before withdrawal (MEV protection)
    uint256 public constant MIN_SHIELD_BLOCKS = 5;
    
    /// @notice Maximum teleport deadline (1 hour)
    uint256 public constant MAX_DEADLINE = 3600;
    
    // ═══════════════════════════════════════════════════════════════════════════
    // STATE
    // ═══════════════════════════════════════════════════════════════════════════
    
    /// @notice ZNote contract for shielded UTXO notes
    ZNote public immutable zNote;
    
    /// @notice Private bridge for cross-chain shielded transfers
    PrivateBridge public immutable privateBridge;
    
    /// @notice Z-Chain AMM for private swaps
    IZChainAMM public immutable zChainAMM;
    
    /// @notice Chain ID for X-Chain (XVM)
    bytes32 public xChainId;
    
    /// @notice Chain ID for C-Chain (EVM)
    bytes32 public cChainId;
    
    /// @notice Chain ID for Z-Chain (privacy)
    bytes32 public zChainId;
    
    /// @notice Teleport state tracking
    enum TeleportState {
        Pending,
        Shielded,
        Swapped,
        Exporting,
        Complete,
        Cancelled,
        Expired
    }
    
    /// @notice Teleport record with privacy metadata
    struct TeleportRecord {
        bytes32 teleportId;
        TeleportState state;
        bytes32 sourceChain;
        bytes32 destChain;
        bytes32 sourceAsset;
        bytes32 destAsset;
        bytes32 noteCommitment;      // Pedersen commitment to amount
        bytes32 encryptedAmount;     // FHE-encrypted amount
        bytes32 nullifierHash;       // For spending the note
        address sender;
        address recipient;
        uint256 deadline;
        uint256 createdBlock;
        bool privateSwap;            // Whether to use ZChainAMM
    }
    
    /// @notice Mapping from teleport ID to record
    mapping(bytes32 => TeleportRecord) public teleports;
    
    /// @notice Mapping from nullifier to spent status
    mapping(bytes32 => bool) public nullifierSpent;
    
    /// @notice Teleport nonce for unique IDs
    uint256 private _teleportNonce;
    
    // ═══════════════════════════════════════════════════════════════════════════
    // EVENTS
    // ═══════════════════════════════════════════════════════════════════════════
    
    event TeleportInitiated(
        bytes32 indexed teleportId,
        bytes32 indexed sourceChain,
        bytes32 indexed destChain,
        bytes32 noteCommitment,
        address sender,
        uint256 deadline
    );
    
    event TeleportShielded(
        bytes32 indexed teleportId,
        bytes32 noteCommitment,
        bytes32 encryptedAmount
    );
    
    event TeleportSwapped(
        bytes32 indexed teleportId,
        bytes32 sourceAsset,
        bytes32 destAsset
    );
    
    event TeleportExporting(
        bytes32 indexed teleportId,
        bytes32 destChain,
        address recipient
    );
    
    event TeleportComplete(
        bytes32 indexed teleportId,
        bytes32 nullifierHash
    );
    
    event TeleportCancelled(
        bytes32 indexed teleportId,
        string reason
    );
    
    // ═══════════════════════════════════════════════════════════════════════════
    // ERRORS
    // ═══════════════════════════════════════════════════════════════════════════
    
    error InvalidTeleport();
    error TeleportExpired();
    error TeleportNotFound();
    error InvalidState(TeleportState current, TeleportState expected);
    error InvalidProof();
    error NullifierAlreadySpent();
    error InsufficientShieldBlocks();
    error InvalidWarpMessage();
    error UnauthorizedCaller();
    
    // ═══════════════════════════════════════════════════════════════════════════
    // CONSTRUCTOR
    // ═══════════════════════════════════════════════════════════════════════════
    
    constructor(
        address _zNote,
        address _privateBridge,
        address _zChainAMM,
        bytes32 _xChainId,
        bytes32 _cChainId,
        bytes32 _zChainId
    ) {
        zNote = ZNote(_zNote);
        privateBridge = PrivateBridge(_privateBridge);
        zChainAMM = IZChainAMM(_zChainAMM);
        xChainId = _xChainId;
        cChainId = _cChainId;
        zChainId = _zChainId;
    }
    
    // ═══════════════════════════════════════════════════════════════════════════
    // EXTERNAL FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════
    
    /**
     * @notice Initiate private teleport from X-Chain UTXO
     * @dev Called by Warp relay when UTXO is locked on X-Chain
     * @param warpMessage Signed Warp message from X-Chain
     * @param commitment Pedersen commitment to the amount
     * @param encryptedAmount FHE-encrypted amount
     * @param recipient Destination address
     * @param destChain Destination chain ID
     * @param destAsset Destination asset (for swap)
     * @param privateSwap Whether to swap via ZChainAMM
     */
    function initiateTeleport(
        bytes calldata warpMessage,
        bytes32 commitment,
        bytes32 encryptedAmount,
        address recipient,
        bytes32 destChain,
        bytes32 destAsset,
        bool privateSwap
    ) external returns (bytes32 teleportId) {
        // Verify Warp message from X-Chain
        (bytes32 sourceChain, bytes32 sourceAsset, address sender, uint256 deadline) = 
            _verifyWarpMessage(warpMessage);
        
        if (sourceChain != xChainId) revert InvalidWarpMessage();
        if (block.timestamp > deadline) revert TeleportExpired();
        
        // Generate unique teleport ID
        teleportId = _generateTeleportId(sender, recipient, commitment);
        
        // Create teleport record
        teleports[teleportId] = TeleportRecord({
            teleportId: teleportId,
            state: TeleportState.Pending,
            sourceChain: sourceChain,
            destChain: destChain,
            sourceAsset: sourceAsset,
            destAsset: destAsset,
            noteCommitment: commitment,
            encryptedAmount: encryptedAmount,
            nullifierHash: bytes32(0), // Set when spent
            sender: sender,
            recipient: recipient,
            deadline: deadline,
            createdBlock: block.number,
            privateSwap: privateSwap
        });
        
        emit TeleportInitiated(
            teleportId,
            sourceChain,
            destChain,
            commitment,
            sender,
            deadline
        );
        
        // Create shielded ZNote
        _createShieldedNote(teleportId, commitment, encryptedAmount, sourceAsset);
    }
    
    /**
     * @notice Execute private swap on Z-Chain AMM
     * @dev Uses FHE for fully homomorphic swap computation
     * @param teleportId The teleport ID
     * @param poolId Z-Chain AMM pool ID
     * @param minOutput Minimum output (encrypted)
     * @param proof ZK proof of valid swap request
     */
    function executePrivateSwap(
        bytes32 teleportId,
        bytes32 poolId,
        bytes32 minOutput,
        bytes calldata proof
    ) external {
        TeleportRecord storage record = teleports[teleportId];
        if (record.teleportId == bytes32(0)) revert TeleportNotFound();
        if (record.state != TeleportState.Shielded) {
            revert InvalidState(record.state, TeleportState.Shielded);
        }
        if (!record.privateSwap) revert InvalidTeleport();
        
        // Verify ZK proof of swap validity
        if (!_verifySwapProof(proof, record.noteCommitment, poolId)) {
            revert InvalidProof();
        }
        
        // Execute homomorphic swap on ZChainAMM
        bytes32 outputCommitment = zChainAMM.swapEncrypted(
            poolId,
            record.encryptedAmount,
            minOutput,
            record.recipient
        );
        
        // Update record with new commitment
        record.noteCommitment = outputCommitment;
        record.sourceAsset = record.destAsset;
        record.state = TeleportState.Swapped;
        
        emit TeleportSwapped(teleportId, record.sourceAsset, record.destAsset);
    }
    
    /**
     * @notice Export from Z-Chain to destination chain
     * @dev Generates Bulletproof range proof for withdrawal
     * @param teleportId The teleport ID
     * @param rangeProof Bulletproof range proof
     * @param nullifier Nullifier to spend the note
     * @param merkleProof Merkle proof of note in tree
     */
    function exportToDestination(
        bytes32 teleportId,
        bytes calldata rangeProof,
        bytes32 nullifier,
        bytes32[] calldata merkleProof
    ) external {
        TeleportRecord storage record = teleports[teleportId];
        if (record.teleportId == bytes32(0)) revert TeleportNotFound();
        
        // Must be shielded or swapped
        if (record.state != TeleportState.Shielded && record.state != TeleportState.Swapped) {
            revert InvalidState(record.state, TeleportState.Shielded);
        }
        
        // MEV protection: require minimum blocks
        if (block.number < record.createdBlock + MIN_SHIELD_BLOCKS) {
            revert InsufficientShieldBlocks();
        }
        
        // Check nullifier not spent
        bytes32 nullifierHash = keccak256(abi.encodePacked(nullifier, record.noteCommitment));
        if (nullifierSpent[nullifierHash]) revert NullifierAlreadySpent();
        
        // Verify Bulletproof range proof
        if (!_verifyRangeProof(rangeProof, record.noteCommitment)) {
            revert InvalidProof();
        }
        
        // Verify Merkle proof
        if (!_verifyMerkleProof(merkleProof, record.noteCommitment)) {
            revert InvalidProof();
        }
        
        // Mark nullifier as spent
        nullifierSpent[nullifierHash] = true;
        record.nullifierHash = nullifierHash;
        record.state = TeleportState.Exporting;
        
        emit TeleportExporting(teleportId, record.destChain, record.recipient);
        
        // Send Warp message to destination chain
        _sendWarpExport(record);
    }
    
    /**
     * @notice Complete teleport after destination chain confirms
     * @param teleportId The teleport ID
     * @param warpConfirmation Warp message confirming receipt on dest chain
     */
    function completeTeleport(
        bytes32 teleportId,
        bytes calldata warpConfirmation
    ) external {
        TeleportRecord storage record = teleports[teleportId];
        if (record.teleportId == bytes32(0)) revert TeleportNotFound();
        if (record.state != TeleportState.Exporting) {
            revert InvalidState(record.state, TeleportState.Exporting);
        }
        
        // Verify confirmation from destination chain
        (bytes32 confirmedTeleport, bool success) = _verifyWarpConfirmation(warpConfirmation);
        if (confirmedTeleport != teleportId || !success) revert InvalidWarpMessage();
        
        record.state = TeleportState.Complete;
        
        emit TeleportComplete(teleportId, record.nullifierHash);
    }
    
    // ═══════════════════════════════════════════════════════════════════════════
    // BIDIRECTIONAL: UNSHIELD TO X-CHAIN
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Unshield ZNote back to X-Chain UTXO
     * @dev Amount becomes public on X-Chain (UTXO model)
     * @param teleportId The teleport ID
     * @param destinationAddress X-Chain address (bech32 format)
     * @param amount Decrypted amount for X-Chain UTXO
     * @param nullifier Nullifier to spend the note
     * @param merkleProof Merkle proof of note in tree
     * @param rangeProof Range proof proving amount matches commitment
     */
    function unshieldToXChain(
        bytes32 teleportId,
        bytes calldata destinationAddress,
        uint64 amount,
        bytes32 nullifier,
        bytes32[] calldata merkleProof,
        bytes calldata rangeProof
    ) external returns (bytes32 exportTxId) {
        TeleportRecord storage record = teleports[teleportId];
        if (record.teleportId == bytes32(0)) revert TeleportNotFound();
        
        // Must be shielded or swapped
        if (record.state != TeleportState.Shielded && record.state != TeleportState.Swapped) {
            revert InvalidState(record.state, TeleportState.Shielded);
        }
        
        // MEV protection
        if (block.number < record.createdBlock + MIN_SHIELD_BLOCKS) {
            revert InsufficientShieldBlocks();
        }
        
        // Check nullifier not spent
        bytes32 nullifierHash = keccak256(abi.encodePacked(nullifier, record.noteCommitment));
        if (nullifierSpent[nullifierHash]) revert NullifierAlreadySpent();
        
        // Verify proofs
        if (!_verifyRangeProof(rangeProof, record.noteCommitment)) {
            revert InvalidProof();
        }
        if (!_verifyMerkleProof(merkleProof, record.noteCommitment)) {
            revert InvalidProof();
        }
        
        // Mark nullifier as spent
        nullifierSpent[nullifierHash] = true;
        record.nullifierHash = nullifierHash;
        
        // Export to X-Chain via ZNote
        exportTxId = zNote.exportToXChain(
            ZNote.SpendProof({
                nullifier: nullifier,
                merkleRoot: zNote.getNoteRoot(),
                merkleProof: merkleProof,
                zkProof: rangeProof
            }),
            destinationAddress,
            amount,
            record.sourceAsset
        );
        
        record.state = TeleportState.Complete;
        
        emit TeleportComplete(teleportId, nullifierHash);
        
        return exportTxId;
    }

    /**
     * @notice Private transfer to another recipient (stays shielded)
     * @dev Creates a new note for recipient, spends sender's note
     * @param teleportId The teleport ID
     * @param recipientCommitment New note commitment for recipient
     * @param encryptedNote Note encrypted to recipient's viewing key
     * @param nullifier Nullifier to spend sender's note
     * @param merkleProof Merkle proof of sender's note
     * @param transferProof ZK proof of valid transfer (amount conservation)
     */
    function privateTransferToRecipient(
        bytes32 teleportId,
        bytes32 recipientCommitment,
        bytes calldata encryptedNote,
        bytes32 nullifier,
        bytes32[] calldata merkleProof,
        bytes calldata transferProof
    ) external returns (uint256 newNoteIndex) {
        TeleportRecord storage record = teleports[teleportId];
        if (record.teleportId == bytes32(0)) revert TeleportNotFound();
        
        if (record.state != TeleportState.Shielded && record.state != TeleportState.Swapped) {
            revert InvalidState(record.state, TeleportState.Shielded);
        }
        
        // MEV protection
        if (block.number < record.createdBlock + MIN_SHIELD_BLOCKS) {
            revert InsufficientShieldBlocks();
        }
        
        // Check nullifier not spent
        bytes32 nullifierHash = keccak256(abi.encodePacked(nullifier, record.noteCommitment));
        if (nullifierSpent[nullifierHash]) revert NullifierAlreadySpent();
        
        // Verify transfer proof (proves amount conservation without revealing amount)
        if (transferProof.length < 64) revert InvalidProof();
        if (!_verifyMerkleProof(merkleProof, record.noteCommitment)) {
            revert InvalidProof();
        }
        
        // Mark nullifier as spent
        nullifierSpent[nullifierHash] = true;
        
        // Create new note for recipient via ZNote
        newNoteIndex = zNote.privateTransfer(
            ZNote.SpendProof({
                nullifier: nullifier,
                merkleRoot: zNote.getNoteRoot(),
                merkleProof: merkleProof,
                zkProof: transferProof
            }),
            ZNote.OutputNote({
                commitment: recipientCommitment,
                encryptedNote: encryptedNote,
                encryptedMemo: ""
            })
        );
        
        // Original teleport is now spent, recipient has a new note
        record.state = TeleportState.Complete;
        record.nullifierHash = nullifierHash;
        
        emit TeleportComplete(teleportId, nullifierHash);
        
        return newNoteIndex;
    }

    /**
     * @notice Split note into multiple outputs (e.g., payment + change)
     * @param teleportId The teleport ID
     * @param outputs Array of output notes (recipient + change)
     * @param nullifier Nullifier to spend sender's note
     * @param merkleProof Merkle proof of sender's note
     * @param splitProof ZK proof of valid split (sum of outputs = input)
     */
    function splitAndTransfer(
        bytes32 teleportId,
        ZNote.OutputNote[] calldata outputs,
        bytes32 nullifier,
        bytes32[] calldata merkleProof,
        bytes calldata splitProof
    ) external returns (uint256[] memory noteIndices) {
        TeleportRecord storage record = teleports[teleportId];
        if (record.teleportId == bytes32(0)) revert TeleportNotFound();
        
        if (record.state != TeleportState.Shielded && record.state != TeleportState.Swapped) {
            revert InvalidState(record.state, TeleportState.Shielded);
        }
        
        if (outputs.length == 0 || outputs.length > 16) revert InvalidTeleport();
        
        // MEV protection
        if (block.number < record.createdBlock + MIN_SHIELD_BLOCKS) {
            revert InsufficientShieldBlocks();
        }
        
        // Check nullifier not spent
        bytes32 nullifierHash = keccak256(abi.encodePacked(nullifier, record.noteCommitment));
        if (nullifierSpent[nullifierHash]) revert NullifierAlreadySpent();
        
        // Verify split proof
        if (splitProof.length < 64) revert InvalidProof();
        if (!_verifyMerkleProof(merkleProof, record.noteCommitment)) {
            revert InvalidProof();
        }
        
        // Mark nullifier as spent
        nullifierSpent[nullifierHash] = true;
        
        // Create multiple output notes
        noteIndices = zNote.splitNote(
            ZNote.SpendProof({
                nullifier: nullifier,
                merkleRoot: zNote.getNoteRoot(),
                merkleProof: merkleProof,
                zkProof: splitProof
            }),
            outputs
        );
        
        record.state = TeleportState.Complete;
        record.nullifierHash = nullifierHash;
        
        emit TeleportComplete(teleportId, nullifierHash);
        
        return noteIndices;
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // CANCELLATION
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Cancel expired teleport and refund
     * @param teleportId The teleport ID
     */
    function cancelTeleport(bytes32 teleportId) external {
        TeleportRecord storage record = teleports[teleportId];
        if (record.teleportId == bytes32(0)) revert TeleportNotFound();
        if (record.state == TeleportState.Complete || record.state == TeleportState.Cancelled) {
            revert InvalidState(record.state, TeleportState.Pending);
        }
        
        // Only sender or after deadline
        if (msg.sender != record.sender && block.timestamp <= record.deadline) {
            revert UnauthorizedCaller();
        }
        
        record.state = TeleportState.Cancelled;
        
        // Send Warp message to unlock on source chain
        _sendWarpCancel(record);
        
        emit TeleportCancelled(teleportId, "User cancelled or deadline expired");
    }
    
    // ═══════════════════════════════════════════════════════════════════════════
    // VIEW FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════
    
    /**
     * @notice Get teleport record
     */
    function getTeleport(bytes32 teleportId) external view returns (TeleportRecord memory) {
        return teleports[teleportId];
    }
    
    /**
     * @notice Check if teleport is complete
     */
    function isComplete(bytes32 teleportId) external view returns (bool) {
        return teleports[teleportId].state == TeleportState.Complete;
    }
    
    /**
     * @notice Check if teleport is expired
     */
    function isExpired(bytes32 teleportId) external view returns (bool) {
        TeleportRecord storage record = teleports[teleportId];
        return block.timestamp > record.deadline && 
               record.state != TeleportState.Complete &&
               record.state != TeleportState.Cancelled;
    }
    
    // ═══════════════════════════════════════════════════════════════════════════
    // INTERNAL FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════
    
    /**
     * @dev Create shielded ZNote from teleport
     */
    function _createShieldedNote(
        bytes32 teleportId,
        bytes32 commitment,
        bytes32 encryptedAmount,
        bytes32 asset
    ) internal {
        TeleportRecord storage record = teleports[teleportId];
        
        // Import from X-Chain creates a ZNote
        zNote.importFromXChain(
            commitment,
            encryptedAmount,
            asset,
            record.recipient
        );
        
        record.state = TeleportState.Shielded;
        
        emit TeleportShielded(teleportId, commitment, encryptedAmount);
    }
    
    /**
     * @dev Generate unique teleport ID
     */
    function _generateTeleportId(
        address sender,
        address recipient,
        bytes32 commitment
    ) internal returns (bytes32) {
        return keccak256(abi.encodePacked(
            sender,
            recipient,
            commitment,
            block.timestamp,
            _teleportNonce++
        ));
    }
    
    /**
     * @dev Verify Warp message from X-Chain
     */
    function _verifyWarpMessage(bytes calldata warpMessage) internal view returns (
        bytes32 sourceChain,
        bytes32 sourceAsset,
        address sender,
        uint256 deadline
    ) {
        // Call Warp precompile to verify message
        (bool success, bytes memory result) = WARP_PRECOMPILE.staticcall(
            abi.encodeWithSignature("getVerifiedWarpMessage(uint32)", 0)
        );
        require(success, "Warp verification failed");
        
        // Decode message payload
        // Format: [sourceChain (32)] [sourceAsset (32)] [sender (20)] [deadline (32)] [data...]
        assembly {
            sourceChain := mload(add(result, 32))
            sourceAsset := mload(add(result, 64))
            sender := mload(add(result, 96))
            deadline := mload(add(result, 128))
        }
    }
    
    /**
     * @dev Verify ZK proof for swap request
     */
    function _verifySwapProof(
        bytes calldata proof,
        bytes32 commitment,
        bytes32 poolId
    ) internal view returns (bool) {
        // Delegate to ZChainAMM proof verification
        return zChainAMM.verifySwapProof(proof, commitment, poolId);
    }
    
    /**
     * @dev Verify Bulletproof range proof
     */
    function _verifyRangeProof(
        bytes calldata proof,
        bytes32 commitment
    ) internal view returns (bool) {
        return privateBridge.verifyRangeProof(proof, commitment);
    }
    
    /**
     * @dev Verify Merkle proof of note in tree
     */
    function _verifyMerkleProof(
        bytes32[] calldata proof,
        bytes32 commitment
    ) internal view returns (bool) {
        return zNote.verifyMerkleProof(proof, commitment);
    }
    
    /**
     * @dev Send Warp message to export to destination chain
     */
    function _sendWarpExport(TeleportRecord storage record) internal {
        bytes memory payload = abi.encode(
            record.teleportId,
            record.destAsset,
            record.recipient,
            record.noteCommitment, // Still hidden until decrypted
            uint8(1) // Export action
        );
        
        // Call Warp precompile to send message
        (bool success,) = WARP_PRECOMPILE.call(
            abi.encodeWithSignature(
                "sendWarpMessage(bytes)",
                payload
            )
        );
        require(success, "Warp send failed");
    }
    
    /**
     * @dev Send Warp message to cancel on source chain
     */
    function _sendWarpCancel(TeleportRecord storage record) internal {
        bytes memory payload = abi.encode(
            record.teleportId,
            record.sourceAsset,
            record.sender,
            record.noteCommitment,
            uint8(0) // Cancel action
        );
        
        (bool success,) = WARP_PRECOMPILE.call(
            abi.encodeWithSignature(
                "sendWarpMessage(bytes)",
                payload
            )
        );
        require(success, "Warp cancel failed");
    }
    
    /**
     * @dev Verify Warp confirmation from destination chain
     */
    function _verifyWarpConfirmation(bytes calldata warpConfirmation) internal view returns (
        bytes32 teleportId,
        bool success
    ) {
        // Call Warp precompile to verify confirmation
        (bool callSuccess, bytes memory result) = WARP_PRECOMPILE.staticcall(
            abi.encodeWithSignature("getVerifiedWarpMessage(uint32)", 0)
        );
        require(callSuccess, "Warp verification failed");
        
        // Decode confirmation
        (teleportId, success) = abi.decode(result, (bytes32, bool));
    }
}
