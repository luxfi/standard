// SPDX-License-Identifier: MIT
pragma solidity ^0.8.31;

/**
 * @title Utils Re-exports
 * @author Lux Industries Inc
 * @notice OpenZeppelin utility re-exports for @luxfi/standard
 * @dev Import from here - no need for @openzeppelin imports
 *
 * Usage:
 *   import {ReentrancyGuard} from "@luxfi/standard/utils/Utils.sol";
 *   import {Pausable} from "@luxfi/standard/utils/Utils.sol";
 */

// Security
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";

// Introspection
import {ERC165} from "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {ERC165Checker} from "@openzeppelin/contracts/utils/introspection/ERC165Checker.sol";

// Math
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SignedMath} from "@openzeppelin/contracts/utils/math/SignedMath.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

// Structs
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {EnumerableMap} from "@openzeppelin/contracts/utils/structs/EnumerableMap.sol";
import {BitMaps} from "@openzeppelin/contracts/utils/structs/BitMaps.sol";

// Cryptography
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import {SignatureChecker} from "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";
import {MerkleProof} from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";

// Address utils
import {Address} from "@openzeppelin/contracts/utils/Address.sol";

// Context
import {Context} from "@openzeppelin/contracts/utils/Context.sol";

// Multicall
import {Multicall} from "@openzeppelin/contracts/utils/Multicall.sol";

// Strings
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

// Nonces (for EIP-2612/Permit)
import {Nonces} from "@openzeppelin/contracts/utils/Nonces.sol";

// Storage
import {StorageSlot} from "@openzeppelin/contracts/utils/StorageSlot.sol";
import {ShortStrings} from "@openzeppelin/contracts/utils/ShortStrings.sol";

// EIP712
import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";

// Checkpoints (for ERC20Votes)
import {Checkpoints} from "@openzeppelin/contracts/utils/structs/Checkpoints.sol";
