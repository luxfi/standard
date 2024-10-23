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
    const factoryv3 = networkName === "lux" ? "0xD1A37eF464c6679A0989775E1fAC54E1598FeD18" : "0x373Ea8ad7C0259910033ED91b511336D091b5680";
    const weth = networkName === "lux" ? "0xFbad1306A6b306b1b673ACa75a1CC78C4375e4Dc" : "0x1B3DBA2d66c18a15a6F88B0751366C01bC8CBdd3";
    const factoryv2 = networkName === "lux" ? "0x42c426364d36C2b3aF20F1F498277e6b777132c5" : "0x462e816749A08Adb0085E6257D37E2cab4574273";
    const positionManager = networkName === "lux" ? "0xFb931FDd8bCef71b8101812c2e482C5A465D73DB" : "0xB9983C194fd9731052BF6a7B1A0A2f9A48D6f036";

    // Deploy UniswapV3Factory contract
    const uniSwapRouter02 = await ethers.getContractFactory("SwapRouter02", deployer);
    const swapRouterv2 = await uniSwapRouter02.deploy(factoryv2, factoryv3, positionManager, weth);
    await swapRouterv2.deployed();
    console.log(`SwapRouter02 deployed at: ${swapRouterv2.address}`);

    // Verify the contract on Etherscan
    try {
    await hre.run("verify:verify", {
        address: swapRouterv2.address,
        contract: "src/uni/swapRouter/SwapRouter02.sol:SwapRouter02",
        constructorArguments: [factoryv2, factoryv3, positionManager, weth],
    });
    } catch(error) {
        console.log(error);
    }

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
