import { zeroAddress } from "viem";
import { ERC20Abi } from "../pool-gen/abis/erc20";
import { V2FactoryAbi } from "../pool-gen/abis/v2Factory";
import { V2PairAbi } from "../pool-gen/abis/v2Pair";
import { WethAbi } from "../pool-gen/abis/weth";
import { ACTIVE_CHAIN, ACTIVE_CHAIN_ID, V2_FACTORY_ADDRESS } from "../pool-gen/config";
import { POOL_CONFIGS } from "../pool-gen/config/pools";
import { WRAPPED_NATIVE_CURRENCY } from "../pool-gen/model/token";
import { mintV2AndCreatePoolIfNeeded, mintV3AndCreatePoolIfNeeded, poolSettingsToArgs } from "../pool-gen/pool/pool";
import { publicClients, walletClients } from "../pool-gen/rpc";

// (testnet)  npx hardhat run --network lux_testnet deploy/23_uniswapPools.ts

async function main() {
    const walletClient = walletClients[ACTIVE_CHAIN_ID];
    const publicClient = publicClients[ACTIVE_CHAIN_ID];

    try {
        for(const config of POOL_CONFIGS) {
            if(config.type === "v3") {
                const { token0, token1, fee, amount0, amount1, priceLow, priceHigh } = poolSettingsToArgs(config);
                const data = await mintV3AndCreatePoolIfNeeded(token0, token1, fee, amount0.toFixed(), amount1.toFixed(), priceLow, priceHigh);

                if(!data) {
                    console.log("No data appeared while calculating position info");
                    continue;
                }

                const { to, calldata, value } = data;

                if(token0.contract_address.toLowerCase() === WRAPPED_NATIVE_CURRENCY[ACTIVE_CHAIN_ID].address.toLowerCase() && walletClient.account) {
                    const tx = await walletClient.writeContract({
                        account: walletClient.account,
                        chain: ACTIVE_CHAIN,
                        address: token0.contract_address as `0x${string}`,
                        abi: WethAbi,
                        functionName: "deposit",
                        value: BigInt(amount0.toFixed()),
                    })

                    await publicClient.waitForTransactionReceipt({ hash: tx });
                    console.log(`V3: Lux wrap completed`);
                }

                if(token1.contract_address.toLowerCase() === WRAPPED_NATIVE_CURRENCY[ACTIVE_CHAIN_ID].address.toLowerCase() && walletClient.account) {
                    const tx = await walletClient.writeContract({
                        account: walletClient.account,
                        chain: ACTIVE_CHAIN,
                        address: token1.contract_address as `0x${string}`,
                        abi: WethAbi,
                        functionName: "deposit",
                        value: BigInt(amount0.toFixed()),
                    })

                    await publicClient.waitForTransactionReceipt({ hash: tx });
                    console.log(`V3: Lux wrap completed`);
                }

                if(walletClient.account) {
                    const tx = await walletClient.writeContract({
                        account: walletClient.account,
                        chain: ACTIVE_CHAIN,
                        address: token0.contract_address as `0x${string}`,
                        abi: ERC20Abi,
                        functionName: "approve",
                        args: [to, amount0.toFixed()],
                    })

                    await publicClient.waitForTransactionReceipt({ hash: tx });
                    console.log(`V3: Approval ${token0.asset} completed`);
                }

                if(walletClient.account) {
                    const tx = await walletClient.writeContract({
                        account: walletClient.account,
                        chain: ACTIVE_CHAIN,
                        address: token1.contract_address as `0x${string}`,
                        abi: ERC20Abi,
                        functionName: "approve",
                        args: [to, amount1.toFixed()],
                    })

                    await publicClient.waitForTransactionReceipt({ hash: tx });
                    console.log(`V3: Approval ${token1.asset} completed`);
                }

                if(walletClient.account) {
                    // @ts-ignore
                    const tx = await walletClient.sendTransaction({
                        chain: ACTIVE_CHAIN,
                        account: walletClient.account,
                        data: calldata as `0x${string}`,
                        value: BigInt(value),
                        to,
                    });

                    await publicClient.waitForTransactionReceipt({  hash: tx});
                }

            } else {
                const { token0, token1, amount0, amount1, createPoolCalldata, mintLiquidityCalldata } = mintV2AndCreatePoolIfNeeded(config);

                let poolAddress = await publicClient.readContract({
                    abi: V2FactoryAbi,
                    address: V2_FACTORY_ADDRESS,
                    functionName: "getPair",
                    args: [token0.address, token1.address]
                });

                console.log(`V2: Pool address: ${poolAddress}`);

                if(poolAddress == zeroAddress)
                {
                    // @ts-ignore
                    const poolTx = await walletClient.sendTransaction({
                        chain: ACTIVE_CHAIN,
                        account: walletClient.account,
                        data: createPoolCalldata as `0x${string}`,
                        to: V2_FACTORY_ADDRESS,
                    });

                    await publicClient.waitForTransactionReceipt({ hash: poolTx});

                    poolAddress = await publicClient.readContract({
                        abi: V2FactoryAbi,
                        address: V2_FACTORY_ADDRESS,
                        functionName: "getPair",
                        args: [token0.address, token1.address]
                    });
    
                    console.log(`V2: updated Pool address: ${poolAddress}`);
                }

                if(!poolAddress) {
                    console.log("Failed to get pool address");
                    continue;
                }

                if(token0.address.toLowerCase() === WRAPPED_NATIVE_CURRENCY[ACTIVE_CHAIN_ID].address.toLowerCase() && walletClient.account) {
                    const tx = await walletClient.writeContract({
                        account: walletClient.account,
                        chain: ACTIVE_CHAIN,
                        address: token0.address as `0x${string}`,
                        abi: WethAbi,
                        functionName: "deposit",
                        value: BigInt(amount0.toFixed()),
                    })

                    await publicClient.waitForTransactionReceipt({ hash: tx });
                    console.log(`Lux wrap completed`);
                }

                if(token1.address.toLowerCase() === WRAPPED_NATIVE_CURRENCY[ACTIVE_CHAIN_ID].address.toLowerCase() && walletClient.account) {
                    const tx = await walletClient.writeContract({
                        account: walletClient.account,
                        chain: ACTIVE_CHAIN,
                        address: token1.address as `0x${string}`,
                        abi: WethAbi,
                        functionName: "deposit",
                        value: BigInt(amount0.toFixed()),
                    })

                    await publicClient.waitForTransactionReceipt({ hash: tx });
                    console.log(`Lux wrap completed`);
                }                

                const transfer0Tx = await walletClient.writeContract({
                    account: walletClient.account,
                    address: token0.address,
                    chain: ACTIVE_CHAIN,
                    abi: ERC20Abi,
                    functionName: "transfer",
                    args: [poolAddress, amount0.toFixed()],
                });

                await publicClient.waitForTransactionReceipt({ hash: transfer0Tx });


                const transfer1Tx = await walletClient.writeContract({
                    account: walletClient.account,
                    address: token1.address,
                    chain: ACTIVE_CHAIN,
                    abi: ERC20Abi,
                    functionName: "transfer",
                    args: [poolAddress, amount0.toFixed()],
                });

                await publicClient.waitForTransactionReceipt({ hash: transfer1Tx });

                // @ts-ignore
                const mintTx = await walletClient.sendTransaction({
                    account: walletClient.account,
                    chain: ACTIVE_CHAIN,
                    to: poolAddress,
                    data: mintLiquidityCalldata as `0x${string}`,
                })

                await publicClient.waitForTransactionReceipt({ hash: mintTx });

                console.log(`V2: Mint completed`);
            }
        }
    } catch(err) {
        console.error("Failed to process liquidity mint:", err);
    }

    console.log("Generation completed");
    process.exit(0);
}

main();