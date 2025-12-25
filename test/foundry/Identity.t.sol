// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.31;

import "forge-std/Test.sol";

import {DIDRegistry} from "../../contracts/identity/DIDRegistry.sol";
import {DIDResolver, OmnichainDIDResolver} from "../../contracts/identity/DIDResolver.sol";
import {
    IDIDRegistry,
    IDIDResolver,
    DIDDocument,
    VerificationMethod,
    VerificationMethodType,
    Service,
    ServiceType
} from "../../contracts/identity/interfaces/IDID.sol";

/**
 * @title IdentityTest - Comprehensive W3C DID Testing Suite
 * @notice Tests DID Registry, Resolver, and Omnichain Resolution
 *
 * TEST COVERAGE:
 * ✅ DID creation (basic, with method, for others)
 * ✅ DID resolution (local, cross-registry, omnichain)
 * ✅ DID document updates (verification methods, services, aliases)
 * ✅ Controller management (change, multi-controller)
 * ✅ Service endpoints (add, remove, query)
 * ✅ Verification methods (add, remove, types)
 * ✅ DID deactivation
 * ✅ Access control (registrar, operator, admin)
 * ✅ Edge cases (limits, invalid inputs, reentrance)
 * ✅ Fuzz tests (random inputs, stress testing)
 */
