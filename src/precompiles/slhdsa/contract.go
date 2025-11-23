// Copyright (C) 2019-2025, Lux Industries Inc. All rights reserved.
// See the file LICENSE for licensing terms.

package slhdsa

import (
	"encoding/binary"
	"fmt"

	"github.com/luxfi/crypto/slhdsa"
	"github.com/luxfi/geth/common"
)

const (
	// ContractAddress is the precompile address for SLH-DSA verification
	// 0x0200000000000000000000000000000000000007
	ContractAddressHex = "0x0200000000000000000000000000000000000007"
	
	// Gas costs
	SLHDSAVerifyBaseGas    = 15000 // Base cost for verification
	SLHDSAVerifyPerByteGas = 10    // Cost per message byte
)

var (
	ContractAddress = common.HexToAddress(ContractAddressHex)
)

// SLHDSAPrecompile implements the SLH-DSA signature verification precompile
type SLHDSAPrecompile struct{}

// Address returns the precompile address
func (p *SLHDSAPrecompile) Address() common.Address {
	return ContractAddress
}

// RequiredGas calculates the gas required for SLH-DSA verification
// Gas = BaseGas + (MessageLength * PerByteGas)
func (p *SLHDSAPrecompile) RequiredGas(input []byte) uint64 {
	if len(input) < 5 {
		return SLHDSAVerifyBaseGas
	}
	
	// Parse input to get message length
	// Format: [mode(1)] [pubKeyLen(2)] [pubKey] [msgLen(2)] [message] [signature]
	mode := input[0]
	if mode > byte(slhdsa.SHAKE_256f) {
		return SLHDSAVerifyBaseGas
	}
	
	if len(input) < 3 {
		return SLHDSAVerifyBaseGas
	}
	
	pubKeyLen := binary.BigEndian.Uint16(input[1:3])
	if len(input) < int(3+pubKeyLen+2) {
		return SLHDSAVerifyBaseGas
	}
	
	msgLen := binary.BigEndian.Uint16(input[3+pubKeyLen : 3+pubKeyLen+2])
	
	return SLHDSAVerifyBaseGas + (uint64(msgLen) * SLHDSAVerifyPerByteGas)
}

// Run executes the SLH-DSA signature verification
// Input format: [mode(1)] [pubKeyLen(2)] [pubKey] [msgLen(2)] [message] [signature]
// Output: [valid(1)] where 0x01 = valid, 0x00 = invalid
func (p *SLHDSAPrecompile) Run(input []byte) ([]byte, error) {
	if len(input) < 5 {
		return []byte{0}, fmt.Errorf("invalid input: too short")
	}
	
	// Parse mode
	mode := slhdsa.Mode(input[0])
	if mode > slhdsa.SHAKE_256f {
		return []byte{0}, fmt.Errorf("invalid mode: %d", mode)
	}
	
	// Parse public key length
	if len(input) < 3 {
		return []byte{0}, fmt.Errorf("invalid input: missing public key length")
	}
	pubKeyLen := binary.BigEndian.Uint16(input[1:3])
	
	// Extract public key
	if len(input) < int(3+pubKeyLen+2) {
		return []byte{0}, fmt.Errorf("invalid input: public key too short")
	}
	pubKeyBytes := input[3 : 3+pubKeyLen]
	
	// Parse message length
	msgLen := binary.BigEndian.Uint16(input[3+pubKeyLen : 3+pubKeyLen+2])
	
	// Extract message
	if len(input) < int(3+pubKeyLen+2+msgLen) {
		return []byte{0}, fmt.Errorf("invalid input: message too short")
	}
	message := input[3+pubKeyLen+2 : 3+pubKeyLen+2+msgLen]
	
	// Extract signature (remaining bytes)
	signature := input[3+pubKeyLen+2+msgLen:]
	
	// Reconstruct public key
	pubKey, err := slhdsa.PublicKeyFromBytes(pubKeyBytes, mode)
	if err != nil {
		return []byte{0}, fmt.Errorf("invalid public key: %w", err)
	}
	
	// Verify signature
	valid := pubKey.Verify(message, signature, nil)
	if valid {
		return []byte{1}, nil
	}
	return []byte{0}, nil
}
