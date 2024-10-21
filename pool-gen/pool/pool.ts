import { BigintIsh, Percent, Price, Token } from "@uniswap/sdk-core";
import { FeeAmount, MintOptions, NonfungiblePositionManager, Pool, Position, SqrtPriceMath, TickMath, encodeSqrtRatioX96, priceToClosestTick } from "@uniswap/v3-sdk"
import { ACTIVE_CHAIN, ACTIVE_CHAIN_ID, POSITION_MANAGER_ADDRESSES } from "../config";
import { PoolV2, PoolV3 } from "../model/pool";
import { IToken, LUX_CURRENCY_TESTNET, sdkTokenFromToken, WRAPPED_NATIVE_CURRENCY } from "../model/token"
import { walletClients } from "../rpc";
import bn from "bignumber.js";
import { encodeFunctionData } from "viem";
import { V2FactoryAbi } from "../abis/v2Factory";
import { V2PairAbi } from "../abis/v2Pair";

function getTickFromPrice(price: number) {
    const tick = Math.log(price) / Math.log(1.0001);
    return Math.floor(tick);
}
  

export const poolSettingsToArgs = (settings: PoolV3) => {
    const decimals0 = bn(10).pow(settings.token0.decimals);
    const amount0 = bn(settings.amount0).multipliedBy(decimals0);

    const decimals1 = bn(10).pow(settings.token1.decimals);
    const amount1 = bn(settings.amount1).multipliedBy(decimals1);

    const token0 = sdkTokenFromToken(ACTIVE_CHAIN_ID, settings.token0);
    const token1 = sdkTokenFromToken(ACTIVE_CHAIN_ID, settings.token1);

    const oneToken0 = bn(1).multipliedBy(decimals0);
    const priceLowToken1 = bn(settings.minPrice).multipliedBy(decimals1);
    const priceHighToken1 = bn(settings.maxPrice).multipliedBy(decimals1);

    const priceLow = new Price(token0, token1, oneToken0.toNumber(), priceLowToken1.toNumber());
    const priceHigh = new Price(token0, token1, oneToken0.toNumber(), priceHighToken1.toNumber());

    return {
        token0: settings.token0,
        token1: settings.token1,
        fee: settings.fee,
        amount0,
        amount1,
        priceLow,
        priceHigh,
    }
}

export const mintV3AndCreatePoolIfNeeded = async (
    token0: IToken,
    token1: IToken,
    fee: FeeAmount,
    amount0: BigintIsh,
    amount1: BigintIsh, 
    priceLow: Price<Token, Token>,
    priceHigh: Price<Token, Token>
) => {
    const activeWallet = walletClients[ACTIVE_CHAIN_ID];

    const tokenA = sdkTokenFromToken(ACTIVE_CHAIN_ID, token0);
    const tokenB = sdkTokenFromToken(ACTIVE_CHAIN_ID, token1);

    const initialPrice = bn(amount1.toString()).div(bn(amount0.toString())).toNumber();
    const currentTick = getTickFromPrice(initialPrice);
    const initialPriceSqrt = TickMath.getSqrtRatioAtTick(currentTick);

    const tickLower = priceToClosestTick(priceLow);
    const tickUpper = priceToClosestTick(priceHigh);

    const pool = new Pool(tokenA, tokenB, fee, initialPriceSqrt, 0, currentTick);

    const tickLowerAdjusted = tickLower - tickLower % pool.tickSpacing;
    const tickUpperAdjusted = tickUpper - tickUpper % pool.tickSpacing;

    const [tickLowerOrdered, tickUpperOrdered] = tickLowerAdjusted > tickUpperAdjusted ? [tickUpperAdjusted, tickLowerAdjusted] : [tickLowerAdjusted, tickUpperAdjusted];

    const position = Position.fromAmounts({ pool, tickLower: tickLowerOrdered, tickUpper: tickUpperOrdered, amount0, amount1, useFullPrecision: false });

    const mintOptions: MintOptions = {
        recipient: activeWallet.account?.address ?? "",
        deadline: Math.floor(Date.now() / 1000) + 60 * 20,
        slippageTolerance: new Percent(50, 10_000),
        useNative:
            token0.contract_address.toLowerCase() === WRAPPED_NATIVE_CURRENCY[ACTIVE_CHAIN_ID].address.toLowerCase() ||
            token1.contract_address.toLowerCase() === WRAPPED_NATIVE_CURRENCY[ACTIVE_CHAIN_ID].address.toLowerCase()
            ? LUX_CURRENCY_TESTNET : undefined,
        createPool: true,
    }
    
    const { calldata, value } = NonfungiblePositionManager.addCallParameters(position, mintOptions);

    if(activeWallet.account) {
        return {
            to: POSITION_MANAGER_ADDRESSES[ACTIVE_CHAIN_ID] as `0x${string}`,
            calldata,
            value,
        }
    }

    return undefined;
}
 
export const mintV2AndCreatePoolIfNeeded = (settings: PoolV2) => {
    const activeWallet = walletClients[ACTIVE_CHAIN_ID];

    const decimals0 = bn(10).pow(settings.token0.decimals);
    const amount0 = bn(settings.amount0).multipliedBy(decimals0);

    const decimals1 = bn(10).pow(settings.token1.decimals);
    const amount1 = bn(settings.amount1).multipliedBy(decimals1);

    const token0 = sdkTokenFromToken(ACTIVE_CHAIN_ID, settings.token0);
    const token1 = sdkTokenFromToken(ACTIVE_CHAIN_ID, settings.token1);
    
    const createPoolCalldata = encodeFunctionData({
        abi: V2FactoryAbi,
        functionName: "createPair",
        args: [token0.address, token1.address],
    });

    const mintLiquidityCalldata = encodeFunctionData({
        abi: V2PairAbi,
        functionName: "mint",
        args: [activeWallet.account.address],
    })

    return {
        token0,
        token1,
        amount0,
        amount1,
        createPoolCalldata,
        mintLiquidityCalldata,
    }
}