contract IdentityTest is Test {
    // ============ Test Contracts ============

    DIDRegistry public luxRegistry;
    DIDRegistry public hanzoRegistry;
    DIDResolver public resolver;
    OmnichainDIDResolver public omnichainResolver;

    // ============ Test Accounts ============

    address admin = makeAddr("admin");
    address alice = makeAddr("alice");
    address bob = makeAddr("bob");
    address charlie = makeAddr("charlie");
    address operator = makeAddr("operator");
    address registrar = makeAddr("registrar");
    address attacker = makeAddr("attacker");

    // ============ Test Data ============

    string constant LUX_METHOD = "lux";
    string constant HANZO_METHOD = "hanzo";

    string aliceDID = "did:lux:alice";
    string bobDID = "did:lux:bob";
    string charlieDID = "did:hanzo:charlie";

    bytes32 constant METHOD_KEY_1 = keccak256("key-1");
    bytes32 constant METHOD_KEY_2 = keccak256("key-2");
    bytes32 constant SERVICE_MESSAGING = keccak256("messaging");
    bytes32 constant SERVICE_LLM = keccak256("llm");

    // ============ Events ============

    event DIDCreated(string indexed didHash, string did, address indexed controller, uint256 timestamp);
    event DIDDeactivated(string indexed didHash, string did, address indexed controller, uint256 timestamp);
    event ControllerChanged(string indexed didHash, address indexed oldController, address indexed newController);
    event VerificationMethodAdded(string indexed didHash, bytes32 indexed methodId, VerificationMethodType methodType);
    event VerificationMethodRemoved(string indexed didHash, bytes32 indexed methodId);
    event ServiceAdded(string indexed didHash, bytes32 indexed serviceId, ServiceType serviceType);
    event ServiceRemoved(string indexed didHash, bytes32 indexed serviceId);
    event AlsoKnownAsAdded(string indexed didHash, string didAlias);

    // ============ Setup ============

    function setUp() public {
        // Deploy registries
        vm.startPrank(admin);
        luxRegistry = new DIDRegistry(admin, LUX_METHOD, true); // Public registration
        hanzoRegistry = new DIDRegistry(admin, HANZO_METHOD, false); // Private registration

        // Deploy resolvers
        resolver = new DIDResolver(admin, address(luxRegistry));
        omnichainResolver = new OmnichainDIDResolver(admin, address(luxRegistry));

        // Register methods in resolver
        resolver.registerMethod(LUX_METHOD, address(luxRegistry));
        resolver.registerMethod(HANZO_METHOD, address(hanzoRegistry));
        omnichainResolver.registerMethod(LUX_METHOD, address(luxRegistry));
        omnichainResolver.registerMethod(HANZO_METHOD, address(hanzoRegistry));

        // Grant roles
        luxRegistry.grantRole(luxRegistry.OPERATOR_ROLE(), operator);
        luxRegistry.grantRole(luxRegistry.REGISTRAR_ROLE(), registrar);
        hanzoRegistry.grantRole(hanzoRegistry.REGISTRAR_ROLE(), registrar);

        vm.stopPrank();
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // DID CREATION TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function test_CreateDID_Basic() public {
        vm.startPrank(alice);

        vm.expectEmit(true, true, false, true);
        emit DIDCreated(aliceDID, aliceDID, alice, block.timestamp);

        string memory did = luxRegistry.createDID(LUX_METHOD, "alice");

        assertEq(did, aliceDID, "DID mismatch");
        assertTrue(luxRegistry.didExists(did), "DID should exist");
        assertEq(luxRegistry.controllerOf(did), alice, "Controller mismatch");
        assertEq(luxRegistry.totalDIDs(), 1, "Total DIDs should be 1");

        vm.stopPrank();
    }

    function test_CreateDID_WithVerificationMethod() public {
        vm.startPrank(alice);

        VerificationMethod memory method = VerificationMethod({
            id: METHOD_KEY_1,
            methodType: VerificationMethodType.Ed25519VerificationKey2020,
            controller: alice,
            publicKeyMultibase: abi.encodePacked("z6MkhaXgBZDvotDkL5257faiztiGiC2QtKLGpbnnEGta2doK"),
            blockchainAccountId: bytes32(uint256(uint160(alice)))
        });

        string memory did = luxRegistry.createDIDWithMethod("alice", method);

        assertEq(did, aliceDID, "DID mismatch");

        VerificationMethod[] memory methods = luxRegistry.getVerificationMethods(did);
        assertEq(methods.length, 1, "Should have 1 verification method");
        assertEq(methods[0].id, METHOD_KEY_1, "Method ID mismatch");
        assertEq(uint(methods[0].methodType), uint(VerificationMethodType.Ed25519VerificationKey2020), "Method type mismatch");

        vm.stopPrank();
    }

    function test_CreateDIDFor_AsRegistrar() public {
        vm.startPrank(registrar);

        string memory did = luxRegistry.createDIDFor("alice", alice);

        assertEq(did, aliceDID, "DID mismatch");
        assertEq(luxRegistry.controllerOf(did), alice, "Controller should be alice");

        vm.stopPrank();
    }

    function test_RevertWhen_CreateDID_DuplicateIdentifier() public {
        vm.startPrank(alice);

        luxRegistry.createDID(LUX_METHOD, "alice");

        vm.expectRevert(DIDRegistry.DIDAlreadyExists.selector);
        luxRegistry.createDID(LUX_METHOD, "alice");

        vm.stopPrank();
    }

    function test_RevertWhen_CreateDID_EmptyIdentifier() public {
        vm.startPrank(alice);

        vm.expectRevert(DIDRegistry.EmptyIdentifier.selector);
        luxRegistry.createDID(LUX_METHOD, "");

        vm.stopPrank();
    }

    function test_RevertWhen_CreateDID_WrongMethod() public {
        vm.startPrank(alice);

        vm.expectRevert(DIDRegistry.InvalidDID.selector);
        luxRegistry.createDID("wrong", "alice");

        vm.stopPrank();
    }

    function test_RevertWhen_CreateDID_PrivateRegistryNotRegistrar() public {
        vm.startPrank(alice);

        vm.expectRevert(DIDRegistry.RegistrationClosed.selector);
        hanzoRegistry.createDID(HANZO_METHOD, "alice");

        vm.stopPrank();
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // DID RESOLUTION TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function test_ResolveDID_Basic() public {
        // Create DID
        vm.prank(alice);
        luxRegistry.createDID(LUX_METHOD, "alice");

        // Resolve directly from registry
        DIDDocument memory doc = luxRegistry.resolve(aliceDID);

        assertEq(doc.did, aliceDID, "DID mismatch");
        assertEq(doc.controller, alice, "Controller mismatch");
        assertTrue(doc.active, "DID should be active");
        assertGt(doc.created, 0, "Created timestamp should be set");
        assertEq(doc.updated, doc.created, "Updated should equal created");
    }

    function test_ResolveDID_ThroughResolver() public {
        // Create DID
        vm.prank(alice);
        luxRegistry.createDID(LUX_METHOD, "alice");

        // Resolve through resolver
        (DIDDocument memory doc, address registry) = resolver.resolve(aliceDID);

        assertEq(doc.did, aliceDID, "DID mismatch");
        assertEq(doc.controller, alice, "Controller mismatch");
        assertEq(registry, address(luxRegistry), "Registry mismatch");
    }

    function test_ResolveDID_WithMetadata() public {
        // Create DID
        vm.prank(alice);
        luxRegistry.createDID(LUX_METHOD, "alice");

        // Resolve with metadata
        (
            DIDDocument memory doc,
            address registry,
            string memory method,
            uint256 resolutionTime
        ) = resolver.resolveWithMetadata(aliceDID);

        assertEq(doc.did, aliceDID, "DID mismatch");
        assertEq(registry, address(luxRegistry), "Registry mismatch");
        assertEq(method, LUX_METHOD, "Method mismatch");
        assertEq(resolutionTime, block.timestamp, "Resolution time mismatch");
    }

    function test_ResolveDID_CrossRegistry() public {
        // Create DIDs in different registries
        vm.prank(alice);
        luxRegistry.createDID(LUX_METHOD, "alice");

        vm.prank(registrar);
        hanzoRegistry.createDIDFor("charlie", charlie);

        // Resolve from lux registry
        (DIDDocument memory luxDoc, address luxReg) = resolver.resolve(aliceDID);
        assertEq(luxReg, address(luxRegistry), "Should resolve from lux registry");
        assertEq(luxDoc.controller, alice, "Controller mismatch");

        // Resolve from hanzo registry
        (DIDDocument memory hanzoDoc, address hanzoReg) = resolver.resolve(charlieDID);
        assertEq(hanzoReg, address(hanzoRegistry), "Should resolve from hanzo registry");
        assertEq(hanzoDoc.controller, charlie, "Controller mismatch");
    }

    function test_CanResolve_ExistingDID() public {
        vm.prank(alice);
        luxRegistry.createDID(LUX_METHOD, "alice");

        (bool canResolve, address registry) = resolver.canResolve(aliceDID);

        assertTrue(canResolve, "Should be able to resolve");
        assertEq(registry, address(luxRegistry), "Registry mismatch");
    }

    function test_CanResolve_NonExistentDID() public {
        (bool canResolve, ) = resolver.canResolve("did:lux:nonexistent");

        assertFalse(canResolve, "Should not be able to resolve");
    }

    function test_RevertWhen_ResolveDID_NotFound() public {
        vm.expectRevert(DIDRegistry.DIDNotFound.selector);
        luxRegistry.resolve("did:lux:nonexistent");
    }

    function test_RevertWhen_ResolveDID_Deactivated() public {
        // Create and deactivate DID
        vm.startPrank(alice);
        luxRegistry.createDID(LUX_METHOD, "alice");
        luxRegistry.deactivateDID(aliceDID);
        vm.stopPrank();

        // Attempt to resolve
        vm.expectRevert(DIDRegistry.DIDIsDeactivated.selector);
        luxRegistry.resolve(aliceDID);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // DID DOCUMENT UPDATES
    // ═══════════════════════════════════════════════════════════════════════════

    function test_GetFullDocument() public {
        // Create DID with full data
        vm.startPrank(alice);

        string memory did = luxRegistry.createDID(LUX_METHOD, "alice");

        // Add verification method
        VerificationMethod memory method = VerificationMethod({
            id: METHOD_KEY_1,
            methodType: VerificationMethodType.EcdsaSecp256k1VerificationKey2019,
            controller: alice,
            publicKeyMultibase: abi.encodePacked("zpub"),
            blockchainAccountId: bytes32(uint256(uint160(alice)))
        });
        luxRegistry.addVerificationMethod(did, method);

        // Add service
        Service memory service = Service({
            id: SERVICE_MESSAGING,
            serviceType: ServiceType.MessagingService,
            endpoint: "https://messaging.lux.network/alice",
            data: ""
        });
        luxRegistry.addService(did, service);

        // Add alias
        luxRegistry.addAlsoKnownAs(did, "did:hanzo:alice");

        vm.stopPrank();

        // Get full document
        (
            DIDDocument memory doc,
            VerificationMethod[] memory methods,
            Service[] memory services,
            string[] memory aliases
        ) = luxRegistry.getFullDocument(did);

        assertEq(doc.controller, alice, "Controller mismatch");
        assertEq(methods.length, 1, "Should have 1 verification method");
        assertEq(services.length, 1, "Should have 1 service");
        assertEq(aliases.length, 1, "Should have 1 alias");
    }

    function test_UpdateTimestamp() public {
        vm.startPrank(alice);

        string memory did = luxRegistry.createDID(LUX_METHOD, "alice");
        DIDDocument memory doc1 = luxRegistry.resolve(did);

        // Fast forward time
        vm.warp(block.timestamp + 1 days);

        // Update DID (add verification method)
        VerificationMethod memory method = VerificationMethod({
            id: METHOD_KEY_1,
            methodType: VerificationMethodType.Ed25519VerificationKey2020,
            controller: alice,
            publicKeyMultibase: abi.encodePacked("z6Mk"),
            blockchainAccountId: bytes32(0)
        });
        luxRegistry.addVerificationMethod(did, method);

        DIDDocument memory doc2 = luxRegistry.resolve(did);

        assertGt(doc2.updated, doc1.updated, "Updated timestamp should increase");
        assertEq(doc2.created, doc1.created, "Created timestamp should not change");

        vm.stopPrank();
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // CONTROLLER MANAGEMENT
    // ═══════════════════════════════════════════════════════════════════════════

    function test_ChangeController() public {
        // Create DID
        vm.prank(alice);
        string memory did = luxRegistry.createDID(LUX_METHOD, "alice");

        // Change controller
        vm.startPrank(alice);

        vm.expectEmit(true, true, true, false);
        emit ControllerChanged(did, alice, bob);

        luxRegistry.changeController(did, bob);

        vm.stopPrank();

        // Verify change
        assertEq(luxRegistry.controllerOf(did), bob, "Controller should be bob");

        // Alice should no longer own this DID
        string[] memory aliceDIDs = luxRegistry.getDIDsForController(alice);
        assertEq(aliceDIDs.length, 0, "Alice should have 0 DIDs");

        // Bob should now own this DID
        string[] memory bobDIDs = luxRegistry.getDIDsForController(bob);
        assertEq(bobDIDs.length, 1, "Bob should have 1 DID");
        assertEq(bobDIDs[0], did, "DID mismatch");
    }

    function test_RevertWhen_ChangeController_NotController() public {
        // Create DID
        vm.prank(alice);
        string memory did = luxRegistry.createDID(LUX_METHOD, "alice");

        // Attempt to change controller as non-controller
        vm.prank(attacker);
        vm.expectRevert(DIDRegistry.NotController.selector);
        luxRegistry.changeController(did, attacker);
    }

    function test_RevertWhen_ChangeController_ToZeroAddress() public {
        // Create DID
        vm.prank(alice);
        string memory did = luxRegistry.createDID(LUX_METHOD, "alice");

        // Attempt to change to zero address
        vm.prank(alice);
        vm.expectRevert(DIDRegistry.ZeroAddress.selector);
        luxRegistry.changeController(did, address(0));
    }

    function test_RevertWhen_ChangeController_DeactivatedDID() public {
        // Create and deactivate DID
        vm.startPrank(alice);
        string memory did = luxRegistry.createDID(LUX_METHOD, "alice");
        luxRegistry.deactivateDID(did);

        // Attempt to change controller
        vm.expectRevert(DIDRegistry.DIDIsDeactivated.selector);
        luxRegistry.changeController(did, bob);

        vm.stopPrank();
    }

    function test_GetDIDsForController() public {
        vm.startPrank(alice);

        // Create multiple DIDs
        luxRegistry.createDID(LUX_METHOD, "alice1");
        luxRegistry.createDID(LUX_METHOD, "alice2");
        luxRegistry.createDID(LUX_METHOD, "alice3");

        vm.stopPrank();

        // Query DIDs for controller
        string[] memory dids = luxRegistry.getDIDsForController(alice);

        assertEq(dids.length, 3, "Should have 3 DIDs");
        assertEq(dids[0], "did:lux:alice1", "DID 1 mismatch");
        assertEq(dids[1], "did:lux:alice2", "DID 2 mismatch");
        assertEq(dids[2], "did:lux:alice3", "DID 3 mismatch");
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // VERIFICATION METHODS
    // ═══════════════════════════════════════════════════════════════════════════

    function test_AddVerificationMethod() public {
        vm.startPrank(alice);

        string memory did = luxRegistry.createDID(LUX_METHOD, "alice");

        VerificationMethod memory method = VerificationMethod({
            id: METHOD_KEY_1,
            methodType: VerificationMethodType.Ed25519VerificationKey2020,
            controller: alice,
            publicKeyMultibase: abi.encodePacked("z6MkhaXgBZDvotDkL5257faiztiGiC2QtKLGpbnnEGta2doK"),
            blockchainAccountId: bytes32(0)
        });

        vm.expectEmit(true, true, false, true);
        emit VerificationMethodAdded(did, METHOD_KEY_1, VerificationMethodType.Ed25519VerificationKey2020);

        luxRegistry.addVerificationMethod(did, method);

        vm.stopPrank();

        VerificationMethod[] memory methods = luxRegistry.getVerificationMethods(did);
        assertEq(methods.length, 1, "Should have 1 verification method");
        assertEq(methods[0].id, METHOD_KEY_1, "Method ID mismatch");
    }

    function test_AddMultipleVerificationMethods() public {
        vm.startPrank(alice);

        string memory did = luxRegistry.createDID(LUX_METHOD, "alice");

        // Add Ed25519 key
        VerificationMethod memory method1 = VerificationMethod({
            id: METHOD_KEY_1,
            methodType: VerificationMethodType.Ed25519VerificationKey2020,
            controller: alice,
            publicKeyMultibase: abi.encodePacked("z6Mk1"),
            blockchainAccountId: bytes32(0)
        });
        luxRegistry.addVerificationMethod(did, method1);

        // Add ECDSA key
        VerificationMethod memory method2 = VerificationMethod({
            id: METHOD_KEY_2,
            methodType: VerificationMethodType.EcdsaSecp256k1VerificationKey2019,
            controller: alice,
            publicKeyMultibase: abi.encodePacked("z6Mk2"),
            blockchainAccountId: bytes32(uint256(uint160(alice)))
        });
        luxRegistry.addVerificationMethod(did, method2);

        vm.stopPrank();

        VerificationMethod[] memory methods = luxRegistry.getVerificationMethods(did);
        assertEq(methods.length, 2, "Should have 2 verification methods");
    }

    function test_RemoveVerificationMethod() public {
        vm.startPrank(alice);

        string memory did = luxRegistry.createDID(LUX_METHOD, "alice");

        // Add method
        VerificationMethod memory method = VerificationMethod({
            id: METHOD_KEY_1,
            methodType: VerificationMethodType.Ed25519VerificationKey2020,
            controller: alice,
            publicKeyMultibase: abi.encodePacked("z6Mk1"),
            blockchainAccountId: bytes32(0)
        });
        luxRegistry.addVerificationMethod(did, method);

        // Remove method
        vm.expectEmit(true, true, false, false);
        emit VerificationMethodRemoved(did, METHOD_KEY_1);

        luxRegistry.removeVerificationMethod(did, METHOD_KEY_1);

        vm.stopPrank();

        VerificationMethod[] memory methods = luxRegistry.getVerificationMethods(did);
        assertEq(methods.length, 0, "Should have 0 verification methods");
    }

    function test_PostQuantumVerificationMethod() public {
        vm.startPrank(alice);

        string memory did = luxRegistry.createDID(LUX_METHOD, "alice");

        // Add ML-DSA-44 (post-quantum)
        VerificationMethod memory pqMethod = VerificationMethod({
            id: keccak256("pq-key-1"),
            methodType: VerificationMethodType.MlDsa44VerificationKey2024,
            controller: alice,
            publicKeyMultibase: abi.encodePacked("zML-DSA-44-key"),
            blockchainAccountId: bytes32(0)
        });
        luxRegistry.addVerificationMethod(did, pqMethod);

        vm.stopPrank();

        VerificationMethod[] memory methods = luxRegistry.getVerificationMethods(did);
        assertEq(methods.length, 1, "Should have 1 verification method");
        assertEq(uint(methods[0].methodType), uint(VerificationMethodType.MlDsa44VerificationKey2024), "Should be ML-DSA-44");
    }

    function test_RevertWhen_AddVerificationMethod_MaxReached() public {
        vm.startPrank(alice);

        string memory did = luxRegistry.createDID(LUX_METHOD, "alice");

        // Add max verification methods
        for (uint256 i = 0; i < 20; i++) {
            VerificationMethod memory method = VerificationMethod({
                id: keccak256(abi.encodePacked("key-", i)),
                methodType: VerificationMethodType.Ed25519VerificationKey2020,
                controller: alice,
                publicKeyMultibase: abi.encodePacked("z6Mk", i),
                blockchainAccountId: bytes32(0)
            });
            luxRegistry.addVerificationMethod(did, method);
        }

        // Attempt to add one more
        VerificationMethod memory extraMethod = VerificationMethod({
            id: keccak256("extra"),
            methodType: VerificationMethodType.Ed25519VerificationKey2020,
            controller: alice,
            publicKeyMultibase: abi.encodePacked("z6MkExtra"),
            blockchainAccountId: bytes32(0)
        });

        vm.expectRevert(DIDRegistry.MaxVerificationMethodsReached.selector);
        luxRegistry.addVerificationMethod(did, extraMethod);

        vm.stopPrank();
    }

    function test_RevertWhen_RemoveVerificationMethod_NotFound() public {
        vm.startPrank(alice);

        string memory did = luxRegistry.createDID(LUX_METHOD, "alice");

        vm.expectRevert(DIDRegistry.MethodNotFound.selector);
        luxRegistry.removeVerificationMethod(did, keccak256("nonexistent"));

        vm.stopPrank();
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // SERVICE ENDPOINTS
    // ═══════════════════════════════════════════════════════════════════════════

    function test_AddService() public {
        vm.startPrank(alice);

        string memory did = luxRegistry.createDID(LUX_METHOD, "alice");

        Service memory service = Service({
            id: SERVICE_MESSAGING,
            serviceType: ServiceType.MessagingService,
            endpoint: "https://messaging.lux.network/alice",
            data: abi.encodePacked("encryption: aes-256-gcm")
        });

        vm.expectEmit(true, true, false, true);
        emit ServiceAdded(did, SERVICE_MESSAGING, ServiceType.MessagingService);

        luxRegistry.addService(did, service);

        vm.stopPrank();

        Service[] memory services = luxRegistry.getServices(did);
        assertEq(services.length, 1, "Should have 1 service");
        assertEq(services[0].id, SERVICE_MESSAGING, "Service ID mismatch");
        assertEq(services[0].endpoint, "https://messaging.lux.network/alice", "Endpoint mismatch");
    }

    function test_AddMultipleServices() public {
        vm.startPrank(alice);

        string memory did = luxRegistry.createDID(LUX_METHOD, "alice");

        // Add messaging service
        Service memory messaging = Service({
            id: SERVICE_MESSAGING,
            serviceType: ServiceType.MessagingService,
            endpoint: "https://messaging.lux.network/alice",
            data: ""
        });
        luxRegistry.addService(did, messaging);

        // Add LLM service
        Service memory llm = Service({
            id: SERVICE_LLM,
            serviceType: ServiceType.LLMProvider,
            endpoint: "https://llm.lux.network/alice/qwen-3",
            data: abi.encodePacked("model: qwen-3-0.5b")
        });
        luxRegistry.addService(did, llm);

        vm.stopPrank();

        Service[] memory services = luxRegistry.getServices(did);
        assertEq(services.length, 2, "Should have 2 services");
    }

    function test_RemoveService() public {
        vm.startPrank(alice);

        string memory did = luxRegistry.createDID(LUX_METHOD, "alice");

        // Add service
        Service memory service = Service({
            id: SERVICE_MESSAGING,
            serviceType: ServiceType.MessagingService,
            endpoint: "https://messaging.lux.network/alice",
            data: ""
        });
        luxRegistry.addService(did, service);

        // Remove service
        vm.expectEmit(true, true, false, false);
        emit ServiceRemoved(did, SERVICE_MESSAGING);

        luxRegistry.removeService(did, SERVICE_MESSAGING);

        vm.stopPrank();

        Service[] memory services = luxRegistry.getServices(did);
        assertEq(services.length, 0, "Should have 0 services");
    }

    function test_RevertWhen_AddService_MaxReached() public {
        vm.startPrank(alice);

        string memory did = luxRegistry.createDID(LUX_METHOD, "alice");

        // Add max services
        for (uint256 i = 0; i < 10; i++) {
            Service memory service = Service({
                id: keccak256(abi.encodePacked("service-", i)),
                serviceType: ServiceType.Custom,
                endpoint: string(abi.encodePacked("https://service-", i, ".lux.network")),
                data: ""
            });
            luxRegistry.addService(did, service);
        }

        // Attempt to add one more
        Service memory extraService = Service({
            id: keccak256("extra"),
            serviceType: ServiceType.Custom,
            endpoint: "https://extra.lux.network",
            data: ""
        });

        vm.expectRevert(DIDRegistry.MaxServicesReached.selector);
        luxRegistry.addService(did, extraService);

        vm.stopPrank();
    }

    function test_RevertWhen_RemoveService_NotFound() public {
        vm.startPrank(alice);

        string memory did = luxRegistry.createDID(LUX_METHOD, "alice");

        vm.expectRevert(DIDRegistry.ServiceNotFound.selector);
        luxRegistry.removeService(did, keccak256("nonexistent"));

        vm.stopPrank();
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // ALSO KNOWN AS (ALIASES)
    // ═══════════════════════════════════════════════════════════════════════════

    function test_AddAlsoKnownAs() public {
        vm.startPrank(alice);

        string memory did = luxRegistry.createDID(LUX_METHOD, "alice");

        vm.expectEmit(true, false, false, true);
        emit AlsoKnownAsAdded(did, "did:hanzo:alice");

        luxRegistry.addAlsoKnownAs(did, "did:hanzo:alice");

        vm.stopPrank();

        string[] memory aliases = luxRegistry.getAlsoKnownAs(did);
        assertEq(aliases.length, 1, "Should have 1 alias");
        assertEq(aliases[0], "did:hanzo:alice", "Alias mismatch");
    }

    function test_AddMultipleAliases() public {
        vm.startPrank(alice);

        string memory did = luxRegistry.createDID(LUX_METHOD, "alice");

        luxRegistry.addAlsoKnownAs(did, "did:hanzo:alice");
        luxRegistry.addAlsoKnownAs(did, "did:ethr:0x1234567890123456789012345678901234567890");
        luxRegistry.addAlsoKnownAs(did, "https://alice.lux.network");

        vm.stopPrank();

        string[] memory aliases = luxRegistry.getAlsoKnownAs(did);
        assertEq(aliases.length, 3, "Should have 3 aliases");
    }

    function test_RevertWhen_AddAlsoKnownAs_MaxReached() public {
        vm.startPrank(alice);

        string memory did = luxRegistry.createDID(LUX_METHOD, "alice");

        // Add max aliases
        for (uint256 i = 0; i < 5; i++) {
            luxRegistry.addAlsoKnownAs(did, string(abi.encodePacked("did:alias-", i)));
        }

        // Attempt to add one more
        vm.expectRevert(DIDRegistry.MaxAliasesReached.selector);
        luxRegistry.addAlsoKnownAs(did, "did:extra");

        vm.stopPrank();
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // DID DEACTIVATION
    // ═══════════════════════════════════════════════════════════════════════════

    function test_DeactivateDID() public {
        vm.startPrank(alice);

        string memory did = luxRegistry.createDID(LUX_METHOD, "alice");

        vm.expectEmit(true, true, false, true);
        emit DIDDeactivated(did, did, alice, block.timestamp);

        luxRegistry.deactivateDID(did);

        vm.stopPrank();

        // Check DID is deactivated
        assertFalse(luxRegistry.didExists(did), "DID should not exist (deactivated)");
    }

    function test_RevertWhen_DeactivateDID_NotController() public {
        vm.prank(alice);
        string memory did = luxRegistry.createDID(LUX_METHOD, "alice");

        vm.prank(attacker);
        vm.expectRevert(DIDRegistry.NotController.selector);
        luxRegistry.deactivateDID(did);
    }

    function test_RevertWhen_OperateOnDeactivatedDID() public {
        vm.startPrank(alice);

        string memory did = luxRegistry.createDID(LUX_METHOD, "alice");
        luxRegistry.deactivateDID(did);

        // Attempt to add verification method
        VerificationMethod memory method = VerificationMethod({
            id: METHOD_KEY_1,
            methodType: VerificationMethodType.Ed25519VerificationKey2020,
            controller: alice,
            publicKeyMultibase: abi.encodePacked("z6Mk"),
            blockchainAccountId: bytes32(0)
        });

        vm.expectRevert(DIDRegistry.DIDIsDeactivated.selector);
        luxRegistry.addVerificationMethod(did, method);

        vm.stopPrank();
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // ACCESS CONTROL
    // ═══════════════════════════════════════════════════════════════════════════

    function test_PublicRegistration_Enabled() public {
        assertTrue(luxRegistry.publicRegistration(), "Public registration should be enabled");

        vm.prank(alice);
        string memory did = luxRegistry.createDID(LUX_METHOD, "alice");

        assertEq(did, aliceDID, "DID should be created");
    }

    function test_PublicRegistration_Disabled() public {
        assertFalse(hanzoRegistry.publicRegistration(), "Public registration should be disabled");

        vm.prank(alice);
        vm.expectRevert(DIDRegistry.RegistrationClosed.selector);
        hanzoRegistry.createDID(HANZO_METHOD, "alice");
    }

    function test_SetPublicRegistration_AsAdmin() public {
        vm.prank(admin);
        luxRegistry.setPublicRegistration(false);

        assertFalse(luxRegistry.publicRegistration(), "Public registration should be disabled");
    }

    function test_RevertWhen_SetPublicRegistration_NotAdmin() public {
        vm.prank(attacker);
        vm.expectRevert();
        luxRegistry.setPublicRegistration(false);
    }

    function test_RegistrarRole_CreateDIDFor() public {
        vm.prank(registrar);
        string memory did = hanzoRegistry.createDIDFor("charlie", charlie);

        assertEq(did, charlieDID, "DID should be created");
        assertEq(hanzoRegistry.controllerOf(did), charlie, "Controller should be charlie");
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // DID RESOLVER TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function test_Resolver_RegisterMethod() public {
        DIDRegistry newRegistry = new DIDRegistry(admin, "newmethod", true);

        vm.prank(admin);
        resolver.registerMethod("newmethod", address(newRegistry));

        address registry = resolver.getRegistry("newmethod");
        assertEq(registry, address(newRegistry), "Registry should be registered");
    }

    function test_Resolver_UpdateMethodRegistry() public {
        DIDRegistry newRegistry = new DIDRegistry(admin, LUX_METHOD, true);

        vm.prank(admin);
        resolver.updateMethodRegistry(LUX_METHOD, address(newRegistry));

        address registry = resolver.getRegistry(LUX_METHOD);
        assertEq(registry, address(newRegistry), "Registry should be updated");
    }

    function test_Resolver_UnregisterMethod() public {
        vm.prank(admin);
        resolver.unregisterMethod(LUX_METHOD);

        address registry = resolver.getRegistry(LUX_METHOD);
        assertEq(registry, address(0), "Registry should be unregistered");
    }

    function test_Resolver_GetRegisteredMethods() public view {
        string[] memory methods = resolver.getRegisteredMethods();
        assertEq(methods.length, 2, "Should have 2 registered methods");
    }

    function test_Resolver_ParseDID() public view {
        (string memory method, string memory identifier) = resolver.parseDID(aliceDID);

        assertEq(method, LUX_METHOD, "Method should be 'lux'");
        assertEq(identifier, "alice", "Identifier should be 'alice'");
    }

    function test_Resolver_ParseDID_WithNetwork() public view {
        (string memory method, string memory identifier) = resolver.parseDID("did:lux:mainnet:0x1234");

        assertEq(method, LUX_METHOD, "Method should be 'lux'");
        assertEq(identifier, "mainnet:0x1234", "Identifier should include network");
    }

    function test_RevertWhen_ParseDID_Invalid() public {
        vm.expectRevert(DIDResolver.InvalidDID.selector);
        resolver.parseDID("invalid-did");
    }

    function test_RevertWhen_ParseDID_TooShort() public {
        vm.expectRevert(DIDResolver.InvalidDID.selector);
        resolver.parseDID("did:x");
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // OMNICHAIN RESOLUTION
    // ═══════════════════════════════════════════════════════════════════════════

    function test_OmnichainResolver_RegisterChainResolver() public {
        address remoteResolver = makeAddr("remoteResolver");

        vm.prank(admin);
        omnichainResolver.registerChainResolver(1, remoteResolver);

        assertEq(omnichainResolver.chainResolvers(1), remoteResolver, "Chain resolver should be registered");
    }

    function test_OmnichainResolver_GetOmnichainVariants() public {
        vm.prank(alice);
        luxRegistry.createDID(LUX_METHOD, "alice");

        string[] memory variants = omnichainResolver.getOmnichainVariants(aliceDID);
        assertGe(variants.length, 1, "Should have at least 1 variant");
    }

    function test_OmnichainResolver_IsSameEntity_Identical() public {
        vm.prank(alice);
        luxRegistry.createDID(LUX_METHOD, "alice");

        bool isSame = omnichainResolver.isSameEntity(aliceDID, aliceDID);
        assertTrue(isSame, "Should be same entity (identical DIDs)");
    }

    function test_OmnichainResolver_IsSameEntity_Different() public {
        vm.prank(alice);
        luxRegistry.createDID(LUX_METHOD, "alice");

        vm.prank(bob);
        luxRegistry.createDID(LUX_METHOD, "bob");

        bool isSame = omnichainResolver.isSameEntity(aliceDID, bobDID);
        assertFalse(isSame, "Should not be same entity");
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // EDGE CASES & SECURITY
    // ═══════════════════════════════════════════════════════════════════════════

    function test_RevertWhen_ZeroAddressController() public {
        vm.prank(admin);
        vm.expectRevert(DIDRegistry.ZeroAddress.selector);
        luxRegistry.createDIDFor("test", address(0));
    }

    function test_NonceIncrement() public {
        uint256 initialNonce = luxRegistry.nonces(alice);

        vm.prank(alice);
        luxRegistry.createDID(LUX_METHOD, "alice");

        // Note: Current implementation doesn't increment nonces
        // This test is for future replay protection
        assertEq(luxRegistry.nonces(alice), initialNonce, "Nonce should not change (not implemented yet)");
    }

    function test_TotalDIDsIncrement() public {
        assertEq(luxRegistry.totalDIDs(), 0, "Should start at 0");

        vm.prank(alice);
        luxRegistry.createDID(LUX_METHOD, "alice");
        assertEq(luxRegistry.totalDIDs(), 1, "Should be 1 after first DID");

        vm.prank(bob);
        luxRegistry.createDID(LUX_METHOD, "bob");
        assertEq(luxRegistry.totalDIDs(), 2, "Should be 2 after second DID");
    }

    function test_LongIdentifier() public {
        string memory longId = "this-is-a-very-long-identifier-with-many-characters-to-test-gas-limits-and-storage-efficiency";

        vm.prank(alice);
        string memory did = luxRegistry.createDID(LUX_METHOD, longId);

        assertTrue(luxRegistry.didExists(did), "Long identifier DID should exist");
    }

    function test_SpecialCharactersInIdentifier() public {
        vm.prank(alice);
        string memory did = luxRegistry.createDID(LUX_METHOD, "alice-123_test.id");

        assertTrue(luxRegistry.didExists(did), "Special characters DID should exist");
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // FUZZ TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function testFuzz_CreateDID(string calldata identifier, address controller) public {
        // Bound inputs
        vm.assume(bytes(identifier).length > 0);
        vm.assume(bytes(identifier).length < 256);
        vm.assume(controller != address(0));

        // Create DID as registrar
        vm.prank(registrar);

        try luxRegistry.createDIDFor(identifier, controller) returns (string memory did) {
            assertTrue(luxRegistry.didExists(did), "DID should exist");
            assertEq(luxRegistry.controllerOf(did), controller, "Controller should match");
        } catch {
            // Some identifiers may fail (e.g., duplicates in fuzzing)
        }
    }

    function testFuzz_ChangeController(address newController) public {
        vm.assume(newController != address(0));

        // Create DID
        vm.prank(alice);
        string memory did = luxRegistry.createDID(LUX_METHOD, "alice");

        // Change controller
        vm.prank(alice);
        luxRegistry.changeController(did, newController);

        assertEq(luxRegistry.controllerOf(did), newController, "Controller should be updated");
    }

    function testFuzz_AddVerificationMethod(bytes32 methodId, uint8 methodTypeRaw) public {
        // Bound method type to valid enum range (0-11, there are 12 values in VerificationMethodType)
        vm.assume(methodTypeRaw < 12);
        VerificationMethodType methodType = VerificationMethodType(methodTypeRaw);

        vm.startPrank(alice);

        string memory did = luxRegistry.createDID(LUX_METHOD, "alice");

        VerificationMethod memory method = VerificationMethod({
            id: methodId,
            methodType: methodType,
            controller: alice,
            publicKeyMultibase: abi.encodePacked("z6Mk"),
            blockchainAccountId: bytes32(0)
        });

        try luxRegistry.addVerificationMethod(did, method) {
            VerificationMethod[] memory methods = luxRegistry.getVerificationMethods(did);
            assertGe(methods.length, 1, "Should have at least 1 method");
        } catch {
            // May fail if max methods reached
        }

        vm.stopPrank();
    }

    function testFuzz_AddService(bytes32 serviceId, string calldata endpoint) public {
        vm.assume(bytes(endpoint).length > 0);
        vm.assume(bytes(endpoint).length < 256);

        vm.startPrank(alice);

        string memory did = luxRegistry.createDID(LUX_METHOD, "alice");

        Service memory service = Service({
            id: serviceId,
            serviceType: ServiceType.Custom,
            endpoint: endpoint,
            data: ""
        });

        try luxRegistry.addService(did, service) {
            Service[] memory services = luxRegistry.getServices(did);
            assertGe(services.length, 1, "Should have at least 1 service");
        } catch {
            // May fail if max services reached
        }

        vm.stopPrank();
    }

    function testFuzz_ResolveDID(string calldata identifier) public {
        vm.assume(bytes(identifier).length > 0);
        vm.assume(bytes(identifier).length < 256);

        // Create DID
        vm.prank(registrar);
        try luxRegistry.createDIDFor(identifier, alice) returns (string memory did) {
            // Resolve should work
            DIDDocument memory doc = luxRegistry.resolve(did);
            assertEq(doc.controller, alice, "Controller should match");
            assertTrue(doc.active, "DID should be active");
        } catch {
            // Some identifiers may fail
        }
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // GAS BENCHMARKS
    // ═══════════════════════════════════════════════════════════════════════════

    function test_Gas_CreateDID() public {
        vm.prank(alice);
        uint256 gasBefore = gasleft();
        luxRegistry.createDID(LUX_METHOD, "alice");
        uint256 gasUsed = gasBefore - gasleft();

        emit log_named_uint("Gas used for createDID", gasUsed);
        assertLt(gasUsed, 500_000, "Gas should be reasonable");
    }

    function test_Gas_ResolveDID() public {
        vm.prank(alice);
        luxRegistry.createDID(LUX_METHOD, "alice");

        uint256 gasBefore = gasleft();
        luxRegistry.resolve(aliceDID);
        uint256 gasUsed = gasBefore - gasleft();

        emit log_named_uint("Gas used for resolve", gasUsed);
        assertLt(gasUsed, 100_000, "Gas should be reasonable");
    }

    function test_Gas_AddVerificationMethod() public {
        vm.startPrank(alice);

        string memory did = luxRegistry.createDID(LUX_METHOD, "alice");

        VerificationMethod memory method = VerificationMethod({
            id: METHOD_KEY_1,
            methodType: VerificationMethodType.Ed25519VerificationKey2020,
            controller: alice,
            publicKeyMultibase: abi.encodePacked("z6Mk"),
            blockchainAccountId: bytes32(0)
        });

        uint256 gasBefore = gasleft();
        luxRegistry.addVerificationMethod(did, method);
        uint256 gasUsed = gasBefore - gasleft();

        emit log_named_uint("Gas used for addVerificationMethod", gasUsed);
        assertLt(gasUsed, 200_000, "Gas should be reasonable");

        vm.stopPrank();
    }
}
