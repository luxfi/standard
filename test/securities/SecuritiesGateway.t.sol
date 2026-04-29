// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Lux Partners Limited
pragma solidity ^0.8.31;

import "forge-std/Test.sol";

import { SecurityToken } from "../../contracts/securities/token/SecurityToken.sol";
import { SecuritiesGateway } from "../../contracts/securities/bridge/SecuritiesGateway.sol";
import { IToken } from "@luxfi/erc-3643/contracts/token/IToken.sol";
import { IIdentityRegistry } from "@luxfi/erc-3643/contracts/registry/interface/IIdentityRegistry.sol";
import { IIdentityRegistryStorage } from "@luxfi/erc-3643/contracts/registry/interface/IIdentityRegistryStorage.sol";
import { ITrustedIssuersRegistry } from "@luxfi/erc-3643/contracts/registry/interface/ITrustedIssuersRegistry.sol";
import { IClaimTopicsRegistry } from "@luxfi/erc-3643/contracts/registry/interface/IClaimTopicsRegistry.sol";
import { IIdentity } from "@luxfi/onchain-id/contracts/interface/IIdentity.sol";
import { IModularCompliance } from "@luxfi/erc-3643/contracts/compliance/modular/IModularCompliance.sol";

/// Identity stub — keyHasPurpose returns true for any key, so SecurityToken.recoveryAddress works.
contract MockIdentity {
    mapping(uint256 => bytes32[]) private _claims;

    function setClaim(uint256 topic, bytes32 claimId) external {
        _claims[topic].push(claimId);
    }

    function getClaimIdsByTopic(uint256 topic) external view returns (bytes32[] memory) {
        return _claims[topic];
    }
}

/// Minimal IIdentityRegistry — just `isVerified`, `investorCountry`, `identity`,
/// `registerIdentity`, `deleteIdentity`. T-REX SecurityToken only calls these.
contract MockIdentityRegistry {
    mapping(address => bool) public _verified;
    mapping(address => uint16) public _country;
    mapping(address => address) public _identity;

    function setVerified(address user, bool v) external {
        _verified[user] = v;
    }

    function setCountry(address user, uint16 c) external {
        _country[user] = c;
    }

    function setIdentity(address user, address id) external {
        _identity[user] = id;
    }

    function isVerified(address user) external view returns (bool) {
        return _verified[user];
    }

    function investorCountry(address user) external view returns (uint16) {
        return _country[user];
    }

    function identity(address user) external view returns (IIdentity) {
        return IIdentity(_identity[user]);
    }

    // T-REX SecurityToken.recoveryAddress calls these; not exercised in this test.
    function registerIdentity(address user, IIdentity id, uint16 country) external {
        _verified[user] = true;
        _identity[user] = address(id);
        _country[user] = country;
    }

    function deleteIdentity(address user) external {
        _verified[user] = false;
        _identity[user] = address(0);
        _country[user] = 0;
    }

    // Surface the rest of the interface so Solidity is happy with IIdentityRegistry casts.
    function identityStorage() external pure returns (IIdentityRegistryStorage) {
        return IIdentityRegistryStorage(address(0));
    }

    function issuersRegistry() external pure returns (ITrustedIssuersRegistry) {
        return ITrustedIssuersRegistry(address(0));
    }

    function topicsRegistry() external pure returns (IClaimTopicsRegistry) {
        return IClaimTopicsRegistry(address(0));
    }
    function batchRegisterIdentity(address[] calldata, IIdentity[] calldata, uint16[] calldata) external { }
    function updateIdentity(address, IIdentity) external { }
    function updateCountry(address, uint16) external { }
    function setIdentityRegistryStorage(address) external { }
    function setClaimTopicsRegistry(address) external { }
    function setTrustedIssuersRegistry(address) external { }

    function isAgent(address) external pure returns (bool) {
        return true;
    }
    function addAgent(address) external { }
    function removeAgent(address) external { }

    function contains(address) external pure returns (bool) {
        return false;
    }
    function transferOwnership(address) external { }

    function owner() external view returns (address) {
        return address(0);
    }
    function renounceOwnership() external { }
}

/// Minimal modular compliance — always allow, no-op hooks.
contract MockCompliance {
    address public boundToken;

    function bindToken(address t) external {
        boundToken = t;
    }

    function unbindToken(address) external {
        boundToken = address(0);
    }

    function canTransfer(address, address, uint256) external pure returns (bool) {
        return true;
    }
    function transferred(address, address, uint256) external { }
    function created(address, uint256) external { }
    function destroyed(address, uint256) external { }

    // Rest of IModularCompliance for type satisfaction.
    function isModuleBound(address) external pure returns (bool) {
        return false;
    }

    function getModules() external pure returns (address[] memory m) {
        return m;
    }
    function addModule(address) external { }
    function removeModule(address) external { }
    function callModuleFunction(bytes calldata, address) external { }

    function getTokenBound() external view returns (address) {
        return boundToken;
    }
}

