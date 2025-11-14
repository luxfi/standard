// Copyright (C) 2025, Lux Industries Inc All rights reserved.
// Post-Quantum Cryptography Precompile Implementation

package pqcrypto

import (
	"crypto/rand"
	"errors"
	"fmt"

	"github.com/luxfi/crypto/mldsa"
	"github.com/luxfi/crypto/mlkem"
	"github.com/luxfi/crypto/slhdsa"
	"github.com/luxfi/evm/precompile/contract"
	"github.com/luxfi/geth/common"
	"github.com/luxfi/geth/core/vm"
)

const (
	// Gas costs for PQ operations
	MLDSAVerifyGas      = 10000
	MLKEMEncapsulateGas = 8000
	MLKEMDecapsulateGas = 8000
	SLHDSAVerifyGas     = 15000

	// Function selectors (first 4 bytes must be unique)
	MLDSAVerifySelector      = "mlds_verify"
	MLKEMEncapsulateSelector = "encp_mlkem"
	MLKEMDecapsulateSelector = "decp_mlkem"
	SLHDSAVerifySelector     = "slhs_verify"
)

var (
	_ contract.StatefulPrecompiledContract = &pqCryptoPrecompile{}

	// Singleton instance
	PQCryptoPrecompile = &pqCryptoPrecompile{}

	errInvalidInput     = errors.New("invalid input")
	errInvalidSignature = errors.New("invalid signature")
)

type pqCryptoPrecompile struct{}

// Address returns the address of the PQ crypto precompile
func (p *pqCryptoPrecompile) Address() common.Address {
	return ContractAddress
}

// RequiredGas calculates the gas required for the given input
func (p *pqCryptoPrecompile) RequiredGas(input []byte) uint64 {
	if len(input) < 4 {
		return 0
	}

	// Parse function selector (first 4 bytes)
	selector := string(input[:4])

	switch selector {
	case MLDSAVerifySelector[:4]:
		return MLDSAVerifyGas
	case MLKEMEncapsulateSelector[:4]:
		return MLKEMEncapsulateGas
	case MLKEMDecapsulateSelector[:4]:
		return MLKEMDecapsulateGas
	case SLHDSAVerifySelector[:4]:
		return SLHDSAVerifyGas
	default:
		return 0
	}
}

// Run executes the precompile with the given input
func (p *pqCryptoPrecompile) Run(accessibleState contract.AccessibleState, caller common.Address, addr common.Address, input []byte, suppliedGas uint64, readOnly bool) (ret []byte, remainingGas uint64, err error) {
	if len(input) < 4 {
		return nil, suppliedGas, errInvalidInput
	}

	// Calculate required gas
	requiredGas := p.RequiredGas(input)
	if suppliedGas < requiredGas {
		return nil, 0, vm.ErrOutOfGas
	}
	remainingGas = suppliedGas - requiredGas

	// Parse function selector
	selector := string(input[:4])
	data := input[4:]

	switch selector {
	case MLDSAVerifySelector[:4]:
		return p.mldsaVerify(data)
	case MLKEMEncapsulateSelector[:4]:
		return p.mlkemEncapsulate(data)
	case MLKEMDecapsulateSelector[:4]:
		return p.mlkemDecapsulate(data)
	case SLHDSAVerifySelector[:4]:
		return p.slhdsaVerify(data)
	default:
		return nil, remainingGas, fmt.Errorf("unknown function selector: %x", selector)
	}
}

