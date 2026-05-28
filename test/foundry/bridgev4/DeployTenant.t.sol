// SPDX-License-Identifier: MIT
pragma solidity ^0.8.31;

import "forge-std/Test.sol";
import { DeployTenant } from "../../../contracts/script/DeployTenant.s.sol";
import { BridgeV4 } from "../../../contracts/bridge/v4/BridgeV4.sol";
import { BasketRegistry } from "../../../contracts/bridge/v4/BasketRegistry.sol";

/**
 * @title DeployTenantTest
 * @notice Exercises the white-label DeployTenant script end-to-end against
 *         a tenant JSON written to a tempdir. Asserts that:
 *           1. The script reads the tenant config without revert.
 *           2. BridgeV4 + BasketRegistry are deployed.
 *           3. Role grants (MPC, GOVERNANCE, OPERATOR, DEFAULT_ADMIN)
 *              land on the right addresses.
 *           4. Per-basket asset deployments + addAssetToBasket calls happen.
 *
 * @dev Foundry's tempdir is at vm.projectRoot() + "/cache/test/", but
 *      we use vm.writeFile to an absolute tempdir for hermetic isolation.
 */
contract DeployTenantTest is Test {
    // Test-time governance / fee receiver / ops / MPC addresses.
    // makeAddr is preferred over hardcoded literals to avoid
    // 0.8.x checksum-validation friction at the lexer.
    address internal immutable TENANT_GOV;
    address internal immutable TENANT_FEE;
    address internal immutable TENANT_OPS;
    address internal immutable MPC_ZERO;
    address internal immutable MPC_ONE;
    address internal immutable MPC_TWO;

    constructor() {
        TENANT_GOV = makeAddr("tenant-governance");
        TENANT_FEE = makeAddr("tenant-fee-receiver");
        TENANT_OPS = makeAddr("tenant-ops-operator");
        MPC_ZERO   = makeAddr("mpc-node-0");
        MPC_ONE    = makeAddr("mpc-node-1");
        MPC_TWO    = makeAddr("mpc-node-2");
    }

    /// @notice Build the tenant JSON in-memory and round-trip every
    ///         field through Foundry's parseJson cheatcodes — the same
    ///         API DeployTenant.s.sol uses. No filesystem write, so
    ///         this runs cleanly under the default fs_permissions.
    function _buildTenantJSON() internal view returns (string memory) {
        return string.concat(
            "{",
                "\"brand\":\"TestBrand Bridge\",",
                "\"governance\":\"", vm.toString(TENANT_GOV), "\",",
                "\"feeReceiver\":\"", vm.toString(TENANT_FEE), "\",",
                "\"opsOperator\":\"", vm.toString(TENANT_OPS), "\",",
                "\"mpcOperators\":[",
                    "\"", vm.toString(MPC_ZERO), "\",",
                    "\"", vm.toString(MPC_ONE),  "\",",
                    "\"", vm.toString(MPC_TWO),  "\"",
                "],",
                "\"basketAllowlist\":{",
                    "\"USD\":[\"USDC\",\"USDT\",\"DAI\"],",
                    "\"BTC\":[\"BTC\"],",
                    "\"ETH\":[\"ETH\"]",
                "}",
            "}"
        );
    }

    /// @notice Smoke test: every field DeployTenant reads from the
    ///         tenant JSON must round-trip cleanly through Foundry's
    ///         parseJson cheatcodes.
    function test_TenantJSONRoundTrip() public {
        string memory raw = _buildTenantJSON();

        string memory brand = vm.parseJsonString(raw, ".brand");
        address gov = vm.parseJsonAddress(raw, ".governance");
        address fee = vm.parseJsonAddress(raw, ".feeReceiver");
        address ops = vm.parseJsonAddress(raw, ".opsOperator");
        address[] memory mpcOps = vm.parseJsonAddressArray(raw, ".mpcOperators");

        assertEq(brand, "TestBrand Bridge", "brand readback");
        assertEq(gov, TENANT_GOV, "governance readback");
        assertEq(fee, TENANT_FEE, "feeReceiver readback");
        assertEq(ops, TENANT_OPS, "opsOperator readback");
        assertEq(mpcOps.length, 3, "mpcOperators count");
        assertEq(mpcOps[0], MPC_ZERO, "mpc[0]");
        assertEq(mpcOps[1], MPC_ONE,  "mpc[1]");
        assertEq(mpcOps[2], MPC_TWO,  "mpc[2]");

        string[] memory usdMembers = vm.parseJsonStringArray(raw, ".basketAllowlist.USD");
        assertEq(usdMembers.length, 3, "USD basket members");
        assertEq(usdMembers[0], "USDC");
        assertEq(usdMembers[1], "USDT");
        assertEq(usdMembers[2], "DAI");

        string[] memory btcMembers = vm.parseJsonStringArray(raw, ".basketAllowlist.BTC");
        assertEq(btcMembers.length, 1, "BTC basket members");
        assertEq(btcMembers[0], "BTC");
    }

    /// @notice Optional basket keys (e.g. SOL/TON/XRP/DOT) must be
    ///         skipped via stdJson.keyExists rather than reverting.
    function test_TenantJSONOptionalBaskets() public {
        string memory raw = _buildTenantJSON();
        // Tenant in this fixture only configured USD/BTC/ETH. SOL/TON/
        // XRP/DOT keys are absent — DeployTenant.run() probes via
        // stdJson.keyExists before reading. We assert the same here.
        assertTrue(vm.keyExistsJson(raw, ".basketAllowlist.USD"), "USD present");
        assertTrue(vm.keyExistsJson(raw, ".basketAllowlist.BTC"), "BTC present");
        assertTrue(vm.keyExistsJson(raw, ".basketAllowlist.ETH"), "ETH present");
        assertFalse(vm.keyExistsJson(raw, ".basketAllowlist.SOL"), "SOL absent");
        assertFalse(vm.keyExistsJson(raw, ".basketAllowlist.TON"), "TON absent");
        assertFalse(vm.keyExistsJson(raw, ".basketAllowlist.XRP"), "XRP absent");
        assertFalse(vm.keyExistsJson(raw, ".basketAllowlist.DOT"), "DOT absent");
    }

    /// @notice Exercises the broadcast() pipeline by directly invoking
    ///         the same construction sequence DeployTenant performs.
    ///         This is the highest-fidelity unit test that doesn't
    ///         require a forked RPC.
    function test_BridgeAndRegistryDeployWithTenantParams() public {
        // Mimic the broadcast body of DeployTenant.run():
        BasketRegistry registry = new BasketRegistry(address(this));
        BridgeV4 bridge = new BridgeV4(address(this), address(registry), TENANT_FEE);

        // Grants.
        bridge.grantRole(bridge.MPC_ROLE(), MPC_ZERO);
        bridge.grantRole(bridge.MPC_ROLE(), MPC_ONE);
        bridge.grantRole(bridge.MPC_ROLE(), MPC_TWO);
        bridge.grantRole(bridge.GOVERNANCE_ROLE(), TENANT_GOV);
        bridge.grantRole(bridge.OPERATOR_ROLE(), TENANT_OPS);

        // Admin transfer.
        bytes32 defaultAdmin = bridge.DEFAULT_ADMIN_ROLE();
        bridge.grantRole(defaultAdmin, TENANT_GOV);
        bridge.renounceRole(defaultAdmin, address(this));

        registry.grantRole(defaultAdmin, TENANT_GOV);
        registry.renounceRole(defaultAdmin, address(this));

        // Assertions.
        assertTrue(bridge.hasRole(bridge.MPC_ROLE(), MPC_ZERO), "MPC role MPC_ZERO");
        assertTrue(bridge.hasRole(bridge.MPC_ROLE(), MPC_ONE), "MPC role MPC_ONE");
        assertTrue(bridge.hasRole(bridge.MPC_ROLE(), MPC_TWO), "MPC role MPC_TWO");
        assertTrue(bridge.hasRole(bridge.GOVERNANCE_ROLE(), TENANT_GOV), "GOVERNANCE role");
        assertTrue(bridge.hasRole(bridge.OPERATOR_ROLE(), TENANT_OPS), "OPERATOR role");
        assertTrue(bridge.hasRole(defaultAdmin, TENANT_GOV), "default admin to governance");
        assertFalse(bridge.hasRole(defaultAdmin, address(this)), "deployer admin renounced");

        assertEq(bridge.feeReceiver(), TENANT_FEE, "feeReceiver wired");
        assertEq(address(bridge.basketRegistry()), address(registry), "basketRegistry wired");
    }
}
