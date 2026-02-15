import { HardhatUserConfig } from "hardhat/config";
import "@nomicfoundation/hardhat-ethers";
import "@nomicfoundation/hardhat-verify";
import "@openzeppelin/hardhat-upgrades";
import "hardhat-deploy";
import * as dotenv from "dotenv";

dotenv.config();

const PRIVATE_KEY = process.env.PRIVATE_KEY || process.env.PK || "";
const INFURA_KEY = process.env.INFURA_API_KEY || "";

const config: HardhatUserConfig = {
  solidity: {
    compilers: [
      {
        version: "0.8.28",
        settings: {
          viaIR: true,
          optimizer: {
            enabled: true,
            runs: 200,
          },
          evmVersion: "cancun",
        },
      },
      // Legacy support for older contracts
      {
        version: "0.8.24",
        settings: {
          viaIR: true,
          optimizer: {
            enabled: true,
            runs: 200,
          },
        },
      },
      {
        version: "0.8.20",
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
    ],
  },
  networks: {
    hardhat: {
      allowUnlimitedContractSize: false,
      chainId: 31337,
    },
    localhost: {
      url: "http://127.0.0.1:8545",
      chainId: 31337,
    },
    // Lux Networks
    lux: {
      url: "https://api.lux.network/rpc",
      chainId: 96369,
      accounts: PRIVATE_KEY ? [PRIVATE_KEY] : [],
    },
    lux_testnet: {
      url: "https://api.lux-test.network/rpc",
      chainId: 96368,
      accounts: PRIVATE_KEY ? [PRIVATE_KEY] : [],
    },
    lux_local: {
      url: "http://localhost:9630/ext/bc/C/rpc",
      chainId: 96369,
      accounts: PRIVATE_KEY ? [PRIVATE_KEY] : [],
    },
    lux_devnet: {
      url: process.env.DEVNET_RPC || "http://143.110.230.60:53904/ext/bc/C/rpc",
      chainId: parseInt(process.env.DEVNET_CHAIN_ID || "0"), // Will be set dynamically
      accounts: PRIVATE_KEY ? [PRIVATE_KEY] : [],
      timeout: 60000,
    },
    // Zoo Networks
    zoo: {
      url: "https://api.zoo.network/rpc",
      chainId: 200200,
      accounts: PRIVATE_KEY ? [PRIVATE_KEY] : [],
    },
    zoo_testnet: {
      url: "https://api.zoo-test.network/rpc",
      chainId: 200201,
      accounts: PRIVATE_KEY ? [PRIVATE_KEY] : [],
    },
    // AI Networks
    ai: {
      url: "https://api.ai.network/rpc",
      chainId: 36963,
      accounts: PRIVATE_KEY ? [PRIVATE_KEY] : [],
    },
    ai_testnet: {
      url: "https://api.ai-test.network/rpc",
      chainId: 36964,
      accounts: PRIVATE_KEY ? [PRIVATE_KEY] : [],
    },
    // Ethereum Networks
    mainnet: {
      url: `https://mainnet.infura.io/v3/${INFURA_KEY}`,
      chainId: 1,
      accounts: PRIVATE_KEY ? [PRIVATE_KEY] : [],
    },
    sepolia: {
      url: `https://sepolia.infura.io/v3/${INFURA_KEY}`,
      chainId: 11155111,
      accounts: PRIVATE_KEY ? [PRIVATE_KEY] : [],
    },
  },
  etherscan: {
    apiKey: {
      mainnet: process.env.ETHERSCAN_API_KEY || "",
      sepolia: process.env.ETHERSCAN_API_KEY || "",
      lux: process.env.LUXSCAN_API_KEY || "",
      lux_testnet: process.env.LUXSCAN_API_KEY || "",
    },
    customChains: [
      {
        network: "lux",
        chainId: 96369,
        urls: {
          apiURL: "https://api.explore.lux.network/api",
          browserURL: "https://explore.lux.network",
        },
      },
      {
        network: "lux_testnet",
        chainId: 96368,
        urls: {
          apiURL: "https://api.explore.lux-test.network/api",
          browserURL: "https://explore.lux-test.network",
        },
      },
      {
        network: "zoo",
        chainId: 200200,
        urls: {
          apiURL: "https://api.explore.zoo.network/api",
          browserURL: "https://explore.zoo.network",
        },
      },
    ],
  },
  paths: {
    sources: "./contracts",
    tests: "./test",
    cache: "./cache_hardhat",
    artifacts: "./artifacts",
  },
  namedAccounts: {
    deployer: {
      default: 0,
    },
    treasury: {
      default: 1,
    },
  },
  sourcify: {
    enabled: false,
  },
};

export default config;
