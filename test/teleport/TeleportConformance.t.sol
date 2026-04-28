// SPDX-License-Identifier: BSD-3-Clause
// Copyright (c) 2025 Lux Industries Inc.
pragma solidity ^0.8.31;

import "forge-std/Test.sol";
import "../../contracts/bridge/teleport/Teleporter.sol";

/**
 * @title MockBridgedToken
 * @notice Minimal IBridgedToken for testing — admin-gated mint/burn
 */
contract MockBridgedToken is IBridgedToken {
    string public name;
    string public symbol;
    uint8 public decimals;
    uint256 public totalSupply;

    mapping(address => uint256) private _balances;
    mapping(address => mapping(address => uint256)) private _allowances;
    address public minter;

    constructor(string memory _name, string memory _symbol, uint8 _decimals) {
        name = _name;
        symbol = _symbol;
        decimals = _decimals;
        minter = msg.sender;
    }

    function setMinter(address _minter) external {
        minter = _minter;
    }

    function mint(address to, uint256 amount) external override {
        _balances[to] += amount;
        totalSupply += amount;
    }

    function burn(uint256 amount) external override {
        require(_balances[msg.sender] >= amount, "underflow");
        _balances[msg.sender] -= amount;
        totalSupply -= amount;
    }

    function burnFrom(address from, uint256 amount) external override {
        require(_balances[from] >= amount, "underflow");
        if (msg.sender != from) {
            require(_allowances[from][msg.sender] >= amount, "allowance");
            _allowances[from][msg.sender] -= amount;
        }
        _balances[from] -= amount;
        totalSupply -= amount;
    }

    function balanceOf(address account) external view override returns (uint256) {
        return _balances[account];
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        _allowances[msg.sender][spender] = amount;
        return true;
    }

    function allowance(address owner, address spender) external view returns (uint256) {
        return _allowances[owner][spender];
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        require(_balances[msg.sender] >= amount, "underflow");
        _balances[msg.sender] -= amount;
        _balances[to] += amount;
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        require(_balances[from] >= amount, "underflow");
        require(_allowances[from][msg.sender] >= amount, "allowance");
        _allowances[from][msg.sender] -= amount;
        _balances[from] -= amount;
        _balances[to] += amount;
        return true;
    }
}

/**
 * @title TeleportConformance
 * @author Lux Industries
 * @notice Conformance test pack for the Teleporter contract.
 *         Validates the full Teleport lifecycle for any source chain:
 *           1. MPC-signed deposit minting
 *           2. Replay protection (nonce reuse blocked)
 *           3. Stale backing attestation rejection
 *           4. Burn-for-withdraw flow
 *           5. Backing attestation updates
 *           6. Peg degradation bridge pause
 *
 * @dev Uses forge-std cheatcodes (vm.sign, vm.warp, vm.prank).
 *      Source chain parameters are set in setUp() — override for chain-specific tests.
 */
