// SPDX-License-Identifier: Ecosystem
// Vendored from ava-labs/teleporter@v1.0.0 utilities/.
// Original copyright (c) 2024, Ava Labs, Inc. All rights reserved.

pragma solidity >=0.8.25;

/// ICMInitializable selects whether the contract's initializers stay
/// open (Allowed — implementation can self-initialize and is intended
/// to be the runtime instance) or are disabled at construction
/// (Disallowed — implementation is meant to live behind an upgradeable
/// proxy; calling initialize on the implementation directly would lock
/// out the proxy's initialize).
enum ICMInitializable {
    Allowed,
    Disallowed
}
