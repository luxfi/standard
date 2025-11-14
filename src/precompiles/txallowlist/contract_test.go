// Copyright (C) 2019-2025, Lux Industries, Inc. All rights reserved.
// See the file LICENSE for licensing terms.

package txallowlist

import (
	"testing"

	"github.com/luxfi/evm/precompile/allowlist/allowlisttest"
)

func TestTxAllowListRun(t *testing.T) {
	allowlisttest.RunPrecompileWithAllowListTests(t, Module, nil)
}
