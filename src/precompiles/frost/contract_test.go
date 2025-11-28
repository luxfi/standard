// Copyright (C) 2025, Lux Industries, Inc. All rights reserved.
// See the file LICENSE for licensing terms.

package frost

import (
	"crypto/sha256"
	"encoding/binary"
	"testing"

	"github.com/luxfi/evm/precompile/contract"
	"github.com/luxfi/geth/common"
	"github.com/stretchr/testify/require"
)

func TestFROSTVerify_ValidSignature(t *testing.T) {
	precompile := FROSTVerifyPrecompile

	// Create test input with valid threshold parameters
	input := make([]byte, MinInputSize)

	// threshold = 3, total signers = 5
	binary.BigEndian.PutUint32(input[0:4], 3)
	binary.BigEndian.PutUint32(input[4:8], 5)

	// Mock public key (32 bytes)
	publicKey := make([]byte, 32)
	for i := range publicKey {
		publicKey[i] = byte(i)
	}
	copy(input[8:40], publicKey)

	// Message hash
	messageHash := sha256.Sum256([]byte("test message"))
	copy(input[40:72], messageHash[:])

	// Mock signature (64 bytes)
	signature := make([]byte, 64)
	for i := range signature {
		signature[i] = byte(i)
	}
	copy(input[72:136], signature)

	// Run precompile
	result, remainingGas, err := precompile.Run(
		nil,
		common.Address{},
		ContractFROSTVerifyAddress,
		input,
		1_000_000,
		true,
	)

	// Should not error (even if verification fails, it returns 0)
	require.NoError(t, err)
	require.NotNil(t, result)
	require.Len(t, result, 32)
	require.Greater(t, remainingGas, uint64(0))
}

func TestFROSTVerify_InvalidThreshold(t *testing.T) {
	precompile := FROSTVerifyPrecompile

	input := make([]byte, MinInputSize)

	// Invalid: threshold = 0
	binary.BigEndian.PutUint32(input[0:4], 0)
	binary.BigEndian.PutUint32(input[4:8], 5)

	_, _, err := precompile.Run(
		nil,
		common.Address{},
		ContractFROSTVerifyAddress,
		input,
		1_000_000,
		true,
	)

	require.Error(t, err)
	require.ErrorIs(t, err, ErrInvalidThreshold)
}

func TestFROSTVerify_ThresholdGreaterThanTotal(t *testing.T) {
	precompile := FROSTVerifyPrecompile

	input := make([]byte, MinInputSize)

	// Invalid: threshold > total
	binary.BigEndian.PutUint32(input[0:4], 6)
	binary.BigEndian.PutUint32(input[4:8], 5)

	_, _, err := precompile.Run(
		nil,
		common.Address{},
		ContractFROSTVerifyAddress,
		input,
		1_000_000,
		true,
	)

	require.Error(t, err)
	require.ErrorIs(t, err, ErrInvalidThreshold)
}

func TestFROSTVerify_InputTooShort(t *testing.T) {
	precompile := FROSTVerifyPrecompile

	input := make([]byte, MinInputSize-1)

	_, _, err := precompile.Run(
		nil,
		common.Address{},
		ContractFROSTVerifyAddress,
		input,
		1_000_000,
		true,
	)

	require.Error(t, err)
	require.ErrorIs(t, err, ErrInvalidInputLength)
}

func TestFROSTVerify_GasCost(t *testing.T) {
	tests := []struct {
		name          string
		threshold     uint32
		totalSigners  uint32
		expectedGas   uint64
	}{
		{"2-of-3", 2, 3, FROSTVerifyBaseGas + 3*FROSTVerifyPerSignerGas},
		{"3-of-5", 3, 5, FROSTVerifyBaseGas + 5*FROSTVerifyPerSignerGas},
		{"5-of-7", 5, 7, FROSTVerifyBaseGas + 7*FROSTVerifyPerSignerGas},
		{"10-of-15", 10, 15, FROSTVerifyBaseGas + 15*FROSTVerifyPerSignerGas},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			input := make([]byte, MinInputSize)
			binary.BigEndian.PutUint32(input[0:4], tt.threshold)
			binary.BigEndian.PutUint32(input[4:8], tt.totalSigners)

			gasCost := FROSTVerifyGasCost(input)
			require.Equal(t, tt.expectedGas, gasCost)
		})
	}
}

func TestFROSTVerify_Address(t *testing.T) {
	precompile := FROSTVerifyPrecompile
	require.Equal(t, ContractFROSTVerifyAddress, precompile.Address())
}

func BenchmarkFROSTVerify_3of5(b *testing.B) {
	precompile := FROSTVerifyPrecompile

	input := make([]byte, MinInputSize)
	binary.BigEndian.PutUint32(input[0:4], 3)
	binary.BigEndian.PutUint32(input[4:8], 5)

	// Fill with test data
	for i := 8; i < MinInputSize; i++ {
		input[i] = byte(i)
	}

	b.ResetTimer()
	for i := 0; i < b.N; i++ {
		_, _, _ = precompile.Run(
			nil,
			common.Address{},
			ContractFROSTVerifyAddress,
			input,
			1_000_000,
			true,
		)
	}
}

func BenchmarkFROSTVerify_10of15(b *testing.B) {
	precompile := FROSTVerifyPrecompile

	input := make([]byte, MinInputSize)
	binary.BigEndian.PutUint32(input[0:4], 10)
	binary.BigEndian.PutUint32(input[4:8], 15)

	// Fill with test data
	for i := 8; i < MinInputSize; i++ {
		input[i] = byte(i)
	}

	b.ResetTimer()
	for i := 0; i < b.N; i++ {
		_, _, _ = precompile.Run(
			nil,
			common.Address{},
			ContractFROSTVerifyAddress,
			input,
			1_000_000,
			true,
		)
	}
}
