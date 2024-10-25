import hre, { ethers } from "hardhat";
import {SignerWithAddress} from "@nomiclabs/hardhat-ethers/signers";
const fs = require('fs');  // Import the File System module

// (mainnet)  npx hardhat run --network lux deploy/21_uniswapv3_periphery.ts
// (testnet)  npx hardhat run --network lux_testnet deploy/21_uniswapv3_periphery.ts

async function main() {
    let deployer: SignerWithAddress;

    [deployer] = await ethers.getSigners();

    // Determine the folder based on the network
    const networkName = hre.network.name; // "lux" or "lux_testnet"
    const folder = networkName === "lux" ? "mainnet" : "testnet";
    const v3factory = networkName === "lux" ? "0xa12792DeB2eE726d1b163ba54c876c69ACa41d89" : "0x196CEb9CDE6e804403dFEB16dC91dCFC2bE6cF7d";
    const wlux = networkName === "lux" ? "0xd4b2F0435faca8959A7D2e096C2A3Ce9697Ee9fc" : "0xA01c406bC54aD9363704E9D26522a4629b5E6263";
    const Multi_Call = await ethers.getContractFactory("UniswapInterfaceMulticall");
    const multi_call = await Multi_Call.deploy();
    

    await multi_call.deployed();
    console.log("Multicall:", multi_call.address);

    try {
        await hre.run("verify:verify", {
            address: multi_call.address,
            contract: "src/uni/uni3/periphery/contracts/lens/UniswapInterfaceMulticall.sol:UniswapInterfaceMulticall",
        constructorArguments: [],
        }); 
    } catch(error) {
        console.log(error);
    }

    fs.writeFileSync(`deployments/${folder}/Multicall.json`, JSON.stringify({
        address: multi_call.address,
        abi: JSON.parse(fs.readFileSync('./artifacts/src/uni/uni3/periphery/contracts/lens/UniswapInterfaceMulticall.sol/UniswapInterfaceMulticall.json', 'utf8')).abi,
    }, null, 2));

    console.log('Contract ABI and address saved to Multicall.json');

    const TickLens = await ethers.getContractFactory("TickLens");
    const tickLens = await TickLens.deploy();
    

    await tickLens.deployed();
    console.log("TickLens:", tickLens.address);
    try {
        await hre.run("verify:verify", {
            address: tickLens.address,
            contract: "src/uni/uni3/periphery/contracts/lens/TickLens.sol:TickLens",
        constructorArguments: [],
        });
    } catch(error) {
        console.log(error);
    }

    fs.writeFileSync(`deployments/${folder}/TickLens.json`, JSON.stringify({
        address: tickLens.address,
        abi: JSON.parse(fs.readFileSync('./artifacts/src/uni/uni3/periphery/contracts/lens/TickLens.sol/TickLens.json', 'utf8')).abi,
    }, null, 2));

    console.log('Contract ABI and address saved to TickLens.json');

    const SwapRouter = await ethers.getContractFactory("SwapRouter");
    const swapRouter = await SwapRouter.deploy(v3factory, wlux);
    

    await swapRouter.deployed();
    console.log("Swap router:", swapRouter.address);
    try {
        await hre.run("verify:verify", {
            address: swapRouter.address,
            contract: "src/uni/uni3/periphery/contracts/SwapRouter.sol:SwapRouter",
        constructorArguments: [v3factory, wlux],
        });
    } catch(error) {
        console.log(error);
    }

    fs.writeFileSync(`deployments/${folder}/SwapRouter.json`, JSON.stringify({
        address: swapRouter.address,
        abi: JSON.parse(fs.readFileSync('./artifacts/src/uni/uni3/periphery/contracts/SwapRouter.sol/SwapRouter.json', 'utf8')).abi,
    }, null, 2));

    console.log('Contract ABI and address saved to SwapRouter.json');

    const Quoter = await ethers.getContractFactory("src/uni/uni3/periphery/contracts/lens/Quoter.sol:Quoter");
    const quoter = await Quoter.deploy(v3factory, wlux);

    await quoter.deployed();
    console.log("Quoter:", quoter.address);
    try {
        await hre.run("verify:verify", {
            address: quoter.address,
            contract: "src/uni/uni3/periphery/contracts/lens/Quoter.sol:Quoter",
        constructorArguments: [v3factory, wlux],
        });
    } catch(error) {
        console.log(error);
    }

    fs.writeFileSync(`deployments/${folder}/Quoter.json`, JSON.stringify({
        address: quoter.address,
        abi: JSON.parse(fs.readFileSync('./artifacts/src/uni/uni3/periphery/contracts/lens/Quoter.sol/Quoter.json', 'utf8')).abi,
    }, null, 2));

    console.log('Contract ABI and address saved to Quoter.json');

    const Quoter2 = await ethers.getContractFactory("src/uni/uni3/periphery/contracts/lens/QuoterV2.sol:QuoterV2");
    const quoter2 = await Quoter2.deploy(v3factory, wlux);

    await quoter2.deployed();
    console.log("Quoter v2:", quoter2.address);

    try {
        await hre.run("verify:verify", {
            address: quoter2.address,
            contract: "src/uni/uni3/periphery/contracts/lens/QuoterV2.sol:QuoterV2",
        constructorArguments: [v3factory, wlux],
        });
    } catch(error) {
        console.log(error);
    }
    fs.writeFileSync(`deployments/${folder}/QuoterV2.json`, JSON.stringify({
        address: quoter2.address,
        abi: JSON.parse(fs.readFileSync('./artifacts/src/uni/uni3/periphery/contracts/lens/QuoterV2.sol/QuoterV2.json', 'utf8')).abi,
    }, null, 2));

    console.log('Contract ABI and address saved to QuoterV2.json');

    const NFTDescriptor = await ethers.getContractFactory("NFTDescriptor");
    const nftDescriptor = await NFTDescriptor.deploy();

    console.log("NFT DEscriptor:", nftDescriptor.address);
    await nftDescriptor.deployed();
    try {
        await hre.run("verify:verify", {
            address: nftDescriptor.address,
            contract: "src/uni/uni3/periphery/contracts/libraries/NFTDescriptor.sol:NFTDescriptor",
        constructorArguments: [],
        });
    } catch(error) {
        console.log(error);
    } 
    fs.writeFileSync(`deployments/${folder}/NFTDescriptor.json`, JSON.stringify({
        address: nftDescriptor.address,
        abi: JSON.parse(fs.readFileSync('./artifacts/src/uni/uni3/periphery/contracts/libraries/NFTDescriptor.sol/NFTDescriptor.json', 'utf8')).abi,
    }, null, 2));

    console.log('Contract ABI and address saved to NFTDescriptor.json');

    const luxBytes32 = ethers.utils.formatBytes32String("LUX")

    const TokenDescriptor = await ethers.getContractFactory("NonfungibleTokenPositionDescriptor", {
        libraries: {
            NFTDescriptor: nftDescriptor.address,
        }
    });
    const tokenDescriptor = await TokenDescriptor.deploy(wlux, luxBytes32);

    await tokenDescriptor.deployed();
    console.log("Token descriptor:", tokenDescriptor.address);
    try {
        await hre.run("verify:verify", {
            address: tokenDescriptor.address,
            contract: "src/uni/uni3/periphery/contracts/NonfungibleTokenPositionDescriptor.sol:NonfungibleTokenPositionDescriptor",
        constructorArguments: [wlux, luxBytes32],
        });
    } catch(error) {
        console.log(error);
    }
    fs.writeFileSync(`deployments/${folder}/NonfungibleTokenPositionDescriptor.json`, JSON.stringify({
        address: tokenDescriptor.address,
        abi: JSON.parse(fs.readFileSync('./artifacts/src/uni/uni3/periphery/contracts/NonfungibleTokenPositionDescriptor.sol/NonfungibleTokenPositionDescriptor.json', 'utf8')).abi,
    }, null, 2));

    console.log('Contract ABI and address saved to NonfungibleTokenPositionDescriptor.json');

    const PositonManager = await ethers.getContractFactory("NonfungiblePositionManager");
    const positonManager = await PositonManager.deploy(v3factory, wlux, tokenDescriptor.address);

    await positonManager.deployed();
    console.log(`Position manager: ${positonManager.address}`);
    try {
        await hre.run("verify:verify", {
            address: positonManager.address,
            contract: "src/uni/uni3/periphery/contracts/NonfungiblePositionManager.sol:NonfungiblePositionManager",
        constructorArguments: [v3factory, wlux, tokenDescriptor.address],
        });
    } catch(error) {
        console.log(error);
    }
    fs.writeFileSync(`deployments/${folder}/NonfungiblePositionManager.json`, JSON.stringify({
        address: positonManager.address,
        abi: JSON.parse(fs.readFileSync('./artifacts/src/uni/uni3/periphery/contracts/NonfungiblePositionManager.sol/NonfungiblePositionManager.json', 'utf8')).abi,
    }, null, 2));

    console.log('Contract ABI and address saved to NonfungiblePositionManager.json');

    console.log("Multicall", multi_call.address);
    console.log("TickLens", tickLens.address);
    console.log("SwapRouter", swapRouter.address);
    console.log("Quoter", quoter.address);
    console.log("Quoterv2", quoter2.address);
    console.log("NFT DEscriptor", nftDescriptor.address);
    console.log("Token descriptor:", tokenDescriptor.address);
    console.log(`Position manager: ${positonManager.address}`);
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
