// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.31;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

import {
    IDIDResolver,
    IDIDRegistry,
    DIDDocument
} from "./interfaces/IDID.sol";

/**
 * @title DIDResolver - Universal DID Resolution for Lux Network
 * @notice Resolves DIDs across multiple registries and methods
 * @dev Supports omnichain identity resolution across Lux, AI, Ethereum, etc.
 *
 * SUPPORTED METHODS:
 * ┌─────────────────────────────────────────────────────────────────────────────┐
 * │  Method     │ Format                          │ Example                     │
 * ├─────────────────────────────────────────────────────────────────────────────┤
 * │  lux        │ did:lux:<identifier>            │ did:lux:alice               │
 * │  lux        │ did:lux:mainnet:<address>       │ did:lux:mainnet:0x1234...   │
 * │  lux        │ did:lux:testnet:<address>       │ did:lux:testnet:0x1234...   │
 * │  ai      │ did:ai:<username>            │ did:ai:user123           │
 * │  ai      │ did:ai:eth:<address>         │ did:ai:eth:0x1234...     │
 * │  ethr       │ did:ethr:<address>              │ did:ethr:0x1234...          │
 * │  key        │ did:key:<public-key>            │ did:key:z6Mk...             │
 * │  web        │ did:web:<domain>                │ did:web:lux.network         │
 * └─────────────────────────────────────────────────────────────────────────────┘
 *
 * RESOLUTION FLOW:
 * ┌─────────────┐     ┌─────────────┐     ┌─────────────┐     ┌─────────────┐
 * │   DID       │────▶│   Parse     │────▶│   Route     │────▶│   Resolve   │
 * │   Input     │     │   Method    │     │   Registry  │     │   Document  │
 * └─────────────┘     └─────────────┘     └─────────────┘     └─────────────┘
 */
