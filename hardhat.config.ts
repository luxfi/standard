import '@nomicfoundation/hardhat-ethers'
import '@nomicfoundation/hardhat-verify'
import 'hardhat-deploy'
import * as dotenv from "dotenv";

dotenv.config();

const LOW_OPTIMIZER_COMPILER_SETTINGS = {
  version: '0.7.6',
  settings: {
    evmVersion: 'istanbul',
    optimizer: {
      enabled: true,
      runs: 5,
    },
    metadata: {
      bytecodeHash: 'none',
    },
  },
}

const LOWEST_OPTIMIZER_COMPILER_SETTINGS = {
  version: '0.7.6',
  settings: {
    evmVersion: 'istanbul',
    optimizer: {
      enabled: true,
      runs: 5,
    },
    metadata: {
      bytecodeHash: 'none',
    },
  },
}

const DEFAULT_COMPILER_SETTINGS = {
  version: '0.6.12',
  settings: {
    evmVersion: 'istanbul',
    optimizer: {
      enabled: true,
      runs: 5,
    },
    metadata: {
      bytecodeHash: 'none',
    },
  },
}

export default {
  networks: {
    hardhat: {
      allowUnlimitedContractSize: false,
    },
    mainnet: {
      url: `https://mainnet.infura.io/v3/${process.env.INFURA_API_KEY}`,
    },
    lux: {
      url: "https://api.lux.network/",
      accounts: process.env.PK ? [process.env.PK] : [],
    },
    lux_testnet: {
      url: "https://api.lux-test.network",
      accounts: process.env.PK ? [process.env.PK] : [],
    },
    lux_local: {
      url: "http://localhost:9630/ext/bc/C/rpc",
      chainId: 96369,
      accounts: process.env.PK ? [process.env.PK] : [],
    }
  },
  etherscan: {
    apiKey:  process.env.ETHERSCAN_API_KEY || "",
    customChains: [
      {
        network: "lux",
        chainId: 96369,
        urls: {
          apiURL: "https://api-explore.lux.network",
          browserURL: "https://explore.lux.network"
        }
      },
      {
        network: "lux_testnet",
        chainId: 96368,
        urls: {
          apiURL: "https://api-explore.lux-test.network",
          browserURL: "https://explore.lux-test.network"
        }
      },
    ]
  },
  solidity: {
    compilers: [
      {
        version: "0.4.18",
        settings: {
          optimizer: {
            enabled: true,
            runs: 200,
          },
        },
      },
      {
        version: "0.5.16",
        settings: {
          optimizer: {
            enabled: true,
            runs: 200,
          },
        },
      },
      {
        version: "0.6.6",
        settings: {
          optimizer: {
            enabled: true,
            runs: 200,
          },
        },
      },
      {
        version: "0.6.12",
        settings: {
          optimizer: {
            enabled: true,
            runs: 200,
          },
        },
      },
      {
        version: "0.7.6",
        settings: {
          optimizer: {
            enabled: true,
            runs: 200,
          },
        },
      },
      {
        version: "0.8.26",
        settings: {
          viaIR: true,
          optimizer: {
            enabled: true,
            runs: 200,
          },
        },
      },
      DEFAULT_COMPILER_SETTINGS
    ],
    overrides: {
      'contracts/NonfungiblePositionManager.sol': LOW_OPTIMIZER_COMPILER_SETTINGS,
      'contracts/test/MockTimeNonfungiblePositionManager.sol': LOW_OPTIMIZER_COMPILER_SETTINGS,
      'contracts/test/NFTDescriptorTest.sol': LOWEST_OPTIMIZER_COMPILER_SETTINGS,
      'contracts/NonfungibleTokenPositionDescriptor.sol': LOWEST_OPTIMIZER_COMPILER_SETTINGS,
      'contracts/libraries/NFTDescriptor.sol': LOWEST_OPTIMIZER_COMPILER_SETTINGS,
    },
  },
  paths: {
    sources: "./contracts", // AI contracts in contracts/
    tests: "./test",
    cache: "./cache_hardhat",
    artifacts: "./artifacts",
  },
  sourcify: {
    enabled: false
  },
  namedAccounts: {
    deployer: {
      default: 0,
    },
    dao: {
      default: 0,
    },
  },
}
