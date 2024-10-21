import { createPublicClient, createWalletClient, http, PublicClient, WalletClient } from "viem";
import { privateKeyToAccount } from "viem/accounts";
import { lux, lux_testnet, CHAINS } from "../chains/chains";
import * as dotenv from "dotenv";

dotenv.config();

export const publicClients: Record<number, PublicClient> = {};
export const walletClients: Record<number, WalletClient> = {};

// @ts-ignore
publicClients[CHAINS.MAINNET] = createPublicClient({
    chain: lux,
    transport: http(),
});

// @ts-ignore
publicClients[CHAINS.TESTNET] = createPublicClient({
    chain: lux_testnet,
    transport: http(),
});

export const account = privateKeyToAccount((process.env.PK ?? "") as `0x${string}`);

walletClients[CHAINS.MAINNET] = createWalletClient({
    account,
    chain: lux,
    transport: http(),
});

walletClients[CHAINS.TESTNET] = createWalletClient({
    account,
    chain: lux_testnet,
    transport: http(),
});