// 15_auction.ts

import { HardhatRuntimeEnvironment } from 'hardhat/types'
import { DeployFunction } from 'hardhat-deploy/types'

// Change to support Deploy helper
const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const { deployments, ethers, getNamedAccounts, network } = hre
  const { deploy } = deployments
  const { deployer } = await getNamedAccounts()

  const deployResult = await deploy('Auction', {
    from: deployer,
    args: [],
    log: true,
  })

  const tokenAddress = (await deployments.get('ZOO')).address
  const mediaAddress = (await deployments.get('Media')).address

  const auction = await ethers.getContractAt('Auction', deployResult.address)
  auction.configure(mediaAddress, tokenAddress)

  return hre.network.live
}

export default func
func.id = 'auction'
func.tags = ['Auction']
// func.dependencies = ['Media', 'Market']
