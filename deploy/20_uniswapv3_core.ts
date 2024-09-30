import { ethers } from "hardhat";
import {SignerWithAddress} from "@nomiclabs/hardhat-ethers/signers";

async function main() {
    let deployer: SignerWithAddress;

    [deployer] = await ethers.getSigners();

    const univ3FactoryFactory = await ethers.getContractFactory("UniswapV3Factory", deployer);

    const factoryv3 = await univ3FactoryFactory.deploy();

    await factoryv3.deployed();
    console.log(`Factory v3 deployed at: ${factoryv3.address}`);

    const TokenFactory = await ethers.getContractFactory("TestERC20", deployer);

    const usdt_mock = await TokenFactory.deploy(2000);
    await usdt_mock.deployed();
    console.log(`USDT mock deployed at: ${usdt_mock.address}`);

    const usdc_mock = await TokenFactory.deploy(2000);
    await usdc_mock.deployed();
    console.log(`USDC mock deployed at: ${usdc_mock.address}`);
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
