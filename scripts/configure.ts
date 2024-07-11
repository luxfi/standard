import { ethers } from 'hardhat'
import mint from '../utils/mint'
import { validateConfiguration } from '../utils/validation'

const NETWORK = process.env.HARDHAT_NETWORK ? process.env.HARDHAT_NETWORK : 'hardhat'

console.log(`Configure on ${NETWORK}`)

const DEPLOYMENT = {
  localhost: 'localhost',
  hardhat: 'localhost',
  testnet: 'testnet',
  mainnet: 'mainnet',
}[NETWORK]

const App = require(`../deployments/${DEPLOYMENT}/App.json`)
const Drop = require(`../deployments/${DEPLOYMENT}/Drop.json`)
const Media = require(`../deployments/${DEPLOYMENT}/Media.json`)
const Market = require(`../deployments/${DEPLOYMENT}/Market.json`)

async function main() {
  const [signer] = await ethers.getSigners()

  const app = await (await ethers.getContractAt('App', App.address)).connect(signer)
  const drop = await (await ethers.getContractAt('Drop', Drop.address)).connect(signer)
  const media = await (await ethers.getContractAt('Media', Media.address)).connect(signer)
  const market = await (await ethers.getContractAt('Market', Market.address)).connect(signer)

  await validateConfiguration({ app, drop, media, market })

  await mint(app, drop, NETWORK)
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error)
    process.exit(1)
  })
