import { HardhatUserConfig } from 'hardhat/config'

import fs from 'fs'
import { ethers } from 'ethers'

const alchemyKey = 'EuD-FVgI2gMBGf0aypDghsPHYWHB9nhn'

function mnemonic() {
  try {
    return fs.readFileSync(`./mnemonic.txt`).toString().trim()
  } catch (e) {
    console.log('☢️  warning: No mnemonic file created for a deploy account. Try `yarn run generate` and then `yarn run account`.')
  }
  return ''
}

//
// Select the network you want to deploy to here:
//
const networks: HardhatUserConfig['networks'] = {
  hardhat: {
    chainId: 1337,
    allowUnlimitedContractSize: true,
    mining: {
      auto: true,
      interval: 5000,
    },
    accounts: {
      mnemonic: mnemonic(),
      count: 20,
      accountsBalance: '10000000000000000000000',
    },
  },
  hardhat2: {
    url: 'http://127.0.0.1:3000',
    chainId: 1338,
    allowUnlimitedContractSize: true,
    mining: {
      auto: true,
      interval: 5000,
    },
    accounts: {
      mnemonic: mnemonic(),
      count: 20,
      accountsBalance: '10000000000000000000000',
    },
  },
  coverage: {
    url: 'http://127.0.0.1:8555',
    blockGasLimit: 200000000,
    allowUnlimitedContractSize: true,
  },
  lux: {
    url: 'https://api.lux.network',
    accounts: {
      mnemonic: mnemonic(),
    },
    chainId: 7777,
    live: true,
    saveDeployments: true,
    //gasPrice: ethers.utils.parseUnits(`155`, 'gwei').toNumber(),
    blockGasLimit: 4000000,
  },
  mainnet: {
    url: 'https://mainnet.infura.io/v3/30171d2ba65445de9271453dbc6ca307',
    accounts: {
      mnemonic: mnemonic(),
    },
    chainId: 1,
    live: true,
    saveDeployments: true,
    gasPrice: ethers.utils.parseUnits(`155`, 'gwei').toNumber(),
    blockGasLimit: 4000000,
  },
  // testnet: {
  //   url: 'https://rinkeby.infura.io/v3/9aa3d95b3bc440fa88ea12eaa4456161',
  //   chainId: 4,
  //   // gasPrice: 11e9,
  //   // gas: 20e6,
  //   accounts: {
  //     mnemonic: mnemonic(),
  //   },
  // },
  testnet: {
    url: `https://ropsten.infura.io/v3/9aa3d95b3bc440fa88ea12eaa4456161`,
    accounts: {
      mnemonic: mnemonic(),
    },
    chainId: 3,
    live: true,
    saveDeployments: true,
    tags: ["staging"],
    gasPrice: ethers.utils.parseUnits(`50`, 'gwei').toNumber(),
    blockGasLimit: 4000000,
    gasMultiplier: 2,
  },
}

// if (process.env.FORK_ENABLED == "true") {
//   networks.hardhat = {
//     chainId: 1,
//     forking: {
//       url: `https://eth-mainnet.alchemyapi.io/v2/${alchemyKey}`,
//       // blockNumber: 12226812
//     },
//     accounts: {
//       mnemonic,
//     },
//   }
// }  else {
// }

export {}

export default networks
