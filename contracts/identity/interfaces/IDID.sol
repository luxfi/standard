// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.31;

/**
 * @title IDID - Interface for W3C DID Operations
 * @notice Based on W3C DID Core specification (https://www.w3.org/TR/did-core/)
 * @dev Implements on-chain DID registry and resolution for Lux Network
 */

/// @notice Verification method types as per W3C DID specification
enum VerificationMethodType {
    Ed25519VerificationKey2020,
    Ed25519VerificationKey2018,
    X25519KeyAgreementKey2020,
    X25519KeyAgreementKey2019,
    EcdsaSecp256k1VerificationKey2019,
    EcdsaSecp256k1RecoveryMethod2020,
    JsonWebKey2020,
    Bls12381G2Key2020,
    MlDsa44VerificationKey2024,      // Post-quantum: FIPS 204
    MlDsa65VerificationKey2024,      // Post-quantum: FIPS 204
    SlhDsa128VerificationKey2024,    // Post-quantum: FIPS 205
    Custom
}

/// @notice Service endpoint types
enum ServiceType {
    MessagingService,
    LLMProvider,
    HanzoNode,
    LinkedDomains,
    DIDCommMessaging,
    CredentialRegistry,
    Custom
}

/// @notice Verification method structure
struct VerificationMethod {
    bytes32 id;                      // Fragment ID (e.g., "key-1")
    VerificationMethodType methodType;
    address controller;              // Controller address
    bytes publicKeyMultibase;        // Public key in multibase format
    bytes32 blockchainAccountId;     // Optional: blockchain account identifier
}

/// @notice Service endpoint structure
struct Service {
    bytes32 id;                      // Fragment ID (e.g., "messaging")
    ServiceType serviceType;
    string endpoint;                 // Service endpoint URL
    bytes data;                      // Additional service data
}

/// @notice DID Document structure (simplified for on-chain)
struct DIDDocument {
    string did;                      // Full DID string (e.g., "did:lux:alice")
    address controller;              // Primary controller
    address[] additionalControllers; // Additional controllers
    string[] alsoKnownAs;            // Alternative identifiers
    uint256 created;                 // Creation timestamp
    uint256 updated;                 // Last update timestamp
    bool active;                     // Whether DID is active
}

/**
 * @title IDIDRegistry
 * @notice Interface for DID Registry operations
 */
interface IDIDRegistry {
    // ============ Events ============
    
    event DIDCreated(
        string indexed didHash,
        string did,
        address indexed controller,
        uint256 timestamp
    );
    
    event DIDUpdated(
        string indexed didHash,
        string did,
        address indexed controller,
        uint256 timestamp
    );
    
    event DIDDeactivated(
        string indexed didHash,
        string did,
        address indexed controller,
        uint256 timestamp
    );
    
    event ControllerChanged(
        string indexed didHash,
        address indexed oldController,
        address indexed newController
    );
    
    event VerificationMethodAdded(
        string indexed didHash,
        bytes32 indexed methodId,
        VerificationMethodType methodType
    );
    
    event VerificationMethodRemoved(
        string indexed didHash,
        bytes32 indexed methodId
    );
    
    event ServiceAdded(
        string indexed didHash,
        bytes32 indexed serviceId,
        ServiceType serviceType
    );
    
    event ServiceRemoved(
        string indexed didHash,
        bytes32 indexed serviceId
    );
    
    event AlsoKnownAsAdded(
        string indexed didHash,
        string didAlias
    );
    
    // ============ DID Operations ============
    
    /**
     * @notice Create a new DID
     * @param method DID method (e.g., "lux", "hanzo")
     * @param identifier Method-specific identifier
     * @return did The full DID string
     */
    function createDID(
        string calldata method,
        string calldata identifier
    ) external returns (string memory did);
    
    /**
     * @notice Resolve a DID to its document
     * @param did The DID to resolve
     * @return document The DID Document
     */
    function resolve(string calldata did) external view returns (DIDDocument memory document);
    
    /**
     * @notice Check if a DID exists and is active
     * @param did The DID to check
     * @return exists Whether the DID exists and is active
     */
    function didExists(string calldata did) external view returns (bool exists);
    
    /**
     * @notice Deactivate a DID
     * @param did The DID to deactivate
     */
    function deactivateDID(string calldata did) external;
    
    /**
     * @notice Transfer DID control to a new controller
     * @param did The DID to transfer
     * @param newController The new controller address
     */
    function changeController(string calldata did, address newController) external;
    
    // ============ Verification Methods ============
    
    /**
     * @notice Add a verification method to a DID
     * @param did The DID to add the method to
     * @param method The verification method to add
     */
    function addVerificationMethod(
        string calldata did,
        VerificationMethod calldata method
    ) external;
    
    /**
     * @notice Remove a verification method from a DID
     * @param did The DID to remove the method from
     * @param methodId The method ID to remove
     */
    function removeVerificationMethod(
        string calldata did,
        bytes32 methodId
    ) external;
    
    /**
     * @notice Get all verification methods for a DID
     * @param did The DID to query
     * @return methods Array of verification methods
     */
    function getVerificationMethods(
        string calldata did
    ) external view returns (VerificationMethod[] memory methods);
    
    // ============ Services ============
    
    /**
     * @notice Add a service endpoint to a DID
     * @param did The DID to add the service to
     * @param service The service to add
     */
    function addService(
        string calldata did,
        Service calldata service
    ) external;
    
    /**
     * @notice Remove a service from a DID
     * @param did The DID to remove the service from
     * @param serviceId The service ID to remove
     */
    function removeService(
        string calldata did,
        bytes32 serviceId
    ) external;
    
    /**
     * @notice Get all services for a DID
     * @param did The DID to query
     * @return services Array of services
     */
    function getServices(
        string calldata did
    ) external view returns (Service[] memory services);
    
    // ============ Also Known As ============
    
    /**
     * @notice Add an alternative identifier
     * @param did The DID to add the alias to
     * @param didAlias The alternative identifier
     */
    function addAlsoKnownAs(
        string calldata did,
        string calldata didAlias
    ) external;
    
    /**
     * @notice Get the controller address for a DID
     * @param did The DID to query
     * @return controller The controller address
     */
    function controllerOf(string calldata did) external view returns (address controller);
}

/**
 * @title IDIDResolver
 * @notice Interface for DID resolution across multiple registries
 */
interface IDIDResolver {
    /**
     * @notice Resolve a DID from any supported method
     * @param did The DID to resolve
     * @return document The resolved DID Document
     * @return registry The registry that resolved the DID
     */
    function resolve(
        string calldata did
    ) external view returns (DIDDocument memory document, address registry);
    
    /**
     * @notice Register a DID method resolver
     * @param method The DID method (e.g., "lux", "hanzo")
     * @param registry The registry contract for this method
     */
    function registerMethod(string calldata method, address registry) external;
    
    /**
     * @notice Get the registry for a DID method
     * @param method The DID method
     * @return registry The registry address
     */
    function getRegistry(string calldata method) external view returns (address registry);
}
