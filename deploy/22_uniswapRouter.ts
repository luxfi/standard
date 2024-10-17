import hre, { ethers } from "hardhat";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
const fs = require('fs');  // Import the File System module

// (mainnet) npx hardhat run --network lux deploy/22_uniswapRouter.ts
// (testnet) npx hardhat run --network lux_testnet deploy/22_uniswapRouter.ts

async function main() {
    let deployer: SignerWithAddress;
    [deployer] = await ethers.getSigners();
    // Determine the folder based on the network
    const networkName = hre.network.name; // "lux" or "lux_testnet"
    const folder = networkName === "lux" ? "mainnet" : "testnet";
    const factoryv3 = networkName === "lux" ? "0x0650683db720c793ff7e609A08b5fc2792c91f39" : "0x036A0AE1D760D7582254059BeBD9e5A34062dE23";
    const weth = networkName === "lux" ? "0x53B1aAA5b6DDFD4eD00D0A7b5Ef333dc74B605b5" : "0x0650683db720c793ff7e609A08b5fc2792c91f39";
    const factoryv2 = networkName === "lux" ? "0x759a82c704bb751977F8A31AD682090c29108d6d" : "0xBf6440a627907022D2bb7c57FD20196772935F83";
    const positionManager = networkName === "lux" ? "0xD736808D0cbcC3237b5d8caE10B30FcDcaFf0fEF" : "0x99D5296C6dfADF96f4C51D2c7f93bBEEEe331ec1";

    // Deploy UniswapV3Factory contract
    const uniSwapRouter02 = await ethers.getContractFactory("SwapRouter02", deployer);
    const swapRouterv2 = await uniSwapRouter02.deploy(factoryv2, factoryv3, positionManager, weth);
    await swapRouterv2.deployed();
    console.log(`SwapRouter02 deployed at: ${swapRouterv2.address}`);

    // Verify the contract on Etherscan
    await hre.run("verify:verify", {
        address: swapRouterv2.address,
        contract: "src/uni/swapRouter/SwapRouter02.sol:SwapRouter02",
        constructorArguments: [factoryv2, factoryv3, positionManager, weth],
    });

    // Load the ABI from the compiled contract artifacts
    const abi = JSON.parse(fs.readFileSync('./artifacts/src/uni/swapRouter/SwapRouter02.sol/SwapRouter02.json', 'utf8')).abi;

    // Write ABI and address to the corresponding folder
    const outputPath = `deployments/${folder}/SwapRouter02.json`;
    fs.writeFileSync(outputPath, JSON.stringify({
        address: swapRouterv2.address,
        abi: abi,
    }, null, 2));

    console.log(`Contract ABI and address saved to ${outputPath}`);
    return;
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
