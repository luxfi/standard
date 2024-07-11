import Web3 from 'web3'
import { OpenSeaSDK, Network } from 'opensea-js'


// give me a real provider
const provider = new Web3.providers.HttpProvider('https://goerli.infura.io/v3/0a9791b1429446f79b38dc6e08efddbd')

// const openseaSDK = new OpenSeaSDK(provider, {
//     networkName: Network.Main,
//     apiKey: '',
//   })

//   // Expire this auction one day from now.
// // Note that we convert from the JavaScript timestamp (milliseconds):
// const expirationTime = Math.round(Date.now() / 1000 + 60 * 60 * 24)

// const listing = await openseaSDK.createSellOrder({
//   // deploy the nft to get the token address and id
//     asset: {
//     tokenId,
//     tokenAddress,
//   },
//   accountAddress,
//   startAmount: 3,
//   // If `endAmount` is specified, the order will decline in value to that amount until `expirationTime`. Otherwise, it's a fixed-price order:
//   endAmount: 0.1,
//   expirationTime
// })

// // Create an auction to receive Wrapped Ether (WETH). See note below.
// const paymentTokenAddress = "" // Zach's address or something

// const startAmount = 0 // The minimum amount to sell for, in normal units (e.g. ETH)

// const auction = await openseaSDK.createSellOrder({
//   asset: {
//     tokenId,
//     tokenAddress,
//   },
//   accountAddress,
//   startAmount,
//   expirationTime,
//   paymentTokenAddress,
//   waitForHighestBid: true
// })
