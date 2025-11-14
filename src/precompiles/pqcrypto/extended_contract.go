// Copyright (C) 2025, Lux Industries Inc All rights reserved.
// Extended Post-Quantum Cryptography Precompile Implementation

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
	// Additional gas costs for signing operations
	MLDSASignGas    = 12000
	SLHDSASignGas   = 20000
	MLDSAGenKeyGas  = 15000
	MLKEMGenKeyGas  = 12000
	SLHDSAGenKeyGas = 25000

	// Additional function selectors
	MLDSASignSelector    = "mldsa_sign"
	SLHDSASignSelector   = "slhdsa_sign"
	MLDSAGenKeySelector  = "mldsa_genkey"
	MLKEMGenKeySelector  = "mlkem_genkey"
	SLHDSAGenKeySelector = "slhdsa_genkey"
)

// Extended methods for signing operations

// mldsaSign creates an ML-DSA signature
func (p *pqCryptoPrecompile) mldsaSign(input []byte) ([]byte, uint64, error) {
	// Input format: [mode(1)] [privkey_len(2)] [privkey] [message]
	if len(input) < 4 {
		return nil, 0, errInvalidInput
	}

	mode := mldsa.Mode(input[0])
	privKeyLen := int(input[1])<<8 | int(input[2])

	if len(input) < 3+privKeyLen {
		return nil, 0, errInvalidInput
	}

	privKeyBytes := input[3 : 3+privKeyLen]
	message := input[3+privKeyLen:]

	// Reconstruct private key
	privKey, err := mldsa.PrivateKeyFromBytes(privKeyBytes, mode)
	if err != nil {
		return nil, 0, err
	}

	// Sign message
	signature, err := privKey.Sign(rand.Reader, message, nil)
	if err != nil {
		return nil, 0, err
	}

	return signature, 0, nil
}

// slhdsaSign creates an SLH-DSA signature
func (p *pqCryptoPrecompile) slhdsaSign(input []byte) ([]byte, uint64, error) {
	// Input format: [mode(1)] [privkey_len(2)] [privkey] [message]
	if len(input) < 4 {
		return nil, 0, errInvalidInput
	}

	mode := slhdsa.Mode(input[0])
	privKeyLen := int(input[1])<<8 | int(input[2])

	if len(input) < 3+privKeyLen {
		return nil, 0, errInvalidInput
	}

	privKeyBytes := input[3 : 3+privKeyLen]
	message := input[3+privKeyLen:]

	// Reconstruct private key
	privKey, err := slhdsa.PrivateKeyFromBytes(privKeyBytes, mode)
	if err != nil {
		return nil, 0, err
	}

	// Sign message
	signature, err := privKey.Sign(rand.Reader, message, nil)
	if err != nil {
		return nil, 0, err
	}

	return signature, 0, nil
}

// mldsaGenKey generates an ML-DSA key pair
func (p *pqCryptoPrecompile) mldsaGenKey(input []byte) ([]byte, uint64, error) {
	// Input format: [mode(1)]
	if len(input) < 1 {
		return nil, 0, errInvalidInput
	}

	mode := mldsa.Mode(input[0])

	// Generate key pair
	privKey, err := mldsa.GenerateKey(rand.Reader, mode)
	if err != nil {
		return nil, 0, err
	}

	// Serialize keys
	privBytes := privKey.Bytes()
	pubBytes := privKey.PublicKey.Bytes()

	// Output format: [privkey_len(2)] [privkey] [pubkey]
	output := make([]byte, 2+len(privBytes)+len(pubBytes))
	output[0] = byte(len(privBytes) >> 8)
	output[1] = byte(len(privBytes))
	copy(output[2:2+len(privBytes)], privBytes)
	copy(output[2+len(privBytes):], pubBytes)

	return output, 0, nil
}

