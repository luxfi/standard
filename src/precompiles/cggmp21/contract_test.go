// Copyright (C) 2025, Lux Industries, Inc. All rights reserved.
// See the file LICENSE for licensing terms.

package cggmp21

import (
	"crypto/ecdsa"
	"crypto/rand"
	"encoding/binary"
	"testing"

	"github.com/luxfi/geth/common"
	"github.com/luxfi/geth/crypto"
	"github.com/stretchr/testify/require"
)

func TestCGGMP21Verify_ValidSignature(t *testing.T) {
	precompile := CGGMP21VerifyPrecompile

	// Generate a test key pair
	privateKey, err := ecdsa.GenerateKey(crypto.S256(), rand.Reader)
	require.NoError(t, err)

	publicKey := crypto.FromECDSAPub(&privateKey.PublicKey)
	messageHash := crypto.Keccak256([]byte("test message"))

	// Sign the message
	signature, err := crypto.Sign(messageHash, privateKey)
	require.NoError(t, err)

	// Create input
	input := make([]byte, MinInputSize)

	// threshold = 3, total signers = 5
	binary.BigEndian.PutUint32(input[0:4], 3)
	binary.BigEndian.PutUint32(input[4:8], 5)

	// Public key (uncompressed)
	copy(input[8:73], publicKey)

	// Message hash
	copy(input[73:105], messageHash)

	// Signature
	copy(input[105:170], signature)

	// Run precompile
	result, remainingGas, err := precompile.Run(
		nil,
		common.Address{},
		ContractCGGMP21VerifyAddress,
		input,
		1_000_000,
		true,
	)

	require.NoError(t, err)
	require.NotNil(t, result)
	require.Len(t, result, 32)
	require.Greater(t, remainingGas, uint64(0))

	// Check if signature is valid
	isValid := result[31] == 1
	require.True(t, isValid, "Signature should be valid")
}

func TestCGGMP21Verify_InvalidSignature(t *testing.T) {
	precompile := CGGMP21VerifyPrecompile

	// Generate a test key pair
	privateKey, err := ecdsa.GenerateKey(crypto.S256(), rand.Reader)
	require.NoError(t, err)

	publicKey := crypto.FromECDSAPub(&privateKey.PublicKey)
	messageHash := crypto.Keccak256([]byte("test message"))

	// Sign the message
	signature, err := crypto.Sign(messageHash, privateKey)
	require.NoError(t, err)

	// Corrupt the signature
	signature[10] ^= 0xFF

	// Create input
	input := make([]byte, MinInputSize)
	binary.BigEndian.PutUint32(input[0:4], 3)
	binary.BigEndian.PutUint32(input[4:8], 5)
	copy(input[8:73], publicKey)
	copy(input[73:105], messageHash)
	copy(input[105:170], signature)

	// Run precompile
	result, remainingGas, err := precompile.Run(
		nil,
		common.Address{},
		ContractCGGMP21VerifyAddress,
		input,
		1_000_000,
		true,
	)

	require.NoError(t, err)
	require.NotNil(t, result)
	require.Len(t, result, 32)
	require.Greater(t, remainingGas, uint64(0))

	// Check if signature is invalid
	isValid := result[31] == 1
	require.False(t, isValid, "Signature should be invalid")
}

func TestCGGMP21Verify_WrongMessage(t *testing.T) {
	precompile := CGGMP21VerifyPrecompile

	// Generate a test key pair
	privateKey, err := ecdsa.GenerateKey(crypto.S256(), rand.Reader)
	require.NoError(t, err)

	publicKey := crypto.FromECDSAPub(&privateKey.PublicKey)
	messageHash := crypto.Keccak256([]byte("original message"))

	// Sign the message
	signature, err := crypto.Sign(messageHash, privateKey)
	require.NoError(t, err)

	// Use different message hash
	wrongMessageHash := crypto.Keccak256([]byte("wrong message"))

	// Create input
	input := make([]byte, MinInputSize)
	binary.BigEndian.PutUint32(input[0:4], 3)
	binary.BigEndian.PutUint32(input[4:8], 5)
	copy(input[8:73], publicKey)
	copy(input[73:105], wrongMessageHash)
	copy(input[105:170], signature)

	// Run precompile
	result, _, err := precompile.Run(
		nil,
		common.Address{},
		ContractCGGMP21VerifyAddress,
		input,
		1_000_000,
		true,
	)

	require.NoError(t, err)
	require.NotNil(t, result)

	// Check if signature is invalid
	isValid := result[31] == 1
	require.False(t, isValid, "Signature should be invalid for wrong message")
}

