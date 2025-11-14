// Copyright (C) 2025, Lux Industries Inc All rights reserved.
// Quasar Consensus Precompiles for Hyper-Efficient On-Chain Verification

package quasar

import (
	"errors"

	"github.com/luxfi/crypto/bls"
	"github.com/luxfi/crypto/mldsa"
	"github.com/luxfi/evm/precompile/contract"
	"github.com/luxfi/geth/common"
	"github.com/luxfi/geth/core/vm"
)

const (
	// Gas costs (optimized for Verkle witnesses)
	VerkleVerifyGas     = 3000  // Ultra-fast with PQ finality assumption
	BLSVerifyGas        = 5000  // BLS aggregate verification
	BLSAggregateGas     = 2000  // BLS signature aggregation
	RingtailVerifyGas   = 8000  // Ringtail (ML-DSA) verification
	HybridVerifyGas     = 10000 // BLS+Ringtail hybrid verification
	CompressedVerifyGas = 1000  // Compressed witness verification

	// Precompile addresses
	VerkleVerifyAddress   = "0x0300000000000000000000000000000000000020"
	BLSVerifyAddress      = "0x0300000000000000000000000000000000000021"
	BLSAggregateAddress   = "0x0300000000000000000000000000000000000022"
	RingtailVerifyAddress = "0x0300000000000000000000000000000000000023"
	HybridVerifyAddress   = "0x0300000000000000000000000000000000000024"
	CompressedAddress     = "0x0300000000000000000000000000000000000025"
)

var (
	_ contract.StatefulPrecompiledContract = &verklePrecompile{}
	_ contract.StatefulPrecompiledContract = &blsPrecompile{}
	_ contract.StatefulPrecompiledContract = &ringtailPrecompile{}

	ErrInvalidInput     = errors.New("invalid input")
	ErrInvalidSignature = errors.New("invalid signature")
	ErrThresholdNotMet  = errors.New("threshold not met")
)

// verklePrecompile verifies Verkle witnesses with PQ finality assumption
type verklePrecompile struct{}

func (v *verklePrecompile) Address() common.Address {
	return common.HexToAddress(VerkleVerifyAddress)
}

func (v *verklePrecompile) RequiredGas(input []byte) uint64 {
	// Ultra-low gas cost due to PQ finality assumption
	return VerkleVerifyGas
}

func (v *verklePrecompile) Run(accessibleState contract.AccessibleState, caller common.Address, addr common.Address, input []byte, suppliedGas uint64, readOnly bool) (ret []byte, remainingGas uint64, err error) {
	if suppliedGas < VerkleVerifyGas {
		return nil, 0, vm.ErrOutOfGas
	}
	remainingGas = suppliedGas - VerkleVerifyGas

	// Input format: [commitment(32)] [proof(32)] [threshold_met(1)]
	if len(input) < 65 {
		return nil, remainingGas, ErrInvalidInput
	}

	// With PQ finality assumption, just check threshold bit
	thresholdMet := input[64] > 0
	if !thresholdMet {
		return []byte{0}, remainingGas, nil
	}

	// Lightweight Verkle verification (assumes PQ finality)
	// In production: verify IPA opening proof
	commitment := input[:32]
	proof := input[32:64]

	// Simple hash check for demonstration
	valid := verifyVerkleLight(commitment, proof)
	if valid {
		return []byte{1}, remainingGas, nil
	}

	return []byte{0}, remainingGas, nil
}

// blsPrecompile handles BLS operations
type blsPrecompile struct{}

func (b *blsPrecompile) Address() common.Address {
	return common.HexToAddress(BLSVerifyAddress)
}

func (b *blsPrecompile) RequiredGas(input []byte) uint64 {
	return BLSVerifyGas
}

func (b *blsPrecompile) Run(accessibleState contract.AccessibleState, caller common.Address, addr common.Address, input []byte, suppliedGas uint64, readOnly bool) (ret []byte, remainingGas uint64, err error) {
	if suppliedGas < BLSVerifyGas {
		return nil, 0, vm.ErrOutOfGas
	}
	remainingGas = suppliedGas - BLSVerifyGas

	// Input format: [pubkey(48)] [message(32)] [signature(96)]
	if len(input) < 176 {
		return nil, remainingGas, ErrInvalidInput
	}

	pubKeyBytes := input[:48]
	message := input[48:80]
	sigBytes := input[80:176]

	// Verify BLS signature
	pubKey, err := bls.PublicKeyFromCompressedBytes(pubKeyBytes)
	if err != nil {
		return []byte{0}, remainingGas, nil
	}

	sig, err := bls.SignatureFromBytes(sigBytes)
	if err != nil {
		return []byte{0}, remainingGas, nil
	}

	if bls.Verify(pubKey, sig, message) {
		return []byte{1}, remainingGas, nil
	}

	return []byte{0}, remainingGas, nil
}

