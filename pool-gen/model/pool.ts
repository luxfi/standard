import { FeeAmount } from "@uniswap/v3-sdk";
import { IToken } from "./token";

interface PoolBase {
    /** @type {IToken} */
    token0: IToken;
    /** @type {Token} */
    token1: IToken;
    /** @type {"v2" | "v3"} */
    type: "v2" | "v3";
    /** @type {boolean} */
    skipPool?: boolean;
}

export interface PoolV2 extends PoolBase {
    /** @type {"v2"} */
    type: "v2";
    /** @type {number} */
    amount0: number;
    /** @type {number} */
    amount1: number;
}

export interface PoolV3 extends PoolBase {
    /** @type {"v3"} */
    type: "v3";
    /** @type {FeeAmount} */
    fee: FeeAmount;
    /** @type {number} */
    initialPrice: number;
    /** @type {number} */
    minPrice: number;
    /** @type {number} */
    maxPrice: number;
    /** @type {number} */
    amount0: number;
    /** @type {number} */
    amount1: number;
}

export type PoolSettings = PoolV2 | PoolV3;