// Copyright (C) 2025, Lux Industries, Inc. All rights reserved.
// See the file LICENSE for licensing terms.

package ringtailthreshold

import (
	"github.com/luxfi/evm/precompile/contract"
	"github.com/luxfi/evm/precompile/modules"
	"github.com/luxfi/geth/common"
)

var _ contract.Configurator = &configurator{}

// ConfigKey is the key used in the precompile config file to configure this precompile
const ConfigKey = "ringtailThresholdConfig"

type configurator struct{}

// NewConfigurator creates a new configurator for the Ringtail threshold signature precompile
func NewConfigurator() contract.Configurator {
	return &configurator{}
}

// MakeConfig returns a new Ringtail threshold config instance
func (c *configurator) MakeConfig() contract.Config {
	return &Config{}
}

// Configure configures the Ringtail threshold signature precompile
func (c *configurator) Configure(
	chainConfig contract.ChainConfig,
	cfg contract.Config,
	state contract.StateDB,
	blockContext contract.BlockContext,
) error {
	// No special configuration needed for Ringtail threshold
	// The precompile is stateless and requires no initialization
	return nil
}

// Config implements the StatefulPrecompileConfig interface
type Config struct {
	contract.UpgradeableConfig
}

// Address returns the address of the Ringtail threshold signature precompile
func (c *Config) Address() common.Address {
	return ContractRingtailThresholdAddress
}

// Contract returns the precompile contract instance
func (c *Config) Contract() contract.StatefulPrecompiledContract {
	return RingtailThresholdPrecompile
}

// Configure implements the StatefulPrecompileConfig interface
func (c *Config) Configure(
	chainConfig contract.ChainConfig,
	cfg contract.Config,
	state contract.StateDB,
	blockContext contract.BlockContext,
) error {
	return NewConfigurator().Configure(chainConfig, cfg, state, blockContext)
}

// Equal returns true if the two configs are equal
func (c *Config) Equal(other contract.Config) bool {
	otherConfig, ok := other.(*Config)
	if !ok {
		return false
	}
	return c.UpgradeableConfig.Equal(&otherConfig.UpgradeableConfig)
}

// String returns a string representation of the config
func (c *Config) String() string {
	return "RingtailThresholdConfig"
}

// Key returns the config key
func (c *Config) Key() string {
	return ConfigKey
}

func init() {
	// Register the Ringtail threshold precompile module
	modules.RegisterModule(ConfigKey, NewConfigurator())
}
