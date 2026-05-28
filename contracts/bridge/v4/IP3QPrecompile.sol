// SPDX-License-Identifier: BSD-3-Clause
// Copyright (c) 2026 Lux Industries Inc.
pragma solidity ^0.8.31;

/**
 * @title IP3QPrecompile
 * @author Lux Industries
 * @notice Interface for the Lux P3Q (Post-Quantum Proof) verifier precompile,
 *         registered at address 0x0000000000000000000000000000000000012205.
 *
 * P3Q is the post-quantum cryptographic primitive used to verify Warp 2.0
 * envelopes: it pulls together a Pulsar threshold signature and a Prism
 * commitment cut into a single round signer (quasar.RoundSigner).
 *
 * The precompile takes a concatenated (envelope || proof) payload and returns
 * a single bool packed into the rightmost byte of a 32-byte word:
 *   0x...01 = valid; 0x...00 = invalid; revert = malformed proof.
 *
 * Callers should always use STATICCALL — the verifier is pure on the inputs.
 */
interface IP3QPrecompile {
    /**
     * @notice Verify a Warp 2.0 envelope under the strict-PQ profile.
     * @param encodedProof  abi.encode(envelope, proof)
     * @return valid        true iff the envelope was signed by the quasar round
     */
    function verifyEnvelope(bytes calldata encodedProof) external view returns (bool valid);
}

/// @dev Address of the on-chain P3Q precompile (slot 0x012205 per the Lux
///      precompile registry; matches contract.RefuseUnderStrictPQ gate).
address constant P3Q_PRECOMPILE = address(0x0000000000000000000000000000000000012205);
