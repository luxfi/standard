// SPDX-License-Identifier: MIT
pragma solidity ^0.8.31;

import "forge-std/Script.sol";
import "./Create2Deployer.sol";

// Token imports
import {WLUX} from "../contracts/tokens/WLUX.sol";
import {USDC as BridgeUSDC} from "../contracts/bridge/USDC.sol";
import {USDT as BridgeUSDT} from "../contracts/bridge/USDT.sol";
import {DAI as BridgeDAI} from "../contracts/bridge/DAI.sol";
import {WETH as BridgeWETH} from "../contracts/bridge/WETH.sol";
import {AIToken} from "../contracts/ai/AIToken.sol";
import {xUSD} from "../contracts/synths/xUSD.sol";
import {xETH} from "../contracts/synths/xETH.sol";
import {xBTC} from "../contracts/synths/xBTC.sol";
import {xLUX} from "../contracts/synths/xLUX.sol";
import {Whitelist} from "../contracts/synths/utils/Whitelist.sol";
import {AlchemistV2} from "../contracts/synths/AlchemistV2.sol";
import {TransmuterV2} from "../contracts/synths/TransmuterV2.sol";
import {TransmuterBuffer} from "../contracts/synths/TransmuterBuffer.sol";
import {Vault} from "../contracts/perps/core/Vault.sol";
import {VaultPriceFeed} from "../contracts/perps/core/VaultPriceFeed.sol";
import {Router} from "../contracts/perps/core/Router.sol";
import {PositionRouter} from "../contracts/perps/core/PositionRouter.sol";
import {ShortsTracker} from "../contracts/perps/core/ShortsTracker.sol";
import {USDG} from "../contracts/perps/tokens/LPUSD.sol";
import {GMX} from "../contracts/perps/lux/LPX.sol";
import {LLP} from "../contracts/perps/lux/LLP.sol";
import {LLPManager} from "../contracts/perps/core/LLPManager.sol";