contract DIDResolver is IDIDResolver, AccessControl {
    // ============ Constants ============

    /// @notice Role for method registrars
    bytes32 public constant REGISTRAR_ROLE = keccak256("REGISTRAR_ROLE");

    /// @notice Resolver version
    string public constant VERSION = "1.0.0";

    // ============ State ============

    /// @notice Method to registry mapping
    mapping(bytes32 => address) private _registries;

    /// @notice List of registered methods
    string[] private _methods;

    /// @notice Method hash to method string
    mapping(bytes32 => string) private _methodStrings;

    /// @notice Default registry for fallback resolution
    address public defaultRegistry;

    // ============ Events ============

    event MethodRegistered(string method, address indexed registry);
    event MethodUnregistered(string method, address indexed registry);
    event DefaultRegistryChanged(address indexed oldRegistry, address indexed newRegistry);
    event ResolutionAttempted(string did, address indexed registry, bool success);

    // ============ Errors ============

    error InvalidDID();
    error MethodNotRegistered();
    error RegistryAlreadyExists();
    error ZeroAddress();
    error EmptyMethod();
    error ResolutionFailed();

    // ============ Constructor ============

    /**
     * @notice Initialize the DID Resolver
     * @param admin Admin address for access control
     * @param _defaultRegistry Default registry for unregistered methods
     */
    constructor(address admin, address _defaultRegistry) {
        if (admin == address(0)) revert ZeroAddress();

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(REGISTRAR_ROLE, admin);

        if (_defaultRegistry != address(0)) {
            defaultRegistry = _defaultRegistry;
        }
    }

    // ============ Resolution ============

    /**
     * @notice Resolve a DID to its document
     * @param did The DID to resolve
     * @return document The resolved DID Document
     * @return registry The registry that resolved the DID
     */
    function resolve(
        string calldata did
    ) external view returns (DIDDocument memory document, address registry) {
        // Parse DID method
        string memory method = _parseMethod(did);
        bytes32 methodHash = keccak256(bytes(method));

        // Get registry for method
        registry = _registries[methodHash];
        
        // Fall back to default registry if method not found
        if (registry == address(0)) {
            registry = defaultRegistry;
        }
        
        if (registry == address(0)) revert MethodNotRegistered();

        // Resolve through registry
        try IDIDRegistry(registry).resolve(did) returns (DIDDocument memory doc) {
            document = doc;
        } catch {
            revert ResolutionFailed();
        }
    }

    /**
     * @notice Resolve a DID with detailed resolution metadata
     * @param did The DID to resolve
     * @return document The resolved DID Document
     * @return registry The registry that resolved the DID
     * @return method The DID method
     * @return resolutionTime Block timestamp of resolution
     */
    function resolveWithMetadata(
        string calldata did
    ) external view returns (
        DIDDocument memory document,
        address registry,
        string memory method,
        uint256 resolutionTime
    ) {
        method = _parseMethod(did);
        bytes32 methodHash = keccak256(bytes(method));

        registry = _registries[methodHash];
        if (registry == address(0)) registry = defaultRegistry;
        if (registry == address(0)) revert MethodNotRegistered();

        document = IDIDRegistry(registry).resolve(did);
        resolutionTime = block.timestamp;
    }

    /**
     * @notice Check if a DID can be resolved
     * @param did The DID to check
     * @return resolvable Whether the DID can be resolved
     * @return registry The registry that would handle resolution
     */
    function canResolve(
        string calldata did
    ) external view returns (bool resolvable, address registry) {
        string memory method = _parseMethod(did);
        bytes32 methodHash = keccak256(bytes(method));

        registry = _registries[methodHash];
        if (registry == address(0)) registry = defaultRegistry;

        if (registry == address(0)) {
            return (false, address(0));
        }

        try IDIDRegistry(registry).didExists(did) returns (bool exists) {
            resolvable = exists;
        } catch {
            resolvable = false;
        }
    }

    // ============ Method Registration ============

    /**
     * @notice Register a DID method resolver
     * @param method The DID method (e.g., "lux", "ai")
     * @param registry The registry contract for this method
     */
    function registerMethod(
        string calldata method,
        address registry
    ) external onlyRole(REGISTRAR_ROLE) {
        if (bytes(method).length == 0) revert EmptyMethod();
        if (registry == address(0)) revert ZeroAddress();

        bytes32 methodHash = keccak256(bytes(method));
        
        if (_registries[methodHash] != address(0)) {
            revert RegistryAlreadyExists();
        }

        _registries[methodHash] = registry;
        _methods.push(method);
        _methodStrings[methodHash] = method;

        emit MethodRegistered(method, registry);
    }

    /**
     * @notice Update a method's registry
     * @param method The DID method to update
     * @param newRegistry The new registry contract
     */
    function updateMethodRegistry(
        string calldata method,
        address newRegistry
    ) external onlyRole(REGISTRAR_ROLE) {
        if (newRegistry == address(0)) revert ZeroAddress();

        bytes32 methodHash = keccak256(bytes(method));
        
        if (_registries[methodHash] == address(0)) {
            revert MethodNotRegistered();
        }

        _registries[methodHash] = newRegistry;

        emit MethodRegistered(method, newRegistry);
    }

    /**
     * @notice Unregister a DID method
     * @param method The DID method to unregister
     */
    function unregisterMethod(
        string calldata method
    ) external onlyRole(REGISTRAR_ROLE) {
        bytes32 methodHash = keccak256(bytes(method));
        address registry = _registries[methodHash];
        
        if (registry == address(0)) revert MethodNotRegistered();

        delete _registries[methodHash];
        delete _methodStrings[methodHash];

        // Remove from methods array
        for (uint256 i = 0; i < _methods.length; i++) {
            if (keccak256(bytes(_methods[i])) == methodHash) {
                _methods[i] = _methods[_methods.length - 1];
                _methods.pop();
                break;
            }
        }

        emit MethodUnregistered(method, registry);
    }

    /**
     * @notice Get the registry for a DID method
     */
    function getRegistry(string calldata method) external view returns (address) {
        bytes32 methodHash = keccak256(bytes(method));
        return _registries[methodHash];
    }

    /**
     * @notice Get all registered methods
     */
    function getRegisteredMethods() external view returns (string[] memory) {
        return _methods;
    }

    /**
     * @notice Get method count
     */
    function methodCount() external view returns (uint256) {
        return _methods.length;
    }

    // ============ Admin Functions ============

    /**
     * @notice Set the default registry for fallback resolution
     */
    function setDefaultRegistry(
        address newDefaultRegistry
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        address old = defaultRegistry;
        defaultRegistry = newDefaultRegistry;
        emit DefaultRegistryChanged(old, newDefaultRegistry);
    }

    // ============ Internal Functions ============

    /**
     * @notice Parse the method from a DID string
     * @param did The DID string (e.g., "did:lux:alice")
     * @return method The DID method (e.g., "lux")
     */
    function _parseMethod(string calldata did) internal pure returns (string memory method) {
        bytes memory didBytes = bytes(did);
        
        // Minimum DID: "did:x:y" = 7 characters
        if (didBytes.length < 7) revert InvalidDID();
        
        // Check "did:" prefix
        if (
            didBytes[0] != 'd' ||
            didBytes[1] != 'i' ||
            didBytes[2] != 'd' ||
            didBytes[3] != ':'
        ) {
            revert InvalidDID();
        }

        // Find second colon (end of method)
        uint256 methodEnd = 0;
        for (uint256 i = 4; i < didBytes.length; i++) {
            if (didBytes[i] == ':') {
                methodEnd = i;
                break;
            }
        }

        if (methodEnd == 0) revert InvalidDID();

        // Extract method
        bytes memory methodBytes = new bytes(methodEnd - 4);
        for (uint256 i = 4; i < methodEnd; i++) {
            methodBytes[i - 4] = didBytes[i];
        }

        method = string(methodBytes);
    }

    /**
     * @notice Parse the full DID into components
     * @param did The DID string
     * @return method The DID method
     * @return identifier The method-specific identifier
     */
    function parseDID(
        string calldata did
    ) external pure returns (string memory method, string memory identifier) {
        bytes memory didBytes = bytes(did);
        
        if (didBytes.length < 7) revert InvalidDID();
        
        // Verify "did:" prefix
        if (
            didBytes[0] != 'd' ||
            didBytes[1] != 'i' ||
            didBytes[2] != 'd' ||
            didBytes[3] != ':'
        ) {
            revert InvalidDID();
        }

        // Find method end (second colon)
        uint256 methodEnd = 0;
        for (uint256 i = 4; i < didBytes.length; i++) {
            if (didBytes[i] == ':') {
                methodEnd = i;
                break;
            }
        }

        if (methodEnd == 0) revert InvalidDID();

        // Extract method
        bytes memory methodBytes = new bytes(methodEnd - 4);
        for (uint256 i = 4; i < methodEnd; i++) {
            methodBytes[i - 4] = didBytes[i];
        }
        method = string(methodBytes);

        // Extract identifier (everything after method colon)
        uint256 idLength = didBytes.length - methodEnd - 1;
        bytes memory idBytes = new bytes(idLength);
        for (uint256 i = 0; i < idLength; i++) {
            idBytes[i] = didBytes[methodEnd + 1 + i];
        }
        identifier = string(idBytes);
    }
}

