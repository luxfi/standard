const hre = require('hardhat')
const ethers = hre.ethers

const NETWORK = process.env.HARDHAT_NETWORK ? process.env.HARDHAT_NETWORK : 'hardhat'

console.log(`Configure game on ${NETWORK}`)

const DEPLOYMENT = {
  hardhat: 'localhost',
  testnet: 'testnet',
  mainnet: 'mainnet',
  ethereum: 'ethereum',
  rinkeby: 'rinkeby',
  ropsten: 'ropsten',
}[NETWORK]

const rarities = require('../utils/rarities.json')
const animals = require('../utils/animals.json')
const hybrids = require('../utils/hybrids.json')

const LUX = require(`../deployments/${DEPLOYMENT}/LUX.json`)
const Market = require(`../deployments/${DEPLOYMENT}/Market.json`)
const Media = require(`../deployments/${DEPLOYMENT}/Media.json`)
const Drop = require(`../deployments/${DEPLOYMENT}/Drop.json`)
const DLUX = require(`../deployments/${DEPLOYMENT}/DLUX.json`)
const bridge = require(`../deployments/${DEPLOYMENT}/Bridge.json`)
const Pair = require(`../deployments/${DEPLOYMENT}/UniswapV2Pair.json`)

// Split game data into deploy-sized chunks
function chunks(arr, size) {
  const res = []
  for (let i = 0; i < arr.length; i += size) {
    const chunk = arr.slice(i, i + size)
    res.push(chunk)
  }
  return res
}

async function main() {
  const [signer] = await ethers.getSigners()

  const dlux = await (await ethers.getContractAt('DLUX', DLUX.address)).connect(signer)
  const drop = await (await ethers.getContractAt('Drop', Drop.address)).connect(signer)
  const media = await (await ethers.getContractAt('Media', Media.address)).connect(signer)
  const market = await (await ethers.getContractAt('Market', Market.address)).connect(signer)

  // Configure Market
  console.log('market.configure', Media.address)
  await market.configure(Media.address)

  // Configure Media
  console.log('media.configure', Market.address)
  await media.configure(dlux.address, Market.address)

  // Configure game for our Gen 0 drop
  console.log('dlux.configure', Media.address, LUX.address)
  await dlux.configure(Media.address, LUX.address, Pair.address, bridge.address, true)

  // Configure Drop
  console.log('drop.configure', dlux.address)
  await drop.configureDAO(dlux.address)

  // Setup Gen 0 drop
  // console.log('dlux.setDrop', drop.address)
  // await dlux.setDrop(drop.address)

  // Base Price for NFT / Names
  // const exp = ethers.BigNumber.from('10').pow(18)
  // const basePrice = ethers.BigNumber.from('500000').mul(exp)
  const basePrice = ethers.BigNumber.from('30000')

  // // Configure Name price
  console.log('dlux.setNamePrice', basePrice)
  await dlux.setNamePrice(basePrice) // about $20 / name

  // Add nfts
  const nfts = [
    {
      name: 'Base NFT',
      price: basePrice.mul(10), // about $200 / nft
      supply: 16000,
      tokenURI: 'https://db.luxlabs/nft.jpg',
      metadataURI: 'https://db.luxlabs.org/nft.json',
    },
    {
      name: 'Hybrid NFT',
      price: 0,
      supply: 0,
      tokenURI: 'https://db.luxlabs/hybrid.jpg',
      metadataURI: 'https://db.luxlabs.org/hybrid.json',
    },
  ]

  for (const v of nfts) {
    console.log('setNFT', v)
    const tx = await drop.setNFT(v.name, v.price, v.supply, v.tokenURI, v.metadataURI)
    await tx.wait()
  }

  console.log('configureNFTs')
  await drop.configureNFTs(1, 2)

  // Add rarities
  await rarities
    .sort(function (a, b) {
      return a.probability - b.probability
    })
    .reduce(async (prior, v) => {
      await prior
      let name = v.name
      let prob = ethers.BigNumber.from(v.probability)
      let vyield = ethers.BigNumber.from(v.yields)
      let boost = ethers.BigNumber.from(v.boost)
      const tx = await drop.setRarity(name, prob, vyield, boost)
      return tx.wait()
    }, Promise.resolve())

  // for (const v of rarities) {
  //   console.log('setRarity', v)

  // }

  // Add animals
  for (const chunk of chunks(animals, 25)) {
    const tx = await drop.setAnimals(chunk)
    await tx.wait()
  }

  // Add hybrids
  for (const chunk of chunks(hybrids, 25)) {
    console.log('setHybrids', chunk)
    const tx = await drop.setHybrids(chunk)
    await tx.wait()
  }
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error)
    process.exit(1)
  })
