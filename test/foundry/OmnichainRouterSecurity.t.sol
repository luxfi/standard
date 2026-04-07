// SPDX-License-Identifier: MIT
pragma solidity ^0.8.31;

import "forge-std/Test.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { OmnichainRouter } from "../../contracts/bridge/OmnichainRouter.sol";
import { ECDSA } from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import { MessageHashUtils } from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";

// ================================================================
//  MOCK BRIDGE TOKEN
// ================================================================

contract MockBridgeToken is ERC20 {
    address public router;

    constructor(string memory name, string memory symbol, address _router) ERC20(name, symbol) {
        router = _router;
    }

    function setRouter(address _router) external {
        router = _router;
    }

    function bridgeMint(address to, uint256 amount) external {
        require(msg.sender == router, "Only router");
        _mint(to, amount);
    }

    function bridgeBurn(address from, uint256 amount) external {
        require(msg.sender == router, "Only router");
        _burn(from, amount);
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

// ================================================================
//  SECURITY TEST SUITE
// ================================================================

contract OmnichainRouterSecurity is Test {
    using ECDSA for bytes32;
    using MessageHashUtils for bytes32;

    OmnichainRouter public router;
    MockBridgeToken public token;

    // Keys: 3 individual signers + 1 MPC group key
    uint256 internal signerKey1;
    uint256 internal signerKey2;
    uint256 internal signerKey3;
    uint256 internal mpcGroupKey;

    address internal signer1;
    address internal signer2;
    address internal signer3;
    address internal mpcGroupAddress;

    address internal governor = address(0xAAAA);
    address internal vault = address(0xBBBB);
    address internal treasury = address(0xCCCC);
    address internal recipient = address(0xDDDD);

    uint64 internal constant CHAIN_ID = 96369;
    uint256 internal constant FEE_BPS = 50; // 0.5%
    uint256 internal constant STAKEHOLDER_SHARE = 9000; // 90%

    function setUp() public {
        // Derive keys
        signerKey1 = 0xA1;
        signerKey2 = 0xA2;
        signerKey3 = 0xA3;
        mpcGroupKey = 0xBEEF;

        signer1 = vm.addr(signerKey1);
        signer2 = vm.addr(signerKey2);
        signer3 = vm.addr(signerKey3);
        mpcGroupAddress = vm.addr(mpcGroupKey);

        router = new OmnichainRouter(
            CHAIN_ID,
            governor,
            vault,
            treasury,
            FEE_BPS,
            STAKEHOLDER_SHARE,
            signer1,
            signer2,
            signer3,
            mpcGroupAddress
        );

        token = new MockBridgeToken("Lux ETH", "LETH", address(router));

        // Register token via MPC signature
        _registerToken(address(token), 1_000_000 ether);
    }

    // ================================================================
    //  HELPERS
    // ================================================================

    function _signWithMpc(bytes32 digest) internal view returns (bytes memory) {
        bytes32 ethHash = digest.toEthSignedMessageHash();
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(mpcGroupKey, ethHash);
        return abi.encodePacked(r, s, v);
    }

    function _signWithKey(uint256 key, bytes32 digest) internal pure returns (bytes memory) {
        bytes32 ethHash = MessageHashUtils.toEthSignedMessageHash(digest);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(key, ethHash);
        return abi.encodePacked(r, s, v);
    }

    function _registerToken(address tkn, uint256 dailyLimit) internal {
        bytes32 digest = keccak256(abi.encodePacked("REGISTER", CHAIN_ID, tkn, dailyLimit));
        bytes memory sig = _signWithMpc(digest);
        router.registerToken(tkn, dailyLimit, sig);
    }

    function _mintDeposit(uint64 sourceChain, uint64 nonce, uint256 amount) internal {
        bytes32 digest = keccak256(
            abi.encodePacked("DEPOSIT", CHAIN_ID, sourceChain, nonce, address(token), recipient, amount)
        );
        bytes memory sig = _signWithMpc(digest);
        router.mintDeposit(sourceChain, nonce, address(token), recipient, amount, sig);
    }

    function _updateBacking(uint256 backing, uint256 ts) internal {
        bytes32 digest = keccak256(abi.encodePacked("BACKING", CHAIN_ID, address(token), backing, ts));
        bytes memory sig = _signWithMpc(digest);
        router.updateBacking(address(token), backing, ts, sig);
    }

    // ================================================================
    //  1. FUZZ mintDeposit: only mpcGroupAddress accepted
    // ================================================================

    function testFuzz_mintDeposit_onlyMpcGroup(uint256 amount, uint64 nonce) public {
        amount = bound(amount, 1, 1_000_000 ether);
        nonce = uint64(bound(nonce, 1, type(uint64).max));

        bytes32 digest = keccak256(
            abi.encodePacked("DEPOSIT", CHAIN_ID, uint64(1), nonce, address(token), recipient, amount)
        );
        bytes memory sig = _signWithMpc(digest);

        router.mintDeposit(uint64(1), nonce, address(token), recipient, amount, sig);

        uint256 fee = (amount * FEE_BPS) / 10000;
        uint256 mintAmount = amount - fee;
        assertEq(token.balanceOf(recipient), mintAmount, "Recipient balance wrong");
        assertEq(router.totalMinted(address(token)), amount, "totalMinted wrong");
    }

    function testFuzz_mintDeposit_individualSignerRejected(uint8 signerIdx) public {
        signerIdx = uint8(bound(signerIdx, 0, 2));
        uint256 key;
        if (signerIdx == 0) key = signerKey1;
        else if (signerIdx == 1) key = signerKey2;
        else key = signerKey3;

        uint256 amount = 100 ether;
        bytes32 digest = keccak256(
            abi.encodePacked("DEPOSIT", CHAIN_ID, uint64(1), uint64(999), address(token), recipient, amount)
        );
        bytes memory sig = _signWithKey(key, digest);

        vm.expectRevert("Invalid MPC signature");
        router.mintDeposit(uint64(1), uint64(999), address(token), recipient, amount, sig);
    }

    // ================================================================
    //  2. FUZZ cross-chain replay: same sig, different chainId fails
    // ================================================================

    function testFuzz_crossChainReplay(uint64 otherChainId) public {
        otherChainId = uint64(bound(otherChainId, 1, type(uint64).max));
        vm.assume(otherChainId != CHAIN_ID);

        uint256 amount = 100 ether;
        uint64 nonce = 1;

        // Sign for a DIFFERENT chain
        bytes32 digest = keccak256(
            abi.encodePacked("DEPOSIT", otherChainId, uint64(1), nonce, address(token), recipient, amount)
        );
        bytes memory sig = _signWithMpc(digest);

        // Submit to our router (CHAIN_ID) -- signature won't match because digest has wrong chainId
        vm.expectRevert("Invalid MPC signature");
        router.mintDeposit(uint64(1), nonce, address(token), recipient, amount, sig);
    }

    // ================================================================
    //  3. FUZZ signer rotation: chainId + rotationNonce in digest
    // ================================================================

    function testFuzz_signerRotation_digestBindsChainAndNonce(uint256 newKey) public {
        newKey = bound(newKey, 1, type(uint128).max);
        vm.assume(newKey != mpcGroupKey);

        address newMpc = vm.addr(newKey);
        uint256 currentNonce = router.rotationNonce();

        OmnichainRouter.SignerSet memory newSet =
            OmnichainRouter.SignerSet(signer1, signer2, signer3, newMpc, 2);

        bytes32 digest = keccak256(
            abi.encodePacked(
                "ROTATE_SIGNERS",
                CHAIN_ID,
                currentNonce,
                newSet.signer1,
                newSet.signer2,
                newSet.signer3,
                newSet.mpcGroupAddress,
                newSet.threshold
            )
        );
        bytes memory sig = _signWithMpc(digest);

        router.proposeSignerRotation(newSet, sig);

        assertEq(router.rotationNonce(), currentNonce + 1, "Nonce not incremented");
        assertGt(router.pendingSignersActivateAt(), block.timestamp, "No timelock set");
    }

    function testFuzz_signerRotation_replayOldSigFails(uint256 newKey) public {
        newKey = bound(newKey, 1, type(uint128).max);
        vm.assume(newKey != mpcGroupKey);

        address newMpc = vm.addr(newKey);

        OmnichainRouter.SignerSet memory newSet =
            OmnichainRouter.SignerSet(signer1, signer2, signer3, newMpc, 2);

        // First rotation succeeds
        uint256 nonce0 = router.rotationNonce();
        bytes32 digest0 = keccak256(
            abi.encodePacked(
                "ROTATE_SIGNERS", CHAIN_ID, nonce0,
                newSet.signer1, newSet.signer2, newSet.signer3,
                newSet.mpcGroupAddress, newSet.threshold
            )
        );
        bytes memory sig0 = _signWithMpc(digest0);
        router.proposeSignerRotation(newSet, sig0);

        // Execute timelock
        vm.warp(block.timestamp + 7 days + 1);
        router.executeSignerRotation();

        // Replay old sig with old nonce -- rotationNonce is now different
        vm.expectRevert("Invalid MPC signature");
        router.proposeSignerRotation(newSet, sig0);
    }

    // ================================================================
    //  4. FUZZ cancel rotation: requires pending, digest has chainId+nonce+activateAt
    // ================================================================

    function test_cancelRotation_noPendingReverts() public {
        bytes32 digest = keccak256(
            abi.encodePacked("CANCEL_ROTATION", CHAIN_ID, router.rotationNonce(), uint256(0))
        );
        bytes memory sig = _signWithMpc(digest);

        vm.expectRevert("No pending rotation");
        router.cancelSignerRotation(sig);
    }

    function test_cancelRotation_succeeds() public {
        // Propose rotation first
        OmnichainRouter.SignerSet memory newSet =
            OmnichainRouter.SignerSet(signer1, signer2, signer3, vm.addr(0xDEAD), 2);

        uint256 nonce = router.rotationNonce();
        bytes32 digest = keccak256(
            abi.encodePacked(
                "ROTATE_SIGNERS", CHAIN_ID, nonce,
                newSet.signer1, newSet.signer2, newSet.signer3,
                newSet.mpcGroupAddress, newSet.threshold
            )
        );
        router.proposeSignerRotation(newSet, _signWithMpc(digest));

        uint256 activateAt = router.pendingSignersActivateAt();
        uint256 cancelNonce = router.rotationNonce();

        bytes32 cancelDigest = keccak256(
            abi.encodePacked("CANCEL_ROTATION", CHAIN_ID, cancelNonce, activateAt)
        );
        bytes memory cancelSig = _signWithMpc(cancelDigest);

        router.cancelSignerRotation(cancelSig);

        assertEq(router.pendingSignersActivateAt(), 0, "Pending not cleared");
        assertEq(router.rotationNonce(), cancelNonce + 1, "Cancel nonce not incremented");
    }

    // ================================================================
    //  5. Auto-pause: backing < 98.5% pauses, >= 99% clears (hysteresis)
    // ================================================================

    function test_autoPause_undercollatTriggers() public {
        _mintDeposit(1, 1, 10_000 ether);

        // Backing at 98% (below 98.5% threshold)
        _updateBacking(9800 ether, 1);
        assertTrue(router.autoPaused(), "Should be auto-paused at 98%");
    }

    function test_autoPause_hysteresis() public {
        _mintDeposit(1, 1, 10_000 ether);

        // Drop to 97% -- triggers pause
        _updateBacking(9700 ether, 1);
        assertTrue(router.autoPaused(), "Should be paused at 97%");

        // Recover to 98.6% -- still below 99%, stays paused (hysteresis)
        _updateBacking(9860 ether, 2);
        assertTrue(router.autoPaused(), "Should stay paused at 98.6%");

        // Recover to 99% -- clears pause
        _updateBacking(9900 ether, 3);
        assertFalse(router.autoPaused(), "Should clear at 99%");
    }

    function test_autoPause_aboveThresholdNoPause() public {
        _mintDeposit(1, 1, 10_000 ether);

        // Backing at 99% -- no pause
        _updateBacking(9900 ether, 1);
        assertFalse(router.autoPaused(), "Should not pause at 99%");
    }

    // ================================================================
    //  6. Exit guarantee: burn works even when paused
    // ================================================================

    function test_exitGuarantee_burnWhilePaused() public {
        uint256 amount = 1000 ether;
        _mintDeposit(1, 1, amount);

        // Auto-pause: backing < 98.5% of totalMinted triggers autoPause
        // totalMinted = 1000 ether (pre-fee), so 980 = 98% < 98.5%
        _updateBacking(980 ether, 1);
        assertTrue(router.autoPaused(), "Should be auto-paused");

        // Manual pause too
        bytes32 pauseDigest = keccak256(abi.encodePacked("PAUSE", CHAIN_ID, router.pauseNonce()));
        router.pause(_signWithMpc(pauseDigest));
        assertTrue(router.manualPaused(), "Should be manual-paused");

        // Burn still works (exit guarantee)
        uint256 fee = (amount * FEE_BPS) / 10000;
        uint256 mintAmount = amount - fee;

        vm.startPrank(recipient);
        token.approve(address(router), mintAmount);
        router.burnForWithdrawal(address(token), mintAmount, 1, bytes32(uint256(1)));
        vm.stopPrank();

        assertEq(token.balanceOf(recipient), 0, "Should have burned all");
    }

    function test_exitGuarantee_mintBlockedWhilePaused() public {
        _mintDeposit(1, 1, 1000 ether);

        // Auto-pause: backing < 98.5%
        _updateBacking(980 ether, 1);

        bytes32 digest = keccak256(
            abi.encodePacked("DEPOSIT", CHAIN_ID, uint64(1), uint64(2), address(token), recipient, uint256(100 ether))
        );
        vm.expectRevert("Paused");
        router.mintDeposit(1, 2, address(token), recipient, 100 ether, _signWithMpc(digest));
    }

    // ================================================================
    //  7. Daily limit: fuzz amounts, verify enforcement per period
    // ================================================================

    function testFuzz_dailyLimit(uint256 amount1, uint256 amount2) public {
        uint256 limit = 500 ether;
        vm.prank(governor);
        router.setDailyMintLimit(address(token), limit);

        amount1 = bound(amount1, 1, limit);
        amount2 = bound(amount2, 1, limit);

        // First mint within limit
        _mintDeposit(1, 1, amount1);

        if (amount1 + amount2 > limit) {
            // Second mint should fail
            bytes32 digest = keccak256(
                abi.encodePacked("DEPOSIT", CHAIN_ID, uint64(1), uint64(2), address(token), recipient, amount2)
            );
            vm.expectRevert("Daily mint limit exceeded");
            router.mintDeposit(1, 2, address(token), recipient, amount2, _signWithMpc(digest));
        } else {
            // Second mint should succeed
            _mintDeposit(1, 2, amount2);
        }
    }

    function test_dailyLimit_resetsAfterPeriod() public {
        uint256 limit = 500 ether;
        vm.prank(governor);
        router.setDailyMintLimit(address(token), limit);

        // Mint full limit
        _mintDeposit(1, 1, limit);

        // Advance past daily period
        vm.warp(block.timestamp + 1 days + 1);

        // Should succeed again
        _mintDeposit(1, 2, limit);

        assertEq(router.totalMinted(address(token)), limit * 2, "totalMinted should track both");
    }

    // ================================================================
    //  8. totalMinted tracks pre-fee amount (full including fee shares)
    // ================================================================

    function testFuzz_totalMinted_tracksFull(uint256 amount) public {
        amount = bound(amount, 1, 1_000_000 ether);

        _mintDeposit(1, 1, amount);

        assertEq(router.totalMinted(address(token)), amount, "totalMinted should be full pre-fee amount");

        // Verify actual minted tokens equal amount (recipient + vault + treasury)
        uint256 fee = (amount * FEE_BPS) / 10000;
        uint256 toRecipient = amount - fee;
        uint256 toStakeholders = (fee * STAKEHOLDER_SHARE) / 10000;
        uint256 toTreasury = fee - toStakeholders;

        uint256 totalActuallyMinted = token.balanceOf(recipient) + token.balanceOf(vault) + token.balanceOf(treasury);

        assertEq(token.balanceOf(recipient), toRecipient, "Recipient amount");
        assertEq(token.balanceOf(vault), toStakeholders, "Vault amount");
        assertEq(token.balanceOf(treasury), toTreasury, "Treasury amount");
        assertEq(totalActuallyMinted, amount, "Total minted tokens must equal totalMinted");
    }

    // ================================================================
    //  9. registerToken: chainId in digest prevents cross-chain replay
    // ================================================================

    function testFuzz_registerToken_crossChainReplay(uint64 wrongChain) public {
        wrongChain = uint64(bound(wrongChain, 1, type(uint64).max));
        vm.assume(wrongChain != CHAIN_ID);

        MockBridgeToken token2 = new MockBridgeToken("Test", "TST", address(router));

        // Sign with wrong chainId
        bytes32 digest = keccak256(
            abi.encodePacked("REGISTER", wrongChain, address(token2), uint256(1_000_000 ether))
        );
        bytes memory sig = _signWithMpc(digest);

        vm.expectRevert("Invalid");
        router.registerToken(address(token2), 1_000_000 ether, sig);
    }

    function test_registerToken_succeeds() public {
        MockBridgeToken token2 = new MockBridgeToken("Test", "TST", address(router));

        bytes32 digest = keccak256(
            abi.encodePacked("REGISTER", CHAIN_ID, address(token2), uint256(500 ether))
        );
        router.registerToken(address(token2), 500 ether, _signWithMpc(digest));

        assertTrue(router.registeredTokens(address(token2)), "Should be registered");
        assertEq(router.dailyMintLimit(address(token2)), 500 ether, "Limit wrong");
    }

    function test_registerToken_duplicateReverts() public {
        // token is already registered in setUp
        bytes32 digest = keccak256(
            abi.encodePacked("REGISTER", CHAIN_ID, address(token), uint256(1_000_000 ether))
        );
        vm.expectRevert("Already registered");
        router.registerToken(address(token), 1_000_000 ether, _signWithMpc(digest));
    }

    // ================================================================
    //  10. Nonce replay protection
    // ================================================================

    function test_depositNonceReplay() public {
        _mintDeposit(1, 1, 100 ether);

        // Replay same nonce
        bytes32 digest = keccak256(
            abi.encodePacked("DEPOSIT", CHAIN_ID, uint64(1), uint64(1), address(token), recipient, uint256(100 ether))
        );
        vm.expectRevert("Nonce processed");
        router.mintDeposit(1, 1, address(token), recipient, 100 ether, _signWithMpc(digest));
    }

    // ================================================================
    //  PAUSE / UNPAUSE replay protection
    // ================================================================

    function test_pauseNonceIncrementsAndPreventsReplay() public {
        uint256 nonce0 = router.pauseNonce();

        bytes32 digest0 = keccak256(abi.encodePacked("PAUSE", CHAIN_ID, nonce0));
        bytes memory sig0 = _signWithMpc(digest0);
        router.pause(sig0);
        assertTrue(router.manualPaused());

        // Replay same sig fails
        vm.expectRevert("Invalid");
        router.pause(sig0);

        // Unpause with new nonce
        uint256 nonce1 = router.pauseNonce();
        bytes32 digest1 = keccak256(abi.encodePacked("UNPAUSE", CHAIN_ID, nonce1));
        router.unpause(_signWithMpc(digest1));
        assertFalse(router.manualPaused());
    }
}

// ================================================================
//  INVARIANT TEST: supply <= totalMinted for any registered token
// ================================================================

contract OmnichainRouterInvariant is Test {
    using ECDSA for bytes32;
    using MessageHashUtils for bytes32;

    OmnichainRouter public router;
    MockBridgeToken public token;
    OmnichainRouterHandler public handler;

    uint256 internal constant MPC_KEY = 0xBEEF;
    uint64 internal constant CHAIN_ID = 96369;

    function setUp() public {
        address mpcGroupAddress = vm.addr(MPC_KEY);

        router = new OmnichainRouter(
            CHAIN_ID,
            address(0xAAAA),
            address(0xBBBB),
            address(0xCCCC),
            50,   // 0.5% fee
            9000, // 90% stakeholder
            vm.addr(0xA1),
            vm.addr(0xA2),
            vm.addr(0xA3),
            mpcGroupAddress
        );

        token = new MockBridgeToken("Lux ETH", "LETH", address(router));

        // Register token
        bytes32 digest = keccak256(
            abi.encodePacked("REGISTER", CHAIN_ID, address(token), uint256(0))
        );
        bytes32 ethHash = digest.toEthSignedMessageHash();
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(MPC_KEY, ethHash);
        router.registerToken(address(token), 0, abi.encodePacked(r, s, v));

        handler = new OmnichainRouterHandler(router, token, MPC_KEY, CHAIN_ID);

        targetContract(address(handler));
    }

    /// @notice Supply of the token should never exceed totalMinted
    function invariant_supplyNeverExceedsTotalMinted() public view {
        uint256 supply = token.totalSupply();
        uint256 minted = router.totalMinted(address(token));
        assertLe(supply, minted, "INVARIANT: supply > totalMinted");
    }

    /// @notice totalMinted equals sum of all deposits minus sum of all burns
    function invariant_totalMintedMatchesHandler() public view {
        uint256 minted = router.totalMinted(address(token));
        uint256 expected = handler.totalDeposited() - handler.totalBurned();
        assertEq(minted, expected, "INVARIANT: totalMinted accounting mismatch");
    }
}

/// @notice Handler that drives the invariant test with valid MPC-signed operations
contract OmnichainRouterHandler is Test {
    using ECDSA for bytes32;
    using MessageHashUtils for bytes32;

    OmnichainRouter public router;
    MockBridgeToken public token;
    uint256 internal mpcKey;
    uint64 internal chainId;

    uint64 public nextNonce = 1;
    uint256 public totalDeposited;
    uint256 public totalBurned;

    address internal recipient = address(0xDDDD);

    constructor(
        OmnichainRouter _router,
        MockBridgeToken _token,
        uint256 _mpcKey,
        uint64 _chainId
    ) {
        router = _router;
        token = _token;
        mpcKey = _mpcKey;
        chainId = _chainId;
    }

    function _signMpc(bytes32 digest) internal view returns (bytes memory) {
        bytes32 ethHash = digest.toEthSignedMessageHash();
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(mpcKey, ethHash);
        return abi.encodePacked(r, s, v);
    }

    function deposit(uint256 amount) external {
        amount = bound(amount, 1, 10_000 ether);

        bytes32 digest = keccak256(
            abi.encodePacked("DEPOSIT", chainId, uint64(1), nextNonce, address(token), recipient, amount)
        );
        router.mintDeposit(uint64(1), nextNonce, address(token), recipient, amount, _signMpc(digest));

        nextNonce++;
        totalDeposited += amount;
    }

    function burn(uint256 amount) external {
        uint256 bal = token.balanceOf(recipient);
        if (bal == 0) return;
        amount = bound(amount, 1, bal);

        vm.startPrank(recipient);
        token.approve(address(router), amount);
        router.burnForWithdrawal(address(token), amount, uint64(1), bytes32(uint256(1)));
        vm.stopPrank();

        totalBurned += amount;
    }
}
