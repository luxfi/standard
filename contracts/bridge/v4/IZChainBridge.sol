// SPDX-License-Identifier: BSD-3-Clause
// Copyright (c) 2026 Lux Industries Inc.
pragma solidity ^0.8.31;

/**
 * @title IZChainBridge
 * @author Lux Industries
 * @notice Interface BridgeV4 uses to talk to the Z-Chain shielded-asset VM.
 *
 * Z-Chain is a separate VM in the Lux primary network that holds shielded
 * note commitments. BridgeV4 acts as the boundary: when a user wants to land
 * a bridged claim shielded (zClaim), BridgeV4 verifies the Warp 2.0 envelope
 * via P3Q, then hands the (amount, asset, commitment) tuple off to the
 * Z-Chain VM via this interface. When a user wants to unshield (zRedeem),
 * BridgeV4 receives a (nullifier, asset, amount) tuple from the user,
 * delegates the ZK note-spend proof check to Z-Chain via this interface, and
 * on success emits the redeem event for the daemon broadcaster.
 *
 * The Z-Chain implementation does the actual ZK verification — BridgeV4
 * intentionally does NOT carry a SNARK verifier in its own bytecode. That
 * separation keeps the EVM-side surface small (P3Q precompile + claimId
 * dedup + nullifier dedup) and isolates the heavy crypto in the chain that
 * owns the commitment Merkle tree.
 */
interface IZChainBridge {
    /**
     * @notice Receive a shielded mint from BridgeV4.
     * @param asset       destination bridged-asset on Z-Chain
     * @param amount      amount (raw asset units)
     * @param commitment  ZK commitment that will become a note in the
     *                    Z-Chain Merkle tree
     * @param claimId     V4-side claim id; Z-Chain mirrors it for traceback
     * @return ack        opaque acknowledgement (e.g. note id)
     */
    function receiveShieldedMint(address asset, uint256 amount, bytes32 commitment, bytes32 claimId)
        external
        returns (bytes32 ack);

    /**
     * @notice Verify a note-spend on Z-Chain. Reverts on bad proof.
     * @param nullifier   nullifier disclosed by the spender
     * @param asset       destination bridged-asset
     * @param amount      amount to release on the public side (V4 burns the
     *                    public-side balance via the asset's burn function)
     * @param zkProof     ZK proof bytes opaque to V4; Z-Chain decodes
     * @return ack        opaque acknowledgement
     */
    function verifyShieldedSpend(bytes32 nullifier, address asset, uint256 amount, bytes calldata zkProof)
        external
        returns (bytes32 ack);
}
