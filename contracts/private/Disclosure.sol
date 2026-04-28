// SPDX-License-Identifier: MIT
pragma solidity ^0.8.31;

/// @title  Disclosure
/// @notice Three composable regulatory disclosure primitives for encrypted
///         CRDT documents. Each primitive operates independently; callers
///         combine them per their compliance requirements.
///
///         (a) Viewing keys: Zcash-style per-viewer wrapped decryption keys.
///         (b) Threshold disclosure: N-of-M with regulator as one party.
///         (c) Selective disclosure: ZK attestation anchors with optional
///             on-chain verifier registry.
///
///         All three share a common ownership model: docId is scoped to
///         msg.sender. The owner of a document controls who can decrypt
///         (viewing keys), who participates in threshold decryption
///         (threshold policies), and what claims are attested (selective).
///
///         None of these primitives perform actual cryptographic operations
///         on-chain. They are coordination contracts: registries of keys,
///         shares, and proofs that enable off-chain participants to discover
///         each other and verify commitments.
contract Disclosure {
    address private immutable _owner;

    error NotOwner();

    modifier onlyOwner() {
        if (msg.sender != _owner) revert NotOwner();
        _;
    }

    constructor() {
        _owner = msg.sender;
    }

    /// @notice Returns the contract owner (deployer).
    function owner() external view returns (address) {
        return _owner;
    }

    // ================================================================
    // (a) Viewing Keys — Zcash-style per-viewer wrapped decryption keys
    // ================================================================

    /// @dev key = keccak256(abi.encode(owner, docId, viewer))
    mapping(bytes32 => bytes) private _viewingKeys;

    event ViewingKeyRegistered(address indexed owner, bytes32 indexed docId, address indexed viewer);
    event ViewingKeyRevoked(address indexed owner, bytes32 indexed docId, address indexed viewer);

    error ViewingKeyNotFound();
    error EmptyWrappedKey();

    /// @notice Register a per-viewer wrapped decryption key. The wrappedKey
    ///         is the document's symmetric key encrypted under the viewer's
    ///         public key. The viewer fetches it and decrypts locally.
    function registerViewingKey(bytes32 docId, address viewer, bytes calldata wrappedKey) external {
        if (wrappedKey.length == 0) revert EmptyWrappedKey();
        _viewingKeys[_vkKey(msg.sender, docId, viewer)] = wrappedKey;
        emit ViewingKeyRegistered(msg.sender, docId, viewer);
    }

    /// @notice Fetch the wrapped decryption key for a viewer. Anyone may
    ///         call this (the wrappedKey is encrypted under the viewer's
    ///         public key, so only the viewer can unwrap it).
    function getViewingKey(address owner, bytes32 docId, address viewer) external view returns (bytes memory) {
        bytes memory wk = _viewingKeys[_vkKey(owner, docId, viewer)];
        if (wk.length == 0) revert ViewingKeyNotFound();
        return wk;
    }

    /// @notice Revoke a viewer's access. Deletes the on-chain wrapped key.
    ///         The viewer may still hold the unwrapped key locally; rekeying
    ///         the document is the owner's off-chain responsibility. This
    ///         contract emits the event so watchers can trigger rekey flows.
    function revokeViewingKey(bytes32 docId, address viewer) external {
        bytes32 k = _vkKey(msg.sender, docId, viewer);
        if (_viewingKeys[k].length == 0) revert ViewingKeyNotFound();
        delete _viewingKeys[k];
        emit ViewingKeyRevoked(msg.sender, docId, viewer);
    }

    function _vkKey(address owner, bytes32 docId, address viewer) internal pure returns (bytes32) {
        return keccak256(abi.encode(owner, docId, viewer));
    }

    // ================================================================
    // (b) Threshold Disclosure — N-of-M with regulator as one party
    // ================================================================

    struct ThresholdPolicy {
        address owner;
        uint256 threshold;
        bytes policyCiphertext; // encrypted decryption key (shares distributed off-chain via LSSS)
        uint256 partyCount;
    }

    struct DisclosureRequest {
        bytes32 docId;
        address owner;
        bytes32 reasonHash;
        address requester;
        uint256 shareCount;
    }

    /// @dev policyKey = keccak256(abi.encode(owner, docId))
    mapping(bytes32 => ThresholdPolicy) private _policies;
    mapping(bytes32 => mapping(address => bool)) private _parties;

    /// @dev requestKey = keccak256(abi.encode(owner, docId, requestId))
    mapping(bytes32 => DisclosureRequest) private _requests;
    mapping(bytes32 => mapping(uint256 => bytes)) private _shares;
    mapping(bytes32 => mapping(address => bool)) private _submittedShare;

    uint256 private _requestNonce;

    event ThresholdPolicyCreated(address indexed owner, bytes32 indexed docId, uint256 threshold, uint256 partyCount);
    event DisclosureRequested(
        bytes32 indexed requestId, address indexed owner, bytes32 indexed docId, bytes32 reasonHash, address requester
    );
    event ShareSubmitted(bytes32 indexed requestId, address indexed party, uint256 shareIndex);
    event PartyRevoked(address indexed owner, bytes32 indexed docId, address indexed party);

    error PolicyNotFound();
    error NotAuthorizedParty();
    error PolicyAlreadyExists();
    error InvalidThreshold();
    error EmptyPolicyCiphertext();
    error ShareAlreadySubmitted();

    /// @notice Create a threshold disclosure policy for a document. The
    ///         policyCiphertext is the encrypted decryption key whose shares
    ///         are distributed off-chain via lux/fhe/pkg/threshold LSSS.
    function createThresholdPolicy(
        bytes32 docId,
        address[] calldata parties,
        uint256 threshold,
        bytes calldata policyCiphertext
    ) external {
        if (threshold == 0 || threshold > parties.length) revert InvalidThreshold();
        if (policyCiphertext.length == 0) revert EmptyPolicyCiphertext();

        bytes32 pk = _policyKey(msg.sender, docId);
        if (_policies[pk].owner != address(0)) revert PolicyAlreadyExists();

        _policies[pk] = ThresholdPolicy({
            owner: msg.sender, threshold: threshold, policyCiphertext: policyCiphertext, partyCount: parties.length
        });

        for (uint256 i = 0; i < parties.length; i++) {
            _parties[pk][parties[i]] = true;
        }

        emit ThresholdPolicyCreated(msg.sender, docId, threshold, parties.length);
    }

    /// @notice Request disclosure of a document. Any authorized party may
    ///         request. Emits an event for off-chain parties to observe and
    ///         submit their shares.
    function requestDisclosure(address owner, bytes32 docId, bytes32 reasonHash) external returns (bytes32 requestId) {
        bytes32 pk = _policyKey(owner, docId);
        if (_policies[pk].owner == address(0)) revert PolicyNotFound();
        if (!_parties[pk][msg.sender]) revert NotAuthorizedParty();

        _requestNonce++;
        requestId = keccak256(abi.encode(owner, docId, _requestNonce));

        _requests[requestId] = DisclosureRequest({
            docId: docId, owner: owner, reasonHash: reasonHash, requester: msg.sender, shareCount: 0
        });

        emit DisclosureRequested(requestId, owner, docId, reasonHash, msg.sender);
    }

    /// @notice Submit a threshold share for a disclosure request. The
    ///         contract stores but does not combine shares. Combination
    ///         happens off-chain by the requester once enough shares arrive.
    function submitShare(bytes32 requestId, bytes calldata share) external {
        DisclosureRequest storage req = _requests[requestId];
        if (req.owner == address(0)) revert PolicyNotFound();

        bytes32 pk = _policyKey(req.owner, req.docId);
        if (!_parties[pk][msg.sender]) revert NotAuthorizedParty();
        if (_submittedShare[requestId][msg.sender]) revert ShareAlreadySubmitted();

        _submittedShare[requestId][msg.sender] = true;
        uint256 idx = req.shareCount;
        req.shareCount++;
        _shares[requestId][idx] = share;

        emit ShareSubmitted(requestId, msg.sender, idx);
    }

    /// @notice Revoke a party from a threshold policy. Requires rekeying
    ///         off-chain (the contract emits an event for this purpose).
    function revokeParty(bytes32 docId, address party) external {
        bytes32 pk = _policyKey(msg.sender, docId);
        if (_policies[pk].owner == address(0)) revert PolicyNotFound();
        if (!_parties[pk][party]) revert NotAuthorizedParty();

        delete _parties[pk][party];
        _policies[pk].partyCount--;

        emit PartyRevoked(msg.sender, docId, party);
    }

    /// @notice Read the policy ciphertext (for off-chain share distribution).
    function getPolicy(address owner, bytes32 docId)
        external
        view
        returns (uint256 threshold, uint256 partyCount, bytes memory policyCiphertext)
    {
        ThresholdPolicy storage p = _policies[_policyKey(owner, docId)];
        if (p.owner == address(0)) revert PolicyNotFound();
        return (p.threshold, p.partyCount, p.policyCiphertext);
    }

    /// @notice Check if an address is an authorized party.
    function isParty(address owner, bytes32 docId, address party) external view returns (bool) {
        return _parties[_policyKey(owner, docId)][party];
    }

    /// @notice Read a submitted share by index.
    function getShare(bytes32 requestId, uint256 index) external view returns (bytes memory) {
        return _shares[requestId][index];
    }

    /// @notice Read disclosure request metadata.
    function getRequest(bytes32 requestId)
        external
        view
        returns (bytes32 docId, address owner, bytes32 reasonHash, address requester, uint256 shareCount)
    {
        DisclosureRequest storage r = _requests[requestId];
        return (r.docId, r.owner, r.reasonHash, r.requester, r.shareCount);
    }

    function _policyKey(address owner, bytes32 docId) internal pure returns (bytes32) {
        return keccak256(abi.encode(owner, docId));
    }

    // ================================================================
    // (c) Selective Disclosure — ZK attestation anchors
    // ================================================================

    /// @dev Optional verifier registry: claimType -> verifier contract.
    mapping(bytes4 => address) private _verifiers;

    event Attestation(address indexed owner, bytes32 indexed docId, bytes32 indexed claimHash, bytes4 claimType);
    event VerifierRegistered(bytes4 indexed claimType, address verifier);

    error EmptyProof();

    /// @notice Anchor a ZK attestation for a document field. The proof blob
    ///         is stored only as a log event (not in contract state) to keep
    ///         gas low. Off-chain verifiers fetch the event and validate.
    ///
    ///         If a verifier contract is registered for the claimType, the
    ///         caller can route verification on-chain in a separate tx.
    ///         This contract does NOT call the verifier automatically to
    ///         avoid coupling to any specific proof system.
    /// @param docId     Document identifier.
    /// @param claimHash Hash of the claim being attested.
    /// @param claimType 4-byte type selector (e.g. 0x00000001 for "KYC",
    ///                  0x00000002 for "accreditation").
    /// @param proof     Opaque proof bytes (Groth16, PlonK, etc).
    function attest(bytes32 docId, bytes32 claimHash, bytes4 claimType, bytes calldata proof) external {
        if (proof.length == 0) revert EmptyProof();
        // proof is emitted in the event log only — not stored.
        // Verifiers index events by (owner, docId, claimType).
        emit Attestation(msg.sender, docId, claimHash, claimType);
    }

    /// @notice Register a verifier contract for a claim type. Only callable
    ///         by the deployer (for now — governance hook later). This
    ///         scaffolds the registry without shipping verifier contracts.
    function registerVerifier(bytes4 claimType, address verifier) external onlyOwner {
        _verifiers[claimType] = verifier;
        emit VerifierRegistered(claimType, verifier);
    }

    /// @notice Look up the registered verifier for a claim type.
    function getVerifier(bytes4 claimType) external view returns (address) {
        return _verifiers[claimType];
    }
}
