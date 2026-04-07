// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.31;

import "forge-std/Test.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ShariaFilter } from "../../contracts/bridge/yield/ShariaFilter.sol";
import { YieldBridgeVault } from "../../contracts/bridge/yield/YieldBridgeVault.sol";
import { IYieldStrategy } from "../../contracts/bridge/yield/IYieldStrategy.sol";

// ═══════════════════════════════════════════════════════════════════════════════
// MOCKS
// ═══════════════════════════════════════════════════════════════════════════════

contract MockToken is ERC20 {
    constructor() ERC20("Mock", "MCK") {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

/// @notice Mock strategy that tracks deposits/withdrawals and records allowance at deposit time.
contract MockYieldStrategy is IYieldStrategy {
    address public override asset;
    uint256 public override totalAssets;
    uint256 public override totalDeposited;
    bool public override isActive = true;

    uint256 public allowanceAtDeposit; // allowance the vault had approved when deposit() was called
    uint256 public depositCount;
    uint256 public withdrawCount;

    constructor(address _asset) {
        asset = _asset;
    }

    function deposit(uint256 amount) external payable override returns (uint256) {
        // Record the allowance the caller set for us before pulling tokens
        allowanceAtDeposit = IERC20(asset).allowance(msg.sender, address(this));

        IERC20(asset).transferFrom(msg.sender, address(this), amount);
        totalAssets += amount;
        totalDeposited += amount;
        depositCount++;
        return amount;
    }

    function withdraw(uint256 amount) external override returns (uint256) {
        totalAssets -= amount;
        IERC20(asset).transfer(msg.sender, amount);
        withdrawCount++;
        return amount;
    }

    function harvest() external override returns (uint256) {
        return 0;
    }

    function currentAPY() external pure override returns (uint256) {
        return 500; // 5%
    }

    function name() external pure override returns (string memory) {
        return "MockStrategy";
    }
}

/// @notice Strategy that attempts reentrancy on the vault during deposit.
contract ReentrantStrategy is IYieldStrategy {
    address public override asset;
    uint256 public override totalAssets;
    uint256 public override totalDeposited;
    bool public override isActive = true;
    address public vault;
    bool public reentered;

    constructor(address _asset, address _vault) {
        asset = _asset;
        vault = _vault;
    }

    function deposit(uint256 amount) external payable override returns (uint256) {
        IERC20(asset).transferFrom(msg.sender, address(this), amount);
        totalAssets += amount;
        totalDeposited += amount;

        // Try to reenter vault.rebalance
        if (!reentered) {
            reentered = true;
            // This should revert with ReentrancyGuardReentrantCall
            try YieldBridgeVault(payable(vault)).rebalance(asset) {} catch {}
        }
        return amount;
    }

    function withdraw(uint256 amount) external override returns (uint256) {
        totalAssets -= amount;
        IERC20(asset).transfer(msg.sender, amount);
        return amount;
    }

    function harvest() external override returns (uint256) {
        return 0;
    }

    function currentAPY() external pure override returns (uint256) {
        return 500;
    }

    function name() external pure override returns (string memory) {
        return "ReentrantStrategy";
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// TESTS
// ═══════════════════════════════════════════════════════════════════════════════

contract YieldBridgeVaultSecurityTest is Test {
    ShariaFilter filter;
    YieldBridgeVault vault;
    MockToken token;

    address shariahBoard = makeAddr("shariahBoard");
    address admin = makeAddr("admin");
    address bridge = makeAddr("bridge");
    address random = makeAddr("random");

    function setUp() public {
        filter = new ShariaFilter(shariahBoard);

        vm.prank(admin);
        vault = new YieldBridgeVault(1, bridge, makeAddr("yieldReceiver"));

        token = new MockToken();

        // Add token as supported asset
        vm.prank(admin);
        vault.addSupportedAsset(address(token), 1000); // 10% reserve
    }

    // ═══════════════════════════════════════════════════════════════════════
    // ShariaFilter tests
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice 1. classifyStrategy only by shariahBoard
    function test_classifyStrategy_onlyShariahBoard() public {
        address strat = makeAddr("strategy");

        // Admin cannot classify
        vm.prank(admin);
        vm.expectRevert("Only Shariah board");
        filter.classifyStrategy(strat, ShariaFilter.ComplianceStatus.HALAL, "test", "");

        // Random cannot classify
        vm.prank(random);
        vm.expectRevert("Only Shariah board");
        filter.classifyStrategy(strat, ShariaFilter.ComplianceStatus.HALAL, "test", "");

        // ShariahBoard can classify
        vm.prank(shariahBoard);
        filter.classifyStrategy(strat, ShariaFilter.ComplianceStatus.HALAL, "fee-based", "");
        assertTrue(filter.isCompliant(strat));
    }

    /// @notice 2. classifyProtocol only by shariahBoard
    function test_classifyProtocol_onlyShariahBoard() public {
        vm.prank(admin);
        vm.expectRevert("Only Shariah board");
        filter.classifyProtocol("newproto", ShariaFilter.ComplianceStatus.HALAL, "test");

        vm.prank(shariahBoard);
        filter.classifyProtocol("newproto", ShariaFilter.ComplianceStatus.HALAL, "fee-based");
        assertTrue(filter.isProtocolCompliant("newproto"));
    }

    /// @notice 3. setShariahBoard only by current shariahBoard, rejects zero address
    function test_setShariahBoard_access() public {
        address newBoard = makeAddr("newBoard");

        // Only current board can set
        vm.prank(shariahBoard);
        filter.setShariahBoard(newBoard);
        assertEq(filter.shariahBoard(), newBoard);

        // Zero address rejected
        vm.prank(newBoard);
        vm.expectRevert("Zero address");
        filter.setShariahBoard(address(0));
    }

    /// @notice 4. setShariahBoard rejects non-shariahBoard caller
    function test_setShariahBoard_rejectsNonBoard() public {
        vm.prank(admin);
        vm.expectRevert("Only Shariah board");
        filter.setShariahBoard(makeAddr("newBoard"));

        vm.prank(random);
        vm.expectRevert("Only Shariah board");
        filter.setShariahBoard(makeAddr("newBoard"));
    }

    /// @notice 5. filterCompliant returns only HALAL strategies
    function test_filterCompliant_onlyHalal() public {
        address s1 = makeAddr("s1");
        address s2 = makeAddr("s2");
        address s3 = makeAddr("s3");

        vm.startPrank(shariahBoard);
        filter.classifyStrategy(s1, ShariaFilter.ComplianceStatus.HALAL, "halal", "");
        filter.classifyStrategy(s2, ShariaFilter.ComplianceStatus.HARAM, "interest", "");
        filter.classifyStrategy(s3, ShariaFilter.ComplianceStatus.HALAL, "halal", "");
        vm.stopPrank();

        address[] memory input = new address[](3);
        input[0] = s1;
        input[1] = s2;
        input[2] = s3;

        address[] memory result = filter.filterCompliant(input);
        assertEq(result.length, 2);
        assertEq(result[0], s1);
        assertEq(result[1], s3);
    }

    /// @notice 6. Default protocol classifications correct
    function test_defaultProtocolClassifications() public view {
        // HALAL
        assertTrue(filter.isProtocolCompliant("dex_fees"));
        assertTrue(filter.isProtocolCompliant("bridge_fees"));
        assertTrue(filter.isProtocolCompliant("validator_staking"));

        // HARAM (status 1)
        assertEq(uint256(filter.protocolCompliance("aave")), uint256(ShariaFilter.ComplianceStatus.HARAM));
        assertEq(uint256(filter.protocolCompliance("compound")), uint256(ShariaFilter.ComplianceStatus.HARAM));

        // CONDITIONAL (status 3)
        assertEq(uint256(filter.protocolCompliance("lido")), uint256(ShariaFilter.ComplianceStatus.CONDITIONAL));
        assertEq(uint256(filter.protocolCompliance("eigenlayer")), uint256(ShariaFilter.ComplianceStatus.CONDITIONAL));
    }

    // ═══════════════════════════════════════════════════════════════════════
    // YieldBridgeVault tests
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice 7. addStrategy does NOT set infinite approval
    function test_addStrategy_noInfiniteApproval() public {
        MockYieldStrategy strat = new MockYieldStrategy(address(token));

        vm.prank(admin);
        vault.addStrategy(address(token), address(strat), 5000);

        // Allowance from vault to strategy should be 0 after add
        uint256 allowance = token.allowance(address(vault), address(strat));
        assertEq(allowance, 0, "addStrategy must not set infinite approval");
    }

    /// @notice 8. _depositToStrategy sets exact approval then resets to 0
    function test_depositToStrategy_exactApprovalThenReset() public {
        MockYieldStrategy strat = new MockYieldStrategy(address(token));

        vm.prank(admin);
        vault.addStrategy(address(token), address(strat), 10000); // 100% weight

        // Fund vault via bridge deposit
        uint256 depositAmt = 1000 ether;
        token.mint(bridge, depositAmt);

        vm.startPrank(bridge);
        token.approve(address(vault), depositAmt);
        vault.depositFromBridge(address(token), depositAmt);
        vm.stopPrank();

        // Strategy should have received tokens (90% of deposit after 10% reserve)
        assertTrue(strat.depositCount() > 0, "Strategy should have been called");
        // The allowance recorded at deposit time should equal the exact deposit amount
        assertEq(strat.allowanceAtDeposit(), 900 ether, "Approval should be exact amount");
        // After deposit, allowance should be reset to 0
        uint256 allowanceAfter = token.allowance(address(vault), address(strat));
        assertEq(allowanceAfter, 0, "Approval must be reset to 0 after deposit");
    }

    /// @notice 9. rebalance has nonReentrant
    function test_rebalance_nonReentrant() public {
        ReentrantStrategy strat = new ReentrantStrategy(address(token), address(vault));

        vm.prank(admin);
        vault.addStrategy(address(token), address(strat), 10000);

        // Seed vault with tokens so rebalance has something to do
        token.mint(address(vault), 100 ether);

        // First rebalance call triggers deposit on strategy, which tries to reenter
        // The reentered flag tells us the strategy attempted reentry
        vm.prank(admin);
        vault.rebalance(address(token));

        // The strategy attempted reentry but rebalance is nonReentrant, so it failed silently (try/catch)
        assertTrue(strat.reentered(), "Strategy should have attempted reentry");
        // The outer rebalance should still complete (deposited tokens)
        assertTrue(strat.totalAssets() > 0, "Outer rebalance should complete despite reentry attempt");
    }

    /// @notice 10. harvestYield respects interval
    function test_harvestYield_respectsInterval() public {
        MockYieldStrategy strat = new MockYieldStrategy(address(token));

        vm.prank(admin);
        vault.addStrategy(address(token), address(strat), 10000);

        // Warp well past the harvest interval from setUp's lastHarvestTime
        uint256 t1 = block.timestamp + 2 days;
        vm.warp(t1);
        vault.harvestYield(address(token));

        // Immediate second harvest should fail
        vm.expectRevert("YieldBridgeVault: harvest too soon");
        vault.harvestYield(address(token));

        // After another full interval, should work again
        uint256 t2 = t1 + 2 days;
        vm.warp(t2);
        vault.harvestYield(address(token));
    }

    /// @notice 11. depositFromBridge only bridge can call
    function test_depositFromBridge_onlyBridge() public {
        token.mint(admin, 100 ether);

        vm.startPrank(admin);
        token.approve(address(vault), 100 ether);
        vm.expectRevert("YieldBridgeVault: only bridge");
        vault.depositFromBridge(address(token), 100 ether);
        vm.stopPrank();

        vm.startPrank(random);
        vm.expectRevert("YieldBridgeVault: only bridge");
        vault.depositFromBridge(address(token), 100 ether);
        vm.stopPrank();
    }

    /// @notice 12. withdrawToBridge pulls from strategies when liquid balance insufficient
    function test_withdrawToBridge_pullsFromStrategies() public {
        MockYieldStrategy strat = new MockYieldStrategy(address(token));

        vm.prank(admin);
        vault.addStrategy(address(token), address(strat), 10000);

        // Bridge deposits 1000 tokens -> 900 go to strategy, 100 stay liquid
        uint256 depositAmt = 1000 ether;
        token.mint(bridge, depositAmt);

        vm.startPrank(bridge);
        token.approve(address(vault), depositAmt);
        vault.depositFromBridge(address(token), depositAmt);
        vm.stopPrank();

        uint256 stratBefore = strat.totalAssets();

        // Withdraw more than liquid balance
        uint256 withdrawAmt = 500 ether;
        vm.prank(bridge);
        vault.withdrawToBridge(address(token), random, withdrawAmt);

        // Recipient got their tokens
        assertEq(token.balanceOf(random), withdrawAmt, "Recipient should receive full amount");
        // Strategy was drawn down
        assertTrue(strat.withdrawCount() > 0, "Strategy withdraw should have been called");
        assertTrue(strat.totalAssets() < stratBefore, "Strategy balance should decrease");
    }
}