/// @title ComputeAddresses
/// @notice Compute all deterministic addresses before deployment
/// @dev Run this before mainnet deployment to verify expected addresses
contract ComputeAddresses is Script {
    // Protocol version for salt generation (must match DeployCreate2)
    bytes32 constant PROTOCOL_VERSION = keccak256("LUX_STANDARD_V1");

    function salt(string memory name) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(PROTOCOL_VERSION, name));
    }

    /// @notice Compute address that CREATE2 would produce
    function computeAddress(
        address factory,
        bytes32 _salt,
        bytes memory bytecode
    ) internal pure returns (address) {
        bytes32 bytecodeHash = keccak256(bytecode);
        return address(uint160(uint256(keccak256(abi.encodePacked(
            bytes1(0xff),
            factory,
            _salt,
            bytecodeHash
        )))));
    }

    function run() public view {
        // Get the Create2Deployer address (either from env or compute first deployment)
        address factory = vm.envOr("CREATE2_FACTORY", address(0));

        console.log("");
        console.log("+====================================================================+");
        console.log("|          LUX STANDARD - PREDICTED CONTRACT ADDRESSES              |");
        console.log("+====================================================================+");
        console.log("");

        if (factory == address(0)) {
            console.log("NOTE: CREATE2_FACTORY env var not set.");
            console.log("      Set it after deploying Create2Deployer to compute addresses.");
            console.log("");
            console.log("Example:");
            console.log("  CREATE2_FACTORY=0x... forge script script/ComputeAddresses.s.sol");
            console.log("");
            return;
        }

        console.log("Create2Deployer:", factory);
        console.log("");

        // Treasury address for AIToken (use placeholder if not set)
        address treasury = vm.envOr("TREASURY", address(0x9011E888251AB053B7bD1cdB598Db4f9DEd94714));

        // ═══════════════════════════════════════════════════════════════════
        // TOKENS
        // ═══════════════════════════════════════════════════════════════════

        console.log("TOKENS:");

        address wlux = computeAddress(factory, salt("WLUX"), type(WLUX).creationCode);
        console.log("  WLUX:    ", wlux);

        address usdc = computeAddress(factory, salt("USDC"), type(BridgeUSDC).creationCode);
        console.log("  USDC:    ", usdc);

        address usdt = computeAddress(factory, salt("USDT"), type(BridgeUSDT).creationCode);
        console.log("  USDT:    ", usdt);

        address dai = computeAddress(factory, salt("DAI"), type(BridgeDAI).creationCode);
        console.log("  DAI:     ", dai);

        address weth = computeAddress(factory, salt("WETH"), type(BridgeWETH).creationCode);
        console.log("  WETH:    ", weth);

        bytes memory aiTokenBytecode = abi.encodePacked(
            type(AIToken).creationCode,
            abi.encode(treasury, treasury)
        );
        address aiToken = computeAddress(factory, salt("AIToken"), aiTokenBytecode);
        console.log("  AIToken: ", aiToken);

        console.log("");

        // ═══════════════════════════════════════════════════════════════════
        // SYNTHS
        // ═══════════════════════════════════════════════════════════════════

        console.log("SYNTHS (x* = Lux omnichain synths):");

        address whitelist = computeAddress(factory, salt("Whitelist"), type(Whitelist).creationCode);
        console.log("  Whitelist:     ", whitelist);

        // x* synths have no constructor args - bytecode is complete
        address xUSDAddr = computeAddress(factory, salt("xUSD"), type(xUSD).creationCode);
        console.log("  xUSD:          ", xUSDAddr);

        address xETHAddr = computeAddress(factory, salt("xETH"), type(xETH).creationCode);
        console.log("  xETH:          ", xETHAddr);

        address xBTCAddr = computeAddress(factory, salt("xBTC"), type(xBTC).creationCode);
        console.log("  xBTC:          ", xBTCAddr);

        address xLUXAddr = computeAddress(factory, salt("xLUX"), type(xLUX).creationCode);
        console.log("  xLUX:          ", xLUXAddr);

        address transmuterBuffer = computeAddress(factory, salt("TransmuterBufferUSD"), type(TransmuterBuffer).creationCode);
        console.log("  TransmuterBuffer:", transmuterBuffer);

        address transmuter = computeAddress(factory, salt("TransmuterUSD"), type(TransmuterV2).creationCode);
        console.log("  TransmuterV2:  ", transmuter);

        address xUSDVault = computeAddress(factory, salt("xUSDVault"), type(AlchemistV2).creationCode);
        console.log("  xUSDVault:  ", xUSDVault);

        address alchemistETH = computeAddress(factory, salt("AlchemistETH"), type(AlchemistV2).creationCode);
        console.log("  AlchemistETH:  ", alchemistETH);

        console.log("");

        // ═══════════════════════════════════════════════════════════════════
        // PERPS
        // ═══════════════════════════════════════════════════════════════════

        console.log("PERPS:");

        bytes memory usdgBytecode = abi.encodePacked(
            type(LPUSD).creationCode,
            abi.encode(address(0))
        );
        address usdg = computeAddress(factory, salt("LPUSD"), usdgBytecode);
        console.log("  LPUSD:          ", usdg);

        address vaultPriceFeed = computeAddress(factory, salt("VaultPriceFeed"), type(VaultPriceFeed).creationCode);
        console.log("  VaultPriceFeed:", vaultPriceFeed);

        address vault = computeAddress(factory, salt("Vault"), type(Vault).creationCode);
        console.log("  Vault:         ", vault);

        address gmx = computeAddress(factory, salt("LPX"), type(LPX).creationCode);
        console.log("  LPX:           ", gmx);

        address llp = computeAddress(factory, salt("LLP"), type(LLP).creationCode);
        console.log("  LLP:           ", llp);

        bytes memory shortsTrackerBytecode = abi.encodePacked(
            type(ShortsTracker).creationCode,
            abi.encode(vault)
        );
        address shortsTracker = computeAddress(factory, salt("ShortsTracker"), shortsTrackerBytecode);
        console.log("  ShortsTracker: ", shortsTracker);

        bytes memory routerBytecode = abi.encodePacked(
            type(Router).creationCode,
            abi.encode(vault, usdg, weth)
        );
        address router = computeAddress(factory, salt("Router"), routerBytecode);
        console.log("  Router:        ", router);

        bytes memory positionRouterBytecode = abi.encodePacked(
            type(PositionRouter).creationCode,
            abi.encode(vault, router, weth, shortsTracker, 30, 1e16)
        );
        address positionRouter = computeAddress(factory, salt("PositionRouter"), positionRouterBytecode);
        console.log("  PositionRouter:", positionRouter);

        bytes memory llpManagerBytecode = abi.encodePacked(
            type(LLPManager).creationCode,
            abi.encode(vault, usdg, llp, shortsTracker, 15 minutes)
        );
        address llpManager = computeAddress(factory, salt("LLPManager"), llpManagerBytecode);
        console.log("  LLPManager:    ", llpManager);

        console.log("");
        console.log("+====================================================================+");
        console.log("");
        console.log("These addresses will be the same on ALL chains when deployed through");
        console.log("the same Create2Deployer at:", factory);
        console.log("");
    }
}
