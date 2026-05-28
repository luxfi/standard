// SPDX-License-Identifier: BSD-3-Clause
// Copyright (c) 2026 Lux Industries Inc.
pragma solidity ^0.8.31;

import { Script, console } from "forge-std/Script.sol";
import { stdJson } from "forge-std/StdJson.sol";

import { BridgeV4 } from "../bridge/v4/BridgeV4.sol";
import { BasketRegistry } from "../bridge/v4/BasketRegistry.sol";

// Bridged collateral. Tenants opt into specific assets via the
// tenant JSON's "basketAllowlist" map. Each entry the script deploys
// is one of these — the contracts themselves carry no tenant-specific
// state (they're brand-neutral LRC20B wrappers), so they're safe to
// deploy across every tenant.
import { BridgedUSDC } from "../bridge/collateral/USDC.sol";
import { BridgedUSDT } from "../bridge/collateral/USDT.sol";
import { BridgedDAI } from "../bridge/collateral/DAI.sol";
import { BridgedETH } from "../bridge/collateral/ETH.sol";
import { BridgedBTC } from "../bridge/collateral/BTC.sol";
import { BridgedNativeSOL } from "../bridge/collateral/NativeSOL.sol";
import { BridgedNativeTON } from "../bridge/collateral/NativeTON.sol";
import { BridgedNativeXRP } from "../bridge/collateral/NativeXRP.sol";
import { BridgedNativeDOT } from "../bridge/collateral/NativeDOT.sol";

/**
 * @title DeployTenant
 * @author Lux Industries
 * @notice White-label tenant deployment script — wraps the BridgeV4 + BasketRegistry
 *         deploy with a per-tenant config read from JSON.
 *
 * @dev Usage:
 *
 *   TENANT_FILE=script/tenants/lux.json \
 *   LUX_PRIVATE_KEY=0x... \
 *   forge script contracts/script/DeployTenant.s.sol \
 *     --rpc-url <tenant-rpc> --broadcast --legacy -vvv
 *
 * The script reads the JSON tenant config, deploys the bridged collateral
 * tokens the tenant opted into via `basketAllowlist`, deploys
 * BasketRegistry + BridgeV4 wired to the tenant's governance + fee
 * receiver, and prints a deployment manifest at the end.
 *
 * Brand separation: the script itself ships no tenant-specific
 * strings. The same script runs for every tenant; the only thing
 * that changes is the JSON file at $TENANT_FILE.
 *
 * Schema of $TENANT_FILE — see contracts/script/tenants/_example.json
 * for the canonical example. Required fields:
 *   .brand           — string, human-readable brand label (audit log only)
 *   .governance      — address, grantee of GOVERNANCE_ROLE on BridgeV4
 *   .feeReceiver     — address, BridgeV4 feeReceiver
 *   .basketAllowlist — map of basket name → array of asset symbols
 *                      (subset of {USDC,USDT,DAI,ETH,BTC,SOL,TON,XRP,DOT})
 *   .mpcOperators    — array of addresses, granted MPC_ROLE
 *   .opsOperator     — address, granted OPERATOR_ROLE on BridgeV4
 */
