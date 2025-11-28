// Copyright (C) 2025, Lux Industries, Inc. All rights reserved.
// See the file LICENSE for licensing terms.

package slhdsa

import (
	"encoding/binary"
	"testing"

	"github.com/cloudflare/circl/sign/slh-dsa/slhdsa128s"
	"github.com/luxfi/evm/precompile/contract"
	"github.com/stretchr/testify/require"
)

// TestSLHDSAVerify_ValidSignature tests successful signature verification
func TestSLHDSAVerify_ValidSignature(t *testing.T) {
	// Generate test key pair
	pk, sk := slhdsa128s.GenerateKey()
	message := []byte("test message for SLH-DSA signature verification")

	// Sign message
	signature := slhdsa128s.Sign(sk, message, nil)

	// Prepare input for precompile
	input := prepareInput(pk[:], message, signature)

	// Run precompile
	precompile := &slhdsaVerifyPrecompile{}
	result, _, err := precompile.Run(nil, mockAddress(), mockAddress(), input, 1_000_000, true)

	require.NoError(t, err)
	require.Equal(t, byte(1), result[31], "signature should be valid")
}

// TestSLHDSAVerify_InvalidSignature tests rejection of invalid signatures
func TestSLHDSAVerify_InvalidSignature(t *testing.T) {
	// Generate test key pair
	pk, sk := slhdsa128s.GenerateKey()
	message := []byte("original message")

	// Sign message
	signature := slhdsa128s.Sign(sk, message, nil)

	// Corrupt signature
	signature[0] ^= 0xFF

	// Prepare input for precompile
	input := prepareInput(pk[:], message, signature)

	// Run precompile
	precompile := &slhdsaVerifyPrecompile{}
	result, _, err := precompile.Run(nil, mockAddress(), mockAddress(), input, 1_000_000, true)

	require.NoError(t, err)
	require.Equal(t, byte(0), result[31], "corrupted signature should be invalid")
}

// TestSLHDSAVerify_WrongMessage tests rejection when message doesn't match
func TestSLHDSAVerify_WrongMessage(t *testing.T) {
	// Generate test key pair
	pk, sk := slhdsa128s.GenerateKey()
	originalMessage := []byte("original message")
	wrongMessage := []byte("wrong message!!!")

	// Sign original message
	signature := slhdsa128s.Sign(sk, originalMessage, nil)

	// Verify with wrong message
	input := prepareInput(pk[:], wrongMessage, signature)

	// Run precompile
	precompile := &slhdsaVerifyPrecompile{}
	result, _, err := precompile.Run(nil, mockAddress(), mockAddress(), input, 1_000_000, true)

	require.NoError(t, err)
	require.Equal(t, byte(0), result[31], "signature for different message should be invalid")
}

// TestSLHDSAVerify_InputTooShort tests error handling for insufficient input
func TestSLHDSAVerify_InputTooShort(t *testing.T) {
	input := make([]byte, MinInputSize-1)

	precompile := &slhdsaVerifyPrecompile{}
	_, _, err := precompile.Run(nil, mockAddress(), mockAddress(), input, 1_000_000, true)

	require.Error(t, err)
	require.Contains(t, err.Error(), "invalid input length")
}

// TestSLHDSAVerify_EmptyMessage tests verification with empty message
func TestSLHDSAVerify_EmptyMessage(t *testing.T) {
	// Generate test key pair
	pk, sk := slhdsa128s.GenerateKey()
	message := []byte{}

	// Sign empty message
	signature := slhdsa128s.Sign(sk, message, nil)

	// Prepare input for precompile
	input := prepareInput(pk[:], message, signature)

	// Run precompile
	precompile := &slhdsaVerifyPrecompile{}
	result, _, err := precompile.Run(nil, mockAddress(), mockAddress(), input, 1_000_000, true)

	require.NoError(t, err)
	require.Equal(t, byte(1), result[31], "signature for empty message should be valid")
}

// TestSLHDSAVerify_LargeMessage tests verification with large message
func TestSLHDSAVerify_LargeMessage(t *testing.T) {
	// Generate test key pair
	pk, sk := slhdsa128s.GenerateKey()

	// Create 10KB message
	message := make([]byte, 10*1024)
	for i := range message {
		message[i] = byte(i % 256)
	}

	// Sign large message
	signature := slhdsa128s.Sign(sk, message, nil)

	// Prepare input for precompile
	input := prepareInput(pk[:], message, signature)

	// Calculate expected gas
	expectedGas := SLHDSAVerifyBaseGas + uint64(len(message))*SLHDSAVerifyPerByteGas

	// Run precompile with sufficient gas
	precompile := &slhdsaVerifyPrecompile{}
	result, gasUsed, err := precompile.Run(nil, mockAddress(), mockAddress(), input, expectedGas+100_000, true)

	require.NoError(t, err)
	require.Equal(t, byte(1), result[31], "signature for large message should be valid")
	require.Equal(t, expectedGas, gasUsed, "gas calculation should match expected")
}

