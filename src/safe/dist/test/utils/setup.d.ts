import { Contract, Signer } from "ethers";
import { Safe, SafeL2, SafeMigration } from "../../typechain-types";
type SafeWithSetupConfig = {
    readonly owners: string[];
    readonly threshold?: number;
    readonly to?: string;
    readonly data?: string;
    readonly fallbackHandler?: string;
    readonly saltNumber?: string;
};
type LogGas = {
    readonly logGasUsage?: boolean;
};
type SafeCreationWithGasLog = SafeWithSetupConfig & LogGas;
export declare const defaultTokenCallbackHandlerDeployment: () => Promise<import("hardhat-deploy/dist/types").Deployment>;
export declare const defaultTokenCallbackHandlerContract: () => Promise<import("../../typechain-types").TokenCallbackHandler__factory>;
export declare const compatFallbackHandlerDeployment: () => Promise<import("hardhat-deploy/dist/types").Deployment>;
export declare const compatFallbackHandlerContract: () => Promise<import("../../typechain-types").CompatibilityFallbackHandler__factory>;
export declare const getSafeSingleton: () => Promise<Contract>;
export declare const getSafeSingletonContractFactory: () => Promise<import("../../typechain-types").Safe__factory>;
export declare const getSafeSingletonContract: () => Promise<Safe>;
export declare const getSafeL2SingletonContract: () => Promise<SafeL2>;
export declare const getSafeL2SingletonContractFactory: () => Promise<import("../../typechain-types").SafeL2__factory>;
export declare const getSafeSingletonContractFactoryFromEnvVariable: () => Promise<import("../../typechain-types").Safe__factory | import("../../typechain-types").SafeL2__factory>;
export declare const getSafeSingletonAt: (address: string) => Promise<Safe | SafeL2>;
export declare const getFactoryContract: () => Promise<import("../../typechain-types").SafeProxyFactory__factory>;
export declare const getFactory: () => Promise<import("../../typechain-types").SafeProxyFactory>;
export declare const getFactoryAt: (address: string) => Promise<import("../../typechain-types").SafeProxyFactory>;
export declare const getSimulateTxAccessor: () => Promise<import("../../typechain-types").SimulateTxAccessor>;
export declare const getMultiSend: () => Promise<import("../../typechain-types").MultiSend>;
export declare const getMultiSendCallOnly: () => Promise<import("../../typechain-types").MultiSendCallOnly>;
export declare const getCreateCall: () => Promise<import("../../typechain-types").CreateCall>;
export declare const migrationContract: () => Promise<import("../../typechain-types").Migration__factory>;
export declare const safeMigrationContract: () => Promise<SafeMigration>;
export declare const getMock: () => Promise<import("../../typechain-types").MockContract & {
    deploymentTransaction(): import("ethers").ContractTransactionResponse;
}>;
export declare const getSafeTemplate: (saltNumber?: string) => Promise<Safe | SafeL2>;
export declare const getSafeWithOwners: (safe: SafeCreationWithGasLog) => Promise<Safe | SafeL2>;
export declare const getSafeWithSingleton: (singleton: Safe | SafeL2, owners: string[], saltNumber?: string) => Promise<Safe | SafeL2>;
export declare const getTokenCallbackHandler: (address?: string) => Promise<import("../../typechain-types").TokenCallbackHandler>;
export declare const getCompatFallbackHandler: (address?: string) => Promise<import("../../typechain-types").CompatibilityFallbackHandler>;
export declare const getSafeProxyRuntimeCode: () => Promise<string>;
export declare const getDelegateCaller: () => Promise<import("../../typechain-types").DelegateCaller & {
    deploymentTransaction(): import("ethers").ContractTransactionResponse;
}>;
export declare const compile: (source: string) => Promise<{
    data: string;
    interface: any;
}>;
export declare const deployContract: (deployer: Signer, source: string) => Promise<Contract>;
export {};
