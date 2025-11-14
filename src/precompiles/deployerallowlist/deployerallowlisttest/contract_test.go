// Copyright (C) 2019-2025, Lux Industries, Inc. All rights reserved.
// See the file LICENSE for licensing terms.

package deployerallowlisttest

import (
	"testing"

	"github.com/luxfi/evm/precompile/allowlist/allowlisttest"
	"github.com/luxfi/evm/precompile/contracts/deployerallowlist"
)

func TestContractDeployerAllowListRun(t *testing.T) {
	allowlisttest.RunPrecompileWithAllowListTests(t, deployerallowlist.Module, nil)
}
