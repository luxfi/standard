// SPDX-License-Identifier: Ecosystem
// Vendored from ava-labs/subnet-evm@v0.6.11 contracts/interfaces/INativeMinter.sol.
// Original SPDX header: MIT.

pragma solidity >=0.8.25;

/// IAllowList is the upstream prerequisite for INativeMinter. The
/// NativeMinter precompile (0x0200000000000000000000000000000000000001)
/// inherits the allow-list permissioning model so only sanctioned
/// addresses can call `mintNativeCoin`. We vendor a minimal copy here so
/// the validator-manager stack composes against luxfi/standard without
/// reaching into avalabs/subnet-evm-contracts.
interface IAllowList {
    event RoleSet(uint256 indexed role, address indexed account, address indexed sender, uint256 oldRole);

    function setAdmin(address addr) external;
    function setEnabled(address addr) external;
    function setManager(address addr) external;
    function setNone(address addr) external;
    function readAllowList(address addr) external view returns (uint256 role);
}

/// INativeMinter exposes the NativeMinter precompile at the canonical
/// address 0x0200000000000000000000000000000000000001. `mintNativeCoin`
/// is gated by the allow-list — caller must have the Enabled, Manager,
/// or Admin role.
///
/// Required by NativeTokenStakingManager._reward to inflate the native
/// gas token as a validation reward. If the host chain does NOT activate
/// the NativeMinter precompile at genesis, downstream consumers MUST
/// either:
///   - extend PoSValidatorManager directly (skip NativeTokenStakingManager)
///   - override _reward to transfer from a pre-funded pool instead
interface INativeMinter is IAllowList {
    event NativeCoinMinted(address indexed sender, address indexed recipient, uint256 amount);

    function mintNativeCoin(address addr, uint256 amount) external;
}
