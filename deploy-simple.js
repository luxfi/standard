const { ethers } = require("hardhat");
const fs = require("fs");

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("Deploying contracts with account:", deployer.address);

  const contracts = {};

  // WLUX is already deployed
  contracts.WLUX = "0x5FbDB2315678afecb367f032d93F642f64180aa3";
  console.log("WLUX already deployed at:", contracts.WLUX);

  // Deploy USDC
  const USDC = await ethers.getContractFactory("USDC");
  const usdc = await USDC.deploy(ethers.utils.parseUnits("1000000", 6), [deployer.address]);
  await usdc.deployed();
  contracts.USDC = usdc.address;
  console.log("USDC deployed to:", usdc.address);

  // Deploy USDT
  const USDT = await ethers.getContractFactory("USDT");
  const usdt = await USDT.deploy(ethers.utils.parseUnits("1000000", 6), [deployer.address]);
  await usdt.deployed();
  contracts.USDT = usdt.address;
  console.log("USDT deployed to:", usdt.address);

  // Deploy UniswapV2Factory
  const UniswapV2Factory = await ethers.getContractFactory("UniswapV2Factory");
  const factory = await UniswapV2Factory.deploy(deployer.address);
  await factory.deployed();
  contracts.UniswapV2Factory = factory.address;
  console.log("UniswapV2Factory deployed to:", factory.address);

  // Deploy UniswapV2Router02
  const UniswapV2Router02 = await ethers.getContractFactory("UniswapV2Router02");
  const router = await UniswapV2Router02.deploy(factory.address, contracts.WLUX);
  await router.deployed();
  contracts.UniswapV2Router02 = router.address;
  console.log("UniswapV2Router02 deployed to:", router.address);

  // Deploy DAO
  const DAO = await ethers.getContractFactory("DAO");
  const dao = await DAO.deploy();
  await dao.deployed();
  contracts.DAO = dao.address;
  console.log("DAO deployed to:", dao.address);

  // Deploy Bridge
  const Bridge = await ethers.getContractFactory("Bridge");
  const bridge = await Bridge.deploy(dao.address, 25);
  await bridge.deployed();
  contracts.Bridge = bridge.address;
  console.log("Bridge deployed to:", bridge.address);

  // Save deployment addresses
  const deployment = {
    chainId: 31337,
    contracts: contracts,
    deployer: deployer.address,
    timestamp: new Date().toISOString()
  };

  fs.writeFileSync(
    "/Users/z/work/lux/stack/deployments/localhost.json",
    JSON.stringify(deployment, null, 2)
  );

  console.log("\nDeployment complete! Addresses saved to /Users/z/work/lux/stack/deployments/localhost.json");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });