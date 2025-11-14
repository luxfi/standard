// Copyright (C) 2025, Lux Industries, Inc. All rights reserved.
// See the file LICENSE for licensing terms.

package mldsa

import (
	"testing"

	"github.com/luxfi/crypto/mldsa"
	"github.com/luxfi/geth/common"
	"github.com/stretchr/testify/require"
)

// Helper function to create test keys and signatures
func createTestSignature(t testing.TB, message []byte) ([]byte, []byte, []byte) {
	seed := make([]byte, 32)
	for i := range seed {
		seed[i] = byte(i)
	}

	sk, err := mldsa.NewSigningKey(mldsa.ModeML_DSA_65, seed)
	require.NoError(t, err)
	pk := sk.PublicKey()
	signature := sk.Sign(message, []byte(""))

	return pk, signature, message
}

func TestMLDSAVerify_ValidSignature(t *testing.T) {
	message := []byte("test message for ML-DSA-65 verification")
	pk, signature, msg := createTestSignature(t, message)

	// Prepare input: publicKey (1952 bytes) + message length (32 bytes) + signature (3309 bytes) + message
	input := make([]byte, 0)
	input = append(input, pk...)

	// Message length as big-endian uint256
	msgLen := make([]byte, 32)
	msgLen[31] = byte(len(msg))
	input = append(input, msgLen...)

	input = append(input, signature...)
	input = append(input, msg...)

	// Get required gas
	gas := MLDSAVerifyPrecompile.RequiredGas(input)

	// Call precompile
	ret, remainingGas, err := MLDSAVerifyPrecompile.Run(
		nil,
		common.Address{},
		ContractMLDSAVerifyAddress,
		input,
		gas,
		false,
	)

	require.NoError(t, err)
	require.NotNil(t, ret)
	require.Equal(t, uint64(0), remainingGas) // All gas consumed

	// Verify output is 32-byte word with value 1
	require.Len(t, ret, 32)
	require.Equal(t, byte(1), ret[31])
}

func TestMLDSAVerify_InvalidSignature(t *testing.T) {
	message := []byte("test message")
	pk, signature, msg := createTestSignature(t, message)

	// Modify signature to make it invalid
	signature[0] ^= 0xFF

	// Prepare input
	input := make([]byte, 0)
	input = append(input, pk...)

	msgLen := make([]byte, 32)
	msgLen[31] = byte(len(msg))
	input = append(input, msgLen...)

	input = append(input, signature...)
	input = append(input, msg...)

	// Get required gas
	gas := MLDSAVerifyPrecompile.RequiredGas(input)

	// Call precompile
	ret, _, err := MLDSAVerifyPrecompile.Run(
		nil,
		common.Address{},
		ContractMLDSAVerifyAddress,
		input,
		gas,
		false,
	)

	require.NoError(t, err)
	require.NotNil(t, ret)

	// Verify output is 32-byte word with value 0
	require.Len(t, ret, 32)
	require.Equal(t, byte(0), ret[31])
}

func TestMLDSAVerify_WrongMessage(t *testing.T) {
	message1 := []byte("original message")
	pk, signature, _ := createTestSignature(t, message1)

	message2 := []byte("different message")

	// Prepare input with wrong message
	input := make([]byte, 0)
	input = append(input, pk...)

	msgLen := make([]byte, 32)
	msgLen[31] = byte(len(message2))
	input = append(input, msgLen...)

	input = append(input, signature...)
	input = append(input, message2...)

	// Get required gas
	gas := MLDSAVerifyPrecompile.RequiredGas(input)

	// Call precompile
	ret, _, err := MLDSAVerifyPrecompile.Run(
		nil,
		common.Address{},
		ContractMLDSAVerifyAddress,
		input,
		gas,
		false,
	)

	require.NoError(t, err)
	require.NotNil(t, ret)
	require.Len(t, ret, 32)
	require.Equal(t, byte(0), ret[31])
}

func TestMLDSAVerify_InputTooShort(t *testing.T) {
	// Input too short (less than minimum required)
	input := make([]byte, 100)

	gas := MLDSAVerifyPrecompile.RequiredGas(input)

	ret, _, err := MLDSAVerifyPrecompile.Run(
		nil,
		common.Address{},
		ContractMLDSAVerifyAddress,
		input,
		gas,
		false,
	)

	require.Error(t, err)
	require.Nil(t, ret)
	require.Contains(t, err.Error(), "invalid input length")
}

