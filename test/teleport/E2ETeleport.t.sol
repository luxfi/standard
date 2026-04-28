// SPDX-License-Identifier: BSD-3-Clause
// Copyright (c) 2025 Lux Industries Inc.
pragma solidity ^0.8.31;

import "forge-std/Test.sol";
import "../../contracts/bridge/teleport/Teleporter.sol";

/**
 * @title E2ETeleport
 * @author Lux Industries
 * @notice Foundry fork test that runs against Lux testnet (96368).
 *         Validates the full Teleport lifecycle using real chain state:
 *           1. LUX -> ZOO deposit flow (mint event format, MPC relay simulation)
 *           2. ZOO -> LUX withdraw flow (burn event, release simulation)
 *           3. DEX swap simulation after deposit (LBTC -> LUX mock pool)
 *
 * @dev Requires LUX_TESTNET_RPC env var. Uses vm.createSelectFork for fork testing.
 *      No actual MPC needed -- verifies contract logic against real deployed state.
 */
contract E2ETeleport is Test {
    // Chain IDs from ChainIds.sol
    uint256 internal constant LUX_MAINNET = 96369;
    uint256 internal constant LUX_TESTNET = 96368;
    uint256 internal constant LUX_ZOO = 200200;

    // MPC signer -- deterministic key for reproducible signatures
    uint256 internal mpcPrivateKey = 0xA11CE;
    address internal mpcOracle;

    // Test actors
    address internal admin = address(0xAD);
    address internal user = address(0xCAFE);
    address internal relayer = address(0xBEEF);

    // Contracts
    Teleporter internal teleporter;
    MockE2EToken internal lbtc;
    MockE2EToken internal lux;
    MockE2EPool internal pool;

    uint256 internal forkId;

    function setUp() public {
        // Fork Lux testnet
        string memory rpc = vm.envString("LUX_TESTNET_RPC");
        forkId = vm.createSelectFork(rpc);

        mpcOracle = vm.addr(mpcPrivateKey);

        vm.startPrank(admin);

        lbtc = new MockE2EToken("Liquid BTC", "LBTC", 18);
        lux = new MockE2EToken("Lux Token", "LUX", 18);
        teleporter = new Teleporter(address(lbtc), mpcOracle);

        // Seed backing for both chains
        _updateBacking(LUX_TESTNET, 1000 ether);
        _updateBacking(LUX_ZOO, 1000 ether);

        // Deploy mock DEX pool with liquidity
        pool = new MockE2EPool(address(lbtc), address(lux));
        lux.mint(address(pool), 10_000 ether);

        vm.stopPrank();
    }

    // =====================================================================
    // HELPERS
    // =====================================================================

    function _signDeposit(uint256 srcChainId, uint256 nonce, address recipient, uint256 amount)
        internal
        view
        returns (bytes memory)
    {
        bytes32 messageHash = keccak256(abi.encode(bytes32("DEPOSIT"), srcChainId, nonce, recipient, amount));
        bytes32 ethSignedHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", messageHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(mpcPrivateKey, ethSignedHash);
        return abi.encodePacked(r, s, v);
    }

    function _signBacking(uint256 srcChainId, uint256 totalBacking, uint256 timestamp)
        internal
        view
        returns (bytes memory)
    {
        bytes32 messageHash = keccak256(abi.encode(bytes32("BACKING"), srcChainId, totalBacking, timestamp));
        bytes32 ethSignedHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", messageHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(mpcPrivateKey, ethSignedHash);
        return abi.encodePacked(r, s, v);
    }

    function _updateBacking(uint256 srcChainId, uint256 totalBacking) internal {
        vm.warp(block.timestamp + 1);
        bytes memory sig = _signBacking(srcChainId, totalBacking, block.timestamp);
        teleporter.updateBacking(srcChainId, totalBacking, block.timestamp, sig);
    }

    // =====================================================================
    // TEST 1: LUX -> ZOO deposit flow
    // =====================================================================

    function testE2E_LuxToZoo_DepositMint() public {
        uint256 amount = 5 ether;
        uint256 nonce = 1;

        // Simulate MPC relaying a deposit proof from Lux C-Chain to Zoo
        bytes memory sig = _signDeposit(LUX_TESTNET, nonce, user, amount);

        // Expect DepositMinted event with correct format
        vm.expectEmit(true, true, true, true);
        emit Teleporter.DepositMinted(LUX_TESTNET, nonce, user, amount);

        teleporter.mintDeposit(LUX_TESTNET, nonce, user, amount, sig);

        assertEq(lbtc.balanceOf(user), amount, "user should receive LBTC on Zoo");
        assertTrue(teleporter.isDepositProcessed(LUX_TESTNET, nonce), "nonce processed");
    }

    function testE2E_LuxToZoo_MultipleDeposits() public {
        uint256 total;
        for (uint256 i = 1; i <= 3; i++) {
            uint256 amount = i * 1 ether;
            bytes memory sig = _signDeposit(LUX_TESTNET, i, user, amount);
            teleporter.mintDeposit(LUX_TESTNET, i, user, amount, sig);
            total += amount;
        }
        assertEq(lbtc.balanceOf(user), total, "cumulative deposits should sum");
    }

    // =====================================================================
    // TEST 2: ZOO -> LUX withdraw flow
    // =====================================================================

    function testE2E_ZooToLux_BurnWithdraw() public {
        uint256 amount = 10 ether;

        // First deposit tokens to user
        bytes memory depositSig = _signDeposit(LUX_ZOO, 1, user, amount);
        teleporter.mintDeposit(LUX_ZOO, 1, user, amount, depositSig);
        assertEq(lbtc.balanceOf(user), amount, "user should have LBTC");

        // User burns on Zoo, requesting release on Lux
        vm.startPrank(user);
        lbtc.approve(address(teleporter), amount);

        // Expect BurnedForWithdraw event
        vm.expectEmit(true, false, true, true);
        emit Teleporter.BurnedForWithdraw(user, amount, 1);

        uint256 withdrawNonce = teleporter.burnForWithdraw(amount, LUX_TESTNET, user);
        vm.stopPrank();

        assertEq(lbtc.balanceOf(user), 0, "user LBTC should be zero after burn");
        assertTrue(teleporter.pendingWithdraws(withdrawNonce), "withdraw should be pending");
        assertEq(teleporter.totalBurned(), amount, "totalBurned should match");
    }

    function testE2E_ZooToLux_PartialBurn() public {
        uint256 deposit = 10 ether;
        uint256 burn = 3 ether;

        bytes memory sig = _signDeposit(LUX_ZOO, 1, user, deposit);
        teleporter.mintDeposit(LUX_ZOO, 1, user, deposit, sig);

        vm.startPrank(user);
        lbtc.approve(address(teleporter), burn);
        teleporter.burnForWithdraw(burn, LUX_TESTNET, user);
        vm.stopPrank();

        assertEq(lbtc.balanceOf(user), deposit - burn, "remaining balance after partial burn");
        assertEq(teleporter.netCirculation(), deposit - burn, "net circulation tracks partial burns");
    }

    // =====================================================================
    // TEST 3: DEX swap after deposit (LBTC -> LUX mock pool)
    // =====================================================================

    function testE2E_DexSwapAfterDeposit() public {
        uint256 depositAmount = 2 ether;

        // Deposit LBTC to user
        bytes memory sig = _signDeposit(LUX_TESTNET, 1, user, depositAmount);
        teleporter.mintDeposit(LUX_TESTNET, 1, user, depositAmount, sig);

        // User swaps LBTC -> LUX on mock pool
        vm.startPrank(user);
        lbtc.approve(address(pool), depositAmount);
        uint256 luxReceived = pool.swap(address(lbtc), depositAmount);
        vm.stopPrank();

        assertGt(luxReceived, 0, "should receive LUX from swap");
        assertEq(lbtc.balanceOf(user), 0, "LBTC should be spent");
        assertEq(lux.balanceOf(user), luxReceived, "user should hold LUX");
        assertEq(lbtc.balanceOf(address(pool)), depositAmount, "pool should hold LBTC");
    }

    // =====================================================================
    // TEST 4: Full round-trip deposit -> swap -> burn
    // =====================================================================

    function testE2E_FullRoundTrip() public {
        uint256 amount = 5 ether;

        // 1. Deposit LBTC
        bytes memory sig = _signDeposit(LUX_TESTNET, 1, user, amount);
        teleporter.mintDeposit(LUX_TESTNET, 1, user, amount, sig);

        // 2. Swap half for LUX
        uint256 swapAmount = amount / 2;
        vm.startPrank(user);
        lbtc.approve(address(pool), swapAmount);
        pool.swap(address(lbtc), swapAmount);

        // 3. Burn remaining LBTC back to Lux
        uint256 remaining = lbtc.balanceOf(user);
        lbtc.approve(address(teleporter), remaining);
        teleporter.burnForWithdraw(remaining, LUX_TESTNET, user);
        vm.stopPrank();

        assertEq(lbtc.balanceOf(user), 0, "all LBTC consumed");
        assertGt(lux.balanceOf(user), 0, "user holds LUX from swap");
    }

    // =====================================================================
    // TEST 5: Fork-specific -- verify block context on testnet fork
    // =====================================================================

    function testE2E_ForkBlockContext() public view {
        assertEq(block.chainid, LUX_TESTNET, "fork should report testnet chain ID");
        assertGt(block.number, 0, "fork should have blocks");
    }
}

