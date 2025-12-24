// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import "forge-std/console.sol";

// Core tokens
import {WLUX} from "../contracts/tokens/WLUX.sol";

// Governance
import {vLUX} from "../contracts/governance/vLUX.sol";
import {GaugeController} from "../contracts/governance/GaugeController.sol";

// Treasury
import {FeeSplitter} from "../contracts/treasury/FeeSplitter.sol";
import {ValidatorVault} from "../contracts/treasury/ValidatorVault.sol";
import {SynthFeeSplitter} from "../contracts/treasury/SynthFeeSplitter.sol";

// Staking
import {sLUX} from "../contracts/staking/sLUX.sol";

// Synths
import {xLUX} from "../contracts/synths/xLUX.sol";
import {xUSD} from "../contracts/synths/xUSD.sol";

/**
 * @title DeployGovernance
 * @notice Deploy full Lux governance and fee distribution system
 */
contract DeployGovernance is Script {
    // Deployed contracts
    WLUX public wlux;
    vLUX public vlux;
    GaugeController public gaugeController;
    FeeSplitter public feeSplitter;
    ValidatorVault public validatorVault;
    SynthFeeSplitter public synthFeeSplitter;
    sLUX public slux;
    
    // Gauge IDs
    uint256 public burnGaugeId;
    uint256 public validatorGaugeId;
    uint256 public daoGaugeId;
    uint256 public polGaugeId;
    
    // Addresses
    address public deployer;
    address public daoTreasury;
    address public pol;
    
    address constant BURN_ADDRESS = 0x000000000000000000000000000000000000dEaD;

    function run() external {
        uint256 deployerKey = vm.envOr("PRIVATE_KEY", uint256(0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80));
        deployer = vm.addr(deployerKey);
        
        // For testing, DAO and POL are just the deployer
        daoTreasury = deployer;
        pol = deployer;
        
        console.log("========================================");
        console.log("   LUX GOVERNANCE DEPLOYMENT");
        console.log("========================================");
        console.log("Deployer:", deployer);
        console.log("");
        
        vm.startBroadcast(deployerKey);
        
        // ========== Phase 1: Core Token ==========
        console.log("--- Phase 1: Core Token ---");
        
        wlux = new WLUX();
        console.log("WLUX:", address(wlux));
        
        // Wrap some ETH for testing
        wlux.deposit{value: 10000 ether}();
        console.log("Wrapped 10000 ETH -> WLUX");
        console.log("");
        
        // ========== Phase 2: Governance ==========
        console.log("--- Phase 2: Governance ---");
        
        vlux = new vLUX(address(wlux));
        console.log("vLUX:", address(vlux));
        
        gaugeController = new GaugeController(address(vlux));
        console.log("GaugeController:", address(gaugeController));
        console.log("");
        
        // ========== Phase 3: Treasury ==========
        console.log("--- Phase 3: Treasury ---");
        
        validatorVault = new ValidatorVault(address(wlux));
        console.log("ValidatorVault:", address(validatorVault));
        
        feeSplitter = new FeeSplitter(address(wlux));
        console.log("FeeSplitter:", address(feeSplitter));
        
        // ========== Phase 4: Staking ==========
        console.log("--- Phase 4: Staking ---");
        
        slux = new sLUX(address(wlux));
        console.log("sLUX:", address(slux));
        
        // SynthFeeSplitter needs sLUX
        synthFeeSplitter = new SynthFeeSplitter(
            address(wlux),
            pol,
            daoTreasury,
            address(slux),
            address(slux) // vault reserve = sLUX for now
        );
        console.log("SynthFeeSplitter:", address(synthFeeSplitter));
        console.log("");
        
        // ========== Phase 5: Setup Gauges ==========
        console.log("--- Phase 5: Setup Gauges ---");
        
        // Add gauges (ID 0 is reserved/invalid)
        burnGaugeId = gaugeController.addGauge(BURN_ADDRESS, "Burn", 0);
        console.log("BurnGauge ID:", burnGaugeId);
        
        validatorGaugeId = gaugeController.addGauge(address(validatorVault), "Validators", 0);
        console.log("ValidatorGauge ID:", validatorGaugeId);
        
        daoGaugeId = gaugeController.addGauge(daoTreasury, "DAO Treasury", 0);
        console.log("DAOGauge ID:", daoGaugeId);
        
        polGaugeId = gaugeController.addGauge(pol, "Protocol Liquidity", 0);
        console.log("POLGauge ID:", polGaugeId);
        console.log("");
        
        // ========== Phase 6: Connect Components ==========
        console.log("--- Phase 6: Connect Components ---");
        
        // Set GaugeController on FeeSplitter
        feeSplitter.setGaugeController(address(gaugeController));
        feeSplitter.setBurnGaugeId(burnGaugeId);
        console.log("FeeSplitter connected to GaugeController");
        
        // Add recipients to FeeSplitter
        feeSplitter.addRecipient(address(validatorVault));
        feeSplitter.addRecipient(daoTreasury);
        // Note: POL is same as daoTreasury in test (both deployer)
        // Skip adding if same address
        if (pol != daoTreasury) {
            feeSplitter.addRecipient(pol);
        }
        console.log("Recipients added to FeeSplitter");
        
        // Set protocol vault on sLUX
        slux.setProtocolVault(address(synthFeeSplitter));
        console.log("sLUX connected to SynthFeeSplitter");
        console.log("");
        
        // ========== Phase 7: Initial Votes ==========
        console.log("--- Phase 7: Initial Voting Setup ---");
        
        // Lock some LUX for voting power
        uint256 lockAmount = 1000 ether;
        uint256 lockEnd = block.timestamp + 4 * 365 days; // 4 year lock
        
        wlux.approve(address(vlux), lockAmount);
        vlux.createLock(lockAmount, lockEnd);
        console.log("Locked 1000 LUX for 4 years");
        
        uint256 votingPower = vlux.balanceOf(deployer);
        console.log("Voting power:", votingPower / 1e18, "vLUX");
        
        // Cast initial votes (50% burn, 48% validators, 1% DAO, 1% POL)
        uint256[] memory gaugeIds = new uint256[](4);
        uint256[] memory weights = new uint256[](4);
        
        gaugeIds[0] = burnGaugeId;
        gaugeIds[1] = validatorGaugeId;
        gaugeIds[2] = daoGaugeId;
        gaugeIds[3] = polGaugeId;
        
        weights[0] = 5000; // 50% burn
        weights[1] = 4800; // 48% validators
        weights[2] = 100;  // 1% DAO
        weights[3] = 100;  // 1% POL
        
        gaugeController.voteMultiple(gaugeIds, weights);
        console.log("Initial votes cast: 50% burn, 48% validators, 1% DAO, 1% POL");
        
        console.log("Note: Weights update weekly - call updateWeights() after 7 days");
        console.log("");
        
        vm.stopBroadcast();
        
        // ========== Summary ==========
        console.log("========================================");
        console.log("       DEPLOYMENT COMPLETE");
        console.log("========================================");
        console.log("");
        console.log("GOVERNANCE:");
        console.log("  vLUX:", address(vlux));
        console.log("  GaugeController:", address(gaugeController));
        console.log("");
        console.log("TREASURY:");
        console.log("  FeeSplitter:", address(feeSplitter));
        console.log("  ValidatorVault:", address(validatorVault));
        console.log("  SynthFeeSplitter:", address(synthFeeSplitter));
        console.log("");
        console.log("STAKING:");
        console.log("  sLUX:", address(slux));
        console.log("");
        console.log("GAUGES:");
        console.log("  Burn (ID", burnGaugeId, "):", BURN_ADDRESS);
        console.log("  Validators (ID", validatorGaugeId, "):", address(validatorVault));
        console.log("  DAO (ID", daoGaugeId, "):", daoTreasury);
        console.log("  POL (ID", polGaugeId, "):", pol);
        console.log("");
    }
}