func TestMLDSAVerify_EmptyMessage(t *testing.T) {
	message := []byte("")
	pk, signature, msg := createTestSignature(t, message)

	// Prepare input
	input := make([]byte, 0)
	input = append(input, pk...)

	msgLen := make([]byte, 32)
	// msgLen[31] = 0 (empty message)
	input = append(input, msgLen...)

	input = append(input, signature...)
	input = append(input, msg...)

	// Get required gas
	gas := MLDSAVerifyPrecompile.RequiredGas(input)

	// Call precompile
	ret, _, err := MLDSAVerifyPrecompile.Run(
		nil,
		common.Address{},
		ContractMLDSAVerifyAddress,
		input,
		gas,
		false,
	)

	require.NoError(t, err)
	require.NotNil(t, ret)
	require.Equal(t, byte(1), ret[31])
}

func TestMLDSAVerify_LargeMessage(t *testing.T) {
	// Create a large message (10KB)
	message := make([]byte, 10240)
	for i := range message {
		message[i] = byte(i % 256)
	}

	pk, signature, msg := createTestSignature(t, message)

	// Prepare input
	input := make([]byte, 0)
	input = append(input, pk...)

	msgLen := make([]byte, 32)
	msgLen[29] = byte(len(msg) >> 16)
	msgLen[30] = byte(len(msg) >> 8)
	msgLen[31] = byte(len(msg))
	input = append(input, msgLen...)

	input = append(input, signature...)
	input = append(input, msg...)

	// Get required gas
	gas := MLDSAVerifyPrecompile.RequiredGas(input)

	// Call precompile
	ret, _, err := MLDSAVerifyPrecompile.Run(
		nil,
		common.Address{},
		ContractMLDSAVerifyAddress,
		input,
		gas,
		false,
	)

	require.NoError(t, err)
	require.NotNil(t, ret)
	require.Equal(t, byte(1), ret[31])
}

func TestMLDSAVerify_GasCost(t *testing.T) {
	message := []byte("test")
	pk, signature, msg := createTestSignature(t, message)

	input := make([]byte, 0)
	input = append(input, pk...)
	msgLen := make([]byte, 32)
	msgLen[31] = byte(len(msg))
	input = append(input, msgLen...)
	input = append(input, signature...)
	input = append(input, msg...)

	// Calculate expected gas
	expectedGas := MLDSAVerifyGasCost(input)

	// Should be base cost + per-byte cost
	require.Greater(t, expectedGas, uint64(50000)) // Minimum base cost

	// Verify RequiredGas returns same value
	actualGas := MLDSAVerifyPrecompile.RequiredGas(input)
	require.Equal(t, expectedGas, actualGas)
}

func TestMLDSAPrecompile_Address(t *testing.T) {
	// Verify precompile is at correct address
	expectedAddr := common.HexToAddress("0x0200000000000000000000000000000000000006")
	require.Equal(t, expectedAddr, ContractMLDSAVerifyAddress)
	require.Equal(t, expectedAddr, MLDSAVerifyPrecompile.Address())
}

// Benchmark tests
func BenchmarkMLDSAVerify_SmallMessage(b *testing.B) {
	message := []byte("small test message")
	pk, signature, msg := createTestSignature(b, message)

	input := make([]byte, 0)
	input = append(input, pk...)
	msgLen := make([]byte, 32)
	msgLen[31] = byte(len(msg))
	input = append(input, msgLen...)
	input = append(input, signature...)
	input = append(input, msg...)

	gas := MLDSAVerifyPrecompile.RequiredGas(input)

	b.ResetTimer()
	for i := 0; i < b.N; i++ {
		_, _, _ = MLDSAVerifyPrecompile.Run(
			nil,
			common.Address{},
			ContractMLDSAVerifyAddress,
			input,
			gas,
			false,
		)
	}
}

func BenchmarkMLDSAVerify_LargeMessage(b *testing.B) {
	message := make([]byte, 10240)
	pk, signature, msg := createTestSignature(b, message)

	input := make([]byte, 0)
	input = append(input, pk...)
	msgLen := make([]byte, 32)
	msgLen[29] = byte(len(msg) >> 16)
	msgLen[30] = byte(len(msg) >> 8)
	msgLen[31] = byte(len(msg))
	input = append(input, msgLen...)
	input = append(input, signature...)
	input = append(input, msg...)

	gas := MLDSAVerifyPrecompile.RequiredGas(input)

	b.ResetTimer()
	for i := 0; i < b.N; i++ {
		_, _, _ = MLDSAVerifyPrecompile.Run(
			nil,
			common.Address{},
			ContractMLDSAVerifyAddress,
			input,
			gas,
			false,
		)
	}
}
