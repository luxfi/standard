import hre, { ethers } from "hardhat";
import {SignerWithAddress} from "@nomiclabs/hardhat-ethers/signers";
const fs = require('fs');  // Import the File System module

//(mainnet) npx hardhat run --network lux deploy/20_uniswapv3_core.ts
//(testnet) npx hardhat run --network lux_testnet deploy/20_uniswapv3_core.ts
async function main() {
    let deployer: SignerWithAddress;

    [deployer] = await ethers.getSigners();

    const univ3FactoryFactory = await ethers.getContractFactory("UniswapV3Factory", deployer);

    const factoryv3 = await univ3FactoryFactory.deploy();

    await factoryv3.deployed();
    console.log(`Factory v3 deployed at: ${factoryv3.address}`);

    await hre.run("verify:verify", {
        address: factoryv3.address,
        contract: "src/uni3/core/contracts/UniswapV3Factory.sol:UniswapV3Factory",
      constructorArguments: [],
    });

     // Load the ABI from the compiled contract artifacts
    const abi = JSON.parse(fs.readFileSync('./artifacts/src/uni3/core/contracts/UniswapV3Factory.sol/UniswapV3Factory.json', 'utf8')).abi;

    fs.writeFileSync('deployments/mainnet/UniswapV3Factory.json', JSON.stringify({
        address: factoryv3.address,
        abi: abi,
    }, null, 2));

    console.log('Contract ABI and address saved to UniswapV3Factory.json');
    return;
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
