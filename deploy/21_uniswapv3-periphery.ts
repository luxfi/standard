import { ethers } from "hardhat";
import {SignerWithAddress} from "@nomiclabs/hardhat-ethers/signers";

async function main() {
    let deployer: SignerWithAddress;

    [deployer] = await ethers.getSigners();

    const factory = "0x0650683db720c793ff7e609A08b5fc2792c91f39";
    const weth = "0x0650683db720c793ff7e609A08b5fc2792c91f39";

    const SwapRouter = await ethers.getContractFactory("SwapRouter");
    const swapRouter = await SwapRouter.deploy(factory, weth);

    await swapRouter.deployed();
    console.log("Swap router:", swapRouter.address);

    const Quoter = await ethers.getContractFactory("Quoter");
    const quoter = await Quoter.deploy(factory, weth);

    await quoter.deployed();
    console.log("Quoter:", quoter.address);

    const Quoter2 = await ethers.getContractFactory("QuoterV2");
    const quoter2 = await Quoter2.deploy(factory, weth);

    await quoter2.deployed();
    console.log("Quoter v2:", quoter2.address);

    const NFTDescriptor = await ethers.getContractFactory("NFTDescriptor");
    const nftDescriptor = await NFTDescriptor.deploy();

    console.log("NFT DEscriptor:", nftDescriptor.address);
    await nftDescriptor.deployed();

    const luxBytes32 = ethers.utils.formatBytes32String("LUX")


    const TokenDescriptor = await ethers.getContractFactory("NonfungibleTokenPositionDescriptor", {
        libraries: {
            NFTDescriptor: nftDescriptor.address,
        }
    });
    const tokenDescriptor = await TokenDescriptor.deploy(weth, luxBytes32);

    await tokenDescriptor.deployed();
    console.log("Token descriptor:", tokenDescriptor.address);

    const PositonManager = await ethers.getContractFactory("NonfungiblePositionManager");
    const positonManager = await PositonManager.deploy(factory, weth, tokenDescriptor.address);

    await positonManager.deployed();
    console.log(`Position manager: ${positonManager.address}`);
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