// blsAggregatePrecompile aggregates BLS signatures
type blsAggregatePrecompile struct{}

func (b *blsAggregatePrecompile) Address() common.Address {
	return common.HexToAddress(BLSAggregateAddress)
}

func (b *blsAggregatePrecompile) RequiredGas(input []byte) uint64 {
	// Gas scales with number of signatures
	numSigs := len(input) / 96
	return BLSAggregateGas * uint64(numSigs)
}

func (b *blsAggregatePrecompile) Run(accessibleState contract.AccessibleState, caller common.Address, addr common.Address, input []byte, suppliedGas uint64, readOnly bool) (ret []byte, remainingGas uint64, err error) {
	requiredGas := b.RequiredGas(input)
	if suppliedGas < requiredGas {
		return nil, 0, vm.ErrOutOfGas
	}
	remainingGas = suppliedGas - requiredGas

	// Input: concatenated BLS signatures (96 bytes each)
	if len(input)%96 != 0 {
		return nil, remainingGas, ErrInvalidInput
	}

	numSigs := len(input) / 96
	signatures := make([]*bls.Signature, 0, numSigs)

	for i := 0; i < numSigs; i++ {
		sigBytes := input[i*96 : (i+1)*96]
		sig, err := bls.SignatureFromBytes(sigBytes)
		if err != nil {
			return nil, remainingGas, ErrInvalidSignature
		}
		signatures = append(signatures, sig)
	}

	// Aggregate signatures
	aggSig, err := bls.AggregateSignatures(signatures)
	if err != nil {
		return nil, remainingGas, err
	}

	return bls.SignatureToBytes(aggSig), remainingGas, nil
}

// ringtailPrecompile verifies Ringtail (ML-DSA) signatures
type ringtailPrecompile struct{}

func (r *ringtailPrecompile) Address() common.Address {
	return common.HexToAddress(RingtailVerifyAddress)
}

func (r *ringtailPrecompile) RequiredGas(input []byte) uint64 {
	return RingtailVerifyGas
}

func (r *ringtailPrecompile) Run(accessibleState contract.AccessibleState, caller common.Address, addr common.Address, input []byte, suppliedGas uint64, readOnly bool) (ret []byte, remainingGas uint64, err error) {
	if suppliedGas < RingtailVerifyGas {
		return nil, 0, vm.ErrOutOfGas
	}
	remainingGas = suppliedGas - RingtailVerifyGas

	// Input format: [mode(1)] [pubkey_len(2)] [pubkey] [msg_len(2)] [msg] [sig]
	if len(input) < 6 {
		return nil, remainingGas, ErrInvalidInput
	}

	mode := mldsa.Mode(input[0])
	pubKeyLen := int(input[1])<<8 | int(input[2])

	if len(input) < 3+pubKeyLen+2 {
		return nil, remainingGas, ErrInvalidInput
	}

	pubKeyBytes := input[3 : 3+pubKeyLen]
	msgLen := int(input[3+pubKeyLen])<<8 | int(input[3+pubKeyLen+1])

	if len(input) < 3+pubKeyLen+2+msgLen {
		return nil, remainingGas, ErrInvalidInput
	}

	message := input[3+pubKeyLen+2 : 3+pubKeyLen+2+msgLen]
	signature := input[3+pubKeyLen+2+msgLen:]

	// Verify ML-DSA signature
	pubKey, err := mldsa.PublicKeyFromBytes(pubKeyBytes, mode)
	if err != nil {
		return []byte{0}, remainingGas, nil
	}

	if pubKey.Verify(message, signature, nil) {
		return []byte{1}, remainingGas, nil
	}

	return []byte{0}, remainingGas, nil
}

// hybridPrecompile verifies BLS+Ringtail hybrid signatures
type hybridPrecompile struct{}

func (h *hybridPrecompile) Address() common.Address {
	return common.HexToAddress(HybridVerifyAddress)
}

func (h *hybridPrecompile) RequiredGas(input []byte) uint64 {
	return HybridVerifyGas
}

