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
 * @title PremiumDIDRegistry - Paid DID Registration with Tiered Pricing
 * @notice On-chain DID registry with premium pricing for short names
 * @dev Deployable on Lux, AI, and Zoo networks with network-specific configuration
 *
 * PRICING TIERS:
 * ┌─────────────────────────────────────────────────────────────────────────────┐
 * │  Length  │  Price (Native Token)  │  Examples                              │
 * ├─────────────────────────────────────────────────────────────────────────────┤
 * │  1 char  │  1000 tokens           │  did:lux:a, did:ai:x                │
 * │  2 chars │  100 tokens            │  did:lux:ab, did:zoo:ox                │
 * │  3 chars │  10 tokens             │  did:lux:bob, did:ai:ace            │
 * │  4 chars │  1 token               │  did:lux:john, did:zoo:luna            │
 * │  5+ chars│  0.1 tokens            │  did:lux:alice, did:ai:saturn       │
 * └─────────────────────────────────────────────────────────────────────────────┘
 *
 * NETWORK DEPLOYMENTS:
 * ┌─────────────────────────────────────────────────────────────────────────────┐
 * │  Network   │  Method  │  Native Token  │  Chain IDs                        │
 * ├─────────────────────────────────────────────────────────────────────────────┤
 * │  Lux       │  lux     │  LUX           │  96369 (mainnet), 96368 (testnet)  │
 * │  AI     │  ai   │  HANZO         │  TBD                               │
 * │  Zoo       │  zoo     │  ZOO           │  200200 (mainnet), 200201 (test)   │
 * └─────────────────────────────────────────────────────────────────────────────┘
 *
 * CROSS-NETWORK RESOLUTION:
 * Each network maintains its own registry, but the DIDResolver can aggregate
 * across networks using Warp messaging or off-chain indexing.
 */