/**
 * @title OmnichainDIDResolver
 * @notice Extended resolver for cross-chain DID resolution
 * @dev Integrates with Warp messaging for cross-chain lookups
 */
contract OmnichainDIDResolver is DIDResolver {
    // ============ State ============

    /// @notice Chain ID to resolver mapping for cross-chain lookups
    mapping(uint256 => address) public chainResolvers;

    /// @notice Cached cross-chain resolutions
    mapping(bytes32 => DIDDocument) private _crossChainCache;

    /// @notice Cache expiry per DID
    mapping(bytes32 => uint256) private _cacheExpiry;

    /// @notice Default cache TTL (1 hour)
    uint256 public constant CACHE_TTL = 1 hours;

    // ============ Events ============

    event ChainResolverRegistered(uint256 indexed chainId, address resolver);
    event CrossChainResolutionCached(string did, uint256 sourceChain);

    // ============ Constructor ============

    constructor(
        address admin,
        address _defaultRegistry
    ) DIDResolver(admin, _defaultRegistry) {}

    // ============ Cross-Chain Resolution ============

    /**
     * @notice Register a resolver for another chain
     * @param chainId The chain ID
     * @param resolver The resolver address on that chain
     */
    function registerChainResolver(
        uint256 chainId,
        address resolver
    ) external onlyRole(REGISTRAR_ROLE) {
        chainResolvers[chainId] = resolver;
        emit ChainResolverRegistered(chainId, resolver);
    }

    /**
     * @notice Get omnichain variants of a DID
     * @param did The base DID
     * @return variants Array of equivalent DIDs across chains
     */
    function getOmnichainVariants(
        string calldata did
    ) external view returns (string[] memory variants) {
        // This would be extended to generate cross-chain DID variants
        // e.g., did:lux:alice -> [did:ai:alice, did:ethr:0x...]
        variants = new string[](1);
        variants[0] = did;
    }

    /**
     * @notice Check if two DIDs represent the same entity
     * @param did1 First DID
     * @param did2 Second DID
     * @return isSame Whether they represent the same entity
     */
    function isSameEntity(
        string calldata did1,
        string calldata did2
    ) external view returns (bool isSame) {
        // Check if DIDs are directly equal
        if (keccak256(bytes(did1)) == keccak256(bytes(did2))) {
            return true;
        }

        // Check also-known-as relationships
        bytes32 did1Hash = keccak256(bytes(did1));
        bytes32 did2Hash = keccak256(bytes(did2));

        // Would check cross-references in DID documents
        // This is a simplified implementation
        return false;
    }
}
