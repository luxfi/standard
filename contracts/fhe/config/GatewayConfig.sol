// SPDX-License-Identifier: MIT
pragma solidity >=0.8.19 <0.9.0;

/**
 * @title GatewayConfig
 * @dev Configuration for LuxFHE Gateway
 * @notice Configures gateway address for decryption operations
 */
abstract contract GatewayConfig {
    address internal constant GATEWAY_ADDRESS = address(0); // Set on deployment
}

// Network-specific configs
abstract contract LuxGatewayConfig is GatewayConfig {}
abstract contract LuxTestnetGatewayConfig is GatewayConfig {}
abstract contract LuxMainnetGatewayConfig is GatewayConfig {}

// Legacy aliases for backward compatibility
abstract contract SepoliaZamaGatewayConfig is LuxGatewayConfig {}
abstract contract SepoliaGatewayConfig is LuxTestnetGatewayConfig {}
abstract contract MainnetGatewayConfig is LuxMainnetGatewayConfig {}
