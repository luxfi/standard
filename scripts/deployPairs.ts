import { ethers, upgrades } from 'hardhat'

async function main() {
  const MockERC20 = await ethers.getContractFactory('MockERC20')
  const UniswapV2Factory = await ethers.getContractFactory('UniswapV2Factory')
  const UniswapV2Pair = await ethers.getContractFactory('UniswapV2Pair')
  const FarmTokenV2 = await ethers.getContractFactory('FarmTokenV2')
  const Farm = await ethers.getContractFactory('Farm')

  // Attach to farm, token contracts
  const farm  = await Farm.attach('0x0')
  const token = await FarmTokenV2.attach('0x0')

  // Get current account
  const [signer] = await ethers.getSigners()

  // Create mock ERC20's for each token we'll create trading pairs for
  const weth  = await MockERC20.deploy('WETH',  'WETH',  '100000000000')
  const sushi = await MockERC20.deploy('SUSHI', 'SUSHI', '100000000000')
  const link  = await MockERC20.deploy('LINK',  'LINK',  '100000000000')
  const usdc  = await MockERC20.deploy('USDC',  'USDC',  '100000000000')
  const comp  = await MockERC20.deploy('COMP',  'COMP',  '100000000000')
  const uni   = await MockERC20.deploy('UNI',   'UNI',   '100000000000')
  const yfi   = await MockERC20.deploy('YFI',   'YFI',   '100000000000')

  console.log('WETH address', weth.address)
  console.log('SUSHI address', sushi.address)
  console.log('LINK address', link.address)
  console.log('USDC address', usdc.address)
  console.log('COMP address', comp.address)
  console.log('UNI address', uni.address)
  console.log('YFI address', yfi.address)

  // Get factory instance (same address on each network)
  const factory = await UniswapV2Factory.attach('0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f')

  // Create trading pairs
  await factory.createPair(weth.address, sushi.address)
  await factory.createPair(weth.address, link.address)
  await factory.createPair(weth.address, usdc.address)
  await factory.createPair(weth.address, comp.address)
  await factory.createPair(weth.address, uni.address)
  await factory.createPair(weth.address, yfi.address)

  console.log('SUSHI LP address', await factory.getPair(weth.address, sushi.address))
  console.log('LINK LP address',  await factory.getPair(weth.address, link.address))
  console.log('USDC LP address',  await factory.getPair(weth.address, usdc.address))
  console.log('COMP LP address',  await factory.getPair(weth.address, comp.address))
  console.log('UNI LP address',   await factory.getPair(weth.address, uni.address))
  console.log('YFI LP address',   await factory.getPair(weth.address, yfi.address))
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error)
    process.exit(1)
  })
