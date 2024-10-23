import * as dotenv from "dotenv";
import { CHAINS, lux, lux_testnet } from "../chains/chains";

dotenv.config();

export const environment = process.env.ACTIVE_ENVIRONMENT ?? "testnet";

export const ACTIVE_CHAIN_ID = environment === "testnet" ? CHAINS.TESTNET : CHAINS.MAINNET;
export const ACTIVE_CHAIN = environment === "testnet" ? lux_testnet : lux;

export const V2_FACTORY_ADDRESS = environment === "testnet" ? "0xF056B976d77170B951f7ECf40aF614A74147ec24" : "0x80bBc7C4C7a59C899D1B37BC14539A22D5830a84";

export const POSITION_MANAGER_ADDRESSES = {
    [CHAINS.MAINNET]: "0x3d79EdAaBC0EaB6F08ED885C05Fc0B014290D95A",
    [CHAINS.TESTNET]: "0x020459c46E26A44346765B23009B35fd728C91ce",
};
