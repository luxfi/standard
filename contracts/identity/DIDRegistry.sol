// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.31;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import {
    IDIDRegistry,
    DIDDocument,
    VerificationMethod,
    VerificationMethodType,
    Service,
    ServiceType
} from "./interfaces/IDID.sol";

/**
 * @title DIDRegistry - On-Chain W3C DID Registry for Lux Network
 * @notice Implements W3C DID Core specification for on-chain identity management
 * @dev Ported from ai-did Rust implementation to Solidity
 *
 * SUPPORTED DID METHODS:
 * ┌─────────────────────────────────────────────────────────────────────────────┐
 * │  did:lux:<identifier>                                                       │
 * │  did:lux:mainnet:<address>                                                  │
 * │  did:lux:testnet:<address>                                                  │
 * │  did:ai:<username>                                                       │
 * │  did:ai:eth:<address>                                                    │
 * └─────────────────────────────────────────────────────────────────────────────┘
 *
 * ARCHITECTURE:
 * ┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐
 * │   DIDRegistry   │────▶│   DIDDocument   │────▶│  Verification   │
 * │   (this)        │     │   (storage)     │     │    Methods      │
 * └─────────────────┘     └─────────────────┘     └─────────────────┘
 *         │                       │                       │
 *         ▼                       ▼                       ▼
 * ┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐
 * │     Karma.sol   │     │   Services      │     │   Resolution    │
 * │   (reputation)  │     │  (endpoints)    │     │   (lookup)      │
 * └─────────────────┘     └─────────────────┘     └─────────────────┘
 */
