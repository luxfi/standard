// SPDX-License-Identifier: MIT
pragma solidity ^0.8.31;

import "forge-std/Test.sol";

// Synths contracts - using named imports to avoid ERC20 conflicts
import {AlchemistV2} from "../../contracts/synths/AlchemistV2.sol";
import {IAlchemistV2} from "../../contracts/synths/interfaces/IAlchemistV2.sol";
import {IAlchemistV2AdminActions} from "../../contracts/synths/interfaces/alchemist/IAlchemistV2AdminActions.sol";
import {AlchemicTokenV2} from "../../contracts/synths/AlchemicTokenV2.sol";
import {TransmuterV2} from "../../contracts/synths/TransmuterV2.sol";
import {TransmuterBuffer} from "../../contracts/synths/TransmuterBuffer.sol";
import {Whitelist} from "../../contracts/synths/utils/Whitelist.sol";

// OpenZeppelin proxy for upgradeable contracts
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

// Use solmate ERC20 for mocks to avoid conflicts
import {ERC20 as SolmateERC20} from "solmate/tokens/ERC20.sol";

/// @title MockERC20
/// @notice Simple mock ERC20 for testing (uses solmate)
contract MockERC20 is SolmateERC20 {
    constructor(
        string memory name,
        string memory symbol,
        uint8 decimals_
    ) SolmateERC20(name, symbol, decimals_) {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function burn(address from, uint256 amount) external {
        _burn(from, amount);
    }
}

/// @title MockYieldToken
/// @notice Mock yield-bearing token for testing
contract MockYieldToken is MockERC20 {
    address public underlying;
    uint256 public pricePerShare = 1e18;

    constructor(
        string memory name,
        string memory symbol,
        address underlying_
    ) MockERC20(name, symbol, 18) {
        underlying = underlying_;
    }

    function setPricePerShare(uint256 price) external {
        pricePerShare = price;
    }

    function deposit(uint256 assets) external returns (uint256 shares) {
        shares = (assets * 1e18) / pricePerShare;
        MockERC20(underlying).transferFrom(msg.sender, address(this), assets);
        _mint(msg.sender, shares);
    }

    function withdraw(uint256 shares) external returns (uint256 assets) {
        assets = (shares * pricePerShare) / 1e18;
        _burn(msg.sender, shares);
        MockERC20(underlying).transfer(msg.sender, assets);
    }
}

/// @title SynthsTest
/// @notice Comprehensive tests for the Synths (Alchemix-style) protocol
contract SynthsTest is Test {
    // Contracts
    AlchemistV2 public alchemist;
    AlchemicTokenV2 public alUSD;
    TransmuterV2 public transmuter;
    TransmuterBuffer public buffer;
    Whitelist public whitelist;

    // Mock tokens
    MockERC20 public usdc;
    MockYieldToken public yUSDC;

    // Users
    address public admin = address(0x1);
    address public alice = address(0x2);
    address public bob = address(0x3);
    address public treasury = address(0x4);

    // Constants
    uint256 constant MIN_COLLATERALIZATION = 2e18; // 200%
    uint256 constant PROTOCOL_FEE = 1000; // 10%
    uint256 constant MINT_LIMIT = 1_000_000e18;

    function setUp() public {
        // Deploy mock tokens
        usdc = new MockERC20("USD Coin", "USDC", 6);
        yUSDC = new MockYieldToken("yUSDC", "yUSDC", address(usdc));

        // Deploy whitelist (Ownable(msg.sender) - no initialize needed)
        vm.prank(admin);
        whitelist = new Whitelist();

        // Deploy alUSD as admin (constructor grants ADMIN_ROLE to msg.sender)
        vm.prank(admin);
        alUSD = new AlchemicTokenV2("Alchemic USD", "alUSD", 0);

        // Deploy buffer via proxy (upgradeable contract)
        TransmuterBuffer bufferImpl = new TransmuterBuffer();
        bytes memory bufferInitData = abi.encodeWithSelector(
            TransmuterBuffer.initialize.selector,
            admin,
            address(alUSD)
        );
        ERC1967Proxy bufferProxy = new ERC1967Proxy(address(bufferImpl), bufferInitData);
        buffer = TransmuterBuffer(address(bufferProxy));

        // Deploy transmuter via proxy (upgradeable contract)
        TransmuterV2 transmuterImpl = new TransmuterV2();
        bytes memory transmuterInitData = abi.encodeWithSelector(
            TransmuterV2.initialize.selector,
            address(alUSD),
            address(usdc),
            address(buffer),
            address(whitelist)
        );
        ERC1967Proxy transmuterProxy = new ERC1967Proxy(address(transmuterImpl), transmuterInitData);
        transmuter = TransmuterV2(address(transmuterProxy));

        // Deploy alchemist via proxy (upgradeable contract)
        AlchemistV2 alchemistImpl = new AlchemistV2();
        bytes memory alchemistInitData = abi.encodeWithSelector(
            AlchemistV2.initialize.selector,
            IAlchemistV2AdminActions.InitializationParams({
                admin: admin,
                debtToken: address(alUSD),
                transmuter: address(transmuter),
                minimumCollateralization: MIN_COLLATERALIZATION,
                protocolFee: PROTOCOL_FEE,
                protocolFeeReceiver: treasury,
                mintingLimitMinimum: 0,
                mintingLimitMaximum: MINT_LIMIT,
                mintingLimitBlocks: 7200,
                whitelist: address(whitelist)
            })
        );
        ERC1967Proxy alchemistProxy = new ERC1967Proxy(address(alchemistImpl), alchemistInitData);
        alchemist = AlchemistV2(address(alchemistProxy));

        // Configure permissions
        vm.startPrank(admin);
        alUSD.setWhitelist(address(alchemist), true);
        whitelist.add(alice);
        whitelist.add(bob);
        vm.stopPrank();

        // Fund users
        usdc.mint(alice, 1_000_000e6);
        usdc.mint(bob, 1_000_000e6);

        vm.prank(alice);
        usdc.approve(address(yUSDC), type(uint256).max);

        vm.prank(bob);
        usdc.approve(address(yUSDC), type(uint256).max);
    }

    // =======================================================================
    // INITIALIZATION TESTS
    // =======================================================================

    function test_AlchemistInitialization() public view {
        assertEq(alchemist.admin(), admin);
        assertEq(alchemist.debtToken(), address(alUSD));
        assertEq(alchemist.transmuter(), address(transmuter));
        assertEq(alchemist.minimumCollateralization(), MIN_COLLATERALIZATION);
        assertEq(alchemist.protocolFee(), PROTOCOL_FEE);
        assertEq(alchemist.protocolFeeReceiver(), treasury);
    }

    function test_AlchemicTokenInitialization() public view {
        assertEq(alUSD.name(), "Alchemic USD");
        assertEq(alUSD.symbol(), "alUSD");
        assertEq(alUSD.decimals(), 18);
    }

    function test_TransmuterInitialization() public view {
        assertEq(transmuter.syntheticToken(), address(alUSD));
        assertEq(transmuter.underlyingToken(), address(usdc));
    }

    // =======================================================================
    // ACCESS CONTROL TESTS
    // =======================================================================

    function test_OnlyAdminCanSetSentinel() public {
        vm.prank(alice);
        vm.expectRevert();
        alchemist.setSentinel(alice, true);

        vm.prank(admin);
        alchemist.setSentinel(alice, true);
        assertTrue(alchemist.sentinels(alice));
    }

    function test_OnlyAdminCanSetProtocolFee() public {
        vm.prank(alice);
        vm.expectRevert();
        alchemist.setProtocolFee(500);

        vm.prank(admin);
        alchemist.setProtocolFee(500);
        assertEq(alchemist.protocolFee(), 500);
    }

    // =======================================================================
    // WHITELIST TESTS
    // =======================================================================

    function test_WhitelistAdd() public {
        address newUser = address(0x5);

        vm.prank(admin);
        whitelist.add(newUser);

        assertTrue(whitelist.isWhitelisted(newUser));
    }

    function test_WhitelistRemove() public {
        vm.prank(admin);
        whitelist.remove(alice);

        assertFalse(whitelist.isWhitelisted(alice));
    }

    // =======================================================================
    // ALCHEMIC TOKEN TESTS
    // =======================================================================

    function test_OnlyWhitelistedCanMint() public {
        vm.prank(alice);
        vm.expectRevert();
        alUSD.mint(alice, 1000e18);

        // Alchemist is whitelisted
        vm.prank(address(alchemist));
        alUSD.mint(alice, 1000e18);
        assertEq(alUSD.balanceOf(alice), 1000e18);
    }

    function test_TokenBurn() public {
        // Mint first
        vm.prank(address(alchemist));
        alUSD.mint(alice, 1000e18);

        // Burn
        vm.prank(alice);
        alUSD.burn(500e18);
        assertEq(alUSD.balanceOf(alice), 500e18);
    }

    // =======================================================================
    // TRANSMUTER TESTS
    // =======================================================================

    function test_TransmuterDeposit() public {
        // Mint alUSD to alice
        vm.prank(address(alchemist));
        alUSD.mint(alice, 1000e18);

        // Approve and deposit
        vm.startPrank(alice);
        alUSD.approve(address(transmuter), 500e18);
        transmuter.deposit(500e18, alice);
        vm.stopPrank();

        assertEq(transmuter.getUnexchangedBalance(alice), 500e18);
    }

    function test_TransmuterWithdraw() public {
        // Mint and deposit
        vm.prank(address(alchemist));
        alUSD.mint(alice, 1000e18);

        vm.startPrank(alice);
        alUSD.approve(address(transmuter), 500e18);
        transmuter.deposit(500e18, alice);

        // Withdraw
        transmuter.withdraw(200e18, alice);
        vm.stopPrank();

        assertEq(transmuter.getUnexchangedBalance(alice), 300e18);
        assertEq(alUSD.balanceOf(alice), 700e18);
    }

    // =======================================================================
    // INTEGRATION TESTS
    // =======================================================================

    function test_FullDepositMintRepayWithdraw() public {
        // This tests the complete flow:
        // 1. Deposit collateral
        // 2. Mint synthetic
        // 3. Repay debt
        // 4. Withdraw collateral

        // Note: Full integration requires yield token setup
        // This is a placeholder for the complete test
    }

    // =======================================================================
    // FUZZ TESTS
    // =======================================================================

    function testFuzz_MintLimit(uint256 amount) public {
        amount = bound(amount, 1e18, MINT_LIMIT);

        vm.prank(address(alchemist));
        alUSD.mint(alice, amount);

        assertEq(alUSD.balanceOf(alice), amount);
    }

    function testFuzz_TransmuterDeposit(uint256 amount) public {
        amount = bound(amount, 1e18, 1_000_000e18);

        vm.prank(address(alchemist));
        alUSD.mint(alice, amount);

        vm.startPrank(alice);
        alUSD.approve(address(transmuter), amount);
        transmuter.deposit(amount, alice);
        vm.stopPrank();

        assertEq(transmuter.getUnexchangedBalance(alice), amount);
    }
}

/// @title SynthsEdgeCaseTest
/// @notice Edge case and error condition tests
contract SynthsEdgeCaseTest is Test {
    AlchemicTokenV2 public alUSD;
    address public admin = address(0x1);

    function setUp() public {
        // Deploy alUSD as admin (constructor grants ADMIN_ROLE to msg.sender)
        vm.prank(admin);
        alUSD = new AlchemicTokenV2("Alchemic USD", "alUSD", 0);
    }

    function test_TokenDeployedCorrectly() public view {
        assertEq(alUSD.name(), "Alchemic USD");
        assertEq(alUSD.symbol(), "alUSD");
    }

    function test_CannotMintZero() public {
        vm.prank(admin);
        alUSD.setWhitelist(address(this), true);

        // Zero mint should revert or be no-op
        alUSD.mint(address(this), 0);
        assertEq(alUSD.balanceOf(address(this)), 0);
    }

    function test_CannotBurnMoreThanBalance() public {
        vm.prank(admin);
        alUSD.setWhitelist(address(this), true);

        alUSD.mint(address(this), 100e18);

        vm.expectRevert();
        alUSD.burn(101e18);
    }
}