contract PremiumDIDRegistry is IDIDRegistry, AccessControl, ReentrancyGuard {
    // ============ Constants ============

    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");
    bytes32 public constant REGISTRAR_ROLE = keccak256("REGISTRAR_ROLE");
    bytes32 public constant TREASURY_ROLE = keccak256("TREASURY_ROLE");

    uint256 public constant MAX_VERIFICATION_METHODS = 20;
    uint256 public constant MAX_SERVICES = 10;
    uint256 public constant MAX_ALIASES = 5;

    string public constant VERSION = "2.0.0";

    // ============ Pricing Constants ============

    /// @notice Price for 1-character DIDs (ultra premium)
    uint256 public constant PRICE_1_CHAR = 1000 ether;

    /// @notice Price for 2-character DIDs (super premium)
    uint256 public constant PRICE_2_CHAR = 100 ether;

    /// @notice Price for 3-character DIDs (premium)
    uint256 public constant PRICE_3_CHAR = 10 ether;

    /// @notice Price for 4-character DIDs (standard)
    uint256 public constant PRICE_4_CHAR = 1 ether;

    /// @notice Price for 5+ character DIDs (basic)
    uint256 public constant PRICE_5_PLUS = 0.1 ether;

    /// @notice Renewal period (1 year)
    uint256 public constant RENEWAL_PERIOD = 365 days;

    /// @notice Grace period after expiry
    uint256 public constant GRACE_PERIOD = 30 days;

    // ============ Network Configuration ============

    /// @notice Network identifier (lux, ai, zoo)
    string public network;

    /// @notice DID method for this registry
    string public method;

    /// @notice Chain ID this registry is deployed on
    uint256 public immutable chainId;

    /// @notice Treasury address for collecting fees
    address public treasury;

    // ============ State ============

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

    /// @notice DID expiration timestamps
    mapping(bytes32 => uint256) public expiresAt;

    /// @notice Reserved DIDs (admin only)
    mapping(bytes32 => bool) public reserved;

    /// @notice Total DIDs registered
    uint256 public totalDIDs;

    /// @notice Total revenue collected
    uint256 public totalRevenue;

    /// @notice Whether public registration is enabled
    bool public publicRegistration;

    /// @notice Price multiplier (basis points, 10000 = 1x)
    uint256 public priceMultiplier = 10000;

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

    event PriceMultiplierUpdated(uint256 oldMultiplier, uint256 newMultiplier);

    event TreasuryUpdated(address indexed oldTreasury, address indexed newTreasury);

    event RevenueWithdrawn(address indexed to, uint256 amount);

    event DIDReserved(string identifier, bool reserved);

    // ============ Errors ============

    error InvalidDID();
    error DIDAlreadyExists();
    error DIDNotFound();
    error DIDNotActive();
    error DIDIsExpired();
    error DIDIsReserved();
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
    error InsufficientPayment();
    error InvalidIdentifier();
    error WithdrawalFailed();

    // ============ Constructor ============

    /**
     * @notice Initialize the Premium DID Registry
     * @param admin Admin address
     * @param _network Network name (lux, ai, zoo)
     * @param _method DID method (lux, ai, zoo)
     * @param _treasury Treasury address for fees
     */
    constructor(
        address admin,
        string memory _network,
        string memory _method,
        address _treasury
    ) {
        if (admin == address(0)) revert ZeroAddress();
        if (_treasury == address(0)) revert ZeroAddress();
        if (bytes(_network).length == 0) revert EmptyIdentifier();
        if (bytes(_method).length == 0) revert EmptyIdentifier();

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(OPERATOR_ROLE, admin);
        _grantRole(REGISTRAR_ROLE, admin);
        _grantRole(TREASURY_ROLE, admin);

        network = _network;
        method = _method;
        treasury = _treasury;
        chainId = block.chainid;
        publicRegistration = true;
    }

    // ============ Pricing Functions ============

    /**
     * @notice Calculate price for a DID identifier
     * @param identifier The identifier (without method prefix)
     * @return price The price in native tokens
     */
    function getPrice(string calldata identifier) public view returns (uint256 price) {
        return _getPrice(identifier);
    }

    /**
     * @notice Calculate renewal price (50% of registration)
     * @param identifier The identifier
     * @return price The renewal price
     */
    function getRenewalPrice(string calldata identifier) public view returns (uint256 price) {
        return _getPrice(identifier) / 2;
    }

    /**
     * @dev Internal price calculation that works with memory strings
     */
    function _getPrice(string memory identifier) internal view returns (uint256 price) {
        uint256 length = bytes(identifier).length;

        if (length == 0) revert InvalidIdentifier();

        if (length == 1) {
            price = PRICE_1_CHAR;
        } else if (length == 2) {
            price = PRICE_2_CHAR;
        } else if (length == 3) {
            price = PRICE_3_CHAR;
        } else if (length == 4) {
            price = PRICE_4_CHAR;
        } else {
            price = PRICE_5_PLUS;
        }

        // Apply price multiplier
        price = (price * priceMultiplier) / 10000;
    }

    /**
     * @dev Internal renewal price calculation
     */
    function _getRenewalPrice(string memory identifier) internal view returns (uint256) {
        return _getPrice(identifier) / 2;
    }

    /**
     * @notice Get price tier name
     * @param identifier The identifier
     * @return tier The tier name
     */
    function getPriceTier(string calldata identifier) external pure returns (string memory tier) {
        uint256 length = bytes(identifier).length;

        if (length == 1) return "Ultra Premium";
        if (length == 2) return "Super Premium";
        if (length == 3) return "Premium";
        if (length == 4) return "Standard";
        return "Basic";
    }

    // ============ Registration Functions ============

    /**
     * @notice Register a new DID with payment
     * @param _method DID method (must match registry)
     * @param identifier The identifier to register
     * @return did The full DID string
     */
    function createDID(
        string calldata _method,
        string calldata identifier
    ) external payable nonReentrant returns (string memory did) {
        if (keccak256(bytes(_method)) != keccak256(bytes(method))) {
            revert InvalidDID();
        }

        if (!publicRegistration && !hasRole(REGISTRAR_ROLE, msg.sender)) {
            revert RegistrationClosed();
        }

        // Validate identifier
        if (!_isValidIdentifier(identifier)) revert InvalidIdentifier();

        // Check if reserved
        bytes32 idHash = keccak256(bytes(identifier));
        if (reserved[idHash] && !hasRole(REGISTRAR_ROLE, msg.sender)) {
            revert DIDIsReserved();
        }

        // Calculate and verify payment
        uint256 price = getPrice(identifier);
        if (msg.value < price) revert InsufficientPayment();

        // Create DID
        did = _createDID(identifier, msg.sender, price);

        // Refund excess payment
        if (msg.value > price) {
            (bool success, ) = msg.sender.call{value: msg.value - price}("");
            if (!success) revert WithdrawalFailed();
        }
    }

    /**
     * @notice Register a DID for free (registrar only)
     * @param identifier The identifier
     * @param controller The controller address
     * @return did The full DID string
     */
    function createDIDFree(
        string calldata identifier,
        address controller
    ) external onlyRole(REGISTRAR_ROLE) nonReentrant returns (string memory did) {
        if (!_isValidIdentifier(identifier)) revert InvalidIdentifier();
        return _createDID(identifier, controller, 0);
    }

    /**
     * @notice Internal DID creation
     */
    function _createDID(
        string calldata identifier,
        address controller,
        uint256 pricePaid
    ) internal returns (string memory did) {
        if (bytes(identifier).length == 0) revert EmptyIdentifier();
        if (controller == address(0)) revert ZeroAddress();

        // Construct DID string
        did = string(abi.encodePacked("did:", method, ":", identifier));
        bytes32 didHash = keccak256(bytes(did));

        // Check if DID already exists and not expired
        if (_documents[didHash].created != 0) {
            if (expiresAt[didHash] > block.timestamp) {
                revert DIDAlreadyExists();
            }
            // Expired DID - allow re-registration after grace period
            if (expiresAt[didHash] + GRACE_PERIOD > block.timestamp) {
                revert DIDAlreadyExists(); // Still in grace period
            }
        }

        // Set expiration
        uint256 expiry = block.timestamp + RENEWAL_PERIOD;

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
        expiresAt[didHash] = expiry;
        totalDIDs++;
        totalRevenue += pricePaid;

        emit DIDCreated(did, did, controller, block.timestamp);
        emit DIDRegistered(did, did, controller, pricePaid, expiry);
    }

    /**
     * @notice Renew a DID
     * @param did The DID to renew
     */
    function renewDID(string calldata did) external payable nonReentrant {
        bytes32 didHash = keccak256(bytes(did));
        DIDDocument storage doc = _documents[didHash];

        if (doc.created == 0) revert DIDNotFound();
        if (!_isController(didHash, msg.sender)) revert NotController();

        // Extract identifier for pricing
        string memory identifier = _extractIdentifier(did);
        uint256 price = _getRenewalPrice(identifier);

        if (msg.value < price) revert InsufficientPayment();

        // Extend expiration
        uint256 currentExpiry = expiresAt[didHash];
        uint256 newExpiry;

        if (currentExpiry < block.timestamp) {
            // Expired - renew from now
            newExpiry = block.timestamp + RENEWAL_PERIOD;
        } else {
            // Not expired - extend from current expiry
            newExpiry = currentExpiry + RENEWAL_PERIOD;
        }

        expiresAt[didHash] = newExpiry;
        doc.updated = block.timestamp;
        doc.active = true;
        totalRevenue += price;

        emit DIDRenewed(did, did, newExpiry, price);

        // Refund excess
        if (msg.value > price) {
            (bool success, ) = msg.sender.call{value: msg.value - price}("");
            if (!success) revert WithdrawalFailed();
        }
    }

    // ============ Resolution Functions ============

    /**
     * @notice Resolve a DID to its document
     */
    function resolve(string calldata did) external view returns (DIDDocument memory document) {
        bytes32 didHash = keccak256(bytes(did));
        document = _documents[didHash];

        if (document.created == 0) revert DIDNotFound();
        if (!document.active) revert DIDNotActive();
        if (expiresAt[didHash] < block.timestamp) revert DIDIsExpired();
    }

    /**
     * @notice Check if a DID exists and is active
     */
    function didExists(string calldata did) external view returns (bool) {
        bytes32 didHash = keccak256(bytes(did));
        DIDDocument storage doc = _documents[didHash];
        return doc.created != 0 && doc.active && expiresAt[didHash] >= block.timestamp;
    }

    /**
     * @notice Check if a DID is available for registration
     * @param identifier The identifier to check
     * @return available Whether the DID is available
     * @return price The price to register
     */
    function isAvailable(string calldata identifier) external view returns (bool available, uint256 price) {
        string memory did = string(abi.encodePacked("did:", method, ":", identifier));
        bytes32 didHash = keccak256(bytes(did));

        DIDDocument storage doc = _documents[didHash];

        // Available if never registered or expired past grace period
        if (doc.created == 0) {
            available = true;
        } else if (expiresAt[didHash] + GRACE_PERIOD < block.timestamp) {
            available = true;
        } else {
            available = false;
        }

        // Check if reserved
        if (reserved[keccak256(bytes(identifier))]) {
            available = false;
        }

        price = getPrice(identifier);
    }

    /**
     * @notice Get DID expiration info
     * @param did The DID to check
     * @return expiry Expiration timestamp
     * @return isExpired Whether currently expired
     * @return inGracePeriod Whether in grace period
     */
    function getExpiry(string calldata did) external view returns (
        uint256 expiry,
        bool isExpired,
        bool inGracePeriod
    ) {
        bytes32 didHash = keccak256(bytes(did));
        expiry = expiresAt[didHash];
        isExpired = expiry < block.timestamp;
        inGracePeriod = isExpired && expiry + GRACE_PERIOD >= block.timestamp;
    }

    // ============ Verification Methods ============

    function addVerificationMethod(
        string calldata did,
        VerificationMethod calldata _method
    ) external nonReentrant {
        bytes32 didHash = keccak256(bytes(did));
        _requireActiveController(didHash);

        if (_verificationMethods[didHash].length >= MAX_VERIFICATION_METHODS) {
            revert MaxVerificationMethodsReached();
        }

        _verificationMethods[didHash].push(_method);
        _documents[didHash].updated = block.timestamp;

        emit VerificationMethodAdded(did, _method.id, _method.methodType);
    }

    function removeVerificationMethod(
        string calldata did,
        bytes32 methodId
    ) external nonReentrant {
        bytes32 didHash = keccak256(bytes(did));
        _requireActiveController(didHash);

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
        _documents[didHash].updated = block.timestamp;

        emit VerificationMethodRemoved(did, methodId);
    }

    function getVerificationMethods(
        string calldata did
    ) external view returns (VerificationMethod[] memory) {
        bytes32 didHash = keccak256(bytes(did));
        if (_documents[didHash].created == 0) revert DIDNotFound();
        return _verificationMethods[didHash];
    }

    // ============ Services ============

    function addService(
        string calldata did,
        Service calldata service
    ) external nonReentrant {
        bytes32 didHash = keccak256(bytes(did));
        _requireActiveController(didHash);

        if (_services[didHash].length >= MAX_SERVICES) revert MaxServicesReached();

        _services[didHash].push(service);
        _documents[didHash].updated = block.timestamp;

        emit ServiceAdded(did, service.id, service.serviceType);
    }

    function removeService(
        string calldata did,
        bytes32 serviceId
    ) external nonReentrant {
        bytes32 didHash = keccak256(bytes(did));
        _requireActiveController(didHash);

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
        _documents[didHash].updated = block.timestamp;

        emit ServiceRemoved(did, serviceId);
    }

    function getServices(string calldata did) external view returns (Service[] memory) {
        bytes32 didHash = keccak256(bytes(did));
        if (_documents[didHash].created == 0) revert DIDNotFound();
        return _services[didHash];
    }

    // ============ Also Known As ============

    function addAlsoKnownAs(
        string calldata did,
        string calldata aliasUri
    ) external nonReentrant {
        bytes32 didHash = keccak256(bytes(did));
        _requireActiveController(didHash);

        if (_alsoKnownAs[didHash].length >= MAX_ALIASES) revert MaxAliasesReached();

        _alsoKnownAs[didHash].push(aliasUri);
        _documents[didHash].updated = block.timestamp;

        emit AlsoKnownAsAdded(did, aliasUri);
    }

    function getAlsoKnownAs(string calldata did) external view returns (string[] memory) {
        bytes32 didHash = keccak256(bytes(did));
        if (_documents[didHash].created == 0) revert DIDNotFound();
        return _alsoKnownAs[didHash];
    }

    // ============ Controller Functions ============

    function controllerOf(string calldata did) external view returns (address) {
        bytes32 didHash = keccak256(bytes(did));
        DIDDocument storage doc = _documents[didHash];
        if (doc.created == 0) revert DIDNotFound();
        return doc.controller;
    }

    function changeController(string calldata did, address newController) external nonReentrant {
        if (newController == address(0)) revert ZeroAddress();

        bytes32 didHash = keccak256(bytes(did));
        _requireActiveController(didHash);

        address oldController = _documents[didHash].controller;
        _documents[didHash].controller = newController;
        _documents[didHash].updated = block.timestamp;

        _removeControllerDID(oldController, didHash);
        _controllerDIDs[newController].push(didHash);

        emit ControllerChanged(did, oldController, newController);
    }

    function deactivateDID(string calldata did) external nonReentrant {
        bytes32 didHash = keccak256(bytes(did));
        _requireActiveController(didHash);

        _documents[didHash].active = false;
        _documents[didHash].updated = block.timestamp;

        emit DIDDeactivated(did, did, msg.sender, block.timestamp);
    }

    function getDIDsForController(address controller) external view returns (string[] memory) {
        bytes32[] storage didHashes = _controllerDIDs[controller];
        string[] memory dids = new string[](didHashes.length);

        for (uint256 i = 0; i < didHashes.length; i++) {
            dids[i] = _didStrings[didHashes[i]];
        }

        return dids;
    }

    // ============ Admin Functions ============

    /**
     * @notice Reserve identifiers (admin only)
     * @param identifiers List of identifiers to reserve
     * @param _reserved Whether to reserve or unreserve
     */
    function setReserved(
        string[] calldata identifiers,
        bool _reserved
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        for (uint256 i = 0; i < identifiers.length; i++) {
            bytes32 idHash = keccak256(bytes(identifiers[i]));
            reserved[idHash] = _reserved;
            emit DIDReserved(identifiers[i], _reserved);
        }
    }

    /**
     * @notice Update price multiplier
     * @param newMultiplier New multiplier in basis points (10000 = 1x)
     */
    function setPriceMultiplier(uint256 newMultiplier) external onlyRole(DEFAULT_ADMIN_ROLE) {
        uint256 old = priceMultiplier;
        priceMultiplier = newMultiplier;
        emit PriceMultiplierUpdated(old, newMultiplier);
    }

    /**
     * @notice Update treasury address
     * @param newTreasury New treasury address
     */
    function setTreasury(address newTreasury) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (newTreasury == address(0)) revert ZeroAddress();
        address old = treasury;
        treasury = newTreasury;
        emit TreasuryUpdated(old, newTreasury);
    }

    /**
     * @notice Toggle public registration
     */
    function setPublicRegistration(bool enabled) external onlyRole(DEFAULT_ADMIN_ROLE) {
        publicRegistration = enabled;
    }

    /**
     * @notice Withdraw collected fees to treasury
     */
    function withdrawToTreasury() external onlyRole(TREASURY_ROLE) {
        uint256 balance = address(this).balance;
        if (balance == 0) return;

        (bool success, ) = treasury.call{value: balance}("");
        if (!success) revert WithdrawalFailed();

        emit RevenueWithdrawn(treasury, balance);
    }

    /**
     * @notice Get registry stats
     */
    function getStats() external view returns (
        uint256 _totalDIDs,
        uint256 _totalRevenue,
        uint256 _contractBalance,
        string memory _network,
        string memory _method,
        uint256 _chainId
    ) {
        return (totalDIDs, totalRevenue, address(this).balance, network, method, chainId);
    }

    // ============ Internal Functions ============

    function _requireActiveController(bytes32 didHash) internal view {
        DIDDocument storage doc = _documents[didHash];
        if (doc.created == 0) revert DIDNotFound();
        if (!doc.active) revert DIDNotActive();
        if (expiresAt[didHash] < block.timestamp) revert DIDIsExpired();
        if (!_isController(didHash, msg.sender)) revert NotController();
    }

    function _isController(bytes32 didHash, address account) internal view returns (bool) {
        DIDDocument storage doc = _documents[didHash];

        if (doc.controller == account) return true;

        for (uint256 i = 0; i < doc.additionalControllers.length; i++) {
            if (doc.additionalControllers[i] == account) return true;
        }

        return false;
    }

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

    function _isValidIdentifier(string calldata identifier) internal pure returns (bool) {
        bytes memory b = bytes(identifier);
        if (b.length == 0 || b.length > 64) return false;

        for (uint256 i = 0; i < b.length; i++) {
            bytes1 char = b[i];
            // Allow: a-z, 0-9, -, _
            bool isLower = (char >= 0x61 && char <= 0x7A);
            bool isDigit = (char >= 0x30 && char <= 0x39);
            bool isDash = (char == 0x2D);
            bool isUnderscore = (char == 0x5F);

            if (!isLower && !isDigit && !isDash && !isUnderscore) {
                return false;
            }
        }

        // Cannot start or end with dash/underscore
        if (b[0] == 0x2D || b[0] == 0x5F) return false;
        if (b[b.length - 1] == 0x2D || b[b.length - 1] == 0x5F) return false;

        return true;
    }

    function _extractIdentifier(string calldata did) internal view returns (string memory) {
        bytes memory didBytes = bytes(did);
        // Format: did:method:identifier
        // Find second colon
        uint256 colonCount = 0;
        uint256 start = 0;

        for (uint256 i = 0; i < didBytes.length; i++) {
            if (didBytes[i] == ':') {
                colonCount++;
                if (colonCount == 2) {
                    start = i + 1;
                    break;
                }
            }
        }

        bytes memory identifier = new bytes(didBytes.length - start);
        for (uint256 i = start; i < didBytes.length; i++) {
            identifier[i - start] = didBytes[i];
        }

        return string(identifier);
    }

    // ============ Receive Function ============

    receive() external payable {}
}
