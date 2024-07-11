// Generated from Yield Matrix spreadsheet (see: `yarn matrix`)
import rarities from './rarities.json'
import animals from './animals.json'
import hybrids from './hybrids.json'

// Configure game for our Gen 0 drop
export default async function configureGame(dlux: any, drop: any) {

  // Add Drop to DLUX
  await dlux.addDrop(drop.address)

  // Set name price
  await dlux.setNamePrice(18000)

  // Configure Drop
  await drop.configureDAO(dlux.address)

  // Add nfts
  const nfts = [
    {
      name: 'Base NFT',
      price: 360000,
      supply: 18000,
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

  nfts.map(async (v) => {
    await drop.setNFT(v.name, v.price, v.supply, v.tokenURI, v.metadataURI)
  })

  await drop.configureNFTs(1)

  // // Add rarities
  rarities.sort(function (a, b) {
    return a.probability - b.probability
  })
  rarities.map(async (v) => {
    await drop.setRarity(v.name, v.probability, v.yields, v.boost)
  })

  // Add animals
  animals.map(async (v) => {
    await drop.setAnimal(v.name, v.rarity, v.tokenURI, v.metadataURI, v.tokenURI, v.metadataURI, v.tokenURI, v.metadataURI)
  })

  // Add hybrids
  hybrids.map(async (v) => {
    await drop.setHybrid(v.name, v.rarity, v.yields, v.parentA, v.parentB, v.tokenURI, v.metadataURI)
  })
}
