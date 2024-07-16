import { HardhatUserConfig } from 'hardhat/config'

import fs from 'fs'

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
  mainnet: {
    url: `https://eth-mainnet.g.alchemy.com/v2/${process.env.ETH_ALCHEMY_ID}`,
    chainId: 1,
    accounts: {
      mnemonic: mnemonic(),
    },
  },
  testnet: {
    url: `https://eth-sepolia.g.alchemy.com/v2/${process.env.SEPOLIA_ALCHEMY_ID}`,
    chainId: 5,
    gasPrice: 10e9,
    gas: 10e6,
    accounts: {
      mnemonic: mnemonic(),
    },
  },
}

export default networks
