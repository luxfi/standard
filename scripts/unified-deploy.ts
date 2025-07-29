#!/usr/bin/env ts-node

/**
 * Unified Deployment Script for Lux Standard Contracts
 * 
 * This script provides a standardized way to deploy all Lux contracts
 * across different networks with proper dependency management.
 */

import { ethers } from "hardhat";
import { Contract } from "ethers";
import fs from "fs";
import path from "path";

// Deployment configuration
interface DeploymentConfig {
  network: string;
  contracts: {
    [key: string]: {
      name: string;
      args?: any[];
      dependencies?: string[];
      verify?: boolean;
    };
  };
  deploymentOrder: string[];
}

// Network configurations
const NETWORK_CONFIGS: { [key: string]: any } = {
  localhost: {
    url: "http://localhost:8545",
    chainId: 31337,
  },
  testnet: {
    url: process.env.TESTNET_RPC_URL || "https://testnet.lux.network",
    chainId: 96368,
  },
  mainnet: {
    url: process.env.MAINNET_RPC_URL || "https://api.lux.network",
    chainId: 96369,
  },
};

// Deployment configurations for each network
const DEPLOYMENT_CONFIGS: { [key: string]: DeploymentConfig } = {
  localhost: {
    network: "localhost",
    contracts: {
      // Core tokens
      LUX: {
        name: "LUX",
        args: [],
      },
      WLUX: {
        name: "WLUX",
        args: [],
      },
      
      // DeFi infrastructure
      UniswapV2Factory: {
        name: "UniswapV2Factory",
        args: ["0x0000000000000000000000000000000000000000"], // Fee setter
      },
      UniswapV2Router02: {
        name: "UniswapV2Router02",
        args: [], // Set after factory deployment
        dependencies: ["UniswapV2Factory", "WLUX"],
      },
      
      // Core protocols
      Bridge: {
        name: "Bridge",
        args: [], // Set after token deployment
        dependencies: ["LUX"],
      },
      Farm: {
        name: "Farm",
        args: [],
        dependencies: ["LUX"],
      },
      Market: {
        name: "Market",
        args: [],
      },
      Auction: {
        name: "Auction",
        args: [],
      },
      
      // Utilities
      Multicall3: {
        name: "Multicall3",
        args: [],
      },
      
      // Governance
      LuxDAO: {
        name: "LuxDAO",
        args: [],
        dependencies: ["LUX"],
      },
    },
    deploymentOrder: [
      "LUX",
      "WLUX",
      "UniswapV2Factory",
      "UniswapV2Router02",
      "Bridge",
      "Farm",
      "Market",
      "Auction",
      "Multicall3",
      "LuxDAO",
    ],
  },
  testnet: {
    // Similar structure for testnet
    network: "testnet",
    contracts: {
      // ... testnet specific configs
    },
    deploymentOrder: [
      // ... testnet deployment order
    ],
  },
  mainnet: {
    // Similar structure for mainnet
    network: "mainnet",
    contracts: {
      // ... mainnet specific configs
    },
    deploymentOrder: [
      // ... mainnet deployment order
    ],
  },
};

// Deployed contracts tracker
const deployedContracts: { [key: string]: Contract } = {};
const deploymentAddresses: { [key: string]: string } = {};

// Logging utilities
function log(message: string, level: "info" | "success" | "error" = "info") {
  const colors = {
    info: "\x1b[34m",    // Blue
    success: "\x1b[32m", // Green
    error: "\x1b[31m",   // Red
  };
  const reset = "\x1b[0m";
  console.log(`${colors[level]}${message}${reset}`);
}

// Deploy a single contract
async function deployContract(
  contractKey: string,
  config: DeploymentConfig
): Promise<Contract> {
  const contractConfig = config.contracts[contractKey];
  log(`Deploying ${contractConfig.name}...`);

  // Check dependencies
  if (contractConfig.dependencies) {
    for (const dep of contractConfig.dependencies) {
      if (!deployedContracts[dep]) {
        throw new Error(`Dependency ${dep} not deployed yet!`);
      }
    }
  }

  // Prepare constructor arguments
  let args = contractConfig.args || [];
  
  // Special argument handling
  if (contractKey === "UniswapV2Router02") {
    args = [
      deploymentAddresses["UniswapV2Factory"],
      deploymentAddresses["WLUX"],
    ];
  } else if (contractKey === "Bridge") {
    args = [deploymentAddresses["LUX"]];
  } else if (contractKey === "Farm") {
    args = [
      deploymentAddresses["LUX"],
      ethers.utils.parseEther("100"), // Reward per block
      0, // Start block
    ];
  }

  // Deploy contract
  const ContractFactory = await ethers.getContractFactory(contractConfig.name);
  const contract = await ContractFactory.deploy(...args);
  await contract.deployed();

  deployedContracts[contractKey] = contract;
  deploymentAddresses[contractKey] = contract.address;

  log(`✅ ${contractConfig.name} deployed at: ${contract.address}`, "success");

  // Verify on Etherscan if configured
  if (contractConfig.verify && config.network !== "localhost") {
    await verifyContract(contract.address, args);
  }

  return contract;
}

