// Copyright (C) 2025, Lux Industries, Inc. All rights reserved.
// See the file LICENSE for licensing terms.

package ringtailthreshold

import (
	"bytes"
	"encoding/binary"
	"math/big"
	"testing"

	"github.com/luxfi/geth/common"
	"github.com/luxfi/lattice/v6/ring"
	"github.com/luxfi/lattice/v6/utils/sampling"
	"github.com/luxfi/lattice/v6/utils/structs"
	"github.com/stretchr/testify/require"

	"ringtail/primitives"
	"ringtail/sign"
	"ringtail/utils"
)

// TestRingtailThresholdVerify_2of3 tests 2-of-3 threshold signature
func TestRingtailThresholdVerify_2of3(t *testing.T) {
	threshold := uint32(2)
	totalParties := uint32(3)
	message := "test message for 2-of-3 threshold"

	// Generate threshold signature
	signature, messageHash, err := generateThresholdSignature(threshold, totalParties, message)
	require.NoError(t, err)

	// Create input
	input := createInput(threshold, totalParties, messageHash, signature)

	// Verify signature
	precompile := &ringtailThresholdPrecompile{}
	result, _, err := precompile.Run(nil, common.Address{}, precompile.Address(), input, 1_000_000, true)
	require.NoError(t, err)
	require.NotNil(t, result)
	require.Equal(t, byte(1), result[31], "Signature should be valid")
}

// TestRingtailThresholdVerify_3of5 tests 3-of-5 threshold signature
func TestRingtailThresholdVerify_3of5(t *testing.T) {
	threshold := uint32(3)
	totalParties := uint32(5)
	message := "test message for 3-of-5 threshold"

	// Generate threshold signature
	signature, messageHash, err := generateThresholdSignature(threshold, totalParties, message)
	require.NoError(t, err)

	// Create input
	input := createInput(threshold, totalParties, messageHash, signature)

	// Verify signature
	precompile := &ringtailThresholdPrecompile{}
	result, _, err := precompile.Run(nil, common.Address{}, precompile.Address(), input, 2_000_000, true)
	require.NoError(t, err)
	require.NotNil(t, result)
	require.Equal(t, byte(1), result[31], "Signature should be valid")
}

// TestRingtailThresholdVerify_FullThreshold tests n-of-n (full threshold)
func TestRingtailThresholdVerify_FullThreshold(t *testing.T) {
	threshold := uint32(4)
	totalParties := uint32(4)
	message := "test message for full threshold"

	// Generate threshold signature
	signature, messageHash, err := generateThresholdSignature(threshold, totalParties, message)
	require.NoError(t, err)

	// Create input
	input := createInput(threshold, totalParties, messageHash, signature)

	// Verify signature
	precompile := &ringtailThresholdPrecompile{}
	result, _, err := precompile.Run(nil, common.Address{}, precompile.Address(), input, 2_000_000, true)
	require.NoError(t, err)
	require.NotNil(t, result)
	require.Equal(t, byte(1), result[31], "Signature should be valid")
}

// TestRingtailThresholdVerify_InvalidSignature tests invalid signature rejection
func TestRingtailThresholdVerify_InvalidSignature(t *testing.T) {
	threshold := uint32(2)
	totalParties := uint32(3)
	message := "test message"

	// Generate valid signature
	signature, messageHash, err := generateThresholdSignature(threshold, totalParties, message)
	require.NoError(t, err)

	// Corrupt signature
	signature[100] ^= 0xFF

	// Create input with corrupted signature
	input := createInput(threshold, totalParties, messageHash, signature)

	// Verify should fail
	precompile := &ringtailThresholdPrecompile{}
	result, _, err := precompile.Run(nil, common.Address{}, precompile.Address(), input, 1_000_000, true)
	require.NoError(t, err)
	require.NotNil(t, result)
	require.Equal(t, byte(0), result[31], "Invalid signature should be rejected")
}

// TestRingtailThresholdVerify_WrongMessage tests wrong message rejection
func TestRingtailThresholdVerify_WrongMessage(t *testing.T) {
	threshold := uint32(2)
	totalParties := uint32(3)
	message := "original message"

	// Generate signature for original message
	signature, _, err := generateThresholdSignature(threshold, totalParties, message)
	require.NoError(t, err)

	// Use different message hash
	wrongMessage := "different message"
	wrongHash := hashMessage(wrongMessage)

	// Create input with wrong message hash
	input := createInput(threshold, totalParties, wrongHash, signature)

	// Verify should fail
	precompile := &ringtailThresholdPrecompile{}
	result, _, err := precompile.Run(nil, common.Address{}, precompile.Address(), input, 1_000_000, true)
	require.NoError(t, err)
	require.NotNil(t, result)
	require.Equal(t, byte(0), result[31], "Wrong message should be rejected")
}

