// 14_drop.ts

import { Deploy } from '@zoolabs/contracts/utils/deploy'

import configureGame from '../utils/configureGame'

export default Deploy('DropEggs', {}, async({ hre, ethers, deploy, deployments, deps }) => {
  const tx = await deploy()

  if (hre.network.name == 'mainnet') return
})