// mlkemGenKey generates an ML-KEM key pair
func (p *pqCryptoPrecompile) mlkemGenKey(input []byte) ([]byte, uint64, error) {
	// Input format: [mode(1)]
	if len(input) < 1 {
		return nil, 0, errInvalidInput
	}

	mode := mlkem.Mode(input[0])

	// Generate key pair - returns (privKey, pubKey, error)
	privKey, _, err := mlkem.GenerateKeyPair(rand.Reader, mode)
	if err != nil {
		return nil, 0, err
	}

	// Serialize keys - extract public key from private key
	privBytes := privKey.Bytes()
	pubKey := privKey.PublicKey
	pubBytes := pubKey.Bytes()

	// Output format: [privkey_len(2)] [privkey] [pubkey]
	output := make([]byte, 2+len(privBytes)+len(pubBytes))
	output[0] = byte(len(privBytes) >> 8)
	output[1] = byte(len(privBytes))
	copy(output[2:2+len(privBytes)], privBytes)
	copy(output[2+len(privBytes):], pubBytes)

	return output, 0, nil
}

// slhdsaGenKey generates an SLH-DSA key pair
func (p *pqCryptoPrecompile) slhdsaGenKey(input []byte) ([]byte, uint64, error) {
	// Input format: [mode(1)]
	if len(input) < 1 {
		return nil, 0, errInvalidInput
	}

	mode := slhdsa.Mode(input[0])

	// Generate key pair
	privKey, err := slhdsa.GenerateKey(rand.Reader, mode)
	if err != nil {
		return nil, 0, err
	}

	// Serialize keys
	privBytes := privKey.Bytes()
	pubBytes := privKey.PublicKey.Bytes()

	// Output format: [privkey_len(2)] [privkey] [pubkey]
	output := make([]byte, 2+len(privBytes)+len(pubBytes))
	output[0] = byte(len(privBytes) >> 8)
	output[1] = byte(len(privBytes))
	copy(output[2:2+len(privBytes)], privBytes)
	copy(output[2+len(privBytes):], pubBytes)

	return output, 0, nil
}

// ExtendedRequiredGas calculates gas for extended operations
func (p *pqCryptoPrecompile) ExtendedRequiredGas(input []byte) uint64 {
	if len(input) < 4 {
		return 0
	}

	// Parse function selector (first 4 bytes)
	selector := string(input[:4])

	switch selector {
	case MLDSASignSelector[:4]:
		return MLDSASignGas
	case SLHDSASignSelector[:4]:
		return SLHDSASignGas
	case MLDSAGenKeySelector[:4]:
		return MLDSAGenKeyGas
	case MLKEMGenKeySelector[:4]:
		return MLKEMGenKeyGas
	case SLHDSAGenKeySelector[:4]:
		return SLHDSAGenKeyGas
	default:
		return p.RequiredGas(input) // Fall back to original
	}
}

// ExtendedRun executes extended precompile operations
func (p *pqCryptoPrecompile) ExtendedRun(accessibleState contract.AccessibleState, caller common.Address, addr common.Address, input []byte, suppliedGas uint64, readOnly bool) (ret []byte, remainingGas uint64, err error) {
	if len(input) < 4 {
		return nil, suppliedGas, errInvalidInput
	}

	// Calculate required gas
	requiredGas := p.ExtendedRequiredGas(input)
	if requiredGas == 0 {
		// Try original run
		return p.Run(accessibleState, caller, addr, input, suppliedGas, readOnly)
	}

	if suppliedGas < requiredGas {
		return nil, 0, vm.ErrOutOfGas
	}
	remainingGas = suppliedGas - requiredGas

	// Parse function selector
	selector := string(input[:4])
	data := input[4:]

	switch selector {
	case MLDSASignSelector[:4]:
		if readOnly {
			return nil, remainingGas, errors.New("cannot sign in read-only mode")
		}
		return p.mldsaSign(data)
	case SLHDSASignSelector[:4]:
		if readOnly {
			return nil, remainingGas, errors.New("cannot sign in read-only mode")
		}
		return p.slhdsaSign(data)
	case MLDSAGenKeySelector[:4]:
		if readOnly {
			return nil, remainingGas, errors.New("cannot generate keys in read-only mode")
		}
		return p.mldsaGenKey(data)
	case MLKEMGenKeySelector[:4]:
		if readOnly {
			return nil, remainingGas, errors.New("cannot generate keys in read-only mode")
		}
		return p.mlkemGenKey(data)
	case SLHDSAGenKeySelector[:4]:
		if readOnly {
			return nil, remainingGas, errors.New("cannot generate keys in read-only mode")
		}
		return p.slhdsaGenKey(data)
	default:
		return nil, remainingGas, fmt.Errorf("unknown function selector: %x", selector)
	}
}
