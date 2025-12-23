import { ContractFactory, ethers } from 'ethers'
import hre from 'hardhat'
import { getContractData, sleep, verifyContract } from './utils'

async function main() {
  let artifacts = getContractData()

  const [owner] = await hre.ethers.getSigners()

  let nonfungiblePositionManager
  let nonfungibleTokenPositionDescriptor
  let swapRouter
  let v3Migrator
  let quoterV2
  let nftDescriptorEx

  const NonfungibleTokenPositionDescriptor = new ContractFactory(
    artifacts.NonfungibleTokenPositionDescriptor.abi,
    artifacts.NonfungibleTokenPositionDescriptor.bytecode,
    owner
  )

  nonfungibleTokenPositionDescriptor = await NonfungibleTokenPositionDescriptor.deploy(
    '0x7b79995e5f793A07Bc00c21412e50Ecae098E7f9',
    '0x4554480000000000000000000000000000000000000000000000000000000000',
    '0x6534f88646a4A5FBAA154b242F3B900D9340d3aA'
  )

  console.log('NonfungibleTokenPositionDescriptor:', nonfungibleTokenPositionDescriptor.address)

  const NonfungiblePositionManager = new ContractFactory(
    artifacts.NonfungiblePositionManager.abi,
    artifacts.NonfungiblePositionManager.bytecode,
    owner
  )

  nonfungiblePositionManager = await NonfungiblePositionManager.deploy(
    '0x86044FAD07EC39214F7341230A3FE2930726a6CE',
    '0x7b79995e5f793A07Bc00c21412e50Ecae098E7f9',
    '0x308359c543612803CD0Bc292f970F1401Adf3C2c'
  )

  console.log('NonfungiblePositionManager:', nonfungiblePositionManager.address)

  const SwapRouter = new ContractFactory(artifacts.SwapRouter.abi, artifacts.SwapRouter.bytecode, owner)

  swapRouter = await SwapRouter.deploy(
    '0x86044FAD07EC39214F7341230A3FE2930726a6CE',
    '0x7b79995e5f793A07Bc00c21412e50Ecae098E7f9'
  )

  console.log('SwapRouter:', swapRouter.address)

  const QuoterV2 = new ContractFactory(artifacts.QuoterV2.abi, artifacts.QuoterV2.bytecode, owner)

  quoterV2 = await QuoterV2.deploy(
    '0x86044FAD07EC39214F7341230A3FE2930726a6CE',
    '0x7b79995e5f793A07Bc00c21412e50Ecae098E7f9'
  )

  console.log('QuoterV2:', quoterV2.address)

  const NFTDescriptorEx = new ContractFactory(artifacts.NFTDescriptorEx.abi, artifacts.NFTDescriptorEx.bytecode, owner)

  nftDescriptorEx = await NFTDescriptorEx.deploy()

  console.log('NFTDescriptorEx:', nftDescriptorEx.address)

  const V3Migrator = new ContractFactory(artifacts.V3Migrator.abi, artifacts.V3Migrator.bytecode, owner)

  v3Migrator = await V3Migrator.deploy(
    '0x86044FAD07EC39214F7341230A3FE2930726a6CE',
    '0x7b79995e5f793A07Bc00c21412e50Ecae098E7f9',
    '0x32984d00Fcd29e8F2AF269A548771d967be51C83'
  )

  console.log('V3Migrator:', v3Migrator.address)
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error)
    process.exit(1)
  })
