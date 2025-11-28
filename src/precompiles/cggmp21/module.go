// Copyright (C) 2025, Lux Industries, Inc. All rights reserved.
// See the file LICENSE for licensing terms.

package cggmp21

import (
	"github.com/luxfi/evm/precompile/contract"
	"github.com/luxfi/evm/precompile/modules"
	"github.com/luxfi/geth/common"
)

var _ contract.Configurator = &configurator{}

type configurator struct{}

func init() {
	// Register CGGMP21 precompile module
	if err := modules.RegisterModule(
		ContractCGGMP21VerifyAddress.String(),
		&configurator{},
	); err != nil {
		panic(err)
	}
}

func (*configurator) MakeConfig() contract.StatefulPrecompileConfig {
	return &Config{
		Address: ContractCGGMP21VerifyAddress,
	}
}

// Config implements the StatefulPrecompileConfig interface for CGGMP21
type Config struct {
	Address common.Address `json:"address"`
}

func (c *Config) Key() string {
	return c.Address.String()
}

func (c *Config) Timestamp() *uint64 {
	return nil
}

func (c *Config) IsDisabled() bool {
	return false
}

func (c *Config) Equal(cfg contract.StatefulPrecompileConfig) bool {
	other, ok := cfg.(*Config)
	if !ok {
		return false
	}
	return c.Address == other.Address
}

func (c *Config) Configure(
	chainConfig contract.ChainConfig,
	precompileConfig contract.PrecompileConfig,
	state contract.StateDB,
) error {
	// No state initialization required
	return nil
}

func (c *Config) Contract() contract.StatefulPrecompiledContract {
	return CGGMP21VerifyPrecompile
}
