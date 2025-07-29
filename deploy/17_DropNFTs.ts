// 17_drop.ts

import { Deploy } from '@luxfi/standard/utils/deploy'

import configureGame from '../utils/configureGame'

export default Deploy('DropNFTs', {}, async({ hre, ethers, deploy, deployments, deps }) => {
  const tx = await deploy()

  if (hre.network.name == 'mainnet') return
})
