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
    const factoryv3 = networkName === "lux" ? "0x80bBc7C4C7a59C899D1B37BC14539A22D5830a84" : "0x80bBc7C4C7a59C899D1B37BC14539A22D5830a84";
    const weth = networkName === "lux" ? "0x4888E4a2Ee0F03051c72D2BD3ACf755eD3498B3E" : "0x4888E4a2Ee0F03051c72D2BD3ACf755eD3498B3E";
    const factoryv2 = networkName === "lux" ? "0xD173926A10A0C4eCd3A51B1422270b65Df0551c1" : "0xD173926A10A0C4eCd3A51B1422270b65Df0551c1";
    const positionManager = networkName === "lux" ? "0x7a4C48B9dae0b7c396569b34042fcA604150Ee28" : "0x7a4C48B9dae0b7c396569b34042fcA604150Ee28";

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