// mldsaVerify verifies an ML-DSA signature
func (p *pqCryptoPrecompile) mldsaVerify(input []byte) ([]byte, uint64, error) {
	// Input format: [mode(1)] [pubkey_len(2)] [pubkey] [msg_len(2)] [msg] [sig]
	if len(input) < 6 {
		return nil, 0, errInvalidInput
	}

	mode := mldsa.Mode(input[0])
	pubKeyLen := int(input[1])<<8 | int(input[2])

	if len(input) < 3+pubKeyLen+2 {
		return nil, 0, errInvalidInput
	}

	pubKeyBytes := input[3 : 3+pubKeyLen]
	msgLen := int(input[3+pubKeyLen])<<8 | int(input[3+pubKeyLen+1])

	if len(input) < 3+pubKeyLen+2+msgLen {
		return nil, 0, errInvalidInput
	}

	message := input[3+pubKeyLen+2 : 3+pubKeyLen+2+msgLen]
	signature := input[3+pubKeyLen+2+msgLen:]

	// Reconstruct public key
	pubKey, err := mldsa.PublicKeyFromBytes(pubKeyBytes, mode)
	if err != nil {
		return nil, 0, err
	}

	// Verify signature
	valid := pubKey.Verify(message, signature, nil)
	if valid {
		return []byte{1}, 0, nil
	}
	return []byte{0}, 0, nil
}

// mlkemEncapsulate performs ML-KEM encapsulation
func (p *pqCryptoPrecompile) mlkemEncapsulate(input []byte) ([]byte, uint64, error) {
	// Input format: [mode(1)] [pubkey]
	if len(input) < 2 {
		return nil, 0, errInvalidInput
	}

	mode := mlkem.Mode(input[0])
	pubKeyBytes := input[1:]

	// Reconstruct public key
	pubKey, err := mlkem.PublicKeyFromBytes(pubKeyBytes, mode)
	if err != nil {
		return nil, 0, err
	}

	// Encapsulate - returns EncapsulationResult and error
	result, err := pubKey.Encapsulate(rand.Reader)
	if err != nil {
		return nil, 0, err
	}

	// Return ciphertext + shared secret
	output := append(result.Ciphertext, result.SharedSecret...)
	return output, 0, nil
}

// mlkemDecapsulate performs ML-KEM decapsulation
func (p *pqCryptoPrecompile) mlkemDecapsulate(input []byte) ([]byte, uint64, error) {
	// Input format: [mode(1)] [privkey_len(2)] [privkey] [ciphertext]
	if len(input) < 4 {
		return nil, 0, errInvalidInput
	}

	mode := mlkem.Mode(input[0])
	privKeyLen := int(input[1])<<8 | int(input[2])

	if len(input) < 3+privKeyLen {
		return nil, 0, errInvalidInput
	}

	privKeyBytes := input[3 : 3+privKeyLen]
	ciphertext := input[3+privKeyLen:]

	// Reconstruct private key
	privKey, err := mlkem.PrivateKeyFromBytes(privKeyBytes, mode)
	if err != nil {
		return nil, 0, err
	}

	// Decapsulate
	sharedSecret, err := privKey.Decapsulate(ciphertext)
	if err != nil {
		return nil, 0, err
	}

	return sharedSecret, 0, nil
}

// slhdsaVerify verifies an SLH-DSA signature
func (p *pqCryptoPrecompile) slhdsaVerify(input []byte) ([]byte, uint64, error) {
	// Similar to mldsaVerify but for SLH-DSA
	if len(input) < 6 {
		return nil, 0, errInvalidInput
	}

	mode := slhdsa.Mode(input[0])
	pubKeyLen := int(input[1])<<8 | int(input[2])

	if len(input) < 3+pubKeyLen+2 {
		return nil, 0, errInvalidInput
	}

	pubKeyBytes := input[3 : 3+pubKeyLen]
	msgLen := int(input[3+pubKeyLen])<<8 | int(input[3+pubKeyLen+1])

	if len(input) < 3+pubKeyLen+2+msgLen {
		return nil, 0, errInvalidInput
	}

	message := input[3+pubKeyLen+2 : 3+pubKeyLen+2+msgLen]
	signature := input[3+pubKeyLen+2+msgLen:]

	// Reconstruct public key
	pubKey, err := slhdsa.PublicKeyFromBytes(pubKeyBytes, mode)
	if err != nil {
		return nil, 0, err
	}

	// Verify signature
	valid := pubKey.Verify(message, signature, nil)
	if valid {
		return []byte{1}, 0, nil
	}
	return []byte{0}, 0, nil
}
