// Importing required modules and libraries from the ethers.js library.
import { Contract, ContractFactory, Wallet } from "ethers";
import hre, { ethers } from "hardhat";
import {SignerWithAddress} from "@nomiclabs/hardhat-ethers/signers";
const fs = require('fs');  // Import the File System module
import * as dotenv from "dotenv";

//(testnet) npx hardhat run --network lux_testnet deploy/19_uniswapv2.ts
//(mainnet) npx hardhat run --network lux deploy/19_uniswapv2.ts

// Importing the contract JSON artifacts.
import pairArtifact from "@uniswap/v2-periphery/build/IUniswapV2Pair.json";
import factoryArtifact from "@uniswap/v2-core/build/UniswapV2Factory.json";

dotenv.config();

// Main deployment function.
async function main() {
    let deployer: SignerWithAddress;
    [deployer] = await ethers.getSigners();

    // Determine the folder based on the network
    const networkName = hre.network.name; // "lux" or "lux_testnet"
    const folder = networkName === "lux" ? "mainnet" : "testnet";

    console.log(`Deploying contracts with the account: ${deployer.address}`);
    const Factory = new ContractFactory(
        factoryArtifact.abi,
        factoryArtifact.bytecode,
        deployer
    );

    const factory = await Factory.deploy(deployer.address);

    console.log(`Factory deployed to ${factory.address}`);
    try {
        await hre.run("verify:verify", {
            address: factory.address,
            contract: "src/uni/uni2/v2-core/contracts/UniswapV2Factory.sol:UniswapV2Factory",
        constructorArguments: [deployer.address],
        });
    } catch(error) {
        console.log("already verified");
    }

    fs.writeFileSync(`deployments/${folder}/UniswapV2Factory.json`, JSON.stringify({
        address: factory.address,
        abi: JSON.parse(fs.readFileSync('./artifacts/src/uni/uni2/v2-core/contracts/UniswapV2Factory.sol/UniswapV2Factory.json', 'utf8')).abi,
    }, null, 2));

    console.log('Contract ABI and address saved to UniswapV2Factory.json');

    const USDT = await ethers.getContractFactory("Tether", deployer);
    const usdt = await USDT.deploy();
    console.log(`USDT deployed to ${usdt.address}`);
    try {
        await hre.run("verify:verify", {
            address: usdt.address,
            contract: "src/uni/uni2/USDT.sol:Tether",
        constructorArguments: [],
        });
    } catch(error) {
        console.log("already verified");
    }
    fs.writeFileSync(`deployments/${folder}/mockUSDT.json`, JSON.stringify({
        address: usdt.address,
        abi: JSON.parse(fs.readFileSync('./artifacts/src/uni/uni2/USDT.sol/Tether.json', 'utf8')).abi,
    }, null, 2));
    console.log('Contract ABI and address saved to mockUSDT.json');


    const USDC = await ethers.getContractFactory("UsdCoin", deployer);

    const usdc = await USDC.deploy();
    console.log(`USDC deployed to ${usdc.address}`);
    try {
        await hre.run("verify:verify", {
            address: usdc.address,
            contract: "src/uni/uni2/USDC.sol:UsdCoin",
        constructorArguments: [],
        });
    } catch(error) {
        console.log("already verified");
    }
    fs.writeFileSync(`deployments/${folder}/mockUSDC.json`, JSON.stringify({
        address: usdc.address,
        abi: JSON.parse(fs.readFileSync('./artifacts/src/uni/uni2/USDC.sol/UsdCoin.json', 'utf8')).abi,
    }, null, 2));
    console.log('Contract ABI and address saved to mockUSDC.json');

    /**
     * Now that we have deployed the Factory contract and the two ERC20 tokens,
     * we can deploy the Router contract.
     * The Router contract requires the address of the Factory contract and the WLUX contract.
     * The WLUX contract is a wrapper for the ETH token.
     * But prior to that, we need to mint some USDT and USDC tokens to the deployer. Lets do that first.
     */

    // Mint 1000 USDT tokens to the deployer.
    await usdt.connect(deployer).mint(deployer.address, ethers.utils.parseEther("1000"));

    // Mint 1000 USDC tokens to the deployer.
    await usdc.connect(deployer).mint(deployer.address, ethers.utils.parseEther("1000"));

    // Utilizing the Factory contract, create a trading pair using the addresses of USDT and USDC.
    const tx1 = await factory.createPair(usdt.address, usdc.address);

    // Wait for the transaction to be confirmed on the blockchain.
    await tx1.wait();

    // Retrieve the address of the created trading pair from the Factory contract.
    const pairAddress = await factory.getPair(usdt.address, usdc.address);
    console.log(`Pair deployed to ${pairAddress}`);

    // Initialize a new contract instance for the trading pair using its address and ABI.
    const pair = new Contract(pairAddress, pairArtifact.abi, deployer);

    // Query the reserves of the trading pair to check liquidity.
    let reserves = await pair.getReserves();
    console.log(`Reserves: ${reserves[0].toString()}, ${reserves[1].toString()}`);

    // Initialize a new contract factory for the WLUX contract.
    const WLUX = await ethers.getContractFactory("WLUX", deployer);
    const wlux = await WLUX.deploy();
    console.log(`WLUX deployed to ${wlux.address}`);
    try {
    await hre.run("verify:verify", {
        address: wlux.address,
        contract: "src/uni/uni2/v2-periphery/contracts/test/WLUX.sol:WLUX",
    constructorArguments: [],
    });
    } catch(error) {
        console.log("already verified");
    }
    fs.writeFileSync(`deployments/${folder}/WLUX.json`, JSON.stringify({
        address: wlux.address,
        abi: JSON.parse(fs.readFileSync('./artifacts/src/uni/uni2/v2-periphery/contracts/test/WLUX.sol/WLUX.json', 'utf8')).abi,
    }, null, 2));
    console.log('Contract ABI and address saved to WLUX.json');

    // Initialize a new contract factory for the Router contract.
    const Router = await ethers.getContractFactory("UniswapV2Router02", deployer);

    // Deploy the Router contract using the above-initialized factory.
    const router = await Router.deploy(factory.address, wlux.address);
    console.log(`Router deployed to ${router.address}`);
    try {
    await hre.run("verify:verify", {
        address: router.address,
        contract: "src/uni/uni2/v2-periphery/contracts/UniswapV2Router02.sol:UniswapV2Router02",
    constructorArguments: [factory.address, wlux.address],
    });
    } catch(error) {
        console.log("already verified");
    }
    fs.writeFileSync(`deployments/${folder}/UniswapV2Router02.json`, JSON.stringify({
        address: router.address,
        abi: JSON.parse(fs.readFileSync('./artifacts/src/uni/uni2/v2-periphery/contracts/UniswapV2Router02.sol/UniswapV2Router02.json', 'utf8')).abi,
    }, null, 2));
    console.log('Contract ABI and address saved to UniswapV2Router02.json');

    const MaxUint256 =
        "0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff";

    const approveTx1 = await usdt.approve(router.address, MaxUint256);
    await approveTx1.wait();
    const approvalTx2 = await usdc.approve(router.address, MaxUint256);
    await approvalTx2.wait();

    const token0Amount = ethers.utils.parseUnits("100");
    const token1Amount = ethers.utils.parseUnits("100");

    const lpTokenBalanceBefore = await pair.balanceOf(deployer.address);
    console.log(
        `LP tokens for the deployer before: ${lpTokenBalanceBefore.toString()}`
    );

    const deadline = Math.floor(Date.now() / 1000) + 10 * 60;
    try {
    const addLiquidityTx = await router
        .connect(deployer)
        .addLiquidity(
        usdt.address,
        usdc.address,
        token0Amount,
        token1Amount,
        0,
        0,
        deployer.address,
        deadline
        );
        await addLiquidityTx.wait();

    } catch (error) {
        console.log('Transaction reverted with error:', error.reason);
      }

    // Check LP token balance for the deployer
    const lpTokenBalance = await pair.balanceOf(deployer.address);
    console.log(`LP tokens for the deployer: ${lpTokenBalance.toString()}`);

    reserves = await pair.getReserves();
    console.log(`Reserves: ${reserves[0].toString()}, ${reserves[1].toString()}`);

    console.log("USDT_ADDRESS", usdt.address);
    console.log("USDC_ADDRESS", usdc.address);
    console.log("WLUX_ADDRESS", wlux.address);
    console.log("V2FACTORY_ADDRESS", factory.address);
    console.log("ROUTER_ADDRESS", router.address);
    console.log("PAIR_ADDRESS", pairAddress);
}

// This command is used to run the script using hardhat.
// npx hardhat run --network LuxNetwork scripts/lux-deploy.ts

// Executing the main function and handling possible outcomes.
main()
  .then(() => process.exit(0)) // Exiting the process if deployment is successful.
  .catch((error) => {
    console.error(error); // Logging any errors encountered during deployment.
    process.exit(1); // Exiting the process with an error code.
  });