// TestRingtailThresholdVerify_ThresholdNotMet tests threshold not met rejection
func TestRingtailThresholdVerify_ThresholdNotMet(t *testing.T) {
	// Generate signature with 2 parties
	actualParties := uint32(2)
	claimedThreshold := uint32(3)
	message := "test message"

	signature, messageHash, err := generateThresholdSignature(actualParties, actualParties, message)
	require.NoError(t, err)

	// Claim higher threshold than available
	input := createInput(claimedThreshold, actualParties, messageHash, signature)

	// Verify should fail
	precompile := &ringtailThresholdPrecompile{}
	_, _, err = precompile.Run(nil, common.Address{}, precompile.Address(), input, 1_000_000, true)
	require.Error(t, err)
	require.Contains(t, err.Error(), "invalid threshold")
}

// TestRingtailThresholdVerify_InputTooShort tests short input rejection
func TestRingtailThresholdVerify_InputTooShort(t *testing.T) {
	input := make([]byte, 20) // Too short

	precompile := &ringtailThresholdPrecompile{}
	_, _, err := precompile.Run(nil, common.Address{}, precompile.Address(), input, 1_000_000, true)
	require.Error(t, err)
	require.Contains(t, err.Error(), "invalid input length")
}

// TestRingtailThresholdVerify_GasCost tests gas cost calculation
func TestRingtailThresholdVerify_GasCost(t *testing.T) {
	tests := []struct {
		name         string
		parties      uint32
		expectedGas  uint64
	}{
		{"3 parties", 3, 150_000 + (3 * 10_000)},
		{"5 parties", 5, 150_000 + (5 * 10_000)},
		{"10 parties", 10, 150_000 + (10 * 10_000)},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			// Create minimal valid input
			input := make([]byte, MinInputSize+100)
			binary.BigEndian.PutUint32(input[0:4], tt.parties)
			binary.BigEndian.PutUint32(input[4:8], tt.parties)

			precompile := &ringtailThresholdPrecompile{}
			gas := precompile.RequiredGas(input)
			require.Equal(t, tt.expectedGas, gas)
		})
	}
}

// TestRingtailThresholdPrecompile_Address tests precompile address
func TestRingtailThresholdPrecompile_Address(t *testing.T) {
	precompile := &ringtailThresholdPrecompile{}
	expectedAddress := common.HexToAddress("0x020000000000000000000000000000000000000B")
	require.Equal(t, expectedAddress, precompile.Address())
}

// TestEstimateGas tests gas estimation utility
func TestEstimateGas(t *testing.T) {
	tests := []struct {
		parties uint32
		gas     uint64
	}{
		{2, 170_000},
		{3, 180_000},
		{5, 200_000},
		{10, 250_000},
	}

	for _, tt := range tests {
		gas := EstimateGas(tt.parties)
		require.Equal(t, tt.gas, gas)
	}
}

// Helper functions

