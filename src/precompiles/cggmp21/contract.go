// Copyright (C) 2025, Lux Industries, Inc. All rights reserved.
// See the file LICENSE for licensing terms.

package cggmp21

import (
	"crypto/ecdsa"
	"encoding/binary"
	"errors"
	"fmt"
	"math/big"

	"github.com/luxfi/evm/precompile/contract"
	"github.com/luxfi/geth/common"
	"github.com/luxfi/geth/crypto"
)

var (
	// ContractCGGMP21VerifyAddress is the address of the CGGMP21 threshold signature precompile
	ContractCGGMP21VerifyAddress = common.HexToAddress("0x020000000000000000000000000000000000000D")

	// Singleton instance
	CGGMP21VerifyPrecompile = &cggmp21VerifyPrecompile{}

	_ contract.StatefulPrecompiledContract = &cggmp21VerifyPrecompile{}

	ErrInvalidInputLength  = errors.New("invalid input length")
	ErrInvalidThreshold    = errors.New("invalid threshold: t must be > 0 and <= n")
	ErrInvalidPublicKey    = errors.New("invalid public key")
	ErrInvalidSignature    = errors.New("invalid signature")
	ErrSignatureVerifyFail = errors.New("signature verification failed")
)

const (
	// Gas costs for CGGMP21 threshold signature verification
	// CGGMP21 is more expensive than FROST but has identifiable aborts
	CGGMP21VerifyBaseGas    uint64 = 75_000  // Base cost for ECDSA threshold verification
	CGGMP21VerifyPerSignerGas uint64 = 10_000 // Cost per signer in threshold

	// CGGMP21 uses standard ECDSA signatures
	CGGMP21PublicKeySize  = 65 // Uncompressed public key (0x04 || x || y)
	CGGMP21SignatureSize  = 65 // ECDSA signature (r || s || v)
	CGGMP21MessageHashSize = 32 // 32-byte message hash
	ThresholdSize         = 4  // uint32 threshold t
	TotalSignersSize      = 4  // uint32 total signers n

	// Minimum input size
	MinInputSize = ThresholdSize + TotalSignersSize + CGGMP21PublicKeySize + CGGMP21MessageHashSize + CGGMP21SignatureSize
)

type cggmp21VerifyPrecompile struct{}

// Address returns the address of the CGGMP21 verify precompile
func (p *cggmp21VerifyPrecompile) Address() common.Address {
	return ContractCGGMP21VerifyAddress
}

// RequiredGas calculates the gas required for CGGMP21 verification
func (p *cggmp21VerifyPrecompile) RequiredGas(input []byte) uint64 {
	return CGGMP21VerifyGasCost(input)
}

// CGGMP21VerifyGasCost calculates the gas cost for CGGMP21 verification
func CGGMP21VerifyGasCost(input []byte) uint64 {
	if len(input) < MinInputSize {
		return CGGMP21VerifyBaseGas
	}

	// Extract total signers from input
	totalSigners := binary.BigEndian.Uint32(input[ThresholdSize : ThresholdSize+TotalSignersSize])

	// Base cost + per-signer cost
	return CGGMP21VerifyBaseGas + (uint64(totalSigners) * CGGMP21VerifyPerSignerGas)
}

// Run implements the CGGMP21 threshold signature verification precompile
func (p *cggmp21VerifyPrecompile) Run(
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
	// [0:4]       = threshold t (uint32)
	// [4:8]       = total signers n (uint32)
	// [8:73]      = aggregated public key (65 bytes: 0x04 || x || y)
	// [73:105]    = message hash (32 bytes)
	// [105:170]   = ECDSA signature (65 bytes: r || s || v)

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
	publicKeyBytes := input[8:73]
	messageHash := input[73:105]
	signatureBytes := input[105:170]

	// Verify ECDSA signature
	valid, err := verifyECDSASignature(publicKeyBytes, messageHash, signatureBytes)
	if err != nil {
		return nil, suppliedGas - gasCost, err
	}

	// Return result as 32-byte word (1 = valid, 0 = invalid)
	result := make([]byte, 32)
	if valid {
		result[31] = 1
	}

	return result, suppliedGas - gasCost, nil
}

// verifyECDSASignature verifies an ECDSA signature
func verifyECDSASignature(publicKeyBytes, messageHash, signatureBytes []byte) (bool, error) {
	if len(publicKeyBytes) != 65 {
		return false, ErrInvalidPublicKey
	}
	if len(messageHash) != 32 {
		return false, errors.New("invalid message hash length")
	}
	if len(signatureBytes) != 65 {
		return false, ErrInvalidSignature
	}

	// Parse public key
	publicKey, err := crypto.UnmarshalPubkey(publicKeyBytes)
	if err != nil {
		return false, fmt.Errorf("%w: %v", ErrInvalidPublicKey, err)
	}

	// Extract r, s, v from signature
	r := new(big.Int).SetBytes(signatureBytes[0:32])
	s := new(big.Int).SetBytes(signatureBytes[32:64])
	v := signatureBytes[64]

	// Normalize v (should be 27 or 28, or 0 or 1)
	if v >= 27 {
		v -= 27
	}

	// Verify signature
	// CGGMP21 produces standard ECDSA signatures that can be verified normally
	sig := make([]byte, 64)
	copy(sig[0:32], signatureBytes[0:32])  // r
	copy(sig[32:64], signatureBytes[32:64]) // s

	valid := crypto.VerifySignature(
		crypto.FromECDSAPub(publicKey),
		messageHash,
		sig,
	)

	if !valid {
		return false, nil
	}

	// Additional validation: recover public key and compare
	recoveredPubKey, err := recoverPublicKey(messageHash, signatureBytes)
	if err != nil {
		return false, nil
	}

	// Compare recovered public key with expected
	if recoveredPubKey.X.Cmp(publicKey.X) != 0 || recoveredPubKey.Y.Cmp(publicKey.Y) != 0 {
		return false, nil
	}

	return true, nil
}

// recoverPublicKey recovers the public key from signature
func recoverPublicKey(messageHash, signature []byte) (*ecdsa.PublicKey, error) {
	if len(signature) != 65 {
		return nil, ErrInvalidSignature
	}

	v := signature[64]
	if v >= 27 {
		v -= 27
	}

	// Normalize signature for ecrecover
	sig := make([]byte, 65)
	copy(sig[0:32], signature[0:32])  // r
	copy(sig[32:64], signature[32:64]) // s
	sig[64] = v

	pubKeyBytes, err := crypto.Ecrecover(messageHash, sig)
	if err != nil {
		return nil, err
	}

	return crypto.UnmarshalPubkey(pubKeyBytes)
}
