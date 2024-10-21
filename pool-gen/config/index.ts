import * as dotenv from "dotenv";
import { CHAINS, lux, lux_testnet } from "../chains/chains";

dotenv.config();

export const environment = process.env.ACTIVE_ENVIRONMENT ?? "testnet";

export const ACTIVE_CHAIN_ID = environment === "testnet" ? CHAINS.TESTNET : CHAINS.MAINNET;
export const ACTIVE_CHAIN = environment === "testnet" ? lux_testnet : lux;

export const V2_FACTORY_ADDRESS = environment === "testnet" ? "0xBf6440a627907022D2bb7c57FD20196772935F83" : "0x80bBc7C4C7a59C899D1B37BC14539A22D5830a84";

export const POSITION_MANAGER_ADDRESSES = {
    [CHAINS.MAINNET]: "0x3d79EdAaBC0EaB6F08ED885C05Fc0B014290D95A",
    [CHAINS.TESTNET]: "0x99D5296C6dfADF96f4C51D2c7f93bBEEEe331ec1",
};
