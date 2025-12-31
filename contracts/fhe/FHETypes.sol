// SPDX-License-Identifier: MIT
// FHETypes.sol - User-defined encrypted types for FHE operations
pragma solidity >=0.8.19 <0.9.0;

// ===== Encrypted Value Types =====
// All encrypted types are represented as uint256 containing a ciphertext hash
type ebool is uint256;
type euint8 is uint256;
type euint16 is uint256;
type euint32 is uint256;
type euint64 is uint256;
type euint128 is uint256;
type euint256 is uint256;
type eaddress is uint256;
type einput is bytes32;

// ===== Lux FHE Precompile Addresses =====
// FHE precompiles are in the Lux reserved range: 0x0200...0080-0083
// These are EVM precompiles, NOT deployed contracts

/// @dev Main FHE operations precompile (arithmetic, comparison, etc.)
address constant FHE_PRECOMPILE = 0x0200000000000000000000000000000000000080;

/// @dev Access Control List precompile (allow/deny ciphertext access)
address constant FHE_ACL_PRECOMPILE = 0x0200000000000000000000000000000000000081;

/// @dev Input Verifier precompile (verify encrypted inputs)
address constant FHE_INPUT_PRECOMPILE = 0x0200000000000000000000000000000000000082;

/// @dev Gateway precompile (decryption requests to T-Chain)
address constant FHE_GATEWAY_PRECOMPILE = 0x0200000000000000000000000000000000000083;

/// @dev Legacy alias for backward compatibility - points to main FHE precompile
address constant T_CHAIN_FHE_ADDRESS = FHE_PRECOMPILE;
