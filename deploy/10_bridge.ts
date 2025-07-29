// 10_bridge.ts

import { Deploy } from '@luxfi/standard/utils/deploy'

export default Deploy('Bridge', { dependencies: ['DAO'] }, async ({ ethers, deploy, deployments, deps, hre }) => {
  const { DAO } = deps
  const tx = await deploy([DAO.address, 25])

  await deployments.fixture(["ZOO"]);

  const myContract = await deployments.get("ZOO");

  const zoo = await ethers.getContractAt(
    myContract.abi,
    myContract.address
  );



  await zoo.configure(tx.address)
})