// Verify contract on Etherscan
async function verifyContract(address: string, args: any[]) {
  log(`Verifying contract at ${address}...`);
  try {
    await run("verify:verify", {
      address,
      constructorArguments: args,
    });
    log("✅ Contract verified!", "success");
  } catch (error: any) {
    if (error.message.toLowerCase().includes("already verified")) {
      log("Contract already verified", "info");
    } else {
      log(`Verification failed: ${error.message}`, "error");
    }
  }
}

// Post-deployment setup
async function postDeploymentSetup(config: DeploymentConfig) {
  log("\nRunning post-deployment setup...");

  // Setup Bridge
  if (deployedContracts["Bridge"] && deployedContracts["LUX"]) {
    const bridge = deployedContracts["Bridge"];
    const lux = deployedContracts["LUX"];
    
    log("Setting up Bridge permissions...");
    await lux.addBridge(bridge.address);
    log("✅ Bridge permissions configured", "success");
  }

  // Setup Farm pools
  if (deployedContracts["Farm"]) {
    const farm = deployedContracts["Farm"];
    
    log("Adding farming pools...");
    // Add LUX staking pool
    await farm.add(
      1000, // Allocation points
      deploymentAddresses["LUX"],
      true // With update
    );
    log("✅ Farming pools configured", "success");
  }

  // Setup DAO
  if (deployedContracts["LuxDAO"] && deployedContracts["LUX"]) {
    const dao = deployedContracts["LuxDAO"];
    const lux = deployedContracts["LUX"];
    
    log("Setting up DAO...");
    // Transfer some tokens to DAO treasury
    await lux.transfer(dao.address, ethers.utils.parseEther("1000000"));
    log("✅ DAO treasury funded", "success");
  }
}

// Save deployment addresses
async function saveDeploymentAddresses(network: string) {
  const deploymentsDir = path.join(__dirname, "..", "deployments", network);
  
  // Create directory if it doesn't exist
  if (!fs.existsSync(deploymentsDir)) {
    fs.mkdirSync(deploymentsDir, { recursive: true });
  }

  // Save addresses
  const addressesFile = path.join(deploymentsDir, "addresses.json");
  fs.writeFileSync(
    addressesFile,
    JSON.stringify(deploymentAddresses, null, 2)
  );

  log(`\n📄 Deployment addresses saved to: ${addressesFile}`, "success");

  // Generate deployment summary
  const summaryFile = path.join(deploymentsDir, "deployment-summary.md");
  let summary = `# Deployment Summary - ${network}\n\n`;
  summary += `Deployed at: ${new Date().toISOString()}\n\n`;
  summary += `## Deployed Contracts\n\n`;
  summary += `| Contract | Address |\n`;
  summary += `|----------|----------|\n`;
  
  for (const [key, address] of Object.entries(deploymentAddresses)) {
    summary += `| ${key} | ${address} |\n`;
  }

  fs.writeFileSync(summaryFile, summary);
  log(`📄 Deployment summary saved to: ${summaryFile}`, "success");
}

// Main deployment function
async function main() {
  const [deployer] = await ethers.getSigners();
  const network = process.env.HARDHAT_NETWORK || "localhost";

  log(`\n🚀 Starting unified deployment on ${network}`);
  log(`Deployer address: ${deployer.address}`);
  log(`Deployer balance: ${ethers.utils.formatEther(await deployer.getBalance())} ETH\n`);

  // Get deployment configuration
  const config = DEPLOYMENT_CONFIGS[network];
  if (!config) {
    throw new Error(`No deployment configuration for network: ${network}`);
  }

  // Deploy contracts in order
  for (const contractKey of config.deploymentOrder) {
    try {
      await deployContract(contractKey, config);
    } catch (error: any) {
      log(`Failed to deploy ${contractKey}: ${error.message}`, "error");
      throw error;
    }
  }

  // Run post-deployment setup
  await postDeploymentSetup(config);

  // Save deployment addresses
  await saveDeploymentAddresses(network);

  log("\n✨ Deployment completed successfully!", "success");
  
  // Print summary
  log("\n📊 Deployment Summary:");
  for (const [key, address] of Object.entries(deploymentAddresses)) {
    log(`${key}: ${address}`);
  }
}

// Error handling
main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });

// Allow running with npx ts-node
if (require.main === module) {
  main();
}