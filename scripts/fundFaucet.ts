#!/usr/bin/env node

import { ethers } from 'hardhat'
const { BigNumber } = ethers
const ZooToken = require('../deployments/testnet/ZOO.json')
const Drop = require('../deployments/testnet/Drop.json')
const Faucet = require('../deployments/testnet/Faucet.json')

async function main() {
  const { deployer } = await ethers.getNamedSigners()
  const signers = await ethers.getSigners();
  const token = (await ethers.getContractAt('ZOO', ZooToken.address)).connect(deployer)
  const faucet = (await ethers.getContractAt('Faucet', Faucet.address)).connect(deployer)
  // const drop = await (await ethers.getContractAt('Drop', ZooToken.address)).connect(signers[0])
  const fundAmount = BigNumber.from(1000000000000)
  // console.log('token ->', faucet.address)
  const tx1 = await token.mint(faucet.address, fundAmount.mul(10 * 18))
  console.log('Minted Zoo for faucet')
  const tx2 = await token.mint(signers[0].address, fundAmount.mul(10 * 18))
  console.log('Minted Zoo for Signer', signers[0].address)
  process.exit(0);
}

main()
  .then(() => process.exit(0))
  .catch((e) => {
    console.error(e)
    process.exit(-1)
  })