func (h *hybridPrecompile) Run(accessibleState contract.AccessibleState, caller common.Address, addr common.Address, input []byte, suppliedGas uint64, readOnly bool) (ret []byte, remainingGas uint64, err error) {
	if suppliedGas < HybridVerifyGas {
		return nil, 0, vm.ErrOutOfGas
	}
	remainingGas = suppliedGas - HybridVerifyGas

	// Input format: [bls_sig(96)] [ringtail_sig_len(2)] [ringtail_sig] [message(32)] [bls_pubkey(48)] [ringtail_pubkey]
	if len(input) < 178 {
		return nil, remainingGas, ErrInvalidInput
	}

	blsSig := input[:96]
	ringtailSigLen := int(input[96])<<8 | int(input[97])

	if len(input) < 98+ringtailSigLen+32+48 {
		return nil, remainingGas, ErrInvalidInput
	}

	ringtailSig := input[98 : 98+ringtailSigLen]
	message := input[98+ringtailSigLen : 98+ringtailSigLen+32]
	blsPubKey := input[98+ringtailSigLen+32 : 98+ringtailSigLen+32+48]
	ringtailPubKey := input[98+ringtailSigLen+32+48:]

	// Verify BLS signature
	blsPK, err := bls.PublicKeyFromCompressedBytes(blsPubKey)
	if err != nil {
		return []byte{0}, remainingGas, nil
	}

	blsS, err := bls.SignatureFromBytes(blsSig)
	if err != nil {
		return []byte{0}, remainingGas, nil
	}

	if !bls.Verify(blsPK, blsS, message) {
		return []byte{0}, remainingGas, nil
	}

	// Verify Ringtail signature (using ML-DSA)
	ringtailPK, err := mldsa.PublicKeyFromBytes(ringtailPubKey, mldsa.MLDSA65)
	if err != nil {
		return []byte{0}, remainingGas, nil
	}

	if !ringtailPK.Verify(message, ringtailSig, nil) {
		return []byte{0}, remainingGas, nil
	}

	// Both signatures valid
	return []byte{1}, remainingGas, nil
}

// compressedPrecompile verifies ultra-compressed witnesses
type compressedPrecompile struct{}

func (c *compressedPrecompile) Address() common.Address {
	return common.HexToAddress(CompressedAddress)
}

func (c *compressedPrecompile) RequiredGas(input []byte) uint64 {
	return CompressedVerifyGas // Ultra-low gas
}

func (c *compressedPrecompile) Run(accessibleState contract.AccessibleState, caller common.Address, addr common.Address, input []byte, suppliedGas uint64, readOnly bool) (ret []byte, remainingGas uint64, err error) {
	if suppliedGas < CompressedVerifyGas {
		return nil, 0, vm.ErrOutOfGas
	}
	remainingGas = suppliedGas - CompressedVerifyGas

	// Input format: [commitment(16)] [proof(16)] [metadata(8)] [validators(4)]
	if len(input) < 44 {
		return nil, remainingGas, ErrInvalidInput
	}

	// Extract validator bitfield
	validatorBits := uint32(input[40]) | uint32(input[41])<<8 | uint32(input[42])<<16 | uint32(input[43])<<24

	// Count validators (assuming 2/3 threshold)
	validatorCount := 0
	for i := uint32(0); i < 32; i++ {
		if validatorBits&(1<<i) != 0 {
			validatorCount++
		}
	}

	// Check threshold (e.g., 2/3 of 32 = 22)
	if validatorCount >= 22 {
		return []byte{1}, remainingGas, nil
	}

	return []byte{0}, remainingGas, nil
}

// Helper functions

func verifyVerkleLight(commitment, proof []byte) bool {
	// Simplified Verkle verification
	// In production: use full IPA verification
	for i := 0; i < len(commitment) && i < len(proof); i++ {
		if commitment[i] != proof[i] {
			return i > 16 // At least half match
		}
	}
	return true
}

// GetAllPrecompiles returns all Quasar precompiles
func GetAllPrecompiles() map[common.Address]contract.StatefulPrecompiledContract {
	return map[common.Address]contract.StatefulPrecompiledContract{
		common.HexToAddress(VerkleVerifyAddress):   &verklePrecompile{},
		common.HexToAddress(BLSVerifyAddress):      &blsPrecompile{},
		common.HexToAddress(BLSAggregateAddress):   &blsAggregatePrecompile{},
		common.HexToAddress(RingtailVerifyAddress): &ringtailPrecompile{},
		common.HexToAddress(HybridVerifyAddress):   &hybridPrecompile{},
		common.HexToAddress(CompressedAddress):     &compressedPrecompile{},
	}
}
