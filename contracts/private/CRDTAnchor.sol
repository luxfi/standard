// SPDX-License-Identifier: MIT
pragma solidity ^0.8.31;

/// @title  CRDTAnchor
/// @notice On-chain checkpoint registry for encrypted CRDT documents.
///
///         Each (owner, docId) pair gets a monotonically-advancing checkpoint
///         consisting of a state root (keccak256 of the serialized CRDT
///         snapshot) and an operation count. The contract enforces that
///         opCount strictly increases, preventing rollback of document state.
///
///         The pattern:
///           1. Off-chain: EncryptedDocument.MarshalBinary() -> snapshot
///           2. Off-chain: PrivateStore.put(keccak256(docId), snapshot)
///           3. On-chain:  CRDTAnchor.checkpoint(docId, stateRoot, opCount)
///
///         This gives us causal consistency (opCount monotonicity), tamper
///         evidence (stateRoot on-chain), and privacy (ciphertext in
///         PrivateStore, only hash on-chain).
///
/// Trust model:
///   * Only msg.sender can write checkpoints for their own docId.
///   * Anyone can read checkpoints (they are hashes, not data).
///   * opCount monotonicity prevents state rollback attacks.
contract CRDTAnchor {
    struct Checkpoint {
        bytes32 root;
        uint64 opCount;
        uint64 timestamp;
    }

    /// @dev key = keccak256(abi.encode(owner, docId))
    mapping(bytes32 => Checkpoint) private _checkpoints;

    /// Maximum opCount jump allowed in a single checkpoint. Prevents gap
    /// attacks where an adversary claims a very high opCount to block all
    /// future legitimate checkpoints below that value.
    uint64 public immutable maxOpCountJump;

    /// Emitted on every successful checkpoint.
    event CheckpointEvent(address indexed owner, bytes32 indexed docId, bytes32 root, uint64 opCount, uint64 timestamp);

    error OpCountNotMonotonic(uint64 current, uint64 attempted);
    error ZeroOpCount();
    error OpCountJumpTooLarge(uint64 jump, uint64 max);

    constructor(uint64 _maxOpCountJump) {
        maxOpCountJump = _maxOpCountJump == 0 ? uint64(1) << 32 : _maxOpCountJump;
    }

    /// @notice Record a state root for (msg.sender, docId).
    /// @param docId   Identifier for the CRDT document.
    /// @param root    keccak256 of the serialized document snapshot.
    /// @param opCount Total operation count at this checkpoint. Must be
    ///                strictly greater than the previous checkpoint's opCount.
    function checkpoint(bytes32 docId, bytes32 root, uint64 opCount) external {
        if (opCount == 0) revert ZeroOpCount();

        bytes32 k = _key(msg.sender, docId);
        Checkpoint storage prev = _checkpoints[k];

        if (opCount <= prev.opCount) {
            revert OpCountNotMonotonic(prev.opCount, opCount);
        }

        uint64 jump = opCount - prev.opCount;
        if (jump > maxOpCountJump) {
            revert OpCountJumpTooLarge(jump, maxOpCountJump);
        }

        prev.root = root;
        prev.opCount = opCount;
        prev.timestamp = uint64(block.timestamp);

        emit CheckpointEvent(msg.sender, docId, root, opCount, uint64(block.timestamp));
    }

    /// @notice Read the latest checkpoint for (owner, docId).
    /// @return root      State root hash.
    /// @return opCount   Operation count at checkpoint.
    /// @return timestamp Block timestamp of the checkpoint.
    function latest(address owner, bytes32 docId)
        external
        view
        returns (bytes32 root, uint64 opCount, uint64 timestamp)
    {
        Checkpoint storage cp = _checkpoints[_key(owner, docId)];
        return (cp.root, cp.opCount, cp.timestamp);
    }

    function _key(address owner, bytes32 docId) internal pure returns (bytes32) {
        return keccak256(abi.encode(owner, docId));
    }
}
