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
    AINode,
    LinkedDomains,
    DIDCommMessaging,
    CredentialRegistry,
    // x402 Payment Protocol services
    X402PaymentEndpoint,     // x402 payment verification endpoint
    X402Facilitator,         // x402 facilitator service
    X402Resource,            // x402 protected resource
    // Verifiable Credentials
    CredentialIssuer,        // VC issuer service
    CredentialVerifier,      // VC verification service
    CredentialStatus,        // Credential status/revocation
    // Cross-chain
    OmnichainBridge,         // Cross-chain identity bridge
    WarpMessenger,           // Lux Warp messaging service
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
     * @param method DID method (e.g., "lux", "ai")
     * @param identifier Method-specific identifier
     * @return did The full DID string
     * @dev May be payable in premium implementations
     */
    function createDID(
        string calldata method,
        string calldata identifier
    ) external payable returns (string memory did);
    
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
     * @param method The DID method (e.g., "lux", "ai")
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

/**
 * @title IPremiumDIDRegistry
 * @notice Interface for Premium DID Registry with tiered pricing
 * @dev Supports paid registration for short names (1-4 chars)
 *
 * PRICING TIERS:
 * ┌─────────────────────────────────────────────────────────────────┐
 * │  Length  │  Tier           │  Price (Native)  │  Example       │
 * ├─────────────────────────────────────────────────────────────────┤
 * │  1 char  │  Ultra Premium  │  1000 tokens     │  did:lux:a     │
 * │  2 chars │  Super Premium  │  100 tokens      │  did:lux:ai    │
 * │  3 chars │  Premium        │  10 tokens       │  did:lux:bob   │
 * │  4 chars │  Standard       │  1 token         │  did:lux:john  │
 * │  5+ chars│  Basic          │  0.1 tokens      │  did:lux:alice │
 * └─────────────────────────────────────────────────────────────────┘
 */
interface IPremiumDIDRegistry is IDIDRegistry {
    // ============ Events ============

    event DIDRegistered(
        string indexed didHash,
        string did,
        address indexed controller,
        uint256 price,
        uint256 expiresAt
    );

    event DIDRenewed(
        string indexed didHash,
        string did,
        uint256 newExpiry,
        uint256 price
    );

    event DIDExpired(string indexed didHash, string did);

    // ============ Pricing ============

    /**
     * @notice Get registration price for an identifier
     * @param identifier The identifier to price
     * @return price The price in native tokens
     */
    function getPrice(string calldata identifier) external view returns (uint256 price);

    /**
     * @notice Get renewal price for an identifier
     * @param identifier The identifier
     * @return price The renewal price (typically 50% of registration)
     */
    function getRenewalPrice(string calldata identifier) external view returns (uint256 price);

    /**
     * @notice Get the price tier name for an identifier
     * @param identifier The identifier
     * @return tier The tier name
     */
    function getPriceTier(string calldata identifier) external pure returns (string memory tier);

    /**
     * @notice Check if an identifier is available
     * @param identifier The identifier to check
     * @return available Whether the DID is available
     * @return price The price to register
     */
    function isAvailable(string calldata identifier) external view returns (bool available, uint256 price);

    // ============ Expiration ============

    /**
     * @notice Get DID expiration info
     * @param did The DID to check
     * @return expiry Expiration timestamp
     * @return isExpired Whether expired
     * @return inGracePeriod Whether in grace period
     */
    function getExpiry(string calldata did) external view returns (
        uint256 expiry,
        bool isExpired,
        bool inGracePeriod
    );

    /**
     * @notice Renew a DID
     * @param did The DID to renew
     */
    function renewDID(string calldata did) external payable;

    // ============ Network Info ============

    /**
     * @notice Get network name (lux, ai, zoo)
     */
    function network() external view returns (string memory);

    /**
     * @notice Get chain ID
     */
    function chainId() external view returns (uint256);

    /**
     * @notice Get treasury address
     */
    function treasury() external view returns (address);

    /**
     * @notice Get total revenue collected
     */
    function totalRevenue() external view returns (uint256);
}

/**
 * @title IX402DIDService
 * @notice Interface for x402 payment protocol integration with DIDs
 * @dev Enables DIDs to advertise x402 payment capabilities
 *
 * x402 INTEGRATION:
 * ┌─────────────────────────────────────────────────────────────────┐
 * │  DID documents can include x402 service endpoints:             │
 * │                                                                 │
 * │  {                                                              │
 * │    "id": "did:lux:alice#x402-payment",                         │
 * │    "type": "X402PaymentEndpoint",                              │
 * │    "serviceEndpoint": "https://pay.alice.lux/x402",            │
 * │    "acceptedTokens": ["LUX", "USDC", "ETH"],                   │
 * │    "facilitator": "did:lux:ai-facilitator"                  │
 * │  }                                                              │
 * └─────────────────────────────────────────────────────────────────┘
 */
interface IX402DIDService {
    /// @notice x402 payment endpoint configuration
    struct X402Config {
        string endpoint;           // Payment verification endpoint
        string[] acceptedTokens;   // Accepted payment tokens
        string facilitatorDID;     // Facilitator DID (optional)
        uint256 minPayment;        // Minimum payment amount
        bytes32 resourceHash;      // Protected resource identifier
    }

    /**
     * @notice Set x402 payment configuration for a DID
     * @param did The DID to configure
     * @param config The x402 configuration
     */
    function setX402Config(string calldata did, X402Config calldata config) external;

    /**
     * @notice Get x402 configuration for a DID
     * @param did The DID to query
     * @return config The x402 configuration
     */
    function getX402Config(string calldata did) external view returns (X402Config memory config);

    /**
     * @notice Check if DID supports x402 payments
     * @param did The DID to check
     * @return supported Whether x402 is configured
     */
    function supportsX402(string calldata did) external view returns (bool supported);
}
