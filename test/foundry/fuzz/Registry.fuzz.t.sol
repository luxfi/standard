// SPDX-License-Identifier: MIT
pragma solidity ^0.8.31;

import "forge-std/Test.sol";
import {Registry} from "../../../contracts/did/Registry.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {MockERC20} from "../TestMocks.sol";

/// @title MockIdentityNFT
/// @notice Minimal NFT for Registry fuzz testing
contract MockIdentityNFT {
    uint256 public nextTokenId = 1;
    mapping(uint256 => address) public owners;

    function mint(address to) external returns (uint256) {
        uint256 tokenId = nextTokenId++;
        owners[tokenId] = to;
        return tokenId;
    }

    function burn(uint256 tokenId) external {
        delete owners[tokenId];
    }

    function ownerOf(uint256 tokenId) external view returns (address) {
        return owners[tokenId];
    }
}

/// @title RegistryFuzzTest
/// @notice Fuzz tests for Registry.sol - DID registration and stake management
contract RegistryFuzzTest is Test {
    Registry public registry;
    MockERC20 public stakingToken;
    MockIdentityNFT public identityNft;

    address public owner;
    address public alice;
    address public bob;

    uint256 constant LUX_CHAIN_ID = 96369;

    function setUp() public {
        owner = makeAddr("owner");
        alice = makeAddr("alice");
        bob = makeAddr("bob");

        // Deploy mocks
        stakingToken = new MockERC20("Staking Token", "STAKE", 18);
        identityNft = new MockIdentityNFT();

        // Deploy Registry via proxy
        Registry impl = new Registry();
        bytes memory initData = abi.encodeWithSelector(
            Registry.initialize.selector,
            owner,
            address(stakingToken),
            address(identityNft)
        );
        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), initData);
        registry = Registry(address(proxy));
    }

    // =========================================================================
    // CLAIM FUZZ TESTS
    // =========================================================================

    /// @notice Fuzz test claim with various stake amounts
    /// @dev Tests that stake >= required succeeds, stake < required fails
    function testFuzz_Claim_StakeAmounts(uint256 stakeAmount) public {
        // Bound stake amount to reasonable range (avoid overflow in token minting)
        stakeAmount = bound(stakeAmount, 0, type(uint128).max);

        string memory name = "testuser";
        uint256 required = registry.stakeRequirement(name, false);

        // Fund alice
        stakingToken.mint(alice, stakeAmount);
        vm.prank(alice);
        stakingToken.approve(address(registry), stakeAmount);

        Registry.ClaimParams memory params = Registry.ClaimParams({
            name: name,
            chainId: LUX_CHAIN_ID,
            stakeAmount: stakeAmount,
            owner: alice,
            referrer: ""
        });

        if (stakeAmount < required) {
            vm.expectRevert(Registry.InsufficientStake.selector);
            vm.prank(alice);
            registry.claim(params);
        } else {
            vm.prank(alice);
            string memory did = registry.claim(params);

            // Verify state
            assertEq(registry.ownerOf(did), alice);
            Registry.IdentityData memory data = registry.getData(did);
            assertEq(data.stakedTokens, stakeAmount);
        }
    }

    /// @notice Fuzz test stake requirement calculation for name lengths
    function testFuzz_StakeRequirement_NameLength(uint8 length, bool hasReferrer) public {
        // Bound length to valid range (1-63)
        length = uint8(bound(length, 1, 63));

        // Generate name of given length
        bytes memory nameBytes = new bytes(length);
        for (uint8 i = 0; i < length; i++) {
            nameBytes[i] = bytes1(uint8(0x61 + (i % 26))); // a-z repeating
        }
        string memory name = string(nameBytes);

        uint256 requirement = registry.stakeRequirement(name, hasReferrer);

        // Verify pricing tiers
        uint256 expectedBase;
        if (length == 1) expectedBase = 100000 * 1e18;
        else if (length == 2) expectedBase = 10000 * 1e18;
        else if (length == 3) expectedBase = 1000 * 1e18;
        else if (length == 4) expectedBase = 100 * 1e18;
        else expectedBase = 10 * 1e18;

        if (hasReferrer) {
            // 50% discount
            assertEq(requirement, expectedBase / 2);
        } else {
            assertEq(requirement, expectedBase);
        }
    }

    /// @notice Fuzz test that claiming same name twice fails
    function testFuzz_Claim_DuplicateFails(uint256 stakeAmount) public {
        stakeAmount = bound(stakeAmount, 10 * 1e18, type(uint128).max);

        string memory name = "uniquename";

        // First claim by alice
        stakingToken.mint(alice, stakeAmount);
        vm.prank(alice);
        stakingToken.approve(address(registry), stakeAmount);

        Registry.ClaimParams memory params = Registry.ClaimParams({
            name: name,
            chainId: LUX_CHAIN_ID,
            stakeAmount: stakeAmount,
            owner: alice,
            referrer: ""
        });

        vm.prank(alice);
        registry.claim(params);

        // Second claim by bob should fail
        stakingToken.mint(bob, stakeAmount);
        vm.prank(bob);
        stakingToken.approve(address(registry), stakeAmount);

        params.owner = bob;

        vm.expectRevert(abi.encodeWithSelector(
            Registry.IdentityNotAvailable.selector,
            "did:lux:uniquename"
        ));
        vm.prank(bob);
        registry.claim(params);
    }

    // =========================================================================
    // UNCLAIM FUZZ TESTS
    // =========================================================================

    /// @notice Fuzz test unclaim returns correct stake
    function testFuzz_Unclaim_ReturnsStake(uint256 stakeAmount) public {
        stakeAmount = bound(stakeAmount, 10 * 1e18, type(uint128).max);

        string memory name = "unclaimtest";

        // Claim first
        stakingToken.mint(alice, stakeAmount);
        vm.prank(alice);
        stakingToken.approve(address(registry), stakeAmount);

        Registry.ClaimParams memory params = Registry.ClaimParams({
            name: name,
            chainId: LUX_CHAIN_ID,
            stakeAmount: stakeAmount,
            owner: alice,
            referrer: ""
        });

        vm.prank(alice);
        string memory did = registry.claim(params);

        uint256 balanceBefore = stakingToken.balanceOf(alice);

        // Unclaim
        vm.prank(alice);
        registry.unclaim(did);

        uint256 balanceAfter = stakingToken.balanceOf(alice);

        // Verify stake returned
        assertEq(balanceAfter - balanceBefore, stakeAmount);

        // Verify DID no longer owned
        assertEq(registry.ownerOf(did), address(0));
    }

    /// @notice Fuzz test that non-owner cannot unclaim
    function testFuzz_Unclaim_OnlyOwner(address attacker) public {
        vm.assume(attacker != alice);
        vm.assume(attacker != address(0));

        string memory name = "protected";
        uint256 stakeAmount = 100 * 1e18;

        // Claim by alice
        stakingToken.mint(alice, stakeAmount);
        vm.prank(alice);
        stakingToken.approve(address(registry), stakeAmount);

        Registry.ClaimParams memory params = Registry.ClaimParams({
            name: name,
            chainId: LUX_CHAIN_ID,
            stakeAmount: stakeAmount,
            owner: alice,
            referrer: ""
        });

        vm.prank(alice);
        string memory did = registry.claim(params);

        // Attacker tries to unclaim
        vm.expectRevert(Registry.Unauthorized.selector);
        vm.prank(attacker);
        registry.unclaim(did);
    }

    // =========================================================================
    // STAKE REQUIREMENT INVARIANT TESTS
    // =========================================================================

    /// @notice Invariant: referrer discount never exceeds 100%
    function testFuzz_StakeRequirement_ReferrerDiscountBounded(string calldata name) public {
        // Assume valid name
        bytes memory b = bytes(name);
        vm.assume(b.length >= 1 && b.length <= 63);

        // Check all chars are valid
        for (uint256 i = 0; i < b.length; i++) {
            bytes1 c = b[i];
            bool valid = (c >= 0x30 && c <= 0x39) ||  // 0-9
                        (c >= 0x41 && c <= 0x5A) ||   // A-Z
                        (c >= 0x61 && c <= 0x7A) ||   // a-z
                        (c == 0x5F);                   // _
            vm.assume(valid);
        }

        uint256 withoutReferrer = registry.stakeRequirement(name, false);
        uint256 withReferrer = registry.stakeRequirement(name, true);

        // Invariant: with referrer should be <= without referrer
        assertLe(withReferrer, withoutReferrer);

        // Invariant: with referrer should be > 0 (discount never 100%)
        assertGt(withReferrer, 0);
    }

    /// @notice Invariant: stake requirement monotonically decreases with name length
    function testFuzz_StakeRequirement_MonotonicDecreasing() public {
        // Test that longer names have lower or equal requirements
        uint256 prev = type(uint256).max;

        for (uint256 len = 1; len <= 10; len++) {
            bytes memory nameBytes = new bytes(len);
            for (uint256 i = 0; i < len; i++) {
                nameBytes[i] = bytes1(uint8(0x61)); // all 'a'
            }
            string memory name = string(nameBytes);
            uint256 requirement = registry.stakeRequirement(name, false);

            assertLe(requirement, prev, "Stake requirement should decrease with length");
            prev = requirement;
        }
    }

    // =========================================================================
    // EDGE CASE TESTS
    // =========================================================================

    /// @notice Test claim with minimum valid name (1 char)
    function testFuzz_Claim_MinNameLength() public {
        string memory name = "x";
        uint256 required = registry.stakeRequirement(name, false);

        stakingToken.mint(alice, required);
        vm.prank(alice);
        stakingToken.approve(address(registry), required);

        Registry.ClaimParams memory params = Registry.ClaimParams({
            name: name,
            chainId: LUX_CHAIN_ID,
            stakeAmount: required,
            owner: alice,
            referrer: ""
        });

        vm.prank(alice);
        string memory did = registry.claim(params);

        assertEq(registry.ownerOf(did), alice);
    }

    /// @notice Test claim with maximum valid name (63 chars)
    function testFuzz_Claim_MaxNameLength() public {
        bytes memory nameBytes = new bytes(63);
        for (uint256 i = 0; i < 63; i++) {
            nameBytes[i] = bytes1(uint8(0x61 + (i % 26)));
        }
        string memory name = string(nameBytes);

        uint256 required = registry.stakeRequirement(name, false);

        stakingToken.mint(alice, required);
        vm.prank(alice);
        stakingToken.approve(address(registry), required);

        Registry.ClaimParams memory params = Registry.ClaimParams({
            name: name,
            chainId: LUX_CHAIN_ID,
            stakeAmount: required,
            owner: alice,
            referrer: ""
        });

        vm.prank(alice);
        string memory did = registry.claim(params);

        assertEq(registry.ownerOf(did), alice);
    }

    /// @notice Test invalid names are rejected
    function testFuzz_Claim_InvalidNameRejected() public {
        // Empty name
        Registry.ClaimParams memory params = Registry.ClaimParams({
            name: "",
            chainId: LUX_CHAIN_ID,
            stakeAmount: 100 * 1e18,
            owner: alice,
            referrer: ""
        });

        vm.expectRevert(abi.encodeWithSelector(Registry.InvalidName.selector, ""));
        vm.prank(alice);
        registry.claim(params);

        // Name too long (64 chars)
        bytes memory longNameBytes = new bytes(64);
        for (uint256 i = 0; i < 64; i++) {
            longNameBytes[i] = bytes1(uint8(0x61));
        }
        string memory longName = string(longNameBytes);

        params.name = longName;
        vm.expectRevert(abi.encodeWithSelector(Registry.InvalidName.selector, longName));
        vm.prank(alice);
        registry.claim(params);
    }

    /// @notice Test claim with invalid chain ID
    function testFuzz_Claim_InvalidChainId(uint256 invalidChainId) public {
        // Assume chain ID is not one of the valid ones
        vm.assume(invalidChainId != 96369);   // lux
        vm.assume(invalidChainId != 96368);   // lux-test
        vm.assume(invalidChainId != 494949);  // pars
        vm.assume(invalidChainId != 494950);  // pars-test
        vm.assume(invalidChainId != 200200);  // zoo
        vm.assume(invalidChainId != 200201);  // zoo-test
        vm.assume(invalidChainId != 36963);   // hanzo
        vm.assume(invalidChainId != 36962);   // hanzo-test
        vm.assume(invalidChainId != 31337);   // local

        Registry.ClaimParams memory params = Registry.ClaimParams({
            name: "test",
            chainId: invalidChainId,
            stakeAmount: 100 * 1e18,
            owner: alice,
            referrer: ""
        });

        vm.expectRevert(abi.encodeWithSelector(Registry.InvalidChain.selector, invalidChainId));
        vm.prank(alice);
        registry.claim(params);
    }

    // =========================================================================
    // INCREASE STAKE FUZZ TESTS
    // =========================================================================

    /// @notice Fuzz test increasing stake after claim
    function testFuzz_IncreaseStake(uint256 initialStake, uint256 additionalStake) public {
        initialStake = bound(initialStake, 10 * 1e18, type(uint64).max);
        additionalStake = bound(additionalStake, 1, type(uint64).max);

        string memory name = "staketest";

        // Initial claim
        stakingToken.mint(alice, initialStake);
        vm.prank(alice);
        stakingToken.approve(address(registry), initialStake);

        Registry.ClaimParams memory params = Registry.ClaimParams({
            name: name,
            chainId: LUX_CHAIN_ID,
            stakeAmount: initialStake,
            owner: alice,
            referrer: ""
        });

        vm.prank(alice);
        string memory did = registry.claim(params);

        // Increase stake
        stakingToken.mint(alice, additionalStake);
        vm.prank(alice);
        stakingToken.approve(address(registry), additionalStake);

        vm.prank(alice);
        registry.increaseStake(did, additionalStake);

        // Verify total stake
        Registry.IdentityData memory data = registry.getData(did);
        assertEq(data.stakedTokens, initialStake + additionalStake);
    }
}