func TestCGGMP21Verify_InvalidThreshold(t *testing.T) {
	precompile := CGGMP21VerifyPrecompile

	input := make([]byte, MinInputSize)

	// Invalid: threshold = 0
	binary.BigEndian.PutUint32(input[0:4], 0)
	binary.BigEndian.PutUint32(input[4:8], 5)

	_, _, err := precompile.Run(
		nil,
		common.Address{},
		ContractCGGMP21VerifyAddress,
		input,
		1_000_000,
		true,
	)

	require.Error(t, err)
	require.ErrorIs(t, err, ErrInvalidThreshold)
}

func TestCGGMP21Verify_ThresholdGreaterThanTotal(t *testing.T) {
	precompile := CGGMP21VerifyPrecompile

	input := make([]byte, MinInputSize)

	// Invalid: threshold > total
	binary.BigEndian.PutUint32(input[0:4], 6)
	binary.BigEndian.PutUint32(input[4:8], 5)

	_, _, err := precompile.Run(
		nil,
		common.Address{},
		ContractCGGMP21VerifyAddress,
		input,
		1_000_000,
		true,
	)

	require.Error(t, err)
	require.ErrorIs(t, err, ErrInvalidThreshold)
}

func TestCGGMP21Verify_InputTooShort(t *testing.T) {
	precompile := CGGMP21VerifyPrecompile

	input := make([]byte, MinInputSize-1)

	_, _, err := precompile.Run(
		nil,
		common.Address{},
		ContractCGGMP21VerifyAddress,
		input,
		1_000_000,
		true,
	)

	require.Error(t, err)
	require.ErrorIs(t, err, ErrInvalidInputLength)
}

func TestCGGMP21Verify_GasCost(t *testing.T) {
	tests := []struct {
		name          string
		threshold     uint32
		totalSigners  uint32
		expectedGas   uint64
	}{
		{"2-of-3", 2, 3, CGGMP21VerifyBaseGas + 3*CGGMP21VerifyPerSignerGas},
		{"3-of-5", 3, 5, CGGMP21VerifyBaseGas + 5*CGGMP21VerifyPerSignerGas},
		{"5-of-7", 5, 7, CGGMP21VerifyBaseGas + 7*CGGMP21VerifyPerSignerGas},
		{"10-of-15", 10, 15, CGGMP21VerifyBaseGas + 15*CGGMP21VerifyPerSignerGas},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			input := make([]byte, MinInputSize)
			binary.BigEndian.PutUint32(input[0:4], tt.threshold)
			binary.BigEndian.PutUint32(input[4:8], tt.totalSigners)

			gasCost := CGGMP21VerifyGasCost(input)
			require.Equal(t, tt.expectedGas, gasCost)
		})
	}
}

func TestCGGMP21Verify_Address(t *testing.T) {
	precompile := CGGMP21VerifyPrecompile
	require.Equal(t, ContractCGGMP21VerifyAddress, precompile.Address())
}

func BenchmarkCGGMP21Verify_3of5(b *testing.B) {
	precompile := CGGMP21VerifyPrecompile

	// Generate test data
	privateKey, _ := ecdsa.GenerateKey(crypto.S256(), rand.Reader)
	publicKey := crypto.FromECDSAPub(&privateKey.PublicKey)
	messageHash := crypto.Keccak256([]byte("benchmark message"))
	signature, _ := crypto.Sign(messageHash, privateKey)

	input := make([]byte, MinInputSize)
	binary.BigEndian.PutUint32(input[0:4], 3)
	binary.BigEndian.PutUint32(input[4:8], 5)
	copy(input[8:73], publicKey)
	copy(input[73:105], messageHash)
	copy(input[105:170], signature)

	b.ResetTimer()
	for i := 0; i < b.N; i++ {
		_, _, _ = precompile.Run(
			nil,
			common.Address{},
			ContractCGGMP21VerifyAddress,
			input,
			1_000_000,
			true,
		)
	}
}

func BenchmarkCGGMP21Verify_10of15(b *testing.B) {
	precompile := CGGMP21VerifyPrecompile

	// Generate test data
	privateKey, _ := ecdsa.GenerateKey(crypto.S256(), rand.Reader)
	publicKey := crypto.FromECDSAPub(&privateKey.PublicKey)
	messageHash := crypto.Keccak256([]byte("benchmark message"))
	signature, _ := crypto.Sign(messageHash, privateKey)

	input := make([]byte, MinInputSize)
	binary.BigEndian.PutUint32(input[0:4], 10)
	binary.BigEndian.PutUint32(input[4:8], 15)
	copy(input[8:73], publicKey)
	copy(input[73:105], messageHash)
	copy(input[105:170], signature)

	b.ResetTimer()
	for i := 0; i < b.N; i++ {
		_, _, _ = precompile.Run(
			nil,
			common.Address{},
			ContractCGGMP21VerifyAddress,
			input,
			1_000_000,
			true,
		)
	}
}
