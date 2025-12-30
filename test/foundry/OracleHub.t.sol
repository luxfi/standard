// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.31;

import "forge-std/Test.sol";
import {OracleHub} from "../../contracts/oracle/OracleHub.sol";
import {IOracleWriter} from "../../contracts/oracle/interfaces/IOracleWriter.sol";
import {IOracle} from "../../contracts/oracle/IOracle.sol";

/**
 * @title OracleHub Test Suite
 * @notice Tests for OracleHub price oracle used by oracle-keeper
 *
 * This test validates the Solidity contract works correctly with the
 * Go-based oracle-keeper from github.com/luxfi/dex/cmd/oracle-keeper
 */
contract OracleHubTest is Test {
    // ════════════════════════════════════════════════════════════════
    // Contracts
    // ════════════════════════════════════════════════════════════════

    OracleHub public hub;

    // ════════════════════════════════════════════════════════════════
    // Test Accounts
    // ════════════════════════════════════════════════════════════════

    address public admin = address(this);
    address public keeper = makeAddr("keeper");
    address public validator1 = makeAddr("validator1");
    address public validator2 = makeAddr("validator2");
    address public validator3 = makeAddr("validator3");
    address public reader = makeAddr("reader");

    // Test assets
    address public weth = address(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    address public wbtc = address(0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599);
    address public lusd = address(0x5f98805A4E8be255a32880FDeC7F6728C6568bA0);

    // ════════════════════════════════════════════════════════════════
    // Setup
    // ════════════════════════════════════════════════════════════════

    function setUp() public {
        hub = new OracleHub();

        // Grant keeper the WRITER_ROLE
        bytes32 writerRole = hub.WRITER_ROLE();
        hub.grantRole(writerRole, keeper);

        // Grant validators the VALIDATOR_ROLE
        bytes32 validatorRole = hub.VALIDATOR_ROLE();
        hub.grantRole(validatorRole, validator1);
        hub.grantRole(validatorRole, validator2);
        hub.grantRole(validatorRole, validator3);
    }

    // ════════════════════════════════════════════════════════════════
    // Writer Tests (matches oracle-keeper Go code)
    // ════════════════════════════════════════════════════════════════

    function test_WritePrice_Single() public {
        uint256 ethPrice = 2500e18; // $2500 USD
        uint256 timestamp = block.timestamp;

        vm.prank(keeper);
        hub.writePrice(weth, ethPrice, timestamp);

        (uint256 price, uint256 ts) = hub.getPrice(weth);
        assertEq(price, ethPrice, "Price mismatch");
        assertEq(ts, timestamp, "Timestamp mismatch");
    }

    function test_WritePrices_Batch() public {
        // This matches the Go code's WritePrices batch operation
        IOracleWriter.PriceUpdate[] memory updates = new IOracleWriter.PriceUpdate[](3);

        updates[0] = IOracleWriter.PriceUpdate({
            asset: weth,
            price: 2500e18,
            timestamp: block.timestamp,
            confidence: 9500,
            source: keccak256("dex-aggregator")
        });

        updates[1] = IOracleWriter.PriceUpdate({
            asset: wbtc,
            price: 45000e18,
            timestamp: block.timestamp,
            confidence: 9800,
            source: keccak256("dex-aggregator")
        });

        updates[2] = IOracleWriter.PriceUpdate({
            asset: lusd,
            price: 1e18,
            timestamp: block.timestamp,
            confidence: 10000,
            source: keccak256("dex-aggregator")
        });

        vm.prank(keeper);
        hub.writePrices(updates);

        // Verify all prices written
        (uint256 ethPrice,) = hub.getPrice(weth);
        assertEq(ethPrice, 2500e18);

        (uint256 btcPrice,) = hub.getPrice(wbtc);
        assertEq(btcPrice, 45000e18);

        (uint256 usdPrice,) = hub.getPrice(lusd);
        assertEq(usdPrice, 1e18);
    }

    function test_WritePrice_RevertUnauthorized() public {
        vm.prank(reader);
        vm.expectRevert();
        hub.writePrice(weth, 2500e18, block.timestamp);
    }

    function test_WritePrice_RevertPaused() public {
        // Admin pauses the asset
        hub.setPaused(weth, true);

        vm.prank(keeper);
        vm.expectRevert(abi.encodeWithSelector(OracleHub.AssetPaused.selector, weth));
        hub.writePrice(weth, 2500e18, block.timestamp);
    }

    function test_WritePrice_CircuitBreaker() public {
        // Set initial price
        vm.prank(keeper);
        hub.writePrice(weth, 2500e18, block.timestamp);

        // Try to write price with >10% change (default maxChangeBps)
        vm.prank(keeper);
        vm.expectRevert(abi.encodeWithSelector(
            OracleHub.PriceChangeExceeded.selector,
            weth,
            2000 // 20% change in bps
        ));
        hub.writePrice(weth, 3000e18, block.timestamp);
    }

    // ════════════════════════════════════════════════════════════════
    // Reader Tests (used by DeFi protocols)
    // ════════════════════════════════════════════════════════════════

    function test_GetPrice_Fresh() public {
        vm.prank(keeper);
        hub.writePrice(weth, 2500e18, block.timestamp);

        uint256 price = hub.getPriceIfFresh(weth, 1 hours);
        assertEq(price, 2500e18);
    }

    function test_GetPrice_RevertStale() public {
        vm.prank(keeper);
        hub.writePrice(weth, 2500e18, block.timestamp);

        // Fast forward 2 hours
        vm.warp(block.timestamp + 2 hours);

        vm.expectRevert(abi.encodeWithSelector(OracleHub.StalePrice.selector, weth, 2 hours));
        hub.getPriceIfFresh(weth, 1 hours);
    }

    function test_GetPriceForPerps_Spread() public {
        vm.prank(keeper);
        IOracleWriter.PriceUpdate[] memory updates = new IOracleWriter.PriceUpdate[](1);
        updates[0] = IOracleWriter.PriceUpdate({
            asset: weth,
            price: 2500e18,
            timestamp: block.timestamp,
            confidence: 9500, // 95% confidence = 5bp spread
            source: keccak256("dex-aggregator")
        });
        hub.writePrices(updates);

        uint256 maxPrice = hub.getPriceForPerps(weth, true);
        uint256 minPrice = hub.getPriceForPerps(weth, false);

        // Max should be slightly higher, min slightly lower
        assertGt(maxPrice, minPrice);
        assertGt(maxPrice, 2500e18);
        assertLt(minPrice, 2500e18);
    }

    function test_BatchGetPrices() public {
        // Write prices
        vm.startPrank(keeper);
        hub.writePrice(weth, 2500e18, block.timestamp);
        hub.writePrice(wbtc, 45000e18, block.timestamp);
        vm.stopPrank();

        // Batch read
        address[] memory assets = new address[](2);
        assets[0] = weth;
        assets[1] = wbtc;

        (uint256[] memory prices, uint256[] memory timestamps) = hub.getPrices(assets);

        assertEq(prices[0], 2500e18);
        assertEq(prices[1], 45000e18);
        assertEq(timestamps[0], block.timestamp);
        assertEq(timestamps[1], block.timestamp);
    }

    // ════════════════════════════════════════════════════════════════
    // ABI Compatibility Tests
    // ════════════════════════════════════════════════════════════════

    /// @notice Verify the ABI matches what oracle-keeper expects
    function test_ABICompatibility_WritePrice() public {
        // Simulate exact calldata from Go writer
        bytes memory calldata_ = abi.encodeWithSelector(
            IOracleWriter.writePrice.selector,
            weth,           // asset
            2500e18,        // price
            block.timestamp // timestamp
        );

        vm.prank(keeper);
        (bool success,) = address(hub).call(calldata_);
        assertTrue(success, "writePrice call failed");
    }

    /// @notice Verify batch ABI matches
    function test_ABICompatibility_WritePrices() public {
        IOracleWriter.PriceUpdate[] memory updates = new IOracleWriter.PriceUpdate[](1);
        updates[0] = IOracleWriter.PriceUpdate({
            asset: weth,
            price: 2500e18,
            timestamp: block.timestamp,
            confidence: 10000,
            source: keccak256("dex-aggregator")
        });

        bytes memory calldata_ = abi.encodeWithSelector(
            IOracleWriter.writePrices.selector,
            updates
        );

        vm.prank(keeper);
        (bool success,) = address(hub).call(calldata_);
        assertTrue(success, "writePrices call failed");
    }

    // ════════════════════════════════════════════════════════════════
    // Admin Tests
    // ════════════════════════════════════════════════════════════════

    function test_AddWriter() public {
        address newKeeper = makeAddr("newKeeper");

        hub.addWriter(newKeeper);

        assertTrue(hub.isWriter(newKeeper));
    }

    function test_AddValidator() public {
        address newValidator = makeAddr("newValidator");

        hub.addValidator(newValidator);

        assertTrue(hub.isValidator(newValidator));
    }

    function test_SetMaxStaleness() public {
        hub.setMaxStaleness(30 minutes);
        assertEq(hub.maxStaleness(), 30 minutes);
    }

    function test_SetMaxChangeBps() public {
        hub.setMaxChangeBps(500); // 5%
        assertEq(hub.maxChangeBps(), 500);
    }

    // ════════════════════════════════════════════════════════════════
    // Integration Scenario
    // ════════════════════════════════════════════════════════════════

    /// @notice Simulates oracle-keeper writing prices every 30s
    function test_KeeperScenario() public {
        // Keeper writes initial prices
        vm.prank(keeper);
        IOracleWriter.PriceUpdate[] memory updates = new IOracleWriter.PriceUpdate[](2);
        updates[0] = IOracleWriter.PriceUpdate({
            asset: weth,
            price: 2500e18,
            timestamp: block.timestamp,
            confidence: 9500,
            source: keccak256("dex-aggregator")
        });
        updates[1] = IOracleWriter.PriceUpdate({
            asset: wbtc,
            price: 45000e18,
            timestamp: block.timestamp,
            confidence: 9800,
            source: keccak256("dex-aggregator")
        });
        hub.writePrices(updates);

        // 30 seconds later, price changes by 0.5%
        vm.warp(block.timestamp + 30);

        vm.prank(keeper);
        updates[0].price = 2512.5e18; // 0.5% increase
        updates[0].timestamp = block.timestamp;
        updates[1].price = 45225e18; // 0.5% increase
        updates[1].timestamp = block.timestamp;
        hub.writePrices(updates);

        // Verify updated prices
        (uint256 ethPrice,) = hub.getPrice(weth);
        assertEq(ethPrice, 2512.5e18);

        // Protocol reads price (no staleness with 1 hour window)
        uint256 price = hub.getPriceIfFresh(weth, 1 hours);
        assertEq(price, 2512.5e18);
    }
}
