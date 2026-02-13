// SPDX-License-Identifier: MIT
pragma solidity ^0.8.31;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "../../contracts/treasury/FeeGov.sol";
import "../../contracts/treasury/Vault.sol";
import "../../contracts/treasury/Router.sol";
import "../../contracts/treasury/Collect.sol";

// Mock WLUX for testing
contract MockWLUX is ERC20 {
    constructor() ERC20("Wrapped LUX", "WLUX") {}
    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

/**
 * @title TreasuryTest
 * @notice Tests for Treasury architecture
 * @dev Tests FeeGov, Vault, Router, Collect contracts
 */
contract TreasuryTest is Test {
    MockWLUX public wlux;
    FeeGov public gov;
    Vault public vault;
    Router public router;
    Collect public collect;

    address public owner = makeAddr("owner");
    address public dao = makeAddr("dao");
    address public stakers = makeAddr("stakers");
    address public dev = makeAddr("dev");
    address public relayer = makeAddr("relayer");

    // Chain IDs
    bytes32 constant CHAIN_C = keccak256("C");
    bytes32 constant CHAIN_D = keccak256("D");
    bytes32 constant CHAIN_P = keccak256("P");

    function setUp() public {
        wlux = new MockWLUX();

        // Deploy C-Chain contracts
        gov = new FeeGov(30, 10, 500, owner);    // 0.3% rate, 0.1% floor, 5% cap
        vault = new Vault(address(wlux));
        router = new Router(address(wlux), address(vault), owner);

        // Wire vault to router
        vault.init(address(router));

        // Deploy collector on another chain (simulated)
        collect = new Collect(address(wlux), CHAIN_C, address(vault), owner);

        // Set up router weights: 70% stakers, 20% DAO, 10% dev
        address[] memory recipients = new address[](3);
        uint256[] memory weights = new uint256[](3);
        recipients[0] = stakers;
        recipients[1] = dao;
        recipients[2] = dev;
        weights[0] = 7000;  // 70%
        weights[1] = 2000;  // 20%
        weights[2] = 1000;  // 10%

        vm.prank(owner);
        router.setBatch(recipients, weights);

        // Fund relayer for bridging
        wlux.mint(relayer, 1000 ether);
    }

    // ============ FeeGov Tests ============

    function test_FeeGov_InitialState() public view {
        assertEq(gov.rate(), 30);
        assertEq(gov.floor(), 10);
        assertEq(gov.cap(), 500);
        assertEq(gov.version(), 1);
    }

    function test_FeeGov_SetRate() public {
        vm.prank(owner);
        gov.set(50); // 0.5%

        assertEq(gov.rate(), 50);
        assertEq(gov.version(), 2);
    }

    function test_FeeGov_SetRate_RevertBelowFloor() public {
        vm.prank(owner);
        vm.expectRevert(FeeGov.TooLow.selector);
        gov.set(5); // Below 10 floor
    }

    function test_FeeGov_SetRate_RevertAboveCap() public {
        vm.prank(owner);
        vm.expectRevert(FeeGov.TooHigh.selector);
        gov.set(600); // Above 500 cap
    }

    function test_FeeGov_AddChain() public {
        vm.prank(owner);
        gov.add(CHAIN_D);

        assertTrue(gov.chains(CHAIN_D));
        assertEq(gov.count(), 1);
    }

    function test_FeeGov_RemoveChain() public {
        vm.prank(owner);
        gov.add(CHAIN_D);

        vm.prank(owner);
        gov.remove(CHAIN_D);

        assertFalse(gov.chains(CHAIN_D));
    }

    function test_FeeGov_Broadcast() public {
        vm.startPrank(owner);
        gov.add(CHAIN_D);
        gov.add(CHAIN_P);
        vm.stopPrank();

        uint256 sent = gov.broadcast();
        assertEq(sent, 2);
    }

    function test_FeeGov_Settings() public view {
        (uint16 rate, uint16 floor, uint16 cap, uint32 version) = gov.settings();
        assertEq(rate, 30);
        assertEq(floor, 10);
        assertEq(cap, 500);
        assertEq(version, 1);
    }

    // ============ Vault Tests ============

    function test_Vault_ReceiveFees() public {
        bytes32 warpId = keccak256("warp1");

        vm.startPrank(relayer);
        wlux.approve(address(vault), 10 ether);
        vault.receive_(CHAIN_D, 10 ether, warpId);
        vm.stopPrank();

        assertEq(vault.total(CHAIN_D), 10 ether);
        assertEq(vault.pending(CHAIN_D), 10 ether);
        assertEq(vault.sum(), 10 ether);
        assertEq(vault.balance(), 10 ether);
    }

    function test_Vault_PreventReplay() public {
        bytes32 warpId = keccak256("warp1");

        vm.startPrank(relayer);
        wlux.approve(address(vault), 20 ether);
        vault.receive_(CHAIN_D, 10 ether, warpId);

        vm.expectRevert(Vault.Replay.selector);
        vault.receive_(CHAIN_D, 10 ether, warpId);
        vm.stopPrank();
    }

    function test_Vault_FlushToRouter() public {
        bytes32 warpId = keccak256("warp1");

        vm.startPrank(relayer);
        wlux.approve(address(vault), 10 ether);
        vault.receive_(CHAIN_D, 10 ether, warpId);
        vm.stopPrank();

        // Flush happens via router.distribute()
        bytes32[] memory chains = new bytes32[](1);
        chains[0] = CHAIN_D;

        router.distribute(chains);

        assertEq(vault.pending(CHAIN_D), 0);
        // Router holds tokens until claimed
        assertEq(router.owed(stakers), 7 ether);
        assertEq(router.owed(dao), 2 ether);
        assertEq(router.owed(dev), 1 ether);
    }

    // ============ Router Tests ============

    function test_Router_Weights() public view {
        assertEq(router.weight(stakers), 7000);
        assertEq(router.weight(dao), 2000);
        assertEq(router.weight(dev), 1000);
        assertEq(router.count(), 3);
    }

    function test_Router_Distribute() public {
        // Receive fees into vault
        bytes32 warpId = keccak256("warp1");
        vm.startPrank(relayer);
        wlux.approve(address(vault), 100 ether);
        vault.receive_(CHAIN_D, 100 ether, warpId);
        vm.stopPrank();

        // Distribute
        bytes32[] memory chains = new bytes32[](1);
        chains[0] = CHAIN_D;
        router.distribute(chains);

        // Check owed amounts (70/20/10 split)
        assertEq(router.owed(stakers), 70 ether);
        assertEq(router.owed(dao), 20 ether);
        assertEq(router.owed(dev), 10 ether);
    }

    function test_Router_Claim() public {
        // Setup: receive and distribute
        bytes32 warpId = keccak256("warp1");
        vm.startPrank(relayer);
        wlux.approve(address(vault), 100 ether);
        vault.receive_(CHAIN_D, 100 ether, warpId);
        vm.stopPrank();

        bytes32[] memory chains = new bytes32[](1);
        chains[0] = CHAIN_D;
        router.distribute(chains);

        // Stakers claim
        uint256 before = wlux.balanceOf(stakers);
        vm.prank(stakers);
        uint256 claimed = router.claim();
        uint256 after_ = wlux.balanceOf(stakers);

        assertEq(claimed, 70 ether);
        assertEq(after_ - before, 70 ether);
        assertEq(router.owed(stakers), 0);
        assertEq(router.claimed(stakers), 70 ether);
    }

    function test_Router_ClaimFor() public {
        // Setup: receive and distribute
        bytes32 warpId = keccak256("warp1");
        vm.startPrank(relayer);
        wlux.approve(address(vault), 100 ether);
        vault.receive_(CHAIN_D, 100 ether, warpId);
        vm.stopPrank();

        bytes32[] memory chains = new bytes32[](1);
        chains[0] = CHAIN_D;
        router.distribute(chains);

        // Anyone can claim for dao
        uint256 before = wlux.balanceOf(dao);
        router.claimFor(dao);
        uint256 after_ = wlux.balanceOf(dao);

        assertEq(after_ - before, 20 ether);
    }

    // ============ Collect Tests ============

    function test_Collect_InitialState() public view {
        assertEq(collect.rate(), 30);
        assertEq(collect.version(), 1);
    }

    function test_Collect_FeeCalculation() public view {
        // 0.3% of 1000 = 3
        assertEq(collect.fee(1000 ether), 3 ether);
    }

    function test_Collect_Sync() public {
        // Simulate Warp settings update (H-05 fix: sync is now onlyOwner)
        vm.prank(owner);
        collect.sync(50, 2); // 0.5%, version 2

        assertEq(collect.rate(), 50);
        assertEq(collect.version(), 2);
    }

    function test_Collect_SyncRevertStale() public {
        vm.prank(owner);
        collect.sync(50, 2);

        vm.prank(owner);
        vm.expectRevert(Collect.Stale.selector);
        collect.sync(40, 1); // Older version
    }

    function test_Collect_Push() public {
        wlux.mint(address(this), 10 ether);
        wlux.approve(address(collect), 10 ether);

        collect.push(10 ether);

        assertEq(collect.total(), 10 ether);
        assertEq(collect.pending(), 10 ether);
    }

    function test_Collect_Bridge() public {
        wlux.mint(address(this), 10 ether);
        wlux.approve(address(collect), 10 ether);
        collect.push(10 ether);

        bytes32 warpId = collect.bridge();

        assertTrue(warpId != bytes32(0));
        assertEq(collect.pending(), 0);
        assertEq(collect.bridged(), 10 ether);
    }

    // ============ Integration Tests ============

    function test_FullFlow() public {
        // 1. Gov sets rate and adds chain
        vm.startPrank(owner);
        gov.set(50); // 0.5%
        gov.add(CHAIN_D);
        gov.broadcast();
        vm.stopPrank();

        // 2. Collector syncs settings (simulates Warp receive) - H-05 fix: sync is onlyOwner
        vm.prank(owner);
        collect.sync(50, 2);
        assertEq(collect.rate(), 50);

        // 3. Protocol pushes fees to collector
        wlux.mint(address(this), 100 ether);
        wlux.approve(address(collect), 100 ether);
        collect.push(100 ether);

        // 4. Bridge fees to C-Chain (simulated)
        collect.bridge();

        // 5. Relayer receives Warp and delivers to Vault
        bytes32 warpId = keccak256("warp_bridge_1");
        vm.startPrank(relayer);
        wlux.approve(address(vault), 100 ether);
        vault.receive_(CHAIN_D, 100 ether, warpId);
        vm.stopPrank();

        // 6. Distribute to recipients
        bytes32[] memory chains = new bytes32[](1);
        chains[0] = CHAIN_D;
        router.distribute(chains);

        // 7. Recipients claim
        vm.prank(stakers);
        uint256 stakersClaimed = router.claim();
        assertEq(stakersClaimed, 70 ether);

        vm.prank(dao);
        uint256 daoClaimed = router.claim();
        assertEq(daoClaimed, 20 ether);

        vm.prank(dev);
        uint256 devClaimed = router.claim();
        assertEq(devClaimed, 10 ether);

        // Verify totals
        assertEq(router.total(), 100 ether);
    }

    function test_MultiChainFlow() public {
        // Receive fees from multiple chains
        vm.startPrank(relayer);
        wlux.approve(address(vault), 300 ether);

        vault.receive_(CHAIN_C, 100 ether, keccak256("warp_c"));
        vault.receive_(CHAIN_D, 150 ether, keccak256("warp_d"));
        vault.receive_(CHAIN_P, 50 ether, keccak256("warp_p"));
        vm.stopPrank();

        assertEq(vault.sum(), 300 ether);

        // Distribute all
        bytes32[] memory chains = new bytes32[](3);
        chains[0] = CHAIN_C;
        chains[1] = CHAIN_D;
        chains[2] = CHAIN_P;
        router.distribute(chains);

        assertEq(router.owed(stakers), 210 ether); // 70% of 300
        assertEq(router.owed(dao), 60 ether);      // 20% of 300
        assertEq(router.owed(dev), 30 ether);      // 10% of 300
    }
}
