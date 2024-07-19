import { HardhatRuntimeEnvironment } from 'hardhat/types'
import { DeployFunction } from 'hardhat-deploy/types'

// Change to support Deploy helper
const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  
  const { deployments, ethers, getNamedAccounts, network } = hre
  const { deploy } = deployments

  const [deployerWallet] = await ethers.getSigners()

  const { deployer } = await getNamedAccounts();

  const deployResult = await deploy('LuxKeeper', {
    from: deployer,
    args: [],
    log: true,
  })
  
  return
  if (hre.network.name == 'mainnet') return

  const zooAddress = await ethers.getContract('ZOO')
  const factory = await ethers.getContract('UniswapV2Factory')
  const bridge = await ethers.getContract('Bridge')
  const market = await ethers.getContract('Market')
  const media = await ethers.getContract('Media')
  const bnb = await ethers.getContract('BNB')


  const keeper = await ethers.getContractAt('LuxKeeper', deployResult.address)

  const pair = await factory.connect(deployerWallet).getPair(zooAddress.address, bnb.address)
  

  await market.connect(deployerWallet).configure(media.address)
  await media.connect(deployerWallet).configure(keeper.address, market.address)
  await keeper.connect(deployerWallet).configure(media.address, zooAddress.address, pair, bridge.address, true)

  //   // Mint ZOO to keeper for yield
  await zooAddress.connect(deployerWallet).mint(keeper.address, 1000000000000)

  return hre.network.live
}

export default func
func.id = 'zooKeeper'
func.tags = ['LuxKeeper']
func.dependencies = ['Bridge', 'Media', 'ZOO', 'BNB', 'Market', 'UniswapV2Factory', 'UniswapV2Pair']
