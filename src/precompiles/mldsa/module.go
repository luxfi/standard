// Copyright (C) 2025, Lux Industries Inc. All rights reserved.
// See the file LICENSE for licensing terms.

package mldsa

import (
	"github.com/luxfi/evm/precompile/contract"
	"github.com/luxfi/geth/common"
)

var (
	// ContractAddress is the address of the ML-DSA precompile contract
	// 0x0200000000000000000000000000000000000006
	ContractAddress = common.HexToAddress("0x0200000000000000000000000000000000000006")

	// Module is the precompile module singleton
	Module = &module{
		address:  ContractAddress,
		contract: MLDSAVerifyPrecompile,
	}
)

type module struct {
	address  common.Address
	contract contract.StatefulPrecompiledContract
}

// Address returns the address where the stateful precompile is accessible.
func (m *module) Address() common.Address {
	return m.address
}

// Contract returns a thread-safe singleton that can be used as the StatefulPrecompiledContract
func (m *module) Contract() contract.StatefulPrecompiledContract {
	return m.contract
}

// Configure is a no-op for ML-DSA as it has no configuration
func (m *module) Configure(
	_ contract.StateDB,
	_ common.Address,
) error {
	return nil
}
