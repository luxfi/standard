import { ethers } from 'ethers'

type Contracts = {
  app: any
  drop: any
  media: any
  market: any
}

export const validateConfiguration = async ({ app, drop, media, market }: Contracts) => {
  const dropId = await app.dropAddresses(drop.address)
  const dropAddress = await app.drops(dropId)
  if (dropAddress === ethers.constants.AddressZero) {
    throw new Error('App: Drop address not configured')
  }

  const mediaAddress = await app.media()
  if (mediaAddress !== media.address) {
    throw new Error('App: Media address not configured')
  }

  const marketAddress = await app.market()
  if (marketAddress !== market.address) {
    throw new Error('App: Market address not configured')
  }

  const appAddress = await media.appContract()
  if (appAddress !== app.address) {
    throw new Error('Media: App address not configured')
  }

  const mediaMarketAddress = await media.marketContract()
  if (mediaMarketAddress !== market.address) {
    throw new Error('Media: Market address not configured')
  }

  const marketMediaAddress = await market.mediaContract()
  if (marketMediaAddress !== media.address) {
    throw new Error('Market: Media address not configured')
  }

  console.log('Contracts are configured. Proceed...')
}
