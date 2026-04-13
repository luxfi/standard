// SPDX-License-Identifier: MIT
pragma solidity ^0.8.31;

/// @title  PrivateStore
/// @notice Per-user, on-chain blind ciphertext store. The contract never
///         sees plaintext — it stores opaque bytes indexed by
///         keccak256(msg.sender, tagHash) and emits only size + timestamp.
///
///         Client-side encryption (recommended: luxfi/age — X25519 or
///         X-Wing PQ-hybrid) is the responsibility of the caller. This
///         contract is a deliberately dumb key-value store for encrypted
///         blobs. If an operator can read it, the scheme is broken.
///
///         Same API shape as /v1/base/private/* in hanzo/base — one client
///         SDK can address either backend based on durability/cost trade-offs.
///
/// Trust model:
///   * Write: msg.sender is the only party that can write under their key.
///   * Read:  everyone can read ciphertext (it IS on-chain). Privacy is
///            from encryption, not access control.
///   * Delete: only owner; re-writing to the same key overwrites.
///
/// Gas note:
///   * Contract storage is expensive. This is intended for small, rarely-
///     updated blobs (recovery data, social-graph commitments, cross-device
///     sync seeds). For larger or mutable state, use off-chain Base or IPFS
///     and anchor a hash here.
contract PrivateStore {
    /// @dev key = keccak256(abi.encode(owner, tagHash))
    mapping(bytes32 => bytes) private _blobs;
    mapping(bytes32 => uint64) private _updated;

    /// Maximum ciphertext size in bytes. Default 48 KiB. Set at deploy time.
    uint256 public immutable maxCtSize;

    /// Emitted on every write. tagHash is NOT the raw tag — it's a
    /// client-side hash so observers can't correlate labels across users.
    event Put(
        address indexed owner,
        bytes32 indexed tagHash,
        uint256 size,
        uint64 timestamp
    );

    /// Emitted on explicit deletion.
    event Deleted(address indexed owner, bytes32 indexed tagHash);

    error EmptyCiphertext();
    error NotFound();
    error CiphertextTooLarge(uint256 actual, uint256 max);

    constructor(uint256 _maxCtSize) {
        maxCtSize = _maxCtSize == 0 ? 48 << 10 : _maxCtSize;
    }

    /// @notice Upsert ciphertext for (msg.sender, tagHash).
    /// @param tagHash Client-computed hash of the logical tag.
    /// @param ct      Opaque ciphertext. Must be non-empty.
    function put(bytes32 tagHash, bytes calldata ct) external {
        if (ct.length == 0) revert EmptyCiphertext();
        if (ct.length > maxCtSize) revert CiphertextTooLarge(ct.length, maxCtSize);
        bytes32 k = _key(msg.sender, tagHash);
        _blobs[k] = ct;
        _updated[k] = uint64(block.timestamp);
        emit Put(msg.sender, tagHash, ct.length, uint64(block.timestamp));
    }

    /// @notice Read ciphertext for a given owner + tagHash. View-only; anyone
    ///         can call. The ciphertext is encrypted under the owner's key,
    ///         so access control is not our concern.
    function get(address owner, bytes32 tagHash) external view returns (bytes memory) {
        bytes memory ct = _blobs[_key(owner, tagHash)];
        if (ct.length == 0) revert NotFound();
        return ct;
    }

    /// @notice When was the most recent write for this (owner, tag)?
    /// @return Unix timestamp, or 0 if never written.
    function updatedAt(address owner, bytes32 tagHash) external view returns (uint64) {
        return _updated[_key(owner, tagHash)];
    }

    /// @notice Delete a ciphertext. Only the owner may delete their own.
    ///         Overwriting with put() is cheaper — use del() for compliance
    ///         workflows where a tombstone event is required.
    function del(bytes32 tagHash) external {
        bytes32 k = _key(msg.sender, tagHash);
        if (_blobs[k].length == 0) revert NotFound();
        delete _blobs[k];
        delete _updated[k];
        emit Deleted(msg.sender, tagHash);
    }

    function _key(address owner, bytes32 tagHash) internal pure returns (bytes32) {
        return keccak256(abi.encode(owner, tagHash));
    }
}
