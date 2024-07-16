import { HardhatUserConfig } from "hardhat/config";
import "@nomicfoundation/hardhat-toolbox";

require('dotenv').config({ path: '.env' })
require('@nomiclabs/hardhat-etherscan')

const ALCHEMY_API_KEY_URL = process.env.ALCHEMY_API_KEY_URL
const SEPOLIA_PRIVATE_KEY = process.env.SEPOLIA_PRIVATE_KEY || ''
const ETHERSCAN = process.env.ETHERSCAN || ''

const config: HardhatUserConfig = {
  paths: {
    sources: './src',
  },
  solidity: {
    compilers: [
      {
        version: "0.8.4",
      },
      {
        version: "0.8.7",
      },
      {
        version: "0.8.17",
      },
    ],
  },
  networks: {
    sepolia: {
      url: ALCHEMY_API_KEY_URL,
      accounts: [SEPOLIA_PRIVATE_KEY],
    },
  },
  etherscan: {
    apiKey: {
      sepolia: ETHERSCAN,
    },
  },
};

export default config;
