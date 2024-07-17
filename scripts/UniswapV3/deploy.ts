import { ContractFactory, ethers } from "ethers";
import hre from 'hardhat';
import { getContractData } from "./utils";

async function main() {
  let artifacts = getContractData();

  const [owner] = await hre.ethers.getSigners();
  console.log("owner", owner.address);

  let uniswapV3PoolDeployer;
  let uniswapV3Factory;

  const UniswapV3PoolDeployer = new ContractFactory(
    artifacts.UniswapV3PoolDeployer.abi,
    artifacts.UniswapV3PoolDeployer.bytecode,
    owner
  );

  uniswapV3PoolDeployer = await UniswapV3PoolDeployer.deploy();

  let uniswapV3PoolDeployerAddress = await uniswapV3PoolDeployer.getAddress();

  console.log(
    "uniswapV3PoolDeployerAddress deployed to:",
    uniswapV3PoolDeployerAddress
  );

  const UniswapV3Factory = new ContractFactory(
    artifacts.UniswapV3Factory.abi,
    artifacts.UniswapV3Factory.bytecode,
    owner
  );
  uniswapV3Factory = await UniswapV3Factory.deploy();

  let uniswapV3FactoryAddress = await uniswapV3Factory.getAddress();

  console.log("uniswapV3Factory", uniswapV3FactoryAddress);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
