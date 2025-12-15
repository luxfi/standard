import { BigNumberish } from "ethers";
import { SafeProxyFactory } from "../../typechain-types";
export declare const calculateProxyAddress: (factory: SafeProxyFactory, singleton: string, inititalizer: string, nonce: number | string) => Promise<string>;
export declare const calculateProxyAddressWithCallback: (factory: SafeProxyFactory, singleton: string, inititalizer: string, nonce: number | string, callback: string) => Promise<string>;
export declare const calculateChainSpecificProxyAddress: (factory: SafeProxyFactory, singleton: string, inititalizer: string, nonce: number | string, chainId: BigNumberish) => Promise<string>;
