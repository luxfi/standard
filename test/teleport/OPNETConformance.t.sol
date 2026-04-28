// SPDX-License-Identifier: BSD-3-Clause
// Copyright (c) 2025 Lux Industries Inc.
pragma solidity ^0.8.31;

import "./TeleportConformance.t.sol";

/**
 * @title OPNETConformance
 * @author Lux Industries
 * @notice OP_NET-specific conformance tests for Bitcoin L1 Teleport integration.
 *
 * OP_NET chain manifest:
 *   chain_id:        4294967299 (0x100000003)
 *   class:           bitcoin_script
 *   tier:            yield_enabled
 *   signer:          cggmp21 (secp256k1) + frost native (Taproot Schnorr)
 *   finality:        6 Bitcoin confirmations
 *   asset:           BTC (8 decimals) -> LBTC (18 decimals on Lux C-Chain)
 *   strategy:        BabylonBTCStrategy
 *
 * This test extends TeleportConformance with OP_NET-specific parameters and
 * validates decimal scaling, chain ID binding, and BTC-specific edge cases.
 */
contract OPNETConformance is TeleportConformance {
    // ═══════════════════════════════════════════════════════════════════════
    // OP_NET CONSTANTS
    // ═══════════════════════════════════════════════════════════════════════

    uint256 internal constant OPNET_CHAIN_ID = 4294967299;
    uint8 internal constant BTC_DECIMALS = 8;
    uint8 internal constant LBTC_DECIMALS = 18;
    uint256 internal constant DECIMAL_SCALE = 10 ** (LBTC_DECIMALS - BTC_DECIMALS); // 1e10

    // BTC amounts in 8-decimal native precision
    uint256 internal constant ONE_BTC = 1e8; // 1.00000000 BTC
    uint256 internal constant ONE_SAT = 1; // 0.00000001 BTC
    uint256 internal constant DUST_THRESHOLD = 546; // 546 sats — Bitcoin dust limit

    // ═══════════════════════════════════════════════════════════════════════
    // SETUP — override parent with OP_NET parameters
    // ═══════════════════════════════════════════════════════════════════════

    function setUp() public override {
        mpcOracle = vm.addr(mpcPrivateKey);

        vm.startPrank(admin);

        // LBTC is 18 decimals on Lux C-Chain (scaled from BTC's 8)
        token = new MockBridgedToken("Liquid BTC", "LBTC", LBTC_DECIMALS);
        teleporter = new Teleporter(address(token), mpcOracle);

        // Override source chain config
        srcChainId = OPNET_CHAIN_ID;
        depositAmount = ONE_BTC * DECIMAL_SCALE; // 1 BTC in 18-decimal LBTC terms

        // Backing: 21 BTC worth (in 18-decimal terms)
        _updateBacking(srcChainId, 21 * ONE_BTC * DECIMAL_SCALE);

        vm.stopPrank();
    }

    // ═══════════════════════════════════════════════════════════════════════
    // OP_NET CHAIN ID BINDING
    // ═══════════════════════════════════════════════════════════════════════

    function testOPNET_ChainId() public pure {
        // Verify the chain ID matches manifest (0x100000003)
        assertEq(OPNET_CHAIN_ID, 4294967299, "OP_NET chain ID mismatch");
    }

    function testOPNET_DepositUsesCorrectChainId() public {
        bytes memory sig = _signDeposit(OPNET_CHAIN_ID, 1, recipient, depositAmount);
        teleporter.mintDeposit(OPNET_CHAIN_ID, 1, recipient, depositAmount, sig);

        assertTrue(
            teleporter.isDepositProcessed(OPNET_CHAIN_ID, 1), "deposit should be processed under OP_NET chain ID"
        );

        // Not processed under a different chain ID
        assertFalse(teleporter.isDepositProcessed(1, 1), "should not be processed under Ethereum chain ID");
    }

    // ═══════════════════════════════════════════════════════════════════════
    // BTC DECIMAL SCALING — 8 (source) -> 18 (LBTC on Lux)
    // ═══════════════════════════════════════════════════════════════════════

    function testOPNET_OneBTCMint() public {
        // 1 BTC = 1e8 sats on Bitcoin, minted as 1e18 LBTC on Lux
        uint256 lbtcAmount = ONE_BTC * DECIMAL_SCALE;
        assertEq(lbtcAmount, 1e18, "1 BTC should scale to 1e18 LBTC");

        bytes memory sig = _signDeposit(OPNET_CHAIN_ID, 1, recipient, lbtcAmount);
        teleporter.mintDeposit(OPNET_CHAIN_ID, 1, recipient, lbtcAmount, sig);

        assertEq(token.balanceOf(recipient), 1e18, "recipient should have 1 LBTC");
    }

    function testOPNET_FractionalBTCMint() public {
        // 0.001 BTC = 100,000 sats -> 0.001e18 = 1e15 LBTC
        uint256 fractionalBTC = 100_000; // sats
        uint256 lbtcAmount = fractionalBTC * DECIMAL_SCALE;
        assertEq(lbtcAmount, 1e15, "0.001 BTC should scale to 1e15 LBTC");

        bytes memory sig = _signDeposit(OPNET_CHAIN_ID, 1, recipient, lbtcAmount);
        teleporter.mintDeposit(OPNET_CHAIN_ID, 1, recipient, lbtcAmount, sig);

        assertEq(token.balanceOf(recipient), 1e15, "should mint 0.001 LBTC");
    }

    function testOPNET_SingleSatMint() public {
        // 1 sat = 1e10 LBTC (smallest meaningful unit)
        uint256 lbtcAmount = ONE_SAT * DECIMAL_SCALE;
        assertEq(lbtcAmount, 1e10, "1 sat should scale to 1e10 LBTC");

        bytes memory sig = _signDeposit(OPNET_CHAIN_ID, 1, recipient, lbtcAmount);
        teleporter.mintDeposit(OPNET_CHAIN_ID, 1, recipient, lbtcAmount, sig);

        assertEq(token.balanceOf(recipient), 1e10, "should mint 1 sat worth of LBTC");
    }

    function testOPNET_DustThresholdMint() public {
        // 546 sats = Bitcoin dust threshold. Valid but minimal.
        uint256 lbtcAmount = DUST_THRESHOLD * DECIMAL_SCALE;

        bytes memory sig = _signDeposit(OPNET_CHAIN_ID, 1, recipient, lbtcAmount);
        teleporter.mintDeposit(OPNET_CHAIN_ID, 1, recipient, lbtcAmount, sig);

        assertEq(token.balanceOf(recipient), lbtcAmount, "dust-threshold mint should succeed");
    }

    // ═══════════════════════════════════════════════════════════════════════
    // LBTC MINTING — full deposit-mint-burn cycle
    // ═══════════════════════════════════════════════════════════════════════

    function testOPNET_LBTCMintBurnCycle() public {
        uint256 amount = 5 * ONE_BTC * DECIMAL_SCALE; // 5 BTC

        // Mint
        bytes memory sig = _signDeposit(OPNET_CHAIN_ID, 1, user, amount);
        teleporter.mintDeposit(OPNET_CHAIN_ID, 1, user, amount, sig);
        assertEq(token.balanceOf(user), amount, "should hold 5 LBTC");

        // Approve and burn for withdraw
        vm.startPrank(user);
        token.approve(address(teleporter), amount);
        uint256 withdrawNonce = teleporter.burnForWithdraw(amount, OPNET_CHAIN_ID, user);
        vm.stopPrank();

        assertEq(token.balanceOf(user), 0, "should have 0 LBTC after burn");
        assertTrue(teleporter.pendingWithdraws(withdrawNonce), "withdraw should be pending");
        assertEq(teleporter.totalBurned(), amount, "totalBurned should match");
    }

    function testOPNET_LBTCMultipleDeposits() public {
        // Simulate 3 separate Bitcoin deposits from OP_NET
        uint256 deposit1 = 2 * ONE_BTC * DECIMAL_SCALE;
        uint256 deposit2 = 3 * ONE_BTC * DECIMAL_SCALE;
        uint256 deposit3 = 1 * ONE_BTC * DECIMAL_SCALE;

        bytes memory sig1 = _signDeposit(OPNET_CHAIN_ID, 1, user, deposit1);
        bytes memory sig2 = _signDeposit(OPNET_CHAIN_ID, 2, user, deposit2);
        bytes memory sig3 = _signDeposit(OPNET_CHAIN_ID, 3, user, deposit3);

        teleporter.mintDeposit(OPNET_CHAIN_ID, 1, user, deposit1, sig1);
        teleporter.mintDeposit(OPNET_CHAIN_ID, 2, user, deposit2, sig2);
        teleporter.mintDeposit(OPNET_CHAIN_ID, 3, user, deposit3, sig3);

        assertEq(token.balanceOf(user), deposit1 + deposit2 + deposit3, "total LBTC mismatch");
        assertEq(token.balanceOf(user), 6 * ONE_BTC * DECIMAL_SCALE, "should hold 6 LBTC");
    }

    // ═══════════════════════════════════════════════════════════════════════
    // BACKING — BTC-specific backing scenarios
    // ═══════════════════════════════════════════════════════════════════════

    function testOPNET_BackingEnforcesLimit() public {
        // Set backing to exactly 1 BTC
        vm.prank(admin);
        _updateBacking(OPNET_CHAIN_ID, ONE_BTC * DECIMAL_SCALE);

        // Mint 1 BTC should succeed
        bytes memory sig1 = _signDeposit(OPNET_CHAIN_ID, 1, recipient, ONE_BTC * DECIMAL_SCALE);
        teleporter.mintDeposit(OPNET_CHAIN_ID, 1, recipient, ONE_BTC * DECIMAL_SCALE, sig1);

        // Mint 1 more sat should fail — exceeds backing
        uint256 oneSatLBTC = ONE_SAT * DECIMAL_SCALE;
        bytes memory sig2 = _signDeposit(OPNET_CHAIN_ID, 2, recipient, oneSatLBTC);

        vm.expectRevert(Teleporter.BackingInsufficient.selector);
        teleporter.mintDeposit(OPNET_CHAIN_ID, 2, recipient, oneSatLBTC, sig2);
    }

    function testOPNET_6ConfirmationFinality() public {
        // This is a documentation/assertion test. The watcher enforces 6-block
        // finality off-chain. On-chain, we verify that the contract processes
        // deposits regardless of confirmation count (the watcher gates this).
        // The stale attestation mechanism is the on-chain safety net.

        // 6 confirmations at ~10 min/block = ~60 min max latency
        // Stale attestation threshold = 24h >> 60 min, so normal flow works
        uint256 sixBlocksLatency = 60 minutes;
        vm.warp(block.timestamp + sixBlocksLatency);

        // Should still be within attestation window
        bytes memory sig = _signDeposit(OPNET_CHAIN_ID, 1, recipient, depositAmount);
        teleporter.mintDeposit(OPNET_CHAIN_ID, 1, recipient, depositAmount, sig);

        assertTrue(teleporter.isDepositProcessed(OPNET_CHAIN_ID, 1), "should process after 6-block latency");
    }

    // ═══════════════════════════════════════════════════════════════════════
    // OVERRIDES — parent tests that need different amounts for BTC backing
    // ═══════════════════════════════════════════════════════════════════════

    /// @dev Override: parent mints 100 ether which exceeds 21 BTC backing.
    ///      Use BTC-appropriate amounts instead.
    function testBackingUpdate_InsufficientBackingPauses() public override {
        // Mint 10 BTC first
        uint256 mintAmount = 10 * ONE_BTC * DECIMAL_SCALE;
        bytes memory sig = _signDeposit(OPNET_CHAIN_ID, 1, recipient, mintAmount);
        teleporter.mintDeposit(OPNET_CHAIN_ID, 1, recipient, mintAmount, sig);

        // Update backing to 5 BTC — less than totalMinted (10 BTC)
        vm.prank(admin);
        _updateBacking(OPNET_CHAIN_ID, 5 * ONE_BTC * DECIMAL_SCALE);

        assertTrue(teleporter.paused(), "bridge should be paused when backing < totalMinted");
    }

    /// @dev Override: parent bounds to 999 ether, exceeds 21 BTC backing.
    function testFuzz_DepositMint(uint256 amount) public override {
        amount = bound(amount, 1, 20 * ONE_BTC * DECIMAL_SCALE); // Under 21 BTC backing

        bytes memory sig = _signDeposit(OPNET_CHAIN_ID, 1, recipient, amount);
        teleporter.mintDeposit(OPNET_CHAIN_ID, 1, recipient, amount, sig);

        assertEq(token.balanceOf(recipient), amount, "fuzz: balance mismatch");
        assertEq(teleporter.totalDepositMinted(), amount, "fuzz: totalDepositMinted mismatch");
    }

    // ═══════════════════════════════════════════════════════════════════════
    // FUZZ — BTC-specific amount ranges
    // ═══════════════════════════════════════════════════════════════════════

    function testFuzz_OPNETDeposit(uint256 sats) public {
        // Fuzz between 1 sat and 20 BTC (under the 21 BTC backing)
        sats = bound(sats, 1, 20 * ONE_BTC);
        uint256 lbtcAmount = sats * DECIMAL_SCALE;

        bytes memory sig = _signDeposit(OPNET_CHAIN_ID, 1, recipient, lbtcAmount);
        teleporter.mintDeposit(OPNET_CHAIN_ID, 1, recipient, lbtcAmount, sig);

        assertEq(token.balanceOf(recipient), lbtcAmount, "fuzz: LBTC balance mismatch");
    }
}
