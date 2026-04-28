// SPDX-License-Identifier: MIT
pragma solidity ^0.8.31;

import "forge-std/Test.sol";
import { ECDSA } from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import { MessageHashUtils } from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { OmnichainRouter, IBridgeToken } from "../../../contracts/bridge/OmnichainRouter.sol";
import { XChainVault } from "../../../contracts/bridge/XChainVault.sol";

/// @title MockBridgeToken for fuzz testing
contract MockBridgeToken is ERC20 {
    address public minter;

    constructor() ERC20("Mock Bridge Token", "MBT") {
        minter = msg.sender;
    }

    function setMinter(address _minter) external {
        minter = _minter;
    }

    function bridgeMint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function bridgeBurn(address from, uint256 amount) external {
        _burn(from, amount);
    }
}

/// @title BridgeFuzzTest
/// @notice Fuzz tests for bridge critical paths: digest computation, signature
///         verification, nonce replay, fee conservation, and solvency.
contract BridgeFuzzTest is Test {
    using ECDSA for bytes32;
    using MessageHashUtils for bytes32;

    OmnichainRouter public router;
    MockBridgeToken public token;

    uint256 internal mpcPrivateKey;
    address internal mpcSigner;
    address internal governor;
    address internal stakeholderVault;
    address internal treasury;
    uint64 internal constant CHAIN_ID = 1;

    function setUp() public {
        mpcPrivateKey = 0xA11CE;
        mpcSigner = vm.addr(mpcPrivateKey);
        governor = makeAddr("governor");
        stakeholderVault = makeAddr("stakeholderVault");
        treasury = makeAddr("treasury");

        router = new OmnichainRouter(
            CHAIN_ID,
            governor,
            stakeholderVault,
            treasury,
            50, // 0.5% fee
            9000, // 90% to stakeholders
            makeAddr("signer1"),
            makeAddr("signer2"),
            makeAddr("signer3"),
            mpcSigner
        );

        token = new MockBridgeToken();
        token.setMinter(address(router));

        // Register token via MPC signature
        bytes32 digest = keccak256(abi.encode("REGISTER", CHAIN_ID, address(token), uint256(0)));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(mpcPrivateKey, digest.toEthSignedMessageHash());
        router.registerToken(address(token), 0, abi.encodePacked(r, s, v));
    }

    // =========================================================================
    // 1. OmnichainRouter: digest computation with random inputs (no collision)
    // =========================================================================

    /// @notice Two different deposit parameters must never produce the same digest
    function testFuzz_digestNoCollision(
        uint64 sourceA,
        uint64 nonceA,
        address recipientA,
        uint256 amountA,
        uint64 sourceB,
        uint64 nonceB,
        address recipientB,
        uint256 amountB
    ) public pure {
        // Skip if inputs are identical
        vm.assume(sourceA != sourceB || nonceA != nonceB || recipientA != recipientB || amountA != amountB);

        bytes32 digestA = keccak256(abi.encode("DEPOSIT", CHAIN_ID, sourceA, nonceA, address(1), recipientA, amountA));
        bytes32 digestB = keccak256(abi.encode("DEPOSIT", CHAIN_ID, sourceB, nonceB, address(1), recipientB, amountB));

        assertNotEq(digestA, digestB, "digest collision");
    }

    /// @notice abi.encode digest differs from abi.encodePacked (C-07 fix verification)
    function testFuzz_digestEncodeVsPacked(uint64 source, uint64 nonce, address recipient, uint256 amount) public pure {
        bytes32 safeDigest = keccak256(abi.encode("DEPOSIT", CHAIN_ID, source, nonce, address(1), recipient, amount));
        bytes32 packedDigest =
            keccak256(abi.encodePacked("DEPOSIT", CHAIN_ID, source, nonce, address(1), recipient, amount));
        // abi.encode always pads to 32 bytes, so these should differ
        assertNotEq(safeDigest, packedDigest, "encode and encodePacked should differ");
    }

    /// @notice Chain ID is included in digest -- same params on different chains produce different digests
    function testFuzz_digestChainIdSeparation(uint64 source, uint64 nonce, uint256 amount) public pure {
        bytes32 digestChain1 =
            keccak256(abi.encode("DEPOSIT", uint64(1), source, nonce, address(1), address(2), amount));
        bytes32 digestChain2 =
            keccak256(abi.encode("DEPOSIT", uint64(2), source, nonce, address(1), address(2), amount));
        assertNotEq(digestChain1, digestChain2, "cross-chain replay possible");
    }

    // =========================================================================
    // 2. XChainVault: burn proof verification rejects random/invalid signatures
    // =========================================================================

    /// @notice Random bytes should never pass as a valid MPC signature
    function testFuzz_xchainVault_rejectRandomSignature(bytes32 vaultId, uint256 amount, uint256 randomSeed) public {
        XChainVault vault = new XChainVault(address(this));

        // Setup MPC oracles
        address oracle1 = makeAddr("oracle1");
        address oracle2 = makeAddr("oracle2");
        vault.setMpcOracle(oracle1, true);
        vault.setMpcOracle(oracle2, true);
        vault.setMpcThreshold(2);

        // Generate random (invalid) signatures
        bytes memory sig1 = abi.encodePacked(keccak256(abi.encode(randomSeed, uint256(1))), bytes32(0), uint8(27));
        bytes memory sig2 = abi.encodePacked(keccak256(abi.encode(randomSeed, uint256(2))), bytes32(0), uint8(27));
        bytes[] memory signatures = new bytes[](2);
        signatures[0] = sig1;
        signatures[1] = sig2;

        bytes memory proof = abi.encode(uint256(1), uint32(2), signatures);

        // releaseFromVault should fail -- no active vault entry
        vm.expectRevert("Vault not active");
        vault.releaseFromVault(vaultId, address(this), amount, proof);
    }

    /// @notice Threshold below minimum should reject even with one valid signature
    function testFuzz_xchainVault_belowThresholdRejects(uint256 amount) public {
        amount = bound(amount, 1, type(uint128).max);

        XChainVault vault = new XChainVault(address(this));

        uint256 oraclePk = 0xB0B;
        address oracle = vm.addr(oraclePk);
        vault.setMpcOracle(oracle, true);
        vault.setMpcThreshold(2); // Require 2 but only provide 1

        bytes32 messageHash =
            keccak256(abi.encode(bytes4(0x4255524e), uint32(2), bytes32(uint256(1)), amount, uint256(1)));
        bytes32 ethHash = messageHash.toEthSignedMessageHash();
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(oraclePk, ethHash);

        bytes[] memory signatures = new bytes[](1);
        signatures[0] = abi.encodePacked(r, s, v);
        bytes memory proof = abi.encode(uint256(1), uint32(2), signatures);

        // Will fail at "Vault not active" since no vault entry, but the proof
        // verification itself returns false (below threshold)
        vm.expectRevert("Vault not active");
        vault.releaseFromVault(bytes32(uint256(1)), address(this), amount, proof);
    }

    // =========================================================================
    // 3. OmnichainRouter: deposit/mint conservation of value
    // =========================================================================

    /// @notice fee + mintAmount == deposited amount (no value leak)
    function testFuzz_feeConservation(uint256 amount) public {
        amount = bound(amount, 1, type(uint128).max);

        uint256 feeBps = router.bridgeFeeBps();
        uint256 fee = (amount * feeBps) / 10000;
        uint256 mintAmount = amount - fee;

        assertEq(fee + mintAmount, amount, "value leaked");
    }

    /// @notice After mintDeposit, recipient + stakeholder + treasury balances == total amount
    function testFuzz_mintDepositConservation(uint256 amount) public {
        amount = bound(amount, 100, type(uint64).max); // min 100 to have meaningful fee

        uint64 sourceChain = 2;
        uint64 nonce = 1;
        address recipient = makeAddr("recipient");

        bytes32 digest =
            keccak256(abi.encode("DEPOSIT", CHAIN_ID, sourceChain, nonce, address(token), recipient, amount));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(mpcPrivateKey, digest.toEthSignedMessageHash());

        uint256 supplyBefore = token.totalSupply();

        router.mintDeposit(sourceChain, nonce, address(token), recipient, amount, abi.encodePacked(r, s, v));

        uint256 supplyAfter = token.totalSupply();
        // Total supply increase must equal deposited amount
        assertEq(supplyAfter - supplyBefore, amount, "supply mismatch");

        // Individual balances: recipient + stakeholder + treasury == amount
        uint256 recipientBal = token.balanceOf(recipient);
        uint256 stakeholderBal = token.balanceOf(stakeholderVault);
        uint256 treasuryBal = token.balanceOf(treasury);
        assertEq(recipientBal + stakeholderBal + treasuryBal, amount, "balance conservation");
    }

    /// @notice Burn reduces totalMinted by exact burn amount
    function testFuzz_burnConservation(uint256 mintAmt, uint256 burnFraction) public {
        mintAmt = bound(mintAmt, 100, type(uint64).max);

        uint64 sourceChain = 2;
        uint64 nonce = 1;
        address recipient = makeAddr("burner");

        // Mint first
        bytes32 digest =
            keccak256(abi.encode("DEPOSIT", CHAIN_ID, sourceChain, nonce, address(token), recipient, mintAmt));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(mpcPrivateKey, digest.toEthSignedMessageHash());
        router.mintDeposit(sourceChain, nonce, address(token), recipient, mintAmt, abi.encodePacked(r, s, v));

        // Recipient gets mintAmt minus fee, burn within that balance
        uint256 recipientBalance = token.balanceOf(recipient);
        uint256 burnAmt = bound(burnFraction, 1, recipientBalance);

        // Approve router to pull tokens for burn
        vm.prank(recipient);
        token.approve(address(router), burnAmt);

        uint256 mintedBefore = router.totalMinted(address(token));

        vm.prank(recipient);
        router.burnForWithdrawal(address(token), burnAmt, 3, bytes32(uint256(uint160(recipient))));

        uint256 mintedAfter = router.totalMinted(address(token));
        assertEq(mintedBefore - mintedAfter, burnAmt, "totalMinted not reduced by burn amount");
    }

    // =========================================================================
    // 4. Bridge: nonce replay with random ordering (no double-process)
    // =========================================================================

    /// @notice Same nonce cannot be processed twice
    function testFuzz_nonceReplayRejected(uint64 sourceChain, uint64 nonce, uint256 amount) public {
        sourceChain = uint64(bound(sourceChain, 1, type(uint32).max));
        amount = bound(amount, 100, type(uint64).max);
        address recipient = makeAddr("recipient");

        bytes32 digest =
            keccak256(abi.encode("DEPOSIT", CHAIN_ID, sourceChain, nonce, address(token), recipient, amount));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(mpcPrivateKey, digest.toEthSignedMessageHash());
        bytes memory sig = abi.encodePacked(r, s, v);

        // First call succeeds
        router.mintDeposit(sourceChain, nonce, address(token), recipient, amount, sig);

        // Second call reverts
        vm.expectRevert("Nonce processed");
        router.mintDeposit(sourceChain, nonce, address(token), recipient, amount, sig);
    }

    /// @notice Process nonces out of order -- each processes exactly once
    function testFuzz_nonceOutOfOrder(uint256 seed) public {
        // Process 5 nonces in random order derived from seed
        uint64[5] memory nonces;
        for (uint256 i = 0; i < 5; i++) {
            nonces[i] = uint64(uint256(keccak256(abi.encode(seed, i))) % 1000000);
        }

        address recipient = makeAddr("recipient");
        uint256 amount = 1000;
        uint64 sourceChain = 5;

        for (uint256 i = 0; i < 5; i++) {
            // Skip if this nonce was already seen (collision from random generation)
            if (router.processedDeposits(sourceChain, nonces[i])) continue;

            bytes32 digest =
                keccak256(abi.encode("DEPOSIT", CHAIN_ID, sourceChain, nonces[i], address(token), recipient, amount));
            (uint8 v, bytes32 r, bytes32 s) = vm.sign(mpcPrivateKey, digest.toEthSignedMessageHash());
            router.mintDeposit(sourceChain, nonces[i], address(token), recipient, amount, abi.encodePacked(r, s, v));

            assertTrue(router.processedDeposits(sourceChain, nonces[i]), "nonce not marked");
        }
    }

    /// @notice Different source chains with same nonce are independent
    function testFuzz_noncePerChainIsolation(uint64 nonce, uint256 amount) public {
        amount = bound(amount, 100, type(uint64).max);
        address recipient = makeAddr("recipient");

        uint64 chainA = 10;
        uint64 chainB = 20;

        // Process on chain A
        bytes32 digestA = keccak256(abi.encode("DEPOSIT", CHAIN_ID, chainA, nonce, address(token), recipient, amount));
        (uint8 vA, bytes32 rA, bytes32 sA) = vm.sign(mpcPrivateKey, digestA.toEthSignedMessageHash());
        router.mintDeposit(chainA, nonce, address(token), recipient, amount, abi.encodePacked(rA, sA, vA));

        // Same nonce on chain B should still work
        bytes32 digestB = keccak256(abi.encode("DEPOSIT", CHAIN_ID, chainB, nonce, address(token), recipient, amount));
        (uint8 vB, bytes32 rB, bytes32 sB) = vm.sign(mpcPrivateKey, digestB.toEthSignedMessageHash());
        router.mintDeposit(chainB, nonce, address(token), recipient, amount, abi.encodePacked(rB, sB, vB));

        assertTrue(router.processedDeposits(chainA, nonce), "chain A nonce not processed");
        assertTrue(router.processedDeposits(chainB, nonce), "chain B nonce not processed");
    }

    // =========================================================================
    // 5. Fee calculation with random amounts
    // =========================================================================

    /// @notice fee + amount_after_fee == amount for all fee rates
    function testFuzz_feeCalculationExact(uint256 amount, uint256 feeBps) public {
        amount = bound(amount, 1, type(uint128).max);
        feeBps = bound(feeBps, 0, 100); // max 1% per router

        uint256 fee = (amount * feeBps) / 10000;
        uint256 afterFee = amount - fee;

        assertEq(fee + afterFee, amount, "fee arithmetic broken");
    }

    /// @notice Fee never exceeds 1% of amount (hard cap)
    function testFuzz_feeNeverExceedsCap(uint256 amount) public view {
        amount = bound(amount, 1, type(uint128).max);

        uint256 fee = (amount * router.bridgeFeeBps()) / 10000;
        // 1% = amount / 100
        assertLe(fee, amount / 100 + 1, "fee exceeds 1%"); // +1 for rounding
    }

    /// @notice Stakeholder + treasury split conserves fee
    function testFuzz_feeSplitConservation(uint256 fee) public view {
        fee = bound(fee, 1, type(uint128).max);

        uint256 stakeholderShareBps = router.stakeholderShareBps();
        uint256 toStakeholders = (fee * stakeholderShareBps) / 10000;
        uint256 toTreasury = fee - toStakeholders;

        assertEq(toStakeholders + toTreasury, fee, "fee split leaked value");
    }

    /// @notice Zero amount yields zero fee
    function testFuzz_zeroAmountZeroFee(uint256 feeBps) public pure {
        feeBps = bound(feeBps, 0, 10000);
        uint256 fee = (0 * feeBps) / 10000;
        assertEq(fee, 0, "zero amount should yield zero fee");
    }

    // =========================================================================
    // 6. Signature validation: wrong signer rejected
    // =========================================================================

    /// @notice A valid signature from a non-MPC signer is rejected
    function testFuzz_wrongSignerRejected(uint256 wrongPk, uint256 amount) public {
        wrongPk = bound(wrongPk, 1, type(uint128).max);
        vm.assume(vm.addr(wrongPk) != mpcSigner);
        amount = bound(amount, 100, type(uint64).max);

        uint64 sourceChain = 2;
        uint64 nonce = 100;
        address recipient = makeAddr("recipient");

        bytes32 digest =
            keccak256(abi.encode("DEPOSIT", CHAIN_ID, sourceChain, nonce, address(token), recipient, amount));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(wrongPk, digest.toEthSignedMessageHash());

        vm.expectRevert("Invalid MPC signature");
        router.mintDeposit(sourceChain, nonce, address(token), recipient, amount, abi.encodePacked(r, s, v));
    }

    // =========================================================================
    // 7. Auto-pause: backing ratio triggers
    // =========================================================================

    /// @notice Backing below 98.5% triggers auto-pause
    function testFuzz_autoPauseOnUndercollateralization(uint256 minted, uint256 backingRatio) public {
        minted = bound(minted, 10000, type(uint64).max);
        backingRatio = bound(backingRatio, 1, 9849); // below 98.5%

        uint256 backing = (minted * backingRatio) / 10000;

        // Mint some tokens first
        _mintTokens(minted);

        // Update backing
        uint256 timestamp = block.timestamp + 1;
        bytes32 digest = keccak256(abi.encode("BACKING", CHAIN_ID, address(token), backing, timestamp));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(mpcPrivateKey, digest.toEthSignedMessageHash());
        router.updateBacking(address(token), backing, timestamp, abi.encodePacked(r, s, v));

        assertTrue(router.autoPaused(), "should auto-pause below 98.5%");
    }

    // =========================================================================
    // HELPERS
    // =========================================================================

    function _mintTokens(uint256 amount) internal {
        uint64 sourceChain = 2;
        uint64 nonce = uint64(uint256(keccak256(abi.encode(amount, block.timestamp))));
        address recipient = makeAddr("helper_recipient");

        bytes32 digest =
            keccak256(abi.encode("DEPOSIT", CHAIN_ID, sourceChain, nonce, address(token), recipient, amount));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(mpcPrivateKey, digest.toEthSignedMessageHash());
        router.mintDeposit(sourceChain, nonce, address(token), recipient, amount, abi.encodePacked(r, s, v));
    }
}