contract DeployTenant is Script {
    using stdJson for string;

    /// @notice Subset of asset symbols the script knows how to deploy.
    ///         New collateral classes need a one-line addition in
    ///         _deployAsset() below.
    bytes32 private constant USDC_HASH = keccak256("USDC");
    bytes32 private constant USDT_HASH = keccak256("USDT");
    bytes32 private constant DAI_HASH  = keccak256("DAI");
    bytes32 private constant ETH_HASH  = keccak256("ETH");
    bytes32 private constant BTC_HASH  = keccak256("BTC");
    bytes32 private constant SOL_HASH  = keccak256("SOL");
    bytes32 private constant TON_HASH  = keccak256("TON");
    bytes32 private constant XRP_HASH  = keccak256("XRP");
    bytes32 private constant DOT_HASH  = keccak256("DOT");

    /// @notice Mapping basket symbol → BasketRegistry.BasketClass enum.
    ///         Pulled from the on-chain enum order so script + contract
    ///         stay in lockstep.
    function _basketClassOf(string memory symbol) private pure returns (BasketRegistry.BasketClass) {
        bytes32 h = keccak256(bytes(symbol));
        if (h == keccak256("USD")) return BasketRegistry.BasketClass.USD;
        if (h == keccak256("BTC")) return BasketRegistry.BasketClass.BTC;
        if (h == keccak256("ETH")) return BasketRegistry.BasketClass.ETH;
        if (h == keccak256("SOL")) return BasketRegistry.BasketClass.SOL;
        if (h == keccak256("TON")) return BasketRegistry.BasketClass.TON;
        if (h == keccak256("XRP")) return BasketRegistry.BasketClass.XRP;
        if (h == keccak256("DOT")) return BasketRegistry.BasketClass.DOT;
        if (h == keccak256("LUX")) return BasketRegistry.BasketClass.LUX;
        revert("DeployTenant: unknown basket symbol");
    }

    function _deployAsset(string memory symbol) private returns (address) {
        bytes32 h = keccak256(bytes(symbol));
        if (h == USDC_HASH) return address(new BridgedUSDC());
        if (h == USDT_HASH) return address(new BridgedUSDT());
        if (h == DAI_HASH)  return address(new BridgedDAI());
        if (h == ETH_HASH)  return address(new BridgedETH());
        if (h == BTC_HASH)  return address(new BridgedBTC());
        if (h == SOL_HASH)  return address(new BridgedNativeSOL());
        if (h == TON_HASH)  return address(new BridgedNativeTON());
        if (h == XRP_HASH)  return address(new BridgedNativeXRP());
        if (h == DOT_HASH)  return address(new BridgedNativeDOT());
        revert("DeployTenant: unknown asset symbol");
    }

    function run() external {
        // ─── 1. Read tenant config ────────────────────────────────────────
        string memory tenantFile = vm.envString("TENANT_FILE");
        string memory raw = vm.readFile(tenantFile);

        string memory brand     = raw.readString(".brand");
        address governance      = raw.readAddress(".governance");
        address feeReceiver     = raw.readAddress(".feeReceiver");
        address opsOperator     = raw.readAddress(".opsOperator");
        address[] memory mpcOps = raw.readAddressArray(".mpcOperators");

        require(governance  != address(0), "DeployTenant: zero governance");
        require(feeReceiver != address(0), "DeployTenant: zero feeReceiver");
        require(opsOperator != address(0), "DeployTenant: zero opsOperator");
        require(mpcOps.length > 0,         "DeployTenant: empty mpcOperators");

        // Baskets are USD/BTC/ETH/SOL/TON/XRP/DOT (LUX is native, reserved).
        string[] memory basketSymbols = new string[](7);
        basketSymbols[0] = "USD";
        basketSymbols[1] = "BTC";
        basketSymbols[2] = "ETH";
        basketSymbols[3] = "SOL";
        basketSymbols[4] = "TON";
        basketSymbols[5] = "XRP";
        basketSymbols[6] = "DOT";

        // ─── 2. Broadcast deployment ──────────────────────────────────────
        uint256 deployerKey = vm.envUint("LUX_PRIVATE_KEY");
        address deployer = vm.addr(deployerKey);

        console.log("");
        console.log("=== DeployTenant ===");
        console.log("brand        ", brand);
        console.log("chainId      ", block.chainid);
        console.log("deployer     ", deployer);
        console.log("governance   ", governance);
        console.log("feeReceiver  ", feeReceiver);
        console.log("opsOperator  ", opsOperator);
        console.log("mpcOps count ", mpcOps.length);
        console.log("");

        vm.startBroadcast(deployerKey);

        // 2a. BasketRegistry — admin is the deployer for the bootstrap
        // phase (it must call addAssetToBasket), then DEFAULT_ADMIN_ROLE
        // is transferred to governance at the end of the script.
        BasketRegistry registry = new BasketRegistry(deployer);
        console.log("BasketRegistry", address(registry));

        // 2b. BridgeV4 — admin is the deployer for bootstrap (role grants);
        // we transfer DEFAULT_ADMIN_ROLE to governance at the end.
        BridgeV4 bridgeV4 = new BridgeV4(deployer, address(registry), feeReceiver);
        console.log("BridgeV4      ", address(bridgeV4));

        // 2c. Per-basket asset deployments. We iterate every basket the
        // tenant configured. The order ensures stable on-chain enum
        // indexes.
        for (uint256 i = 0; i < basketSymbols.length; i++) {
            string memory basket = basketSymbols[i];
            // JSON key: .basketAllowlist.USD, .basketAllowlist.BTC, …
            string memory key = string.concat(".basketAllowlist.", basket);
            // readStringArray reverts if the key is missing. We probe
            // existence via keyExists to skip baskets the tenant did
            // not configure (e.g. a DOT-free tenant).
            if (!stdJson.keyExists(raw, key)) {
                continue;
            }
            string[] memory members = raw.readStringArray(key);
            BasketRegistry.BasketClass klass = _basketClassOf(basket);
            for (uint256 j = 0; j < members.length; j++) {
                address asset = _deployAsset(members[j]);
                registry.addAssetToBasket(klass, asset, 0);
                console.log("  basket %s asset %s @", basket, members[j]);
                console.log("    addr:", asset);
            }
        }

        // 2d. Grant tenant roles on the bridge.
        bytes32 mpcRole = bridgeV4.MPC_ROLE();
        bytes32 govRole = bridgeV4.GOVERNANCE_ROLE();
        bytes32 opsRole = bridgeV4.OPERATOR_ROLE();

        for (uint256 i = 0; i < mpcOps.length; i++) {
            bridgeV4.grantRole(mpcRole, mpcOps[i]);
            console.log("  grant MPC_ROLE  ", mpcOps[i]);
        }
        bridgeV4.grantRole(govRole, governance);
        bridgeV4.grantRole(opsRole, opsOperator);
        console.log("  grant GOVERNANCE", governance);
        console.log("  grant OPERATOR  ", opsOperator);

        // 2e. Hand DEFAULT_ADMIN_ROLE on both contracts to governance, then
        // renounce the deployer's admin. Governance now fully owns the
        // tenant deployment.
        bytes32 defaultAdmin = bridgeV4.DEFAULT_ADMIN_ROLE();
        bridgeV4.grantRole(defaultAdmin, governance);
        bridgeV4.renounceRole(defaultAdmin, deployer);

        registry.grantRole(defaultAdmin, governance);
        registry.renounceRole(defaultAdmin, deployer);

        vm.stopBroadcast();

        // ─── 3. Emit deployment manifest as JSON ──────────────────────────
        //
        // foundry-out path: script/out/{tenant}-{chainId}.json — the
        // operator pipes the script's --json output to that file (or
        // copies the addresses from the console log).
        console.log("");
        console.log("=== DEPLOYMENT COMPLETE ===");
        console.log("brand            ", brand);
        console.log("chainId          ", block.chainid);
        console.log("basketRegistry  ", address(registry));
        console.log("bridgeV4        ", address(bridgeV4));
        console.log("feeReceiver     ", feeReceiver);
        console.log("governance      ", governance);
    }
}
