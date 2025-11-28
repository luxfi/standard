// Copyright (C) 2025, Lux Industries, Inc. All rights reserved.
// See the file LICENSE for licensing terms.

package mldsa

import (
	"errors"
	"fmt"

	"github.com/luxfi/crypto/mldsa"
	"github.com/luxfi/evm/precompile/contract"
	"github.com/luxfi/geth/common"
)

var (
	// ContractMLDSAVerifyAddress is the address of the ML-DSA verify precompile
	ContractMLDSAVerifyAddress = common.HexToAddress("0x0200000000000000000000000000000000000006")

	// Singleton instance
	MLDSAVerifyPrecompile = &mldsaVerifyPrecompile{}

	_ contract.StatefulPrecompiledContract = &mldsaVerifyPrecompile{}

	ErrInvalidInputLength = errors.New("invalid input length")
)

const (
	// Gas cost for ML-DSA-65 verification
	// Based on benchmarks: ~108μs verify time on M1
	// Relative to ecrecover (3000 gas for ~50μs) ≈ 6480 gas per 108μs
	MLDSAVerifyBaseGas    uint64 = 100_000 // Base cost for signature verification
	MLDSAVerifyPerByteGas uint64 = 10      // Cost per byte of message

	// ML-DSA-65 constants
	ML_DSA_PublicKeySize  = 1952 // ML-DSA-65 public key size
	ML_DSA_SignatureSize  = 3309 // ML-DSA-65 signature size
	ML_DSA_MessageLenSize = 32   // Size of message length field

	// Minimum input size: public key + message length + signature
	MinInputSize = ML_DSA_PublicKeySize + ML_DSA_MessageLenSize + ML_DSA_SignatureSize
)

type mldsaVerifyPrecompile struct{}

// Address returns the address of the ML-DSA verify precompile
func (p *mldsaVerifyPrecompile) Address() common.Address {
	return ContractMLDSAVerifyAddress
}

// RequiredGas calculates the gas required for ML-DSA verification
func (p *mldsaVerifyPrecompile) RequiredGas(input []byte) uint64 {
	return MLDSAVerifyGasCost(input)
}

// MLDSAVerifyGasCost calculates the gas cost for ML-DSA verification
func MLDSAVerifyGasCost(input []byte) uint64 {
	if len(input) < MinInputSize {
		return MLDSAVerifyBaseGas
	}

	// Extract message length from input
	msgLenBytes := input[ML_DSA_PublicKeySize : ML_DSA_PublicKeySize+ML_DSA_MessageLenSize]
	msgLen := readUint256(msgLenBytes)

	// Base cost + per-byte cost for message
	return MLDSAVerifyBaseGas + (msgLen * MLDSAVerifyPerByteGas)
}

// Run implements the ML-DSA signature verification precompile
func (p *mldsaVerifyPrecompile) Run(
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
	// [0:1952]       = ML-DSA-65 public key (1952 bytes)
	// [1952:1984]    = message length as uint256 (32 bytes)
	// [1984:5293]    = ML-DSA-65 signature (3309 bytes)
	// [5293:...]     = message (variable length)

	if len(input) < MinInputSize {
		return nil, suppliedGas - gasCost, fmt.Errorf("%w: expected at least %d bytes, got %d",
			ErrInvalidInputLength, MinInputSize, len(input))
	}

	// Parse input
	publicKey := input[0:ML_DSA_PublicKeySize]
	messageLenBytes := input[ML_DSA_PublicKeySize : ML_DSA_PublicKeySize+ML_DSA_MessageLenSize]
	signature := input[ML_DSA_PublicKeySize+ML_DSA_MessageLenSize : ML_DSA_PublicKeySize+ML_DSA_MessageLenSize+ML_DSA_SignatureSize]

	// Read message length
	messageLen := readUint256(messageLenBytes)

	// Validate total input size
	expectedSize := MinInputSize + messageLen
	if uint64(len(input)) != expectedSize {
		return nil, suppliedGas - gasCost, fmt.Errorf("%w: expected %d bytes total, got %d",
			ErrInvalidInputLength, expectedSize, len(input))
	}

	// Extract message
	message := input[MinInputSize:expectedSize]

	// Parse public key from bytes (ML-DSA-65 mode)
	pub, err := mldsa.PublicKeyFromBytes(publicKey, mldsa.MLDSA65)
	if err != nil {
		return nil, suppliedGas - gasCost, fmt.Errorf("invalid public key: %w", err)
	}

	// Verify signature using public key method
	valid := pub.Verify(message, signature, nil)

	// Return result as 32-byte word (1 = valid, 0 = invalid)
	result := make([]byte, 32)
	if valid {
		result[31] = 1
	}

	return result, suppliedGas - gasCost, nil
}

// readUint256 reads a big-endian uint256 as uint64
func readUint256(b []byte) uint64 {
	if len(b) != 32 {
		return 0
	}
	// Only read last 8 bytes (assume high bytes are 0 for reasonable message lengths)
	return uint64(b[24])<<56 | uint64(b[25])<<48 | uint64(b[26])<<40 | uint64(b[27])<<32 |
		uint64(b[28])<<24 | uint64(b[29])<<16 | uint64(b[30])<<8 | uint64(b[31])
}
