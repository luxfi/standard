import { Contract, ContractFactory } from 'ethers'
import { run } from 'hardhat'

type ContractJson = { abi: any; bytecode: string }
const artifacts: { [name: string]: ContractJson } = {
  NonfungiblePositionManager: require('../artifacts/contracts/NonfungiblePositionManager.sol/NonfungiblePositionManager.json'),
  NonfungibleTokenPositionDescriptor: require('../artifacts/contracts/NonfungibleTokenPositionDescriptor.sol/NonfungibleTokenPositionDescriptor.json'),
  SwapRouter: require('../artifacts/contracts/SwapRouter.sol/SwapRouter.json'),
  V3Migrator: require('../artifacts/contracts/V3Migrator.sol/V3Migrator.json'),
  TickLens: require('../artifacts/contracts/lens/TickLens.sol/TickLens.json'),
  QuoterV2: require('../artifacts/contracts/lens/QuoterV2.sol/QuoterV2.json'),
  UniswapInterfaceMulticall: require('../artifacts/contracts/lens/UniswapInterfaceMulticall.sol/UniswapInterfaceMulticall.json'),
  NFTDescriptorEx: require('../artifacts/contracts/NFTDescriptorEx.sol/NFTDescriptorEx.json'),
}

export function getContractData() {
  return artifacts
}

export async function verifyContract(contract: string, constructorArguments: any[] = []) {
  try {
    if ((process.env.ETHERSCAN_API_KEY || process.env.API_KEY) && process.env.NETWORK !== 'hardhat') {
      const verify = await run('verify:verify', {
        address: contract,
        constructorArguments,
      })
      console.log('Verified successfully!\n')
    } else {
      console.log('No API key found')
    }
  } catch (error) {
    console.log(
      '....................',
      contract,
      ' error start............................',
      '\n',
      error,
      '\n',
      '....................',
      contract,
      ' error end............................'
    )
  }
}

export function sleep(ms: number) {
  return new Promise((resolve) => setTimeout(resolve, ms))
}
