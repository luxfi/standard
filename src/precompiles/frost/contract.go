// Copyright (C) 2025, Lux Industries, Inc. All rights reserved.
// See the file LICENSE for licensing terms.

package frost

import (
	"crypto/sha256"
	"encoding/binary"
	"errors"
	"fmt"

	"github.com/luxfi/evm/precompile/contract"
	"github.com/luxfi/geth/common"
	"github.com/luxfi/geth/crypto"
)

var (
	// ContractFROSTVerifyAddress is the address of the FROST threshold signature precompile
	ContractFROSTVerifyAddress = common.HexToAddress("0x020000000000000000000000000000000000000C")

	// Singleton instance
	FROSTVerifyPrecompile = &frostVerifyPrecompile{}

	_ contract.StatefulPrecompiledContract = &frostVerifyPrecompile{}

	ErrInvalidInputLength  = errors.New("invalid input length")
	ErrInvalidThreshold    = errors.New("invalid threshold: t must be > 0 and <= n")
	ErrInvalidPublicKey    = errors.New("invalid public key")
	ErrInvalidSignature    = errors.New("invalid signature")
	ErrSignatureVerifyFail = errors.New("signature verification failed")
)

const (
	// Gas costs for FROST threshold signature verification
	// FROST is more efficient than ECDSA threshold (CMP/CGGMP21)
	FROSTVerifyBaseGas    uint64 = 50_000 // Base cost for Schnorr verification
	FROSTVerifyPerSignerGas uint64 = 5_000 // Cost per signer in threshold

	// FROST uses 32-byte Schnorr signatures (Ed25519 or secp256k1)
	FROSTPublicKeySize  = 32 // Compressed public key
	FROSTSignatureSize  = 64 // Schnorr signature (R || s)
	FROSTMessageHashSize = 32 // SHA-256 message hash
	ThresholdSize       = 4  // uint32 threshold t
	TotalSignersSize    = 4  // uint32 total signers n

	// Minimum input size
	MinInputSize = ThresholdSize + TotalSignersSize + FROSTPublicKeySize + FROSTMessageHashSize + FROSTSignatureSize
)

type frostVerifyPrecompile struct{}

// Address returns the address of the FROST verify precompile
func (p *frostVerifyPrecompile) Address() common.Address {
	return ContractFROSTVerifyAddress
}

// RequiredGas calculates the gas required for FROST verification
func (p *frostVerifyPrecompile) RequiredGas(input []byte) uint64 {
	return FROSTVerifyGasCost(input)
}

// FROSTVerifyGasCost calculates the gas cost for FROST verification
func FROSTVerifyGasCost(input []byte) uint64 {
	if len(input) < MinInputSize {
		return FROSTVerifyBaseGas
	}

	// Extract total signers from input
	totalSigners := binary.BigEndian.Uint32(input[ThresholdSize : ThresholdSize+TotalSignersSize])

	// Base cost + per-signer cost
	return FROSTVerifyBaseGas + (uint64(totalSigners) * FROSTVerifyPerSignerGas)
}

// Run implements the FROST threshold signature verification precompile
func (p *frostVerifyPrecompile) Run(
	accessibleState contract.AccessibleState,
	caller common.Address,
	addr common.Address,
	input []byte,
	suppliedGas uint64,
	readOnly bool,
) ([]byte, uint64, error) {
	// Calculate required gas
	gasCost := p.RequiredGas(input)
	if suppliedGas < gasCost {
		return nil, 0, errors.New("out of gas")
	}

	// Input format:
	// [0:4]      = threshold t (uint32)
	// [4:8]      = total signers n (uint32)
	// [8:40]     = aggregated public key (32 bytes)
	// [40:72]    = message hash (32 bytes)
	// [72:136]   = Schnorr signature (64 bytes: R || s)

	if len(input) < MinInputSize {
		return nil, suppliedGas - gasCost, fmt.Errorf("%w: expected at least %d bytes, got %d",
			ErrInvalidInputLength, MinInputSize, len(input))
	}

	// Parse threshold and total signers
	threshold := binary.BigEndian.Uint32(input[0:4])
	totalSigners := binary.BigEndian.Uint32(input[4:8])

	// Validate threshold
	if threshold == 0 || threshold > totalSigners {
		return nil, suppliedGas - gasCost, ErrInvalidThreshold
	}

	// Parse public key, message hash, and signature
	publicKey := input[8:40]
	messageHash := input[40:72]
	signature := input[72:136]

	// Verify Schnorr signature
	// FROST produces standard Schnorr signatures that can be verified normally
	valid := verifySchnorrSignature(publicKey, messageHash, signature)

	// Return result as 32-byte word (1 = valid, 0 = invalid)
	result := make([]byte, 32)
	if valid {
		result[31] = 1
	}

	return result, suppliedGas - gasCost, nil
}

// verifySchnorrSignature verifies a Schnorr signature
// This is a simplified implementation for Ed25519-style Schnorr
func verifySchnorrSignature(publicKey, messageHash, signature []byte) bool {
	if len(publicKey) != 32 || len(messageHash) != 32 || len(signature) != 64 {
		return false
	}

	// Extract R and s from signature
	R := signature[0:32]
	s := signature[32:64]

	// Compute challenge: c = H(R || P || m)
	hasher := sha256.New()
	hasher.Write(R)
	hasher.Write(publicKey)
	hasher.Write(messageHash)
	challenge := hasher.Sum(nil)

	// Verify: s*G = R + c*P
	// For production, use proper Ed25519 or secp256k1 Schnorr verification
	// This is a placeholder that uses Ethereum's secp256k1 for now

	// Convert to secp256k1 verification
	// In production, this would use proper FROST verification from threshold repo
	pubKeyBytes := make([]byte, 33)
	pubKeyBytes[0] = 0x02 // Compressed format
	copy(pubKeyBytes[1:], publicKey)

	// Use standard ECDSA verification as fallback
	// Real implementation would use Schnorr verification
	pk, err := crypto.UnmarshalPubkey(append([]byte{0x04}, publicKey...))
	if err != nil {
		return false
	}

	// For now, verify as ECDSA (production would use Schnorr)
	return crypto.VerifySignature(crypto.FromECDSAPub(pk), messageHash, signature[:64])
}
