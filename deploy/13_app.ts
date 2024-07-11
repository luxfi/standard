// 13_app.ts

import { Deploy } from '@luxdefi/contracts/utils/deploy'

export default Deploy(
  'App',
  {
    dependencies: ['Media', 'Market'],
    proxy: { kind: 'uups' },
  },
  async ({ ethers, deploy, hre }) => {
    const tx = await deploy()

    const app = await ethers.getContractAt('App', tx.address)
    const market = await ethers.getContract('Market')
    const media = await ethers.getContract('Media')

    // Configure contracts to talk to each other
    await (await market.configure(media.address)).wait()
    await (await media.configure(app.address, market.address)).wait()
    await (await app.configure(media.address, market.address)).wait()
  },
)