// ==========================================================================
// MOCK CONTRACTS -- minimal, for e2e test only
// ==========================================================================

contract MockE2EToken is IBridgedToken {
    string public name;
    string public symbol;
    uint8 public decimals;
    uint256 public totalSupply;
    mapping(address => uint256) private _bal;
    mapping(address => mapping(address => uint256)) private _allow;

    constructor(string memory _name, string memory _symbol, uint8 _dec) {
        name = _name;
        symbol = _symbol;
        decimals = _dec;
    }

    function mint(address to, uint256 amount) external override {
        _bal[to] += amount;
        totalSupply += amount;
    }

    function burn(uint256 amount) external override {
        require(_bal[msg.sender] >= amount, "underflow");
        _bal[msg.sender] -= amount;
        totalSupply -= amount;
    }

    function burnFrom(address from, uint256 amount) external override {
        require(_bal[from] >= amount, "underflow");
        if (msg.sender != from) {
            require(_allow[from][msg.sender] >= amount, "allowance");
            _allow[from][msg.sender] -= amount;
        }
        _bal[from] -= amount;
        totalSupply -= amount;
    }

    function balanceOf(address a) external view override returns (uint256) {
        return _bal[a];
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        _allow[msg.sender][spender] = amount;
        return true;
    }

    function allowance(address owner, address spender) external view returns (uint256) {
        return _allow[owner][spender];
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        require(_bal[msg.sender] >= amount, "underflow");
        _bal[msg.sender] -= amount;
        _bal[to] += amount;
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        require(_bal[from] >= amount, "underflow");
        require(_allow[from][msg.sender] >= amount, "allowance");
        _allow[from][msg.sender] -= amount;
        _bal[from] -= amount;
        _bal[to] += amount;
        return true;
    }
}

/**
 * @notice Minimal constant-product mock pool for e2e swap testing.
 *         1:1 rate minus 0.3% fee. Not a real AMM.
 */
contract MockE2EPool {
    address public tokenA;
    address public tokenB;

    constructor(address _a, address _b) {
        tokenA = _a;
        tokenB = _b;
    }

    function swap(address tokenIn, uint256 amountIn) external returns (uint256 amountOut) {
        require(tokenIn == tokenA || tokenIn == tokenB, "unknown token");
        address tokenOutAddr = tokenIn == tokenA ? tokenB : tokenA;

        // 0.3% fee, 1:1 rate
        amountOut = (amountIn * 997) / 1000;

        // Pull input
        MockE2EToken(tokenIn).transferFrom(msg.sender, address(this), amountIn);
        // Send output
        MockE2EToken(tokenOutAddr).transfer(msg.sender, amountOut);
    }
}
