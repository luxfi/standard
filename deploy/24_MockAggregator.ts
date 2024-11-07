import hre, { ethers } from "hardhat";
import { Contract, ContractFactory, Wallet } from "ethers";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
const fs = require('fs');  // Import the File System module

// (mainnet) npx hardhat run --network lux deploy/24_MockAggregator.ts
// (testnet) npx hardhat run --network lux_testnet deploy/24_MockAggregator.ts

async function main() {
    let deployer: SignerWithAddress;
    [deployer] = await ethers.getSigners();

    // Deploy MockAggregator contract
    const MockAggregator = await ethers.getContractFactory("MockAggregator", deployer);
    
    const mockAggregator = await MockAggregator.deploy(10000);
    await mockAggregator.deployed();
    console.log(`mockAggregator deployed at: ${mockAggregator.address}`);

    // Verify the contract on Etherscan
    try {
    await hre.run("verify:verify", {
        address: mockAggregator.address,
        contract: "src/uni/MockAggregator.sol:MockAggregator",
        constructorArguments: [10000],
    });
    } catch(error) {
        console.log(error);
    }

    // // Determine the folder based on the network
    // const networkName = hre.network.name; // "lux" or "lux_testnet"
    // const folder = networkName === "lux" ? "mainnet" : "testnet";

    // // Load the ABI from the compiled contract artifacts
    // const abi = JSON.parse(fs.readFileSync('./artifacts/src/uni/uni3/core/contracts/MockAggregator.sol/MockAggregator.json', 'utf8')).abi;

    // // Write ABI and address to the corresponding folder
    // const outputPath = `deployments/${folder}/MockAggregator.json`;
    // fs.writeFileSync(outputPath, JSON.stringify({
    //     address: factoryv3.address,
    //     abi: abi,
    // }, null, 2));

    console.log(`Contract ABI and address saved to ${outputPath}`);
    console.log("V3 FACTORY ADDRESS", factoryv3.address);
    return;
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
