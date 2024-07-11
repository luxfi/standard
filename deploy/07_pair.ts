//// 07_pair.ts

import { Deploy } from '@zoolabs/contracts/utils/deploy'

export default Deploy('UniswapV2Pair', { dependencies: ['BNB', 'ZOO', 'UniswapV2Factory', 'UniswapV2Router02'] }, async ({ ethers, hre, deploy, deployments, deps, signers }) => {
  // Import so we have the JSON
  if (hre.network.name == 'hardhat') await deploy()


  await deployments.fixture(["BNB"]);

  let myContract = await deployments.get("BNB");

  const bnb = await ethers.getContractAt(
    myContract.abi,
    myContract.address
  );

  // const bnb = await ethers.getContract('BNB')

  await deployments.fixture(["ZOO"]);

  myContract = await deployments.get("ZOO");

  const zoo = await ethers.getContractAt(
    myContract.abi,
    myContract.address
  );

  // const zoo = await ethers.getContract('ZOO')


  await deployments.fixture(["UniswapV2Factory"]);

  myContract = await deployments.get("UniswapV2Factory");

  const factory = await ethers.getContractAt(
    myContract.abi,
    myContract.address
  );

  // const factory = await ethers.getContract('UniswapV2Factory')



  await deployments.fixture(["UniswapV2Router02"]);

  myContract = await deployments.get("UniswapV2Router02");

  const router = await ethers.getContractAt(
    myContract.abi,
    myContract.address
  );


  // const router = await ethers.getContract('UniswapV2Router02')

  if (hre.network.name == 'mainnet') return

  const signer = signers[0]
  const amountZOO = ethers.utils.parseUnits('420000000', 18)
  const amountBNB = ethers.utils.parseUnits('150', 18)

  // Create new LP pair
  const tx = await factory.createPair(zoo.address, bnb.address)
  await tx.wait()

  // Get pair
  const pair = await factory.getPair(zoo.address, bnb.address)
  console.log('UniswapV2Pair', pair)

  // Mint token for Liquidity Pool
  await bnb.mint(signer.address, amountBNB)
  await zoo.mint(signer.address, amountZOO)

  // Appove for Router to withdraw
  await bnb.approve(router.address, amountBNB)
  await zoo.approve(router.address, amountZOO)

  // Add liquidity
  // await router.addLiquidity(
  //   zoo.address,
  //   bnb.address,
  //   amountZOO, amountBNB,
  //   100, 100,
  //   signer.address,
  //   2e9
  // )
})
