// 01_faucet.ts

import { Deploy } from '@zoolabs/standard/utils/deploy'

export default Deploy('Faucet', { dependencies: ['ZOO'] }, async ({ ethers, deploy, deployments, deps, hre }) => {



  await deployments.fixture(["ZOO"]);

  const myContract = await deployments.get("ZOO");

  const token = await ethers.getContractAt(
    myContract.abi,
    myContract.address
  );


  // const token = await ethers.getContract('ZOO')

  const tx = await deploy([token.address])

  if (hre.network.name == 'mainnet') return

  // 100B ZOO to faucet
  const exp = ethers.BigNumber.from('10').pow(18)
  const amount = ethers.BigNumber.from('1000000000000').mul(exp)
  await token.mint(tx.address, amount)

  // Get signers to fund
  const signers = await ethers.getSigners()

  // 100M ZOO to each signer
  const signerAmount = ethers.BigNumber.from('1000000000').mul(exp)

  // Mint new tokens
  for (var i = 0; i < signers.length; i++) {
    await token.mint(signers[i].address, signerAmount)
  }
})