contract DIDRegistry is IDIDRegistry, AccessControl, ReentrancyGuard {
    // ============ Constants ============

    /// @notice Role for DID operators who can assist with management
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");

    /// @notice Role for registrars who can create DIDs on behalf of users
    bytes32 public constant REGISTRAR_ROLE = keccak256("REGISTRAR_ROLE");

    /// @notice Maximum verification methods per DID
    uint256 public constant MAX_VERIFICATION_METHODS = 20;

    /// @notice Maximum services per DID
    uint256 public constant MAX_SERVICES = 10;

    /// @notice Maximum also-known-as aliases per DID
    uint256 public constant MAX_ALIASES = 5;

    /// @notice Registry version
    string public constant VERSION = "1.0.0";

    // ============ State ============

    /// @notice DID method for this registry (e.g., "lux")
    string public method;

    /// @notice DID documents indexed by DID hash
    mapping(bytes32 => DIDDocument) private _documents;

    /// @notice Verification methods per DID
    mapping(bytes32 => VerificationMethod[]) private _verificationMethods;

    /// @notice Services per DID
    mapping(bytes32 => Service[]) private _services;

    /// @notice Also-known-as aliases per DID
    mapping(bytes32 => string[]) private _alsoKnownAs;

    /// @notice DID hash to full DID string
    mapping(bytes32 => string) private _didStrings;

    /// @notice Controller address to DIDs owned
    mapping(address => bytes32[]) private _controllerDIDs;

    /// @notice Nonce per controller for replay protection
    mapping(address => uint256) public nonces;

    /// @notice Total DIDs registered
    uint256 public totalDIDs;

    /// @notice Whether registration is open to public
    bool public publicRegistration;

    // ============ Errors ============

    error InvalidDID();
    error DIDAlreadyExists();
    error DIDNotFound();
    error DIDIsDeactivated();
    error NotController();
    error NotAuthorized();
    error MaxVerificationMethodsReached();
    error MaxServicesReached();
    error MaxAliasesReached();
    error MethodNotFound();
    error ServiceNotFound();
    error ZeroAddress();
    error EmptyIdentifier();
    error RegistrationClosed();

    // ============ Constructor ============

    /**
     * @notice Initialize the DID Registry
     * @param admin Admin address for access control
     * @param _method DID method this registry handles (e.g., "lux")
     * @param _publicRegistration Whether anyone can register DIDs
     */
    constructor(
        address admin,
        string memory _method,
        bool _publicRegistration
    ) {
        if (admin == address(0)) revert ZeroAddress();
        if (bytes(_method).length == 0) revert EmptyIdentifier();

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(OPERATOR_ROLE, admin);
        _grantRole(REGISTRAR_ROLE, admin);

        method = _method;
        publicRegistration = _publicRegistration;
    }

    // ============ DID Operations ============

    /**
     * @notice Create a new DID
     * @param _method DID method (must match registry method)
     * @param identifier Method-specific identifier
     * @return did The full DID string
     */
    function createDID(
        string calldata _method,
        string calldata identifier
    ) external payable nonReentrant returns (string memory did) {
        // Validate method matches
        if (keccak256(bytes(_method)) != keccak256(bytes(method))) {
            revert InvalidDID();
        }

        // Check registration permissions
        if (!publicRegistration && !hasRole(REGISTRAR_ROLE, msg.sender)) {
            revert RegistrationClosed();
        }

        return _createDID(identifier, msg.sender);
    }

    /**
     * @notice Create a DID for another address (registrar only)
     * @param identifier Method-specific identifier
     * @param controller Controller address for the DID
     * @return did The full DID string
     */
    function createDIDFor(
        string calldata identifier,
        address controller
    ) external onlyRole(REGISTRAR_ROLE) nonReentrant returns (string memory did) {
        return _createDID(identifier, controller);
    }

    /**
     * @notice Create DID with initial verification method
     * @param identifier Method-specific identifier
     * @param initialMethod Initial verification method
     * @return did The full DID string
     */
    function createDIDWithMethod(
        string calldata identifier,
        VerificationMethod calldata initialMethod
    ) external nonReentrant returns (string memory did) {
        if (!publicRegistration && !hasRole(REGISTRAR_ROLE, msg.sender)) {
            revert RegistrationClosed();
        }

        did = _createDID(identifier, msg.sender);
        bytes32 didHash = keccak256(bytes(did));
        
        _verificationMethods[didHash].push(initialMethod);
        
        emit VerificationMethodAdded(did, initialMethod.id, initialMethod.methodType);
    }

    /**
     * @notice Internal DID creation
     */
    function _createDID(
        string calldata identifier,
        address controller
    ) internal returns (string memory did) {
        if (bytes(identifier).length == 0) revert EmptyIdentifier();
        if (controller == address(0)) revert ZeroAddress();

        // Construct DID string
        did = string(abi.encodePacked("did:", method, ":", identifier));
        bytes32 didHash = keccak256(bytes(did));

        // Check if DID already exists
        if (_documents[didHash].created != 0) revert DIDAlreadyExists();

        // Create document
        _documents[didHash] = DIDDocument({
            did: did,
            controller: controller,
            additionalControllers: new address[](0),
            alsoKnownAs: new string[](0),
            created: block.timestamp,
            updated: block.timestamp,
            active: true
        });

        _didStrings[didHash] = did;
        _controllerDIDs[controller].push(didHash);
        totalDIDs++;

        emit DIDCreated(did, did, controller, block.timestamp);
    }

    /**
     * @notice Resolve a DID to its document
     */
    function resolve(string calldata did) external view returns (DIDDocument memory document) {
        bytes32 didHash = keccak256(bytes(did));
        document = _documents[didHash];
        
        if (document.created == 0) revert DIDNotFound();
        if (!document.active) revert DIDIsDeactivated();
    }

    /**
     * @notice Check if a DID exists and is active
     */
    function didExists(string calldata did) external view returns (bool) {
        bytes32 didHash = keccak256(bytes(did));
        DIDDocument storage doc = _documents[didHash];
        return doc.created != 0 && doc.active;
    }

    /**
     * @notice Deactivate a DID
     */
    function deactivateDID(string calldata did) external nonReentrant {
        bytes32 didHash = keccak256(bytes(did));
        DIDDocument storage doc = _documents[didHash];

        if (doc.created == 0) revert DIDNotFound();
        if (!_isController(didHash, msg.sender)) revert NotController();

        doc.active = false;
        doc.updated = block.timestamp;

        emit DIDDeactivated(did, did, msg.sender, block.timestamp);
    }

    /**
     * @notice Transfer DID control to a new controller
     */
    function changeController(string calldata did, address newController) external nonReentrant {
        if (newController == address(0)) revert ZeroAddress();

        bytes32 didHash = keccak256(bytes(did));
        DIDDocument storage doc = _documents[didHash];

        if (doc.created == 0) revert DIDNotFound();
        if (!doc.active) revert DIDIsDeactivated();
        if (!_isController(didHash, msg.sender)) revert NotController();

        address oldController = doc.controller;
        doc.controller = newController;
        doc.updated = block.timestamp;

        // Update controller mappings
        _removeControllerDID(oldController, didHash);
        _controllerDIDs[newController].push(didHash);

        emit ControllerChanged(did, oldController, newController);
    }

    // ============ Verification Methods ============

    /**
     * @notice Add a verification method to a DID
     */
    function addVerificationMethod(
        string calldata did,
        VerificationMethod calldata _method
    ) external nonReentrant {
        bytes32 didHash = keccak256(bytes(did));
        DIDDocument storage doc = _documents[didHash];

        if (doc.created == 0) revert DIDNotFound();
        if (!doc.active) revert DIDIsDeactivated();
        if (!_isController(didHash, msg.sender)) revert NotController();
        if (_verificationMethods[didHash].length >= MAX_VERIFICATION_METHODS) {
            revert MaxVerificationMethodsReached();
        }

        _verificationMethods[didHash].push(_method);
        doc.updated = block.timestamp;

        emit VerificationMethodAdded(did, _method.id, _method.methodType);
    }

    /**
     * @notice Remove a verification method from a DID
     */
    function removeVerificationMethod(
        string calldata did,
        bytes32 methodId
    ) external nonReentrant {
        bytes32 didHash = keccak256(bytes(did));
        DIDDocument storage doc = _documents[didHash];

        if (doc.created == 0) revert DIDNotFound();
        if (!doc.active) revert DIDIsDeactivated();
        if (!_isController(didHash, msg.sender)) revert NotController();

        VerificationMethod[] storage methods = _verificationMethods[didHash];
        bool found = false;
        
        for (uint256 i = 0; i < methods.length; i++) {
            if (methods[i].id == methodId) {
                methods[i] = methods[methods.length - 1];
                methods.pop();
                found = true;
                break;
            }
        }

        if (!found) revert MethodNotFound();
        doc.updated = block.timestamp;

        emit VerificationMethodRemoved(did, methodId);
    }

    /**
     * @notice Get all verification methods for a DID
     */
    function getVerificationMethods(
        string calldata did
    ) external view returns (VerificationMethod[] memory) {
        bytes32 didHash = keccak256(bytes(did));
        if (_documents[didHash].created == 0) revert DIDNotFound();
        return _verificationMethods[didHash];
    }

    // ============ Services ============

    /**
     * @notice Add a service endpoint to a DID
     */
    function addService(
        string calldata did,
        Service calldata service
    ) external nonReentrant {
        bytes32 didHash = keccak256(bytes(did));
        DIDDocument storage doc = _documents[didHash];

        if (doc.created == 0) revert DIDNotFound();
        if (!doc.active) revert DIDIsDeactivated();
        if (!_isController(didHash, msg.sender)) revert NotController();
        if (_services[didHash].length >= MAX_SERVICES) revert MaxServicesReached();

        _services[didHash].push(service);
        doc.updated = block.timestamp;

        emit ServiceAdded(did, service.id, service.serviceType);
    }

    /**
     * @notice Remove a service from a DID
     */
    function removeService(
        string calldata did,
        bytes32 serviceId
    ) external nonReentrant {
        bytes32 didHash = keccak256(bytes(did));
        DIDDocument storage doc = _documents[didHash];

        if (doc.created == 0) revert DIDNotFound();
        if (!doc.active) revert DIDIsDeactivated();
        if (!_isController(didHash, msg.sender)) revert NotController();

        Service[] storage services = _services[didHash];
        bool found = false;
        
        for (uint256 i = 0; i < services.length; i++) {
            if (services[i].id == serviceId) {
                services[i] = services[services.length - 1];
                services.pop();
                found = true;
                break;
            }
        }

        if (!found) revert ServiceNotFound();
        doc.updated = block.timestamp;

        emit ServiceRemoved(did, serviceId);
    }

    /**
     * @notice Get all services for a DID
     */
    function getServices(string calldata did) external view returns (Service[] memory) {
        bytes32 didHash = keccak256(bytes(did));
        if (_documents[didHash].created == 0) revert DIDNotFound();
        return _services[didHash];
    }

    // ============ Also Known As ============

    /**
     * @notice Add an alternative identifier
     */
    function addAlsoKnownAs(
        string calldata did,
        string calldata aliasUri
    ) external nonReentrant {
        bytes32 didHash = keccak256(bytes(did));
        DIDDocument storage doc = _documents[didHash];

        if (doc.created == 0) revert DIDNotFound();
        if (!doc.active) revert DIDIsDeactivated();
        if (!_isController(didHash, msg.sender)) revert NotController();
        if (_alsoKnownAs[didHash].length >= MAX_ALIASES) revert MaxAliasesReached();

        _alsoKnownAs[didHash].push(aliasUri);
        doc.updated = block.timestamp;

        emit AlsoKnownAsAdded(did, aliasUri);
    }

    /**
     * @notice Get also-known-as aliases for a DID
     */
    function getAlsoKnownAs(string calldata did) external view returns (string[] memory) {
        bytes32 didHash = keccak256(bytes(did));
        if (_documents[didHash].created == 0) revert DIDNotFound();
        return _alsoKnownAs[didHash];
    }

    // ============ View Functions ============

    /**
     * @notice Get the controller address for a DID
     */
    function controllerOf(string calldata did) external view returns (address) {
        bytes32 didHash = keccak256(bytes(did));
        DIDDocument storage doc = _documents[didHash];
        if (doc.created == 0) revert DIDNotFound();
        return doc.controller;
    }

    /**
     * @notice Get all DIDs owned by a controller
     */
    function getDIDsForController(address controller) external view returns (string[] memory) {
        bytes32[] storage didHashes = _controllerDIDs[controller];
        string[] memory dids = new string[](didHashes.length);
        
        for (uint256 i = 0; i < didHashes.length; i++) {
            dids[i] = _didStrings[didHashes[i]];
        }
        
        return dids;
    }

    /**
     * @notice Get full DID document with all data
     */
    function getFullDocument(
        string calldata did
    ) external view returns (
        DIDDocument memory document,
        VerificationMethod[] memory verificationMethods,
        Service[] memory services,
        string[] memory aliases
    ) {
        bytes32 didHash = keccak256(bytes(did));
        
        document = _documents[didHash];
        if (document.created == 0) revert DIDNotFound();
        
        verificationMethods = _verificationMethods[didHash];
        services = _services[didHash];
        aliases = _alsoKnownAs[didHash];
    }

    // ============ Admin Functions ============

    /**
     * @notice Set public registration status
     */
    function setPublicRegistration(bool enabled) external onlyRole(DEFAULT_ADMIN_ROLE) {
        publicRegistration = enabled;
    }

    // ============ Internal Functions ============

    /**
     * @notice Check if address is a controller of the DID
     */
    function _isController(bytes32 didHash, address account) internal view returns (bool) {
        DIDDocument storage doc = _documents[didHash];
        
        if (doc.controller == account) return true;
        
        for (uint256 i = 0; i < doc.additionalControllers.length; i++) {
            if (doc.additionalControllers[i] == account) return true;
        }
        
        return false;
    }

    /**
     * @notice Remove DID from controller's list
     */
    function _removeControllerDID(address controller, bytes32 didHash) internal {
        bytes32[] storage dids = _controllerDIDs[controller];
        
        for (uint256 i = 0; i < dids.length; i++) {
            if (dids[i] == didHash) {
                dids[i] = dids[dids.length - 1];
                dids.pop();
                break;
            }
        }
    }
}
