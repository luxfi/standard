// SPDX-License-Identifier: BSD-3-Clause
// Copyright (c) 2025 Lux Industries Inc.
pragma solidity ^0.8.31;

/// @title PrecompileRegistry
/// @notice Central registry of all Lux precompile addresses aligned with LP numbering (LP-0099)
/// @dev Address scheme: BASE (0x10000) + 16-bit selector (0xPCII)
/// @dev   P = Family page (aligned with LP-Pxxx range)
/// @dev   C = Chain slot (0=P, 1=X, 2=C, 3=Q, 4=A, 5=B, 6=Z, 7=M, 8=Zoo, 9=Hanzo, A=SPC)
/// @dev   II = Item/function index (256 items per family×chain)
/// @dev
/// @dev Family Pages (P nibble) → LP Range:
/// @dev   P=0 → LP-0xxx (Universal, special addresses like 0x10000)
/// @dev   P=1 → LP-1xxx (Core/Protocol, Treasury, Burn routing)
/// @dev   P=2 → LP-2xxx (Q-Chain, PQ Identity)
/// @dev   P=3 → LP-3xxx (C-Chain, EVM/Crypto)
/// @dev   P=4 → LP-4xxx (Z-Chain, Privacy/ZK)
/// @dev   P=5 → LP-5xxx (T-Chain, Threshold/MPC)
/// @dev   P=6 → LP-6xxx (B-Chain, Bridges)
/// @dev   P=7 → LP-7xxx (A-Chain, AI)
/// @dev   P=9 → LP-9xxx (DEX/Markets)
library PrecompileRegistry {
    /*//////////////////////////////////////////////////////////////
                     STANDARD EVM PRECOMPILES (0x01-0x11)
    //////////////////////////////////////////////////////////////*/

    /// @notice BLS12-381 G1 ADD (EIP-2537)
    address internal constant BLS12381_G1ADD = 0x000000000000000000000000000000000000000b;
    /// @notice BLS12-381 G1 MUL (EIP-2537)
    address internal constant BLS12381_G1MUL = 0x000000000000000000000000000000000000000c;
    /// @notice BLS12-381 G1 MSM (EIP-2537)
    address internal constant BLS12381_G1MSM = 0x000000000000000000000000000000000000000d;
    /// @notice BLS12-381 G2 ADD (EIP-2537)
    address internal constant BLS12381_G2ADD = 0x000000000000000000000000000000000000000e;
    /// @notice BLS12-381 G2 MUL (EIP-2537)
    address internal constant BLS12381_G2MUL = 0x000000000000000000000000000000000000000f;
    /// @notice BLS12-381 G2 MSM (EIP-2537)
    address internal constant BLS12381_G2MSM = 0x0000000000000000000000000000000000000010;
    /// @notice BLS12-381 Pairing (EIP-2537)
    address internal constant BLS12381_PAIRING = 0x0000000000000000000000000000000000000011;

    /// @notice secp256r1/P-256 signature verification (EIP-7212)
    address internal constant P256_VERIFY = 0x0000000000000000000000000000000000000100;

    /*//////////////////////////////////////////////////////////////
                  PAGE 1: CORE/PROTOCOL (0x11CII) → LP-1xxx
    //////////////////////////////////////////////////////////////*/

    // Treasury/Burn Routing - Special address (LP-0150)
    /// @notice Dead Precompile - routes burns to treasury (50% burn, 50% DAO)
    /// @dev Lives at 0xdead (thematic!) - intercepts transfers to dead addresses
    /// @dev Not in LP-aligned address space - uses special "dead" address
    address internal constant DEAD = 0x000000000000000000000000000000000000dEaD;

    // Protocol Control (II = 0x10-0x1F)
    /// @notice DAO Treasury on X-Chain
    address internal constant DAO_TREASURY = 0x0000000000000000000000000000000000011110;
    /// @notice Protocol-owned Liquidity Manager
    address internal constant POL_MANAGER = 0x0000000000000000000000000000000000011211;

    /*//////////////////////////////////////////////////////////////
                  PAGE 2: PQ IDENTITY (0x12CII) → LP-2xxx
    //////////////////////////////////////////////////////////////*/

    // Post-Quantum Signatures (II = 0x01-0x0F)
    /// @notice ML-DSA signatures on C-Chain (FIPS 204)
    address internal constant ML_DSA_C = 0x0000000000000000000000000000000000012201;
    /// @notice ML-DSA signatures on Q-Chain (FIPS 204)
    address internal constant ML_DSA_Q = 0x0000000000000000000000000000000000012301;
    /// @notice ML-KEM key encapsulation on C-Chain (FIPS 203)
    address internal constant ML_KEM_C = 0x0000000000000000000000000000000000012202;
    /// @notice ML-KEM key encapsulation on Q-Chain (FIPS 203)
    address internal constant ML_KEM_Q = 0x0000000000000000000000000000000000012302;
    /// @notice SLH-DSA hash-based signatures on C-Chain (FIPS 205)
    address internal constant SLH_DSA_C = 0x0000000000000000000000000000000000012203;
    /// @notice SLH-DSA hash-based signatures on Q-Chain (FIPS 205)
    address internal constant SLH_DSA_Q = 0x0000000000000000000000000000000000012303;
    /// @notice Falcon signatures on C-Chain
    address internal constant FALCON_C = 0x0000000000000000000000000000000000012204;
    /// @notice Falcon signatures on Q-Chain
    address internal constant FALCON_Q = 0x0000000000000000000000000000000000012304;

    // PQ Key Exchange (II = 0x10-0x1F)
    /// @notice Kyber key exchange on C-Chain
    address internal constant KYBER_C = 0x0000000000000000000000000000000000012210;
    /// @notice Kyber key exchange on Q-Chain
    address internal constant KYBER_Q = 0x0000000000000000000000000000000000012310;

    // Hybrid Modes (II = 0x20-0x2F)
    /// @notice Hybrid ECDSA+ML-DSA signatures on C-Chain
    address internal constant HYBRID_SIGN_C = 0x0000000000000000000000000000000000012220;
    /// @notice Hybrid ECDSA+ML-DSA signatures on Q-Chain
    address internal constant HYBRID_SIGN_Q = 0x0000000000000000000000000000000000012320;

    /*//////////////////////////////////////////////////////////////
                  PAGE 3: EVM/CRYPTO (0x13CII) → LP-3xxx
    //////////////////////////////////////////////////////////////*/

    // Hashing (II = 0x01-0x0F)
    /// @notice Poseidon2 ZK-friendly hash on C-Chain
    address internal constant POSEIDON2_C = 0x0000000000000000000000000000000000013201;
    /// @notice Poseidon2 ZK-friendly hash on Z-Chain
    address internal constant POSEIDON2_Z = 0x0000000000000000000000000000000000013601;
    /// @notice Poseidon2 sponge (variable-length) on C-Chain
    address internal constant POSEIDON2_SPONGE_C = 0x0000000000000000000000000000000000013202;
    /// @notice Blake3 high-performance hash on C-Chain
    address internal constant BLAKE3_C = 0x0000000000000000000000000000000000013203;
    /// @notice Blake3 high-performance hash on Z-Chain
    address internal constant BLAKE3_Z = 0x0000000000000000000000000000000000013603;
    /// @notice Pedersen commitment on C-Chain
    address internal constant PEDERSEN_C = 0x0000000000000000000000000000000000013204;
    /// @notice Pedersen commitment on Z-Chain
    address internal constant PEDERSEN_Z = 0x0000000000000000000000000000000000013604;
    /// @notice MiMC hash on C-Chain
    address internal constant MIMC_C = 0x0000000000000000000000000000000000013205;
    /// @notice Rescue hash on C-Chain
    address internal constant RESCUE_C = 0x0000000000000000000000000000000000013206;

    // Classical Signatures (II = 0x10-0x1F)
    /// @notice Extended ECDSA on C-Chain
    address internal constant ECDSA_C = 0x0000000000000000000000000000000000013210;
    /// @notice Ed25519 signatures on C-Chain
    address internal constant ED25519_C = 0x0000000000000000000000000000000000013211;
    /// @notice BLS12-381 on C-Chain
    address internal constant BLS381_C = 0x0000000000000000000000000000000000013212;
    /// @notice Schnorr (BIP-340) on C-Chain
    address internal constant SCHNORR_C = 0x0000000000000000000000000000000000013213;

    // Encryption (II = 0x20-0x2F)
    /// @notice AES-GCM encryption on C-Chain
    address internal constant AESGCM_C = 0x0000000000000000000000000000000000013220;
    /// @notice ChaCha20-Poly1305 on C-Chain
    address internal constant CHACHA20_C = 0x0000000000000000000000000000000000013221;
    /// @notice HPKE on C-Chain
    address internal constant HPKE_C = 0x0000000000000000000000000000000000013222;
    /// @notice ECIES on C-Chain
    address internal constant ECIES_C = 0x0000000000000000000000000000000000013223;

    /*//////////////////////////////////////////////////////////////
                  PAGE 4: PRIVACY/ZK (0x14CII) → LP-4xxx
    //////////////////////////////////////////////////////////////*/

    // SNARKs (II = 0x01-0x0F)
    /// @notice Groth16 proof verification on C-Chain
    address internal constant GROTH16_C = 0x0000000000000000000000000000000000014201;
    /// @notice Groth16 proof verification on Z-Chain
    address internal constant GROTH16_Z = 0x0000000000000000000000000000000000014601;
    /// @notice PLONK proof verification on C-Chain
    address internal constant PLONK_C = 0x0000000000000000000000000000000000014202;
    /// @notice PLONK proof verification on Z-Chain
    address internal constant PLONK_Z = 0x0000000000000000000000000000000000014602;
    /// @notice fflonk proof verification on C-Chain
    address internal constant FFLONK_C = 0x0000000000000000000000000000000000014203;
    /// @notice fflonk proof verification on Z-Chain
    address internal constant FFLONK_Z = 0x0000000000000000000000000000000000014603;
    /// @notice Halo2 proof verification on C-Chain
    address internal constant HALO2_C = 0x0000000000000000000000000000000000014204;
    /// @notice Halo2 proof verification on Z-Chain
    address internal constant HALO2_Z = 0x0000000000000000000000000000000000014604;
    /// @notice Nova proof verification on C-Chain
    address internal constant NOVA_C = 0x0000000000000000000000000000000000014205;
    /// @notice Nova proof verification on Z-Chain
    address internal constant NOVA_Z = 0x0000000000000000000000000000000000014605;

    // STARKs (II = 0x10-0x1F)
    /// @notice STARK proof verification on C-Chain
    address internal constant STARK_C = 0x0000000000000000000000000000000000014210;
    /// @notice STARK proof verification on Z-Chain
    address internal constant STARK_Z = 0x0000000000000000000000000000000000014610;
    /// @notice STARK recursive verification on C-Chain
    address internal constant STARK_RECURSIVE_C = 0x0000000000000000000000000000000000014211;
    /// @notice STARK recursive verification on Z-Chain
    address internal constant STARK_RECURSIVE_Z = 0x0000000000000000000000000000000000014611;
    /// @notice STARK batch verification on C-Chain
    address internal constant STARK_BATCH_C = 0x0000000000000000000000000000000000014212;
    /// @notice STARK batch verification on Z-Chain
    address internal constant STARK_BATCH_Z = 0x0000000000000000000000000000000000014612;
    /// @notice STARK receipts on C-Chain
    address internal constant STARK_RECEIPTS_C = 0x000000000000000000000000000000000001421F;
    /// @notice STARK receipts on Z-Chain
    address internal constant STARK_RECEIPTS_Z = 0x000000000000000000000000000000000001461F;

    // Commitments (II = 0x20-0x2F)
    /// @notice KZG polynomial commitments on C-Chain
    address internal constant KZG_C = 0x0000000000000000000000000000000000014220;
    /// @notice KZG polynomial commitments on Z-Chain
    address internal constant KZG_Z = 0x0000000000000000000000000000000000014620;
    /// @notice Inner Product Arguments on C-Chain
    address internal constant IPA_C = 0x0000000000000000000000000000000000014221;
    /// @notice Inner Product Arguments on Z-Chain
    address internal constant IPA_Z = 0x0000000000000000000000000000000000014621;
    /// @notice FRI commitments on C-Chain
    address internal constant FRI_C = 0x0000000000000000000000000000000000014222;
    /// @notice FRI commitments on Z-Chain
    address internal constant FRI_Z = 0x0000000000000000000000000000000000014622;

    // Privacy Primitives (II = 0x30-0x3F)
    /// @notice Bulletproof range proofs on C-Chain
    address internal constant RANGE_PROOF_C = 0x0000000000000000000000000000000000014230;
    /// @notice Bulletproof range proofs on Z-Chain
    address internal constant RANGE_PROOF_Z = 0x0000000000000000000000000000000000014630;
    /// @notice Nullifier verification on C-Chain
    address internal constant NULLIFIER_C = 0x0000000000000000000000000000000000014231;
    /// @notice Nullifier verification on Z-Chain
    address internal constant NULLIFIER_Z = 0x0000000000000000000000000000000000014631;
    /// @notice Commitment verification on C-Chain
    address internal constant COMMITMENT_C = 0x0000000000000000000000000000000000014232;
    /// @notice Commitment verification on Z-Chain
    address internal constant COMMITMENT_Z = 0x0000000000000000000000000000000000014632;
    /// @notice Merkle proof verification on C-Chain
    address internal constant MERKLE_PROOF_C = 0x0000000000000000000000000000000000014233;
    /// @notice Merkle proof verification on Z-Chain
    address internal constant MERKLE_PROOF_Z = 0x0000000000000000000000000000000000014633;

    // FHE (II = 0x40-0x4F)
    /// @notice FHE operations on C-Chain
    address internal constant FHE_C = 0x0000000000000000000000000000000000014240;
    /// @notice FHE operations on Z-Chain
    address internal constant FHE_Z = 0x0000000000000000000000000000000000014640;
    /// @notice TFHE operations on C-Chain
    address internal constant TFHE_C = 0x0000000000000000000000000000000000014241;
    /// @notice TFHE operations on Z-Chain
    address internal constant TFHE_Z = 0x0000000000000000000000000000000000014641;
    /// @notice CKKS operations on C-Chain
    address internal constant CKKS_C = 0x0000000000000000000000000000000000014242;
    /// @notice CKKS operations on Z-Chain
    address internal constant CKKS_Z = 0x0000000000000000000000000000000000014642;
    /// @notice BGV operations on C-Chain
    address internal constant BGV_C = 0x0000000000000000000000000000000000014243;
    /// @notice BGV operations on Z-Chain
    address internal constant BGV_Z = 0x0000000000000000000000000000000000014643;
    /// @notice FHE Gateway on C-Chain
    address internal constant FHE_GATEWAY_C = 0x0000000000000000000000000000000000014244;
    /// @notice FHE Gateway on Z-Chain
    address internal constant FHE_GATEWAY_Z = 0x0000000000000000000000000000000000014644;
    /// @notice FHE TaskManager on C-Chain
    address internal constant TASK_MANAGER_C = 0x0000000000000000000000000000000000014245;
    /// @notice FHE TaskManager on Z-Chain
    address internal constant TASK_MANAGER_Z = 0x0000000000000000000000000000000000014645;

    /*//////////////////////////////////////////////////////////////
                  PAGE 5: THRESHOLD/MPC (0x15CII) → LP-5xxx
    //////////////////////////////////////////////////////////////*/

    // Threshold Signatures (II = 0x01-0x0F)
    /// @notice FROST Schnorr threshold on C-Chain
    address internal constant FROST_C = 0x0000000000000000000000000000000000015201;
    /// @notice FROST Schnorr threshold on Q-Chain
    address internal constant FROST_Q = 0x0000000000000000000000000000000000015301;
    /// @notice CGGMP21 ECDSA threshold on C-Chain
    address internal constant CGGMP21_C = 0x0000000000000000000000000000000000015202;
    /// @notice CGGMP21 ECDSA threshold on Q-Chain
    address internal constant CGGMP21_Q = 0x0000000000000000000000000000000000015302;
    /// @notice Ringtail lattice threshold on C-Chain (PQ)
    address internal constant RINGTAIL_C = 0x0000000000000000000000000000000000015203;
    /// @notice Ringtail lattice threshold on Q-Chain (PQ)
    address internal constant RINGTAIL_Q = 0x0000000000000000000000000000000000015303;
    /// @notice Doerner 2-of-n on C-Chain
    address internal constant DOERNER_C = 0x0000000000000000000000000000000000015204;
    /// @notice Doerner 2-of-n on Q-Chain
    address internal constant DOERNER_Q = 0x0000000000000000000000000000000000015304;
    /// @notice BLS threshold on C-Chain
    address internal constant BLS_THRESH_C = 0x0000000000000000000000000000000000015205;
    /// @notice BLS threshold on Q-Chain
    address internal constant BLS_THRESH_Q = 0x0000000000000000000000000000000000015305;

    // Secret Sharing (II = 0x10-0x1F)
    /// @notice LSS (Lux Secret Sharing) on C-Chain
    address internal constant LSS_C = 0x0000000000000000000000000000000000015210;
    /// @notice LSS (Lux Secret Sharing) on Q-Chain
    address internal constant LSS_Q = 0x0000000000000000000000000000000000015310;
    /// @notice Shamir secret sharing on C-Chain
    address internal constant SHAMIR_C = 0x0000000000000000000000000000000000015211;
    /// @notice Shamir secret sharing on Q-Chain
    address internal constant SHAMIR_Q = 0x0000000000000000000000000000000000015311;
    /// @notice Feldman VSS on C-Chain
    address internal constant FELDMAN_C = 0x0000000000000000000000000000000000015212;
    /// @notice Feldman VSS on Q-Chain
    address internal constant FELDMAN_Q = 0x0000000000000000000000000000000000015312;

    // DKG/Custody (II = 0x20-0x2F)
    /// @notice DKG on C-Chain
    address internal constant DKG_C = 0x0000000000000000000000000000000000015220;
    /// @notice DKG on Q-Chain
    address internal constant DKG_Q = 0x0000000000000000000000000000000000015320;
    /// @notice Key refresh on C-Chain
    address internal constant REFRESH_C = 0x0000000000000000000000000000000000015221;
    /// @notice Key refresh on Q-Chain
    address internal constant REFRESH_Q = 0x0000000000000000000000000000000000015321;
    /// @notice Key recovery on C-Chain
    address internal constant RECOVERY_C = 0x0000000000000000000000000000000000015222;
    /// @notice Key recovery on Q-Chain
    address internal constant RECOVERY_Q = 0x0000000000000000000000000000000000015322;

    /*//////////////////////////////////////////////////////////////
                    PAGE 6: BRIDGES (0x16CII) → LP-6xxx
    //////////////////////////////////////////////////////////////*/

    // Warp Messaging (II = 0x01-0x0F)
    /// @notice Warp message send on C-Chain
    address internal constant WARP_SEND_C = 0x0000000000000000000000000000000000016201;
    /// @notice Warp message send on B-Chain
    address internal constant WARP_SEND_B = 0x0000000000000000000000000000000000016501;
    /// @notice Warp message receive on C-Chain
    address internal constant WARP_RECEIVE_C = 0x0000000000000000000000000000000000016202;
    /// @notice Warp message receive on B-Chain
    address internal constant WARP_RECEIVE_B = 0x0000000000000000000000000000000000016502;
    /// @notice Warp receipts on C-Chain
    address internal constant WARP_RECEIPTS_C = 0x0000000000000000000000000000000000016203;
    /// @notice Warp receipts on B-Chain
    address internal constant WARP_RECEIPTS_B = 0x0000000000000000000000000000000000016503;

    // Token Bridges (II = 0x10-0x1F)
    /// @notice Token bridge on C-Chain
    address internal constant BRIDGE_C = 0x0000000000000000000000000000000000016210;
    /// @notice Token bridge on B-Chain
    address internal constant BRIDGE_B = 0x0000000000000000000000000000000000016510;
    /// @notice Teleport on C-Chain
    address internal constant TELEPORT_C = 0x0000000000000000000000000000000000016211;
    /// @notice Teleport on B-Chain
    address internal constant TELEPORT_B = 0x0000000000000000000000000000000000016511;
    /// @notice Bridge router on C-Chain
    address internal constant BRIDGE_ROUTER_C = 0x0000000000000000000000000000000000016212;
    /// @notice Bridge router on B-Chain
    address internal constant BRIDGE_ROUTER_B = 0x0000000000000000000000000000000000016512;

    // Fee Collection (II = 0x20-0x2F)
    /// @notice Fee collection on C-Chain
    address internal constant FEE_COLLECT_C = 0x0000000000000000000000000000000000016220;
    /// @notice Fee collection on B-Chain
    address internal constant FEE_COLLECT_B = 0x0000000000000000000000000000000000016520;
    /// @notice Fee governance on C-Chain
    address internal constant FEE_GOV_C = 0x0000000000000000000000000000000000016221;
    /// @notice Fee governance on B-Chain
    address internal constant FEE_GOV_B = 0x0000000000000000000000000000000000016521;

    /*//////////////////////////////////////////////////////////////
                      PAGE 7: AI (0x17CII) → LP-7xxx
    //////////////////////////////////////////////////////////////*/

    // Attestation (II = 0x01-0x0F)
    /// @notice GPU attestation on C-Chain
    address internal constant GPU_ATTEST_C = 0x0000000000000000000000000000000000017201;
    /// @notice GPU attestation on A-Chain
    address internal constant GPU_ATTEST_A = 0x0000000000000000000000000000000000017401;
    /// @notice GPU attestation on Hanzo
    address internal constant GPU_ATTEST_HANZO = 0x0000000000000000000000000000000000017901;
    /// @notice TEE verification on C-Chain
    address internal constant TEE_VERIFY_C = 0x0000000000000000000000000000000000017202;
    /// @notice TEE verification on A-Chain
    address internal constant TEE_VERIFY_A = 0x0000000000000000000000000000000000017402;
    /// @notice NVTrust attestation on C-Chain
    address internal constant NVTRUST_C = 0x0000000000000000000000000000000000017203;
    /// @notice NVTrust attestation on A-Chain
    address internal constant NVTRUST_A = 0x0000000000000000000000000000000000017403;
    /// @notice SGX attestation on C-Chain
    address internal constant SGX_ATTEST_C = 0x0000000000000000000000000000000000017204;
    /// @notice SGX attestation on A-Chain
    address internal constant SGX_ATTEST_A = 0x0000000000000000000000000000000000017404;
    /// @notice TDX attestation on C-Chain
    address internal constant TDX_ATTEST_C = 0x0000000000000000000000000000000000017205;
    /// @notice TDX attestation on A-Chain
    address internal constant TDX_ATTEST_A = 0x0000000000000000000000000000000000017405;

    // Inference (II = 0x10-0x1F)
    /// @notice AI inference on C-Chain
    address internal constant INFERENCE_C = 0x0000000000000000000000000000000000017210;
    /// @notice AI inference on A-Chain
    address internal constant INFERENCE_A = 0x0000000000000000000000000000000000017410;
    /// @notice AI inference on Hanzo
    address internal constant INFERENCE_HANZO = 0x0000000000000000000000000000000000017910;
    /// @notice Model provenance on C-Chain
    address internal constant PROVENANCE_C = 0x0000000000000000000000000000000000017211;
    /// @notice Model provenance on A-Chain
    address internal constant PROVENANCE_A = 0x0000000000000000000000000000000000017411;
    /// @notice Model hash on C-Chain
    address internal constant MODEL_HASH_C = 0x0000000000000000000000000000000000017212;
    /// @notice Model hash on A-Chain
    address internal constant MODEL_HASH_A = 0x0000000000000000000000000000000000017412;

    // Mining (II = 0x20-0x2F)
    /// @notice AI mining session on C-Chain
    address internal constant SESSION_C = 0x0000000000000000000000000000000000017220;
    /// @notice AI mining session on A-Chain
    address internal constant SESSION_A = 0x0000000000000000000000000000000000017420;
    /// @notice AI mining session on Hanzo
    address internal constant SESSION_HANZO = 0x0000000000000000000000000000000000017920;
    /// @notice AI heartbeat on C-Chain
    address internal constant HEARTBEAT_C = 0x0000000000000000000000000000000000017221;
    /// @notice AI heartbeat on A-Chain
    address internal constant HEARTBEAT_A = 0x0000000000000000000000000000000000017421;
    /// @notice AI reward on C-Chain
    address internal constant REWARD_C = 0x0000000000000000000000000000000000017222;
    /// @notice AI reward on A-Chain
    address internal constant REWARD_A = 0x0000000000000000000000000000000000017422;

    /*//////////////////////////////////////////////////////////////
                  PAGE 9: DEX/MARKETS (0x19CII) → LP-9xxx
    //////////////////////////////////////////////////////////////*/

    // Core AMM (II = 0x01-0x0F)
    /// @notice Pool manager on C-Chain (Uniswap v4-style)
    address internal constant POOL_MANAGER_C = 0x0000000000000000000000000000000000019201;
    /// @notice Pool manager on Zoo
    address internal constant POOL_MANAGER_ZOO = 0x0000000000000000000000000000000000019801;
    /// @notice Swap router on C-Chain
    address internal constant SWAP_ROUTER_C = 0x0000000000000000000000000000000000019202;
    /// @notice Swap router on Zoo
    address internal constant SWAP_ROUTER_ZOO = 0x0000000000000000000000000000000000019802;
    /// @notice Hooks registry on C-Chain
    address internal constant HOOKS_REG_C = 0x0000000000000000000000000000000000019203;
    /// @notice Hooks registry on Zoo
    address internal constant HOOKS_REG_ZOO = 0x0000000000000000000000000000000000019803;
    /// @notice Flash loan on C-Chain
    address internal constant FLASH_LOAN_C = 0x0000000000000000000000000000000000019204;
    /// @notice Flash loan on Zoo
    address internal constant FLASH_LOAN_ZOO = 0x0000000000000000000000000000000000019804;

    // Orderbook (II = 0x10-0x1F)
    /// @notice CLOB on C-Chain
    address internal constant CLOB_C = 0x0000000000000000000000000000000000019210;
    /// @notice CLOB on Zoo
    address internal constant CLOB_ZOO = 0x0000000000000000000000000000000000019810;
    /// @notice Orderbook on C-Chain
    address internal constant ORDERBOOK_C = 0x0000000000000000000000000000000000019211;
    /// @notice Orderbook on Zoo
    address internal constant ORDERBOOK_ZOO = 0x0000000000000000000000000000000000019811;
    /// @notice Matching engine on C-Chain
    address internal constant MATCHING_C = 0x0000000000000000000000000000000000019212;
    /// @notice Matching engine on Zoo
    address internal constant MATCHING_ZOO = 0x0000000000000000000000000000000000019812;

    // Oracle (II = 0x20-0x2F)
    /// @notice Oracle hub on C-Chain
    address internal constant ORACLE_HUB_C = 0x0000000000000000000000000000000000019220;
    /// @notice Oracle hub on Zoo
    address internal constant ORACLE_HUB_ZOO = 0x0000000000000000000000000000000000019820;
    /// @notice TWAP oracle on C-Chain
    address internal constant TWAP_C = 0x0000000000000000000000000000000000019221;
    /// @notice TWAP oracle on Zoo
    address internal constant TWAP_ZOO = 0x0000000000000000000000000000000000019821;
    /// @notice Fast price feed on C-Chain
    address internal constant FAST_PRICE_C = 0x0000000000000000000000000000000000019222;
    /// @notice Fast price feed on Zoo
    address internal constant FAST_PRICE_ZOO = 0x0000000000000000000000000000000000019822;

    // Perps (II = 0x30-0x3F)
    /// @notice Perps vault on C-Chain
    address internal constant VAULT_C = 0x0000000000000000000000000000000000019230;
    /// @notice Perps vault on Zoo
    address internal constant VAULT_ZOO = 0x0000000000000000000000000000000000019830;
    /// @notice Position router on C-Chain
    address internal constant POS_ROUTER_C = 0x0000000000000000000000000000000000019231;
    /// @notice Position router on Zoo
    address internal constant POS_ROUTER_ZOO = 0x0000000000000000000000000000000000019831;
    /// @notice Price feed on C-Chain
    address internal constant PRICE_FEED_C = 0x0000000000000000000000000000000000019232;
    /// @notice Price feed on Zoo
    address internal constant PRICE_FEED_ZOO = 0x0000000000000000000000000000000000019832;

    /*//////////////////////////////////////////////////////////////
                         HELPER FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Calculate precompile address from (P, C, II) components
    /// @param p Family page (aligned with LP-Pxxx)
    /// @param c Chain slot (0=P, 1=X, 2=C, 3=Q, 4=A, 5=B, 6=Z, 7=M, 8=Zoo, 9=Hanzo)
    /// @param ii Item index
    function precompileAddress(uint8 p, uint8 c, uint8 ii) internal pure returns (address) {
        require(p <= 15 && c <= 15, "Invalid P or C nibble");
        uint256 selector = (uint256(p) << 12) | (uint256(c) << 8) | uint256(ii);
        return address(uint160(0x10000 + selector));
    }

    /// @notice Get family page from LP range
    /// @param lpRange LP range first digit (2-9)
    function familyPage(uint8 lpRange) internal pure returns (uint8) {
        require(lpRange >= 2 && lpRange <= 9, "Invalid LP range");
        return lpRange;
    }

    /// @notice Get chain slot from chain name
    /// @param chain Single letter chain identifier
    function chainSlot(bytes1 chain) internal pure returns (uint8) {
        if (chain == "P" || chain == "p") return 0;
        if (chain == "X" || chain == "x") return 1;
        if (chain == "C" || chain == "c") return 2;
        if (chain == "Q" || chain == "q") return 3;
        if (chain == "A" || chain == "a") return 4;
        if (chain == "B" || chain == "b") return 5;
        if (chain == "Z" || chain == "z") return 6;
        if (chain == "M" || chain == "m") return 7;
        revert("Unknown chain");
    }

    /// @notice Check if address is in Lux precompile range
    function isLuxPrecompile(address addr) internal pure returns (bool) {
        uint256 addrInt = uint256(uint160(addr));
        // Lux precompiles: 0x10000 - 0x1FFFF (BASE + 16-bit selector)
        return addrInt >= 0x10000 && addrInt <= 0x1FFFF;
    }

    /// @notice Get LP range from precompile address
    function getLPRange(address addr) internal pure returns (string memory) {
        uint256 addrInt = uint256(uint160(addr));
        if (addrInt < 0x10000 || addrInt > 0x1FFFF) return "N/A";

        uint8 p = uint8((addrInt - 0x10000) >> 12);
        if (p == 2) return "LP-2xxx";
        if (p == 3) return "LP-3xxx";
        if (p == 4) return "LP-4xxx";
        if (p == 5) return "LP-5xxx";
        if (p == 6) return "LP-6xxx";
        if (p == 7) return "LP-7xxx";
        if (p == 9) return "LP-9xxx";
        return "Unknown";
    }
}
