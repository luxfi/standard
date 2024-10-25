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
    const factoryv3 = networkName === "lux" ? "0xa12792DeB2eE726d1b163ba54c876c69ACa41d89" : "0x196CEb9CDE6e804403dFEB16dC91dCFC2bE6cF7d";
    const weth = networkName === "lux" ? "0xd4b2F0435faca8959A7D2e096C2A3Ce9697Ee9fc" : "0xA01c406bC54aD9363704E9D26522a4629b5E6263";
    const factoryv2 = networkName === "lux" ? "0xCfa08d54d3d76289ef88717b921Ce8C3203789e9" : "0xd3CC2350b9CFe15d6e1Ed826dF3150eF3CBb0A47";
    const positionManager = networkName === "lux" ? "0x2f9bB9665c0579B0449E495852F683464d35103B" : "0x59D662ce2682Bb9F98C1B856B99FB9a3E38cd521";

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