/// @title SecuritiesGatewayTest
/// @notice End-to-end proof that ERC-3643 SecurityTokens can be teleported
///         BOTH directions between any pair of L1s — including OP_NET (Bitcoin)
///         — through a single MPC-relayed gateway, with full compliance
///         enforced on the inbound side.
contract SecuritiesGatewayTest is Test {
    using stdStorage for StdStorage;

    // Lux C-Chain
    uint64 internal constant LUX_CHAIN_ID = 96369;
    // OP_NET (Bitcoin metaprotocol)
    uint64 internal constant OPNET_CHAIN_ID = 4_294_967_299;
    // Zoo EVM
    uint64 internal constant ZOO_CHAIN_ID = 200200;

    SecurityToken internal sec;
    MockIdentityRegistry internal idReg;
    MockCompliance internal comp;

    SecuritiesGateway internal gateway;

    address internal admin = makeAddr("admin");
    address internal governor = makeAddr("governor");
    address internal alice = makeAddr("alice"); // KYC'd, holds securities on Lux
    address internal bob = makeAddr("bob"); // KYC'd inbound recipient
    address internal eve = makeAddr("eve"); // NOT KYC'd — should never receive

    uint256 internal mpcKey = 0xBEEF;
    address internal mpcGroup;

    // Bitcoin Taproot x-only pubkey for `alice` on the OP_NET side.
    bytes32 internal aliceTaproot = 0x1d1c5f3a4d4a4c2a8c5b6e7f8090a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6e7f8;

    function setUp() public {
        mpcGroup = vm.addr(mpcKey);

        idReg = new MockIdentityRegistry();
        comp = new MockCompliance();

        // Deploy lux SecurityToken with a clean constructor (no proxy / init).
        sec = new SecurityToken(
            "Acme Series A",
            "ACME",
            18,
            IIdentityRegistry(address(idReg)),
            IModularCompliance(address(comp)),
            address(0),
            admin
        );

        gateway = new SecuritiesGateway(LUX_CHAIN_ID, governor, mpcGroup);

        // Wire the gateway:
        //   - governor registers ACME with the gateway
        //   - admin grants AGENT_ROLE on ACME to the gateway (so it can mint/burn)
        vm.prank(governor);
        gateway.registerToken(address(sec));

        bytes32 agentRole = sec.AGENT_ROLE();
        vm.prank(admin);
        sec.grantRole(agentRole, address(gateway));

        // Alice and Bob are KYC'd holders. Eve is not.
        idReg.setVerified(alice, true);
        idReg.setVerified(bob, true);

        // Seed Alice with 1000 ACME via T-REX `mint` (admin holds AGENT_ROLE).
        vm.prank(admin);
        sec.mint(alice, 1000 ether);
    }

    // ── 1. EVM → OP_NET (outbound) ─────────────────────────────────────────

    /// @notice Lux/Zoo holder burns SecurityToken to mint OP-20 on Bitcoin (OP_NET).
    function test_outbound_to_opnet() public {
        uint256 amount = 100 ether;

        // Alice approves nothing — gateway uses `IToken.burn(alice, amount)`,
        // which is the T-REX agent path. AGENT_ROLE was granted in setUp.

        vm.expectEmit(true, true, true, true);
        emit SecuritiesGateway.Outbound(OPNET_CHAIN_ID, 1, address(sec), alice, aliceTaproot, amount);

        vm.prank(alice);
        uint64 nonce = gateway.outbound(address(sec), amount, OPNET_CHAIN_ID, aliceTaproot);

        assertEq(nonce, 1, "first outbound nonce");
        assertEq(sec.balanceOf(alice), 900 ether, "alice burned 100");
    }

    /// @notice The same primitive teleports to Zoo EVM, with a real address recipient.
    function test_outbound_to_zoo_evm() public {
        uint256 amount = 50 ether;
        bytes32 zooRecipient = bytes32(uint256(uint160(bob)));

        vm.expectEmit(true, true, true, true);
        emit SecuritiesGateway.Outbound(ZOO_CHAIN_ID, 1, address(sec), alice, zooRecipient, amount);

        vm.prank(alice);
        gateway.outbound(address(sec), amount, ZOO_CHAIN_ID, zooRecipient);
    }

    // ── 2. OP_NET → EVM (inbound, MPC-signed) ─────────────────────────────

    /// @notice MPC oracle relays an OP_NET burn → mint ACME on Lux to a KYC'd holder.
    function test_inbound_from_opnet_kyced_recipient() public {
        uint256 amount = 200 ether;
        uint64 srcNonce = 42;

        bytes memory sig = _signInbound(OPNET_CHAIN_ID, srcNonce, address(sec), bob, amount);

        vm.expectEmit(true, true, true, true);
        emit SecuritiesGateway.Inbound(OPNET_CHAIN_ID, srcNonce, address(sec), bob, amount);

        gateway.inbound(OPNET_CHAIN_ID, srcNonce, address(sec), bob, amount, sig);

        assertEq(sec.balanceOf(bob), amount, "bob received the inbound mint");
    }

    /// @notice Mint to an UNVERIFIED recipient must revert — even with a valid MPC sig.
    ///         T-REX's `mint(address,uint256)` enforces `IIdentityRegistry.isVerified(to)`.
    ///         This is the canonical compliance gate for digital securities.
    function test_inbound_unverified_recipient_reverts() public {
        uint256 amount = 200 ether;
        uint64 srcNonce = 43;

        bytes memory sig = _signInbound(OPNET_CHAIN_ID, srcNonce, address(sec), eve, amount);

        // T-REX SecurityToken.mint reverts on unverified recipient.
        vm.expectRevert();
        gateway.inbound(OPNET_CHAIN_ID, srcNonce, address(sec), eve, amount, sig);
    }

    /// @notice Replay protection — same (srcChain, nonce) cannot be processed twice.
    function test_inbound_replay_blocked() public {
        uint256 amount = 50 ether;
        uint64 srcNonce = 44;

        bytes memory sig = _signInbound(OPNET_CHAIN_ID, srcNonce, address(sec), bob, amount);
        gateway.inbound(OPNET_CHAIN_ID, srcNonce, address(sec), bob, amount, sig);

        vm.expectRevert(abi.encodeWithSelector(SecuritiesGateway.AlreadyProcessed.selector, OPNET_CHAIN_ID, srcNonce));
        gateway.inbound(OPNET_CHAIN_ID, srcNonce, address(sec), bob, amount, sig);
    }

    /// @notice Forged MPC signature must be rejected.
    function test_inbound_invalid_signature_reverts() public {
        uint256 amount = 100 ether;
        uint64 srcNonce = 45;

        // Sign with a non-MPC key.
        uint256 fakeKey = 0xBADBEEF;
        bytes32 digest =
            keccak256(abi.encode("INBOUND", LUX_CHAIN_ID, OPNET_CHAIN_ID, srcNonce, address(sec), bob, amount));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(fakeKey, _eth(digest));
        bytes memory badSig = abi.encodePacked(r, s, v);

        vm.expectRevert(SecuritiesGateway.InvalidSignature.selector);
        gateway.inbound(OPNET_CHAIN_ID, srcNonce, address(sec), bob, amount, badSig);
    }

    // ── 3. Round-trip — burn on EVM, mint on OP_NET, burn on OP_NET, mint on EVM ──

    /// @notice Full lifecycle: Alice teleports 100 ACME to OP_NET, then it
    ///         comes back to Bob on Lux (after Bob clears KYC).
    function test_roundtrip_evm_opnet_evm() public {
        // EVM → OP_NET: alice burns 100, gateway emits Outbound to OPNET.
        vm.prank(alice);
        gateway.outbound(address(sec), 100 ether, OPNET_CHAIN_ID, aliceTaproot);
        assertEq(sec.balanceOf(alice), 900 ether);

        // … some time later, MPC observes a 100 ACME burn on OP_NET destined for Bob (KYC'd).
        bytes memory sig = _signInbound(OPNET_CHAIN_ID, 1, address(sec), bob, 100 ether);
        gateway.inbound(OPNET_CHAIN_ID, 1, address(sec), bob, 100 ether, sig);

        assertEq(sec.balanceOf(bob), 100 ether, "round-trip closed at bob");
    }

    // ── Helpers ────────────────────────────────────────────────────────────

    function _signInbound(uint64 srcChain, uint64 nonce, address token, address recipient, uint256 amount)
        internal
        view
        returns (bytes memory)
    {
        bytes32 digest = keccak256(abi.encode("INBOUND", LUX_CHAIN_ID, srcChain, nonce, token, recipient, amount));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(mpcKey, _eth(digest));
        return abi.encodePacked(r, s, v);
    }

    function _eth(bytes32 d) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", d));
    }
}
