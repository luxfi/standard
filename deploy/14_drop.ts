// 14_drop.ts
import { Deploy } from '@luxdefi/contracts/utils/deploy'
// import mint from '../utils/mint'

export default Deploy('Drop', {}, async ({ hre, ethers, deploy }) => {
  const tx = await deploy(['Gen 0'])

  if (hre.network.name == 'mainnet') return

  const drop = await ethers.getContractAt('Drop', tx.address)
  const app = await ethers.getContract('App')

  console.log('App.addDrop', drop.address)
  await (await app.addDrop(drop.address)).wait()

  console.log('Drop.configure', app.address)
  await (await drop.configure(app.address)).wait()
})