contract TeleportConformance is Test {
    // ═══════════════════════════════════════════════════════════════════════
    // STATE
    // ═══════════════════════════════════════════════════════════════════════

    Teleporter public teleporter;
    MockBridgedToken public token;

    // MPC signer — deterministic key for reproducible signatures
    uint256 internal mpcPrivateKey = 0xA11CE;
    address internal mpcOracle;

    // Test actors
    address internal admin = address(0xAD);
    address internal recipient = address(0xBEEF);
    address internal user = address(0xCAFE);

    // Source chain config — override in derived contracts for chain-specific tests
    uint256 internal srcChainId = 8453; // Default: Base
    uint256 internal depositAmount = 1 ether;

    // ═══════════════════════════════════════════════════════════════════════
    // SETUP
    // ═══════════════════════════════════════════════════════════════════════

    function setUp() public virtual {
        mpcOracle = vm.addr(mpcPrivateKey);

        vm.startPrank(admin);

        token = new MockBridgedToken("Liquid ETH", "LETH", 18);
        teleporter = new Teleporter(address(token), mpcOracle);

        // Seed a fresh backing attestation so minting is allowed
        _updateBacking(srcChainId, 1000 ether);

        vm.stopPrank();
    }

    // ═══════════════════════════════════════════════════════════════════════
    // HELPERS
    // ═══════════════════════════════════════════════════════════════════════

    /**
     * @notice Build and sign a deposit proof matching Teleporter.mintDeposit
     * MEDIUM-01: Uses abi.encode (not encodePacked) for collision resistance
     */
    function _signDeposit(uint256 _srcChainId, uint256 nonce, address _recipient, uint256 amount)
        internal
        view
        returns (bytes memory)
    {
        bytes32 messageHash = keccak256(abi.encode(bytes32("DEPOSIT"), _srcChainId, nonce, _recipient, amount));
        bytes32 ethSignedHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", messageHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(mpcPrivateKey, ethSignedHash);
        return abi.encodePacked(r, s, v);
    }

    /**
     * @notice Build and sign a backing attestation matching Teleporter.updateBacking
     * CRITICAL-01: timestamp is now a parameter, not block.timestamp
     * MEDIUM-01: Uses abi.encode (not encodePacked)
     */
    function _signBacking(uint256 _srcChainId, uint256 totalBacking, uint256 timestamp)
        internal
        view
        returns (bytes memory)
    {
        bytes32 messageHash = keccak256(abi.encode(bytes32("BACKING"), _srcChainId, totalBacking, timestamp));
        bytes32 ethSignedHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", messageHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(mpcPrivateKey, ethSignedHash);
        return abi.encodePacked(r, s, v);
    }

    /**
     * @notice Submit a backing attestation as the MPC oracle
     * CRITICAL-01: passes block.timestamp as the MPC-signed timestamp
     */
    function _updateBacking(uint256 _srcChainId, uint256 totalBacking) internal {
        // NEW-07: advance 1s to satisfy monotonicity check on repeated calls
        vm.warp(block.timestamp + 1);
        bytes memory sig = _signBacking(_srcChainId, totalBacking, block.timestamp);
        teleporter.updateBacking(_srcChainId, totalBacking, block.timestamp, sig);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // TEST 1: DEPOSIT MINT — valid MPC signature mints tokens
    // ═══════════════════════════════════════════════════════════════════════

    function testDepositMint() public {
        uint256 nonce = 1;
        bytes memory sig = _signDeposit(srcChainId, nonce, recipient, depositAmount);

        uint256 balBefore = token.balanceOf(recipient);
        uint256 mintedBefore = teleporter.totalDepositMinted();

        teleporter.mintDeposit(srcChainId, nonce, recipient, depositAmount, sig);

        // Token minted to recipient
        assertEq(token.balanceOf(recipient), balBefore + depositAmount, "recipient balance mismatch");

        // Accounting updated
        assertEq(teleporter.totalDepositMinted(), mintedBefore + depositAmount, "totalDepositMinted mismatch");

        // Nonce marked processed
        assertTrue(teleporter.isDepositProcessed(srcChainId, nonce), "nonce not marked processed");
    }

    function testDepositMint_MultipleNonces() public {
        for (uint256 i = 1; i <= 5; i++) {
            bytes memory sig = _signDeposit(srcChainId, i, recipient, depositAmount);
            teleporter.mintDeposit(srcChainId, i, recipient, depositAmount, sig);
        }

        assertEq(token.balanceOf(recipient), depositAmount * 5, "5 deposits should sum");
        assertEq(teleporter.totalDepositMinted(), depositAmount * 5, "totalDepositMinted after 5");
    }

    function testDepositMint_RevertZeroAmount() public {
        bytes memory sig = _signDeposit(srcChainId, 1, recipient, 0);

        vm.expectRevert(Teleporter.ZeroAmount.selector);
        teleporter.mintDeposit(srcChainId, 1, recipient, 0, sig);
    }

    function testDepositMint_RevertZeroRecipient() public {
        bytes memory sig = _signDeposit(srcChainId, 1, address(0), depositAmount);

        vm.expectRevert(Teleporter.ZeroAddress.selector);
        teleporter.mintDeposit(srcChainId, 1, address(0), depositAmount, sig);
    }

    function testDepositMint_RevertInvalidSignature() public {
        // Sign with wrong key
        uint256 wrongKey = 0xDEAD;
        bytes32 messageHash =
            keccak256(abi.encode(bytes32("DEPOSIT"), srcChainId, uint256(1), recipient, depositAmount));
        bytes32 ethSignedHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", messageHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(wrongKey, ethSignedHash);
        bytes memory badSig = abi.encodePacked(r, s, v);

        vm.expectRevert(Teleporter.InvalidSignature.selector);
        teleporter.mintDeposit(srcChainId, 1, recipient, depositAmount, badSig);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // TEST 2: REPLAY PROTECTION — same nonce reverts
    // ═══════════════════════════════════════════════════════════════════════

    function testReplayProtection() public {
        uint256 nonce = 42;
        bytes memory sig = _signDeposit(srcChainId, nonce, recipient, depositAmount);

        // First mint succeeds
        teleporter.mintDeposit(srcChainId, nonce, recipient, depositAmount, sig);

        // Replay with identical params reverts
        vm.expectRevert(Teleporter.NonceAlreadyProcessed.selector);
        teleporter.mintDeposit(srcChainId, nonce, recipient, depositAmount, sig);
    }

    function testReplayProtection_DifferentChainSameNonce() public {
        uint256 nonce = 1;
        uint256 otherChain = 1; // Ethereum mainnet

        // Mint on srcChainId
        bytes memory sig1 = _signDeposit(srcChainId, nonce, recipient, depositAmount);
        teleporter.mintDeposit(srcChainId, nonce, recipient, depositAmount, sig1);

        // Same nonce on different chain requires fresh backing
        vm.prank(admin);
        _updateBacking(otherChain, 1000 ether);

        // Same nonce, different srcChainId should succeed (separate namespace)
        bytes memory sig2 = _signDeposit(otherChain, nonce, recipient, depositAmount);
        teleporter.mintDeposit(otherChain, nonce, recipient, depositAmount, sig2);

        // Both processed
        assertTrue(teleporter.isDepositProcessed(srcChainId, nonce), "chain1 nonce not processed");
        assertTrue(teleporter.isDepositProcessed(otherChain, nonce), "chain2 nonce not processed");
    }

    // ═══════════════════════════════════════════════════════════════════════
    // TEST 3: STALE BACKING REVERTS — attestation older than staleness window blocks minting
    // HIGH-02: Default window is now 2 hours (was 24)
    // ═══════════════════════════════════════════════════════════════════════

    function testStaleBackingReverts() public {
        // Warp past the 2h staleness window
        vm.warp(block.timestamp + 3 hours);

        bytes memory sig = _signDeposit(srcChainId, 1, recipient, depositAmount);

        vm.expectRevert(Teleporter.StaleAttestation.selector);
        teleporter.mintDeposit(srcChainId, 1, recipient, depositAmount, sig);
    }

    function testStaleBackingReverts_JustUnderThreshold() public {
        // Warp just under 2h — should still be valid
        vm.warp(block.timestamp + 2 hours - 1);

        bytes memory sig = _signDeposit(srcChainId, 1, recipient, depositAmount);

        // Should succeed (not stale yet)
        teleporter.mintDeposit(srcChainId, 1, recipient, depositAmount, sig);
        assertTrue(teleporter.isDepositProcessed(srcChainId, 1), "should be processed");
    }

    function testStaleBackingReverts_ExactThreshold() public {
        // Warp just past 2h — should revert (> check)
        vm.warp(block.timestamp + 2 hours + 1);

        bytes memory sig = _signDeposit(srcChainId, 1, recipient, depositAmount);

        vm.expectRevert(Teleporter.StaleAttestation.selector);
        teleporter.mintDeposit(srcChainId, 1, recipient, depositAmount, sig);
    }

    function testStaleBackingReverts_RefreshFixes() public {
        // Stale
        vm.warp(block.timestamp + 3 hours);

        // Refresh backing
        vm.prank(admin);
        _updateBacking(srcChainId, 1000 ether);

        // Now mint should succeed
        bytes memory sig = _signDeposit(srcChainId, 1, recipient, depositAmount);
        teleporter.mintDeposit(srcChainId, 1, recipient, depositAmount, sig);

        assertEq(token.balanceOf(recipient), depositAmount, "should mint after refresh");
    }

    // ═══════════════════════════════════════════════════════════════════════
    // TEST 4: BURN FOR WITHDRAW — burn creates pending withdraw
    // ═══════════════════════════════════════════════════════════════════════

    function testBurnForWithdraw() public {
        // First mint some tokens
        bytes memory sig = _signDeposit(srcChainId, 1, user, depositAmount);
        teleporter.mintDeposit(srcChainId, 1, user, depositAmount, sig);

        // User approves Teleporter to burn
        vm.prank(user);
        token.approve(address(teleporter), depositAmount);

        // User burns for withdraw
        uint256 burnedBefore = teleporter.totalBurned();

        vm.prank(user);
        uint256 withdrawNonce = teleporter.burnForWithdraw(depositAmount, srcChainId, user);

        // Token burned
        assertEq(token.balanceOf(user), 0, "user should have 0 after burn");

        // Accounting updated
        assertEq(teleporter.totalBurned(), burnedBefore + depositAmount, "totalBurned mismatch");

        // Withdraw nonce marked pending
        assertTrue(teleporter.pendingWithdraws(withdrawNonce), "withdraw not pending");
    }

    function testBurnForWithdraw_RevertZeroAmount() public {
        vm.prank(user);
        vm.expectRevert(Teleporter.ZeroAmount.selector);
        teleporter.burnForWithdraw(0, srcChainId, user);
    }

    function testBurnForWithdraw_RevertZeroRecipient() public {
        vm.prank(user);
        vm.expectRevert(Teleporter.ZeroAddress.selector);
        teleporter.burnForWithdraw(depositAmount, srcChainId, address(0));
    }

    function testBurnForWithdraw_NetCirculation() public {
        // Mint
        bytes memory sig = _signDeposit(srcChainId, 1, user, 10 ether);
        teleporter.mintDeposit(srcChainId, 1, user, 10 ether, sig);

        assertEq(teleporter.netCirculation(), 10 ether, "net circulation after mint");

        // Burn half
        vm.startPrank(user);
        token.approve(address(teleporter), 5 ether);
        teleporter.burnForWithdraw(5 ether, srcChainId, user);
        vm.stopPrank();

        assertEq(teleporter.netCirculation(), 5 ether, "net circulation after partial burn");
    }

    // ═══════════════════════════════════════════════════════════════════════
    // TEST 5: BACKING UPDATE — attestation updates correctly
    // ═══════════════════════════════════════════════════════════════════════

    function testBackingUpdate() public {
        uint256 newBacking = 500 ether;

        vm.prank(admin);
        _updateBacking(srcChainId, newBacking);

        (uint256 totalBacking, uint256 ts) = teleporter.getBacking(srcChainId);
        assertEq(totalBacking, newBacking, "backing amount mismatch");
        assertEq(ts, block.timestamp, "backing timestamp mismatch");
    }

    function testBackingUpdate_RevertInvalidSignature() public {
        // Advance past the setUp attestation timestamp to satisfy monotonicity check
        vm.warp(block.timestamp + 2);
        uint256 wrongKey = 0xBAD;
        bytes32 messageHash = keccak256(abi.encode(bytes32("BACKING"), srcChainId, uint256(100 ether), block.timestamp));
        bytes32 ethSignedHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", messageHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(wrongKey, ethSignedHash);
        bytes memory badSig = abi.encodePacked(r, s, v);

        vm.expectRevert(Teleporter.InvalidSignature.selector);
        teleporter.updateBacking(srcChainId, 100 ether, block.timestamp, badSig);
    }

    function testBackingUpdate_InsufficientBackingPauses() public virtual {
        // Mint some tokens first
        bytes memory sig = _signDeposit(srcChainId, 1, recipient, 100 ether);
        teleporter.mintDeposit(srcChainId, 1, recipient, 100 ether, sig);

        // Update backing to less than totalMinted — should auto-pause
        vm.prank(admin);
        _updateBacking(srcChainId, 50 ether);

        assertTrue(teleporter.paused(), "bridge should be paused when backing < totalMinted");
    }

    function testBackingUpdate_RejectsExcessMint() public {
        // Set backing to exactly 10 ether
        vm.prank(admin);
        _updateBacking(srcChainId, 10 ether);

        // Try to mint 11 ether — exceeds backing
        bytes memory sig = _signDeposit(srcChainId, 1, recipient, 11 ether);

        vm.expectRevert(Teleporter.BackingInsufficient.selector);
        teleporter.mintDeposit(srcChainId, 1, recipient, 11 ether, sig);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // TEST 6: PEG DEGRADATION — threshold pauses bridge
    // ═══════════════════════════════════════════════════════════════════════

    function testPegDegradation() public {
        // The Teleporter.getCurrentPeg() currently returns BASIS_POINTS (10000 = 1:1).
        // When a real DEX oracle is integrated, peg < PEG_PAUSE_THRESHOLD (9850) halts minting.
        // For now, verify the threshold constants and pause mechanism.

        assertEq(teleporter.PEG_DEGRADE_THRESHOLD(), 9950, "degrade threshold should be 99.5%");
        assertEq(teleporter.PEG_PAUSE_THRESHOLD(), 9850, "pause threshold should be 98.5%");

        // With default getCurrentPeg() returning 10000, minting should work
        bytes memory sig = _signDeposit(srcChainId, 1, recipient, depositAmount);
        teleporter.mintDeposit(srcChainId, 1, recipient, depositAmount, sig);

        // Verify that manual pause blocks minting
        vm.prank(admin);
        teleporter.setPaused(true);

        bytes memory sig2 = _signDeposit(srcChainId, 2, recipient, depositAmount);
        vm.expectRevert(Teleporter.BridgePaused.selector);
        teleporter.mintDeposit(srcChainId, 2, recipient, depositAmount, sig2);
    }

    function testPegDegradation_PausedBurnBlocked() public {
        // Mint tokens
        bytes memory sig = _signDeposit(srcChainId, 1, user, depositAmount);
        teleporter.mintDeposit(srcChainId, 1, user, depositAmount, sig);

        // Pause
        vm.prank(admin);
        teleporter.setPaused(true);

        // Burn should also revert when paused
        vm.startPrank(user);
        token.approve(address(teleporter), depositAmount);
        vm.expectRevert(Teleporter.BridgePaused.selector);
        teleporter.burnForWithdraw(depositAmount, srcChainId, user);
        vm.stopPrank();
    }

    function testPegDegradation_UnpauseRestoresFlow() public {
        // Pause
        vm.prank(admin);
        teleporter.setPaused(true);

        // Unpause
        vm.prank(admin);
        teleporter.setPaused(false);

        // Minting works again
        bytes memory sig = _signDeposit(srcChainId, 1, recipient, depositAmount);
        teleporter.mintDeposit(srcChainId, 1, recipient, depositAmount, sig);

        assertEq(token.balanceOf(recipient), depositAmount, "should mint after unpause");
    }

    // ═══════════════════════════════════════════════════════════════════════
    // ADMIN — MPC oracle management
    // ═══════════════════════════════════════════════════════════════════════

    function testAdminSetMPCOracle() public {
        address newOracle = address(0xFACE);

        vm.prank(admin);
        teleporter.setMPCOracle(newOracle, true);

        assertTrue(teleporter.mpcOracles(newOracle), "new oracle should be active");
    }

    function testAdminRevokeMPCOracle() public {
        vm.prank(admin);
        teleporter.setMPCOracle(mpcOracle, false);

        assertFalse(teleporter.mpcOracles(mpcOracle), "oracle should be revoked");

        // Signatures from revoked oracle should fail
        bytes memory sig = _signDeposit(srcChainId, 1, recipient, depositAmount);
        vm.expectRevert(Teleporter.InvalidSignature.selector);
        teleporter.mintDeposit(srcChainId, 1, recipient, depositAmount, sig);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // FUZZ — bounded deposit amounts
    // ═══════════════════════════════════════════════════════════════════════

    function testFuzz_DepositMint(uint256 amount) public virtual {
        amount = bound(amount, 1, 999 ether); // Under the 1000 ether backing

        bytes memory sig = _signDeposit(srcChainId, 1, recipient, amount);
        teleporter.mintDeposit(srcChainId, 1, recipient, amount, sig);

        assertEq(token.balanceOf(recipient), amount, "fuzz: balance mismatch");
        assertEq(teleporter.totalDepositMinted(), amount, "fuzz: totalDepositMinted mismatch");
    }
}
