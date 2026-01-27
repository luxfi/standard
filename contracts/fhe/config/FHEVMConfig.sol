// SPDX-License-Identifier: MIT
pragma solidity >=0.8.19 <0.9.0;

/**
 * @title FHEVMConfig
 * @dev Configuration for LuxFHE VM - placeholder for native deployment
 * @notice This is a minimal implementation for compatibility
 */
abstract contract FHEVMConfig {
    // LuxFHE native chain doesn't need external configuration
    // FHE operations are handled natively by the VM
}

// Network-specific configs
abstract contract LuxFHEVMConfig is FHEVMConfig {}
abstract contract LuxTestnetFHEVMConfig is FHEVMConfig {}
abstract contract LuxMainnetFHEVMConfig is FHEVMConfig {}

// Legacy aliases for backward compatibility
abstract contract SepoliaLegacyFHEVMConfig is LuxFHEVMConfig {}
abstract contract SepoliaFHEVMConfig is LuxTestnetFHEVMConfig {}
abstract contract MainnetFHEVMConfig is LuxMainnetFHEVMConfig {}