// generateThresholdSignature generates a threshold signature using Ringtail protocol
func generateThresholdSignature(threshold, totalParties uint32, message string) ([]byte, []byte, error) {
	// Initialize ring parameters
	r, err := ring.NewRing(1<<sign.LogN, []uint64{sign.Q})
	if err != nil {
		return nil, nil, err
	}

	r_xi, err := ring.NewRing(1<<sign.LogN, []uint64{sign.QXi})
	if err != nil {
		return nil, nil, err
	}

	r_nu, err := ring.NewRing(1<<sign.LogN, []uint64{sign.QNu})
	if err != nil {
		return nil, nil, err
	}

	// Initialize sampler
	randomKey := make([]byte, sign.KeySize)
	prng, err := sampling.NewKeyedPRNG(randomKey)
	if err != nil {
		return nil, nil, err
	}
	uniformSampler := ring.NewUniformSampler(prng, r)

	// Set parameters
	sign.K = int(totalParties)
	sign.Threshold = int(threshold)

	// Create party set
	T := make([]int, totalParties)
	for i := 0; i < int(totalParties); i++ {
		T[i] = i
	}

	// Compute Lagrange coefficients
	lagrangeCoeffs := primitives.ComputeLagrangeCoefficients(r, T, big.NewInt(int64(sign.Q)))

	// Run Gen to generate keys and parameters
	A, skShares, seeds, MACKeys, bTilde := sign.Gen(r, r_xi, uniformSampler, randomKey, lagrangeCoeffs)

	// Create parties
	parties := make([]*sign.Party, totalParties)
	for i := 0; i < int(totalParties); i++ {
		parties[i] = sign.NewParty(i, r, r_xi, r_nu, uniformSampler)
		parties[i].SkShare = skShares[i]
		parties[i].Seed = seeds
		parties[i].MACKeys = MACKeys[i]
		parties[i].Lambda = lagrangeCoeffs[i]
	}

	// Round 1: Each party generates their D matrix and MACs
	D := make(map[int]structs.Matrix[ring.Poly])
	MACs := make(map[int]map[int][]byte)
	sid := 1

	for i, party := range parties {
		Di, MACsi := party.SignRound1(A, sid, randomKey, T)
		D[i] = Di
		MACs[i] = MACsi
	}

	// Round 2 Preprocess: Verify MACs and compute DSum
	var DSum structs.Matrix[ring.Poly]
	var hash []byte
	for _, party := range parties {
		valid, DSumLocal, hashLocal := party.SignRound2Preprocess(A, bTilde, D, MACs, sid, T)
		if !valid {
			return nil, nil, fmt.Errorf("MAC verification failed")
		}
		DSum = DSumLocal
		hash = hashLocal
	}

	// Round 2: Each party generates their z share
	z := make(map[int]structs.Vector[ring.Poly])
	for i, party := range parties {
		z[i] = party.SignRound2(A, bTilde, DSum, sid, message, T, randomKey, hash)
	}

	// Finalize: Combine shares to create signature
	c, z_sum, Delta := parties[0].SignFinalize(z, A, bTilde)

	// Serialize signature
	signatureBytes, err := serializeSignature(r, r_xi, r_nu, c, z_sum, Delta, A, bTilde)
	if err != nil {
		return nil, nil, err
	}

	// Hash message
	messageHash := hashMessage(message)

	return signatureBytes, messageHash, nil
}

// serializeSignature serializes signature components to bytes
func serializeSignature(r, r_xi, r_nu *ring.Ring,
	c ring.Poly,
	z structs.Vector[ring.Poly],
	Delta structs.Vector[ring.Poly],
	A structs.Matrix[ring.Poly],
	bTilde structs.Vector[ring.Poly],
) ([]byte, error) {
	var buf bytes.Buffer

	// Serialize c
	if err := serializePoly(&buf, r, c); err != nil {
		return nil, err
	}

	// Serialize z vector
	for i := 0; i < sign.N; i++ {
		if err := serializePoly(&buf, r, z[i]); err != nil {
			return nil, err
		}
	}

	// Serialize Delta vector
	for i := 0; i < sign.M; i++ {
		if err := serializePoly(&buf, r_nu, Delta[i]); err != nil {
			return nil, err
		}
	}

	// Serialize A matrix
	for i := 0; i < sign.M; i++ {
		for j := 0; j < sign.N; j++ {
			if err := serializePoly(&buf, r, A[i][j]); err != nil {
				return nil, err
			}
		}
	}

	// Serialize bTilde vector
	for i := 0; i < sign.M; i++ {
		if err := serializePoly(&buf, r_xi, bTilde[i]); err != nil {
			return nil, err
		}
	}

	return buf.Bytes(), nil
}

// serializePoly serializes a polynomial to binary data
func serializePoly(buf *bytes.Buffer, r *ring.Ring, poly ring.Poly) error {
	coeffs := make([]*big.Int, r.N())
	r.PolyToBigint(poly, 1, coeffs)

	for _, coeff := range coeffs {
		coeffBytes := make([]byte, 8) // 64-bit coefficients
		coeff.FillBytes(coeffBytes)
		if _, err := buf.Write(coeffBytes); err != nil {
			return err
		}
	}
	return nil
}

// hashMessage creates a 32-byte hash of a message
func hashMessage(message string) []byte {
	hash := make([]byte, 32)
	copy(hash, []byte(message))
	return hash
}

// createInput creates precompile input from components
func createInput(threshold, totalParties uint32, messageHash, signature []byte) []byte {
	input := make([]byte, 0, MinInputSize+len(signature))

	// Add threshold
	thresholdBytes := make([]byte, 4)
	binary.BigEndian.PutUint32(thresholdBytes, threshold)
	input = append(input, thresholdBytes...)

	// Add total parties
	partiesBytes := make([]byte, 4)
	binary.BigEndian.PutUint32(partiesBytes, totalParties)
	input = append(input, partiesBytes...)

	// Add message hash
	input = append(input, messageHash...)

	// Add signature
	input = append(input, signature...)

	return input
}
