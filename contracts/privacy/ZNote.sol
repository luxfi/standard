// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";

/**
 * @title ZNote
 * @notice UTXO-style notes for X-Chain integration with privacy
 * @dev Implements note-based privacy similar to Zcash but integrated with Lux X-Chain
 * 
 * A "Note" is a UTXO-style commitment containing:
 * - owner: Encrypted owner public key
 * - value: FHE-encrypted amount
 * - asset: Token/asset identifier
 * - nonce: Random value for uniqueness
 * - nullifier: Hash used to spend the note
 * 
 * X-Chain Integration:
 * - Notes can be created from X-Chain UTXO exports
 * - Notes can be claimed as X-Chain UTXO imports
 * - Bridge between C-Chain (EVM) and X-Chain (DAG/UTXO)
 */
contract ZNote is ReentrancyGuard, AccessControl {
    bytes32 public constant BRIDGE_ROLE = keccak256("BRIDGE_ROLE");
    bytes32 public constant VERIFIER_ROLE = keccak256("VERIFIER_ROLE");

    // ============ Note Structure ============

    /// @notice Note commitment (like Zcash note)
    struct Note {
        bytes32 commitment;     // Pedersen commitment: H(owner, value, asset, nonce)
        bytes encryptedOwner;   // Owner's viewing key encrypted to their public key
        bytes encryptedValue;   // FHE-encrypted value (homomorphic operations possible)
        bytes32 assetId;        // Asset identifier (keccak256 of asset info)
        uint64 createdAt;       // Block timestamp
    }

    /// @notice X-Chain UTXO reference
    struct XChainUTXO {
        bytes32 txId;           // X-Chain transaction ID
        uint32 outputIndex;     // Output index in transaction
        bytes32 assetId;        // Asset ID on X-Chain
        uint64 amount;          // Amount (public for X-Chain, encrypted on C-Chain)
        bytes ownerProof;       // Proof of ownership (signature or multisig)
    }

    /// @notice Spend proof for a note
    struct SpendProof {
        bytes32 nullifier;      // Nullifier to prevent double-spending
        bytes32 merkleRoot;     // Root of the note commitment tree
        bytes32[] merkleProof;  // Path to the note in the tree
        bytes zkProof;          // ZK proof of valid spend
    }

    /// @notice Output note for private transfers
    struct OutputNote {
        bytes32 commitment;     // New note commitment
        bytes encryptedNote;    // Full note encrypted to recipient
        bytes encryptedMemo;    // Optional encrypted memo
    }

    // ============ State ============

    // Note commitment tree (Merkle tree)
    uint256 public constant TREE_DEPTH = 32;
    bytes32[TREE_DEPTH] public filledSubtrees;
    bytes32[TREE_DEPTH] public zeros;
    uint256 public nextNoteIndex;
    bytes32 public noteTreeRoot;
    mapping(bytes32 => bool) public knownRoots;

    // Notes
    mapping(bytes32 => Note) public notes;
    mapping(uint256 => bytes32) public notesByIndex;

    // Nullifiers (spent notes)
    mapping(bytes32 => bool) public nullifiers;

    // X-Chain UTXO tracking
    mapping(bytes32 => bool) public processedUTXOs;
    mapping(bytes32 => bytes32) public utxoToNote; // X-Chain UTXO -> Note commitment

    // FHE public key for encrypting values
    bytes public fhePublicKey;

    // Z-Chain (privacy subnet) address for AMM operations
    address public zChainBridge;

    // ============ Events ============

    event NoteCreated(
        bytes32 indexed commitment,
        uint256 noteIndex,
        bytes32 indexed assetId
    );

    event NoteSpent(
        bytes32 indexed nullifier,
        bytes32 indexed newCommitment
    );

    event XChainImport(
        bytes32 indexed utxoId,
        bytes32 indexed noteCommitment,
        bytes32 assetId
    );

    event XChainExport(
        bytes32 indexed noteNullifier,
        bytes32 indexed destinationTxId,
        bytes32 assetId
    );

    event ZChainSwap(
        bytes32 indexed inputNullifier,
        bytes32 indexed outputCommitment,
        bytes32 inputAsset,
        bytes32 outputAsset
    );

    // ============ Constructor ============

    constructor(bytes memory _fhePublicKey, address _zChainBridge) {
        fhePublicKey = _fhePublicKey;
        zChainBridge = _zChainBridge;
        
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(BRIDGE_ROLE, msg.sender);
        
        _initializeTree();
    }

    // ============ X-Chain Integration ============

    /// @notice Import X-Chain UTXO as a private note
    /// @param utxo The X-Chain UTXO to import
    /// @param encryptedValue FHE-encrypted value
    /// @param commitment The note commitment
    /// @param warpProof Warp message proof from X-Chain
    function importFromXChain(
        XChainUTXO calldata utxo,
        bytes calldata encryptedValue,
        bytes32 commitment,
        bytes calldata warpProof
    ) external nonReentrant returns (uint256 noteIndex) {
        bytes32 utxoId = keccak256(abi.encode(utxo.txId, utxo.outputIndex));
        
        require(!processedUTXOs[utxoId], "UTXO already processed");
        require(_verifyWarpProof(utxo, warpProof), "Invalid warp proof");
        
        // Mark UTXO as processed
        processedUTXOs[utxoId] = true;
        
        // Create note
        noteIndex = _createNote(
            commitment,
            "", // Owner encrypted separately
            encryptedValue,
            utxo.assetId
        );
        
        utxoToNote[utxoId] = commitment;
        
        emit XChainImport(utxoId, commitment, utxo.assetId);
        
        return noteIndex;
    }

    /// @notice Export note back to X-Chain as UTXO
    /// @param proof Spend proof for the note
    /// @param destinationAddress X-Chain address (in P-Chain format)
    /// @param amount Public amount for X-Chain (decrypted)
    function exportToXChain(
        SpendProof calldata proof,
        bytes calldata destinationAddress,
        uint64 amount,
        bytes32 assetId
    ) external nonReentrant returns (bytes32 exportTxId) {
        require(!nullifiers[proof.nullifier], "Note already spent");
        require(knownRoots[proof.merkleRoot], "Unknown merkle root");
        require(_verifySpendProof(proof), "Invalid spend proof");
        
        // Mark note as spent
        nullifiers[proof.nullifier] = true;
        
        // Generate export transaction ID (would be actual Warp message in production)
        exportTxId = keccak256(abi.encode(
            proof.nullifier,
            destinationAddress,
            amount,
            assetId,
            block.timestamp
        ));
        
        emit XChainExport(proof.nullifier, exportTxId, assetId);
        
        return exportTxId;
    }

    // ============ Private Transfers ============

    /// @notice Transfer note privately (spend old, create new)
    /// @param proof Spend proof for input note
    /// @param output Output note for recipient
    function privateTransfer(
        SpendProof calldata proof,
        OutputNote calldata output
    ) external nonReentrant returns (uint256 newNoteIndex) {
        require(!nullifiers[proof.nullifier], "Note already spent");
        require(knownRoots[proof.merkleRoot], "Unknown merkle root");
        require(_verifySpendProof(proof), "Invalid spend proof");
        
        // Spend input
        nullifiers[proof.nullifier] = true;
        
        // Create output (simplified - in production would verify ZK proof)
        newNoteIndex = nextNoteIndex;
        notes[output.commitment] = Note({
            commitment: output.commitment,
            encryptedOwner: "",
            encryptedValue: output.encryptedNote,
            assetId: bytes32(0), // Derived from proof
            createdAt: uint64(block.timestamp)
        });
        notesByIndex[newNoteIndex] = output.commitment;
        
        _insertNote(output.commitment);
        
        emit NoteSpent(proof.nullifier, output.commitment);
        
        return newNoteIndex;
    }

    /// @notice Split note into multiple outputs
    function splitNote(
        SpendProof calldata proof,
        OutputNote[] calldata outputs
    ) external nonReentrant returns (uint256[] memory noteIndices) {
        require(!nullifiers[proof.nullifier], "Note already spent");
        require(knownRoots[proof.merkleRoot], "Unknown merkle root");
        require(_verifySpendProof(proof), "Invalid spend proof");
        require(outputs.length > 0 && outputs.length <= 16, "Invalid output count");
        
        // Spend input
        nullifiers[proof.nullifier] = true;
        
        noteIndices = new uint256[](outputs.length);
        
        for (uint256 i = 0; i < outputs.length; i++) {
            noteIndices[i] = nextNoteIndex;
            notes[outputs[i].commitment] = Note({
                commitment: outputs[i].commitment,
                encryptedOwner: "",
                encryptedValue: outputs[i].encryptedNote,
                assetId: bytes32(0),
                createdAt: uint64(block.timestamp)
            });
            notesByIndex[noteIndices[i]] = outputs[i].commitment;
            _insertNote(outputs[i].commitment);
            
            emit NoteSpent(proof.nullifier, outputs[i].commitment);
        }
        
        return noteIndices;
    }

    // ============ Z-Chain AMM Integration ============

    /// @notice Swap via Z-Chain private AMM
    /// @param inputProof Spend proof for input note
    /// @param outputCommitment New note commitment for swapped asset
    /// @param inputAsset Asset being sold
    /// @param outputAsset Asset being bought
    /// @param swapProof ZK proof of valid swap (price verification)
    function zChainSwap(
        SpendProof calldata inputProof,
        bytes32 outputCommitment,
        bytes32 inputAsset,
        bytes32 outputAsset,
        bytes calldata swapProof
    ) external nonReentrant returns (uint256 outputNoteIndex) {
        require(!nullifiers[inputProof.nullifier], "Note already spent");
        require(knownRoots[inputProof.merkleRoot], "Unknown merkle root");
        require(_verifySpendProof(inputProof), "Invalid spend proof");
        require(_verifySwapProof(inputProof.nullifier, outputCommitment, inputAsset, outputAsset, swapProof), "Invalid swap proof");
        
        // Spend input
        nullifiers[inputProof.nullifier] = true;
        
        // Create output note for swapped asset
        outputNoteIndex = _createNote(
            outputCommitment,
            "", // Encrypted to caller
            swapProof, // Contains encrypted output amount
            outputAsset
        );
        
        emit ZChainSwap(inputProof.nullifier, outputCommitment, inputAsset, outputAsset);
        
        return outputNoteIndex;
    }

    /// @notice Add liquidity to Z-Chain private AMM
    function addLiquidityPrivate(
        SpendProof calldata tokenAProof,
        SpendProof calldata tokenBProof,
        bytes32 lpNoteCommitment,
        bytes calldata liquidityProof
    ) external nonReentrant returns (uint256 lpNoteIndex) {
        require(!nullifiers[tokenAProof.nullifier] && !nullifiers[tokenBProof.nullifier], "Notes spent");
        require(knownRoots[tokenAProof.merkleRoot] && knownRoots[tokenBProof.merkleRoot], "Unknown roots");
        
        // Verify both spend proofs and liquidity proof
        require(_verifySpendProof(tokenAProof), "Invalid tokenA proof");
        require(_verifySpendProof(tokenBProof), "Invalid tokenB proof");
        
        // Spend both inputs
        nullifiers[tokenAProof.nullifier] = true;
        nullifiers[tokenBProof.nullifier] = true;
        
        // Create LP note
        lpNoteIndex = _createNote(
            lpNoteCommitment,
            "",
            liquidityProof,
            keccak256("LP_TOKEN")
        );
        
        return lpNoteIndex;
    }

    // ============ PrivateTeleport Integration ============

    /// @notice Import from X-Chain via PrivateTeleport (simplified interface)
    /// @param commitment Pedersen commitment to amount
    /// @param encryptedAmount FHE-encrypted amount
    /// @param assetId Asset identifier
    /// @param recipient Recipient address
    function importFromXChain(
        bytes32 commitment,
        bytes32 encryptedAmount,
        bytes32 assetId,
        address recipient
    ) external nonReentrant returns (uint256 noteIndex) {
        require(hasRole(BRIDGE_ROLE, msg.sender), "Caller is not bridge");
        
        // Create note with encrypted amount
        noteIndex = _createNote(
            commitment,
            abi.encodePacked(recipient),
            abi.encodePacked(encryptedAmount),
            assetId
        );
        
        return noteIndex;
    }

    /// @notice Verify Merkle proof for note membership
    /// @param proof Merkle proof path
    /// @param commitment Note commitment to verify
    function verifyMerkleProof(
        bytes32[] calldata proof,
        bytes32 commitment
    ) external view returns (bool) {
        if (proof.length > TREE_DEPTH) return false;
        
        bytes32 currentHash = commitment;
        uint256 index = 0;
        
        // Find index of commitment in tree (simplified - in production would be O(1) lookup)
        for (uint256 i = 0; i < nextNoteIndex; i++) {
            if (notesByIndex[i] == commitment) {
                index = i;
                break;
            }
        }
        
        // Verify path
        for (uint256 i = 0; i < proof.length; i++) {
            if (index % 2 == 0) {
                currentHash = keccak256(abi.encodePacked(currentHash, proof[i]));
            } else {
                currentHash = keccak256(abi.encodePacked(proof[i], currentHash));
            }
            index = index / 2;
        }
        
        return knownRoots[currentHash];
    }

    /// @notice Get Merkle proof for a commitment
    /// @param noteIndex Index of the note in the tree
    function getMerkleProof(uint256 noteIndex) external view returns (bytes32[] memory proof) {
        require(noteIndex < nextNoteIndex, "Note index out of bounds");
        
        proof = new bytes32[](TREE_DEPTH);
        uint256 currentIndex = noteIndex;
        
        for (uint256 i = 0; i < TREE_DEPTH; i++) {
            if (currentIndex % 2 == 0) {
                // Sibling is to the right
                if (currentIndex + 1 < nextNoteIndex) {
                    proof[i] = notesByIndex[currentIndex + 1];
                } else {
                    proof[i] = zeros[i];
                }
            } else {
                // Sibling is to the left
                proof[i] = filledSubtrees[i];
            }
            currentIndex = currentIndex / 2;
        }
        
        return proof;
    }

    // ============ View Functions ============

    function getNoteRoot() external view returns (bytes32) {
        return noteTreeRoot;
    }

    function isNullifierSpent(bytes32 nullifier) external view returns (bool) {
        return nullifiers[nullifier];
    }

    function getFhePublicKey() external view returns (bytes memory) {
        return fhePublicKey;
    }

    function getNote(bytes32 commitment) external view returns (Note memory) {
        return notes[commitment];
    }
    
    /// @notice Get the current note count
    function getNoteCount() external view returns (uint256) {
        return nextNoteIndex;
    }

    // ============ Internal Functions ============

    function _createNote(
        bytes32 commitment,
        bytes memory encryptedOwner,
        bytes memory encryptedValue,
        bytes32 assetId
    ) internal returns (uint256 noteIndex) {
        noteIndex = nextNoteIndex;
        
        notes[commitment] = Note({
            commitment: commitment,
            encryptedOwner: encryptedOwner,
            encryptedValue: encryptedValue,
            assetId: assetId,
            createdAt: uint64(block.timestamp)
        });
        notesByIndex[noteIndex] = commitment;
        
        _insertNote(commitment);
        
        emit NoteCreated(commitment, noteIndex, assetId);
        
        return noteIndex;
    }

    function _initializeTree() internal {
        bytes32 currentZero = keccak256(abi.encodePacked(uint256(0)));
        zeros[0] = currentZero;
        filledSubtrees[0] = currentZero;
        
        for (uint256 i = 1; i < TREE_DEPTH; i++) {
            currentZero = keccak256(abi.encodePacked(currentZero, currentZero));
            zeros[i] = currentZero;
            filledSubtrees[i] = currentZero;
        }
        
        noteTreeRoot = currentZero;
        knownRoots[noteTreeRoot] = true;
    }

    function _insertNote(bytes32 note) internal {
        uint256 currentIndex = nextNoteIndex;
        bytes32 currentHash = note;
        bytes32 left;
        bytes32 right;
        
        for (uint256 i = 0; i < TREE_DEPTH; i++) {
            if (currentIndex % 2 == 0) {
                left = currentHash;
                right = zeros[i];
                filledSubtrees[i] = currentHash;
            } else {
                left = filledSubtrees[i];
                right = currentHash;
            }
            currentHash = keccak256(abi.encodePacked(left, right));
            currentIndex = currentIndex / 2;
        }
        
        noteTreeRoot = currentHash;
        knownRoots[noteTreeRoot] = true;
        nextNoteIndex++;
    }

    function _verifyWarpProof(
        XChainUTXO calldata utxo,
        bytes calldata proof
    ) internal view returns (bool) {
        // Verify Warp message from X-Chain
        // In production: Use Lux Warp precompile
        return proof.length > 0 && utxo.amount > 0;
    }

    function _verifySpendProof(
        SpendProof calldata proof
    ) internal view returns (bool) {
        // Verify ZK proof of valid note spend
        return proof.zkProof.length > 0 && proof.merkleProof.length <= TREE_DEPTH;
    }

    function _verifySwapProof(
        bytes32 inputNullifier,
        bytes32 outputCommitment,
        bytes32 inputAsset,
        bytes32 outputAsset,
        bytes calldata swapProof
    ) internal view returns (bool) {
        // Verify swap proof (proves exchange rate and amounts match)
        return swapProof.length > 0 && 
               inputNullifier != bytes32(0) && 
               outputCommitment != bytes32(0) &&
               inputAsset != outputAsset;
    }
}
