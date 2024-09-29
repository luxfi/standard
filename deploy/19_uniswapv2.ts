// Importing required modules and libraries from the ethers.js library.
import { Contract, ContractFactory, Wallet } from "ethers";
import { ethers } from "hardhat";
import fs from "fs";
import * as dotenv from "dotenv";

// Importing the contract JSON artifacts.
import WETH9 from "../WETH9.json";
import factoryArtifact from "@uniswap/v2-core/build/UniswapV2Factory.json";
import routerArtifact from "@uniswap/v2-periphery/build/UniswapV2Router02.json";
import pairArtifact from "@uniswap/v2-periphery/build/IUniswapV2Pair.json";

dotenv.config();
const PRIVATE_KEY = process.env.PRIVATE_KEY || "";
const RPC_ENDPOINT = process.env.RPC_ENDPOINT || "";

// Main deployment function.
async function main() {
    // 1. Retrieve signers from the ethers provider.
    const wallet = new Wallet(PRIVATE_KEY);
    const provider = new ethers.JsonRpcProvider(RPC_ENDPOINT);
    const deployer = wallet.connect(provider);

    console.log(`Deploying contracts with the account: ${deployer.address}`);

    // 2. Initialize a new contract factory for the Uniswap V2 Factory.
    const Factory = new ContractFactory(
        factoryArtifact.abi,
        factoryArtifact.bytecode,
        deployer
    );

    // 3. Use the initialized factory to deploy a new Factory contract.
    const factory = await Factory.deploy(deployer.address);

    // 4. After deployment, retrieve the address of the newly deployed Factory contract.
    const factoryAddress = await factory.getAddress();
    console.log(`Factory deployed to ${factoryAddress}`);

    // 5. Initialize a contract factory specifically for the Tether (USDT) token.
    const USDT = await ethers.getContractFactory("Tether", deployer);

    // 6. Deploy the USDT contract using the above-initialized factory.
    const usdt = await USDT.deploy();

    // 7. Get the address of the deployed USDT contract.
    const usdtAddress = await usdt.getAddress();
    console.log(`USDT deployed to ${usdtAddress}`);

    // 8. Similarly, initialize a contract factory for the UsdCoin (USDC) token.
    const USDC = await ethers.getContractFactory("UsdCoin", deployer);

    // 9. Deploy the USDC contract.
    const usdc = await USDC.deploy();

    // 10. Get the address of the deployed USDC contract.
    const usdcAddress = await usdc.getAddress();
    console.log(`USDC deployed to ${usdcAddress}`);

    /**
     * Now that we have deployed the Factory contract and the two ERC20 tokens,
     * we can deploy the Router contract.
     * The Router contract requires the address of the Factory contract and the WETH9 contract.
     * The WETH9 contract is a wrapper for the ETH token.
     * But prior to that, we need to mint some USDT and USDC tokens to the deployer. Lets do that first.
     */

    // 11. Mint 1000 USDT tokens to the deployer.
    await usdt.connect(deployer).mint(deployer.address, ethers.parseEther("1000"));

    // 12. Mint 1000 USDC tokens to the deployer.
    await usdc.connect(deployer).mint(deployer.address, ethers.parseEther("1000"));

    // 13. Utilizing the Factory contract, create a trading pair using the addresses of USDT and USDC.
    const tx1 = await factory.createPair(usdtAddress, usdcAddress);

    // 14. Wait for the transaction to be confirmed on the blockchain.
    await tx1.wait();

    // 15. Retrieve the address of the created trading pair from the Factory contract.
    const pairAddress = await factory.getPair(usdtAddress, usdcAddress);
    console.log(`Pair deployed to ${pairAddress}`);

    // 16. Initialize a new contract instance for the trading pair using its address and ABI.
    const pair = new Contract(pairAddress, pairArtifact.abi, deployer);

    // 17. Query the reserves of the trading pair to check liquidity.
    let reserves = await pair.getReserves();
    console.log(`Reserves: ${reserves[0].toString()}, ${reserves[1].toString()}`);

    // 18. Initialize a new contract factory for the WETH9 contract.
    const WETH = new ContractFactory(WETH9.abi, WETH9.bytecode, deployer);
    const weth = await WETH.deploy();
    const wethAddress = await weth.getAddress();
    console.log(`WETH deployed to ${wethAddress}`);

    // 19. Initialize a new contract factory for the Router contract.
    const Router = new ContractFactory(
        routerArtifact.abi,
        routerArtifact.bytecode,
        deployer
    );

    // 20. Deploy the Router contract using the above-initialized factory.
    const router = await Router.deploy(factoryAddress, wethAddress);
    const routerAddress = await router.getAddress();
    console.log(`Router deployed to ${routerAddress}`);

    const MaxUint256 =
        "0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff";

    const approveTx1 = await usdt.approve(routerAddress, MaxUint256);
    await approveTx1.wait();
    const approvalTx2 = await usdc.approve(routerAddress, MaxUint256);
    await approvalTx2.wait();

    const token0Amount = ethers.parseUnits("100");
    const token1Amount = ethers.parseUnits("100");

    const lpTokenBalanceBefore = await pair.balanceOf(deployer.address);
    console.log(
        `LP tokens for the deployer before: ${lpTokenBalanceBefore.toString()}`
    );

    const deadline = Math.floor(Date.now() / 1000) + 10 * 60;
    const addLiquidityTx = await router
        .connect(deployer)
        .addLiquidity(
        usdtAddress,
        usdcAddress,
        token0Amount,
        token1Amount,
        0,
        0,
        deployer.address,
        deadline
        );
    await addLiquidityTx.wait();

    // Check LP token balance for the deployer
    const lpTokenBalance = await pair.balanceOf(deployer.address);
    console.log(`LP tokens for the deployer: ${lpTokenBalance.toString()}`);

    reserves = await pair.getReserves();
    console.log(`Reserves: ${reserves[0].toString()}, ${reserves[1].toString()}`);

    console.log("USDT_ADDRESS", usdtAddress);
    console.log("USDC_ADDRESS", usdcAddress);
    console.log("WETH_ADDRESS", wethAddress);
    console.log("FACTORY_ADDRESS", factoryAddress);
    console.log("ROUTER_ADDRESS", routerAddress);
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
