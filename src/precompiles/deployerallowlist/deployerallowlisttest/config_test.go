// Copyright (C) 2019-2025, Lux Industries, Inc. All rights reserved.
// See the file LICENSE for licensing terms.

package deployerallowlisttest

import (
	"testing"

	"github.com/luxfi/evm/precompile/allowlist/allowlisttest"
	"github.com/luxfi/evm/precompile/contracts/deployerallowlist"
	"github.com/luxfi/evm/precompile/precompileconfig"
	"github.com/luxfi/evm/precompile/precompiletest"
	"github.com/luxfi/evm/utils"
	"github.com/luxfi/geth/common"
	"go.uber.org/mock/gomock"
)

func TestVerify(t *testing.T) {
	allowlisttest.VerifyPrecompileWithAllowListTests(t, deployerallowlist.Module, nil)
}

func TestEqual(t *testing.T) {
	admins := []common.Address{allowlisttest.TestAdminAddr}
	enableds := []common.Address{allowlisttest.TestEnabledAddr}
	managers := []common.Address{allowlisttest.TestManagerAddr}
	tests := map[string]precompiletest.ConfigEqualTest{
		"non-nil config and nil other": {
			Config:   deployerallowlist.NewConfig(utils.NewUint64(3), admins, enableds, managers),
			Other:    nil,
			Expected: false,
		},
		"different type": {
			Config:   deployerallowlist.NewConfig(nil, nil, nil, nil),
			Other:    precompileconfig.NewMockConfig(gomock.NewController(t)),
			Expected: false,
		},
		"different timestamp": {
			Config:   deployerallowlist.NewConfig(utils.NewUint64(3), admins, enableds, managers),
			Other:    deployerallowlist.NewConfig(utils.NewUint64(4), admins, enableds, managers),
			Expected: false,
		},
		"same config": {
			Config:   deployerallowlist.NewConfig(utils.NewUint64(3), admins, enableds, managers),
			Other:    deployerallowlist.NewConfig(utils.NewUint64(3), admins, enableds, managers),
			Expected: true,
		},
	}
	allowlisttest.EqualPrecompileWithAllowListTests(t, deployerallowlist.Module, tests)
}