// TestSLHDSAVerify_GasCost tests gas cost calculation
func TestSLHDSAVerify_GasCost(t *testing.T) {
	tests := []struct {
		name        string
		messageSize uint64
		expectedGas uint64
	}{
		{
			name:        "empty message",
			messageSize: 0,
			expectedGas: SLHDSAVerifyBaseGas,
		},
		{
			name:        "small message (100 bytes)",
			messageSize: 100,
			expectedGas: SLHDSAVerifyBaseGas + 100*SLHDSAVerifyPerByteGas,
		},
		{
			name:        "medium message (1KB)",
			messageSize: 1024,
			expectedGas: SLHDSAVerifyBaseGas + 1024*SLHDSAVerifyPerByteGas,
		},
		{
			name:        "large message (10KB)",
			messageSize: 10 * 1024,
			expectedGas: SLHDSAVerifyBaseGas + 10*1024*SLHDSAVerifyPerByteGas,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			// Generate test key pair
			pk, sk := slhdsa128s.GenerateKey()

			// Create message of specified size
			message := make([]byte, tt.messageSize)
			signature := slhdsa128s.Sign(sk, message, nil)

			// Prepare input
			input := prepareInput(pk[:], message, signature)

			// Calculate gas cost
			precompile := &slhdsaVerifyPrecompile{}
			actualGas := precompile.RequiredGas(input)

			require.Equal(t, tt.expectedGas, actualGas, "gas cost should match expected")
		})
	}
}

// TestSLHDSAPrecompile_Address tests precompile address
func TestSLHDSAPrecompile_Address(t *testing.T) {
	precompile := &slhdsaVerifyPrecompile{}
	expectedAddress := ContractSLHDSAVerifyAddress

	require.Equal(t, expectedAddress, precompile.Address())
}

// TestSLHDSAVerify_OutOfGas tests out of gas error
func TestSLHDSAVerify_OutOfGas(t *testing.T) {
	// Generate test key pair
	pk, sk := slhdsa128s.GenerateKey()
	message := []byte("test message")
	signature := slhdsa128s.Sign(sk, message, nil)

	// Prepare input
	input := prepareInput(pk[:], message, signature)

	// Run with insufficient gas
	precompile := &slhdsaVerifyPrecompile{}
	_, _, err := precompile.Run(nil, mockAddress(), mockAddress(), input, 1000, true)

	require.Error(t, err)
	require.Contains(t, err.Error(), "out of gas")
}

// BenchmarkSLHDSAVerify_SmallMessage benchmarks verification with small message
func BenchmarkSLHDSAVerify_SmallMessage(b *testing.B) {
	pk, sk := slhdsa128s.GenerateKey()
	message := []byte("small test message")
	signature := slhdsa128s.Sign(sk, message, nil)
	input := prepareInput(pk[:], message, signature)

	precompile := &slhdsaVerifyPrecompile{}
	b.ResetTimer()

	for i := 0; i < b.N; i++ {
		_, _, _ = precompile.Run(nil, mockAddress(), mockAddress(), input, 1_000_000, true)
	}
}

// BenchmarkSLHDSAVerify_LargeMessage benchmarks verification with large message
func BenchmarkSLHDSAVerify_LargeMessage(b *testing.B) {
	pk, sk := slhdsa128s.GenerateKey()
	message := make([]byte, 10*1024)
	signature := slhdsa128s.Sign(sk, message, nil)
	input := prepareInput(pk[:], message, signature)

	precompile := &slhdsaVerifyPrecompile{}
	b.ResetTimer()

	for i := 0; i < b.N; i++ {
		_, _, _ = precompile.Run(nil, mockAddress(), mockAddress(), input, 2_000_000, true)
	}
}

// Helper functions

func prepareInput(publicKey, message, signature []byte) []byte {
	// Input format:
	// [0:32]     = public key (32 bytes)
	// [32:64]    = message length (32 bytes, big-endian uint256)
	// [64:7920]  = signature (7856 bytes)
	// [7920:...] = message (variable)

	messageLenBytes := make([]byte, 32)
	binary.BigEndian.PutUint64(messageLenBytes[24:], uint64(len(message)))

	input := make([]byte, 0, SLHDSA_PublicKeySize+SLHDSA_MessageLenSize+SLHDSA_SignatureSize+len(message))
	input = append(input, publicKey...)
	input = append(input, messageLenBytes...)
	input = append(input, signature...)
	input = append(input, message...)

	return input
}

func mockAddress() contract.Address {
	return contract.Address{}
}
