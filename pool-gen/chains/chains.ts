import { defineChain } from "viem";
import * as dotenv from "dotenv";

dotenv.config();

const CHAINS = {
    MAINNET: 96369,
    TESTNET: 96368,
}

const lux = defineChain({
    id: CHAINS.MAINNET,
    name: "Lux mainnet",
    nativeCurrency: {
        decimals: 18,
        name: "Lux",
        symbol: "LUX",
    },
    rpcUrls: {
        default: {
            http: [process.env.MAINNET_RPC_URL ?? ""]
        }
    }
})

const lux_testnet = defineChain({
    id: CHAINS.TESTNET,
    name: "Lux testnet",
    nativeCurrency: {
        decimals: 18,
        name: "Lux",
        symbol: "LUX",
    },
    rpcUrls: {
        default: {
            http: [process.env.TESTNET_RPC_URL ?? ""]
        }
    }
})

export {
    CHAINS,
    lux,
    lux_testnet,
}