// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title IShieldedPool
 * @notice Interface for shielded asset pools with FHE-encrypted balances
 * @dev Enables private deposits and withdrawals with range proof verification
 * 
 * Architecture:
 * 1. Deposit: User deposits tokens → receives commitment (Pedersen)
 * 2. Transfer: Move shielded funds between addresses (encrypted)
 * 3. Withdraw: Present range proof → receive tokens
 * 4. Swap: Exchange shielded assets via dark pool
 */
interface IShieldedPool {
    /// @notice Commitment structure for shielded deposits
    struct Commitment {
        bytes32 commitment;      // Pedersen commitment C = gH(r) * vG
        bytes32 nullifierHash;   // Hash of nullifier (revealed on spend)
        uint256 leafIndex;       // Position in Merkle tree
        uint64 timestamp;        // Deposit timestamp
    }

    /// @notice Withdrawal proof for range verification
    struct WithdrawalProof {
        bytes32 nullifier;       // Nullifier to prevent double-spend
        bytes32 root;            // Merkle root at time of proof generation
        bytes rangeProof;        // Bulletproof proving amount in range [0, 2^64)
        bytes32 amountCommitment;// Pedersen commitment to withdrawal amount
        address recipient;       // Recipient address
        uint256 relayerFee;      // Fee for relayer (public)
    }

    /// @notice Shielded transfer between users (encrypted amounts)
    struct ShieldedTransfer {
        bytes32 inputNullifier;  // Spend existing commitment
        bytes32 outputCommitment;// New commitment for recipient
        bytes encryptedAmount;   // FHE-encrypted amount (for recipient)
        bytes zkProof;           // ZK proof of valid transfer
    }

    /// @notice Emitted when tokens are deposited into shielded pool
    event ShieldedDeposit(
        bytes32 indexed commitment,
        uint256 leafIndex,
        uint64 timestamp
    );

    /// @notice Emitted when tokens are withdrawn from shielded pool
    event ShieldedWithdrawal(
        bytes32 indexed nullifier,
        address indexed recipient,
        uint256 relayerFee
    );

    /// @notice Emitted when shielded transfer occurs
    event ShieldedTransferEvent(
        bytes32 indexed inputNullifier,
        bytes32 indexed outputCommitment
    );

    /// @notice Deposit tokens into the shielded pool
    /// @param commitment The Pedersen commitment to the deposited amount
    /// @param encryptedAmount FHE-encrypted amount (using pool's public key)
    /// @return leafIndex The index in the commitment Merkle tree
    function deposit(
        bytes32 commitment,
        bytes calldata encryptedAmount
    ) external payable returns (uint256 leafIndex);

    /// @notice Withdraw tokens with range proof
    /// @param proof The withdrawal proof with range proof and nullifier
    /// @return success Whether withdrawal succeeded
    function withdraw(
        WithdrawalProof calldata proof
    ) external returns (bool success);

    /// @notice Transfer shielded funds to another user
    /// @param transfer The encrypted transfer data
    /// @return outputLeafIndex The new commitment's leaf index
    function shieldedTransfer(
        ShieldedTransfer calldata transfer
    ) external returns (uint256 outputLeafIndex);

    /// @notice Get the current Merkle root
    /// @return The current commitment tree root
    function getRoot() external view returns (bytes32);

    /// @notice Check if a nullifier has been used
    /// @param nullifier The nullifier to check
    /// @return True if nullifier is spent
    function isSpent(bytes32 nullifier) external view returns (bool);

    /// @notice Get pool's FHE public key for encryption
    /// @return The FHE public key
    function getFhePublicKey() external view returns (bytes memory);

    /// @notice Get the number of commitments in the tree
    /// @return The total number of deposits
    function getCommitmentCount() external view returns (uint256);
}
