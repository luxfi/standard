import { ethers } from 'hardhat'

// import { bytecode } from '../deployments/localhost/UniswapV2Pair.json'
// import { deployedBytecode } from '../deployments/localhost/UniswapV2Pair.json'
import { keccak256 } from '@ethersproject/solidity'

async function main() {
  // const initcode = keccak256(['bytes'], [bytecode])
  // console.log('UniswapV2Pair INIT_CODE:', initcode)
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error)
    process.exit(1)
  })
