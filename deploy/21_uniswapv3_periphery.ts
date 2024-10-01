import hre, { ethers } from "hardhat";
import {SignerWithAddress} from "@nomiclabs/hardhat-ethers/signers";
const fs = require('fs');  // Import the File System module

// (mainnet)  npx hardhat run --network lux deploy/21_uniswapv3_periphery.ts
// (testnet)  npx hardhat run --network lux_testnet deploy/21_uniswapv3_periphery.ts
// Before start, you should update factory and weth address as same net.
async function main() {
    let deployer: SignerWithAddress;

    [deployer] = await ethers.getSigners();

    // factory address (mainnet) 0x0650683db720c793ff7e609A08b5fc2792c91f39
    // factory address (testnet) 0x036A0AE1D760D7582254059BeBD9e5A34062dE23
    const factory = "0x036A0AE1D760D7582254059BeBD9e5A34062dE23";

    // mock weth address (mainnet) 0x53B1aAA5b6DDFD4eD00D0A7b5Ef333dc74B605b5
    // mock weth address (testnet) 0x0650683db720c793ff7e609A08b5fc2792c91f39
    const weth = "0x0650683db720c793ff7e609A08b5fc2792c91f39";
    {
        const SwapRouter = await ethers.getContractFactory("SwapRouter");
        const swapRouter = await SwapRouter.deploy(factory, weth);

        await swapRouter.deployed();
        console.log("Swap router:", swapRouter.address);

        await hre.run("verify:verify", {
            address: swapRouter.address,
            contract: "src/uni3/periphery/contracts/SwapRouter.sol:SwapRouter",
        constructorArguments: [factory, weth],
        });

        fs.writeFileSync('deployments/mainnet/SwapRouter.json', JSON.stringify({
            address: swapRouter.address,
            abi: JSON.parse(fs.readFileSync('./artifacts/src/uni3/periphery/contracts/SwapRouter.sol/SwapRouter.json', 'utf8')).abi,
        }, null, 2));

        console.log('Contract ABI and address saved to SwapRouter.json');
    }
    {
        const Quoter = await ethers.getContractFactory("Quoter");
        const quoter = await Quoter.deploy(factory, weth);

        await quoter.deployed();
        console.log("Quoter:", quoter.address);

        await hre.run("verify:verify", {
            address: quoter.address,
            contract: "src/uni3/periphery/contracts/lens/Quoter.sol:Quoter",
        constructorArguments: [factory, weth],
        });

        fs.writeFileSync('deployments/mainnet/Quoter.json', JSON.stringify({
            address: quoter.address,
            abi: JSON.parse(fs.readFileSync('./artifacts/src/uni3/periphery/contracts/lens/Quoter.sol/Quoter.json', 'utf8')).abi,
        }, null, 2));

        console.log('Contract ABI and address saved to Quoter.json');
    }
    {
        const Quoter2 = await ethers.getContractFactory("QuoterV2");
        const quoter2 = await Quoter2.deploy(factory, weth);

        await quoter2.deployed();
        console.log("Quoter v2:", quoter2.address);

        await hre.run("verify:verify", {
            address: quoter2.address,
            contract: "src/uni3/periphery/contracts/lens/QuoterV2.sol:QuoterV2",
        constructorArguments: [factory, weth],
        });
        fs.writeFileSync('deployments/mainnet/QuoterV2.json', JSON.stringify({
            address: quoter2.address,
            abi: JSON.parse(fs.readFileSync('./artifacts/src/uni3/periphery/contracts/lens/QuoterV2.sol/QuoterV2.json', 'utf8')).abi,
        }, null, 2));
    
        console.log('Contract ABI and address saved to QuoterV2.json');
    }

    const NFTDescriptor = await ethers.getContractFactory("NFTDescriptor");
    const nftDescriptor = await NFTDescriptor.deploy();

    console.log("NFT DEscriptor:", nftDescriptor.address);
    await nftDescriptor.deployed();

    await hre.run("verify:verify", {
        address: nftDescriptor.address,
        contract: "src/uni3/periphery/contracts/libraries/NFTDescriptor.sol:NFTDescriptor",
    constructorArguments: [],
    });
    fs.writeFileSync('deployments/mainnet/NFTDescriptor.json', JSON.stringify({
        address: nftDescriptor.address,
        abi: JSON.parse(fs.readFileSync('./artifacts/src/uni3/periphery/contracts/libraries/NFTDescriptor.sol/NFTDescriptor.json', 'utf8')).abi,
    }, null, 2));

    console.log('Contract ABI and address saved to NFTDescriptor.json');

    const luxBytes32 = ethers.utils.formatBytes32String("LUX")

    const TokenDescriptor = await ethers.getContractFactory("NonfungibleTokenPositionDescriptor", {
        libraries: {
            NFTDescriptor: nftDescriptor.address,
        }
    });
    const tokenDescriptor = await TokenDescriptor.deploy(weth, luxBytes32);

    await tokenDescriptor.deployed();
    console.log("Token descriptor:", tokenDescriptor.address);

    await hre.run("verify:verify", {
        address: tokenDescriptor.address,
        contract: "src/uni3/periphery/contracts/NonfungibleTokenPositionDescriptor.sol:NonfungibleTokenPositionDescriptor",
    constructorArguments: [weth, luxBytes32],
    });
    fs.writeFileSync('deployments/mainnet/NonfungibleTokenPositionDescriptor.json', JSON.stringify({
        address: tokenDescriptor.address,
        abi: JSON.parse(fs.readFileSync('./artifacts/src/uni3/periphery/contracts/NonfungibleTokenPositionDescriptor.sol/NonfungibleTokenPositionDescriptor.json', 'utf8')).abi,
    }, null, 2));

    console.log('Contract ABI and address saved to NonfungibleTokenPositionDescriptor.json');

    const PositonManager = await ethers.getContractFactory("NonfungiblePositionManager");
    const positonManager = await PositonManager.deploy(factory, weth, tokenDescriptor.address);

    await positonManager.deployed();
    console.log(`Position manager: ${positonManager.address}`);

    await hre.run("verify:verify", {
        address: positonManager.address,
        contract: "src/uni3/periphery/contracts/NonfungiblePositionManager.sol:NonfungiblePositionManager",
      constructorArguments: [factory, weth, tokenDescriptor.address],
    });
    fs.writeFileSync('deployments/mainnet/NonfungiblePositionManager.json', JSON.stringify({
        address: positonManager.address,
        abi: JSON.parse(fs.readFileSync('./artifacts/src/uni3/periphery/contracts/NonfungiblePositionManager.sol/NonfungiblePositionManager.json', 'utf8')).abi,
    }, null, 2));

    console.log('Contract ABI and address saved to NonfungiblePositionManager.json');
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
