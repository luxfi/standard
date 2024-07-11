import { ethers, upgrades } from 'hardhat'

async function main() {
  const MockERC20 = await ethers.getContractFactory('MockERC20')
  const UniswapV2Factory = await ethers.getContractFactory('UniswapV2Factory')
  const UniswapV2Pair = await ethers.getContractFactory('UniswapV2Pair')
  const Token = await ethers.getContractFactory('ZooFarmTokenV2')
  const Farm = await ethers.getContractFactory('ZooFarm')

  // Get current account
  const [signer] = await ethers.getSigners()

  // Kovan deployed contracts
  const farm    = await Farm.attach('')
  const weth    = await MockERC20.attach('0x8921870C9919e050FC828755B535e69A5802C421')
  const tend    = await MockERC20.attach('0x0dd519F170a06304F966f76997Ec8fAa3e3288dc')
  const sushi   = await MockERC20.attach('0x6c5ee88B617E5319011A1855705B4D22cA7B8d45')
  const link    = await MockERC20.attach('0x1f2e356c6dB6B3916C6f9b67B2cC2E223Cb79325')
  const usdc    = await MockERC20.attach('0x4596AAB9344D78dACaCc4Ae00737052e85C95D2e')
  const comp    = await MockERC20.attach('0x1D71359FDbe96fB0Cc55e22316CF86B808A647F9')
  const uni     = await MockERC20.attach('0xD76A314c33186969a7b71E88936F69ef8f93085F')
  const l2      = await MockERC20.attach('0xB41a7De79c1A88De91D9CCCFaaA3E7a2DD5208C1')
  const yfi     = await MockERC20.attach('0x0e3012A99466FbDB0Cbb4Ccb21A4A3E94C6A60e1')

  // Get factory contract (same on each network)
  const factory = await UniswapV2Factory.attach('0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f')

  // Get pair addresses
  // const tendLp  = await UniswapV2Pair.attach(await factory.getPair(weth.address, tend.address))
  const sushiLp = await UniswapV2Pair.attach(await factory.getPair(weth.address, sushi.address))
  const linkLp  = await UniswapV2Pair.attach(await factory.getPair(weth.address, link.address))
  const usdcLp  = await UniswapV2Pair.attach(await factory.getPair(weth.address, usdc.address))
  const compLp  = await UniswapV2Pair.attach(await factory.getPair(weth.address, comp.address))
  const uniLp   = await UniswapV2Pair.attach(await factory.getPair(weth.address, uni.address))
  const l2Lp    = await UniswapV2Pair.attach(await factory.getPair(weth.address, l2.address))
  const yfiLp   = await UniswapV2Pair.attach(await factory.getPair(weth.address, yfi.address))

  // Add farms
  await farm.add('6',  sushiLp.address, false)
  await farm.add('6',  linkLp.address, false)
  await farm.add('6',  usdcLp.address, false)
  await farm.add('6',  compLp.address, false)
  await farm.add('6',  uniLp.address, false)
  await farm.add('6',  l2Lp.address, false)
  await farm.add('6',  yfiLp.address, false)
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error)
    process.exit(1)
  })
