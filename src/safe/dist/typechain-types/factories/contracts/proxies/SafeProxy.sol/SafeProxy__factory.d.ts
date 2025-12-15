import { ContractFactory, ContractTransactionResponse } from "ethers";
import type { Signer, AddressLike, ContractDeployTransaction, ContractRunner } from "ethers";
import type { NonPayableOverrides } from "../../../../common";
import type { SafeProxy, SafeProxyInterface } from "../../../../contracts/proxies/SafeProxy.sol/SafeProxy";
type SafeProxyConstructorParams = [signer?: Signer] | ConstructorParameters<typeof ContractFactory>;
export declare class SafeProxy__factory extends ContractFactory {
    constructor(...args: SafeProxyConstructorParams);
    getDeployTransaction(_singleton: AddressLike, overrides?: NonPayableOverrides & {
        from?: string;
    }): Promise<ContractDeployTransaction>;
    deploy(_singleton: AddressLike, overrides?: NonPayableOverrides & {
        from?: string;
    }): Promise<SafeProxy & {
        deploymentTransaction(): ContractTransactionResponse;
    }>;
    connect(runner: ContractRunner | null): SafeProxy__factory;
    static readonly bytecode = "0x608060405234801561001057600080fd5b506040516101d63803806101d68339818101604052602081101561003357600080fd5b8101908080519060200190929190505050600073ffffffffffffffffffffffffffffffffffffffff168173ffffffffffffffffffffffffffffffffffffffff1614156100ca576040517f08c379a00000000000000000000000000000000000000000000000000000000081526004018080602001828103825260228152602001806101b46022913960400191505060405180910390fd5b806000806101000a81548173ffffffffffffffffffffffffffffffffffffffff021916908373ffffffffffffffffffffffffffffffffffffffff16021790555050609b806101196000396000f3fe60806040526000547fa619486e00000000000000000000000000000000000000000000000000000000600035141560405780600c1b600c1c60005260206000f35b3660008037600080366000845af43d6000803e60008114156060573d6000fd5b3d6000f3fea2646970667358221220bfbe5e66dfccd59d80684323ec36a561ddc5ef3b39a33a941f25cabefff21eb964736f6c63430007060033496e76616c69642073696e676c65746f6e20616464726573732070726f7669646564";
    static readonly abi: readonly [{
        readonly inputs: readonly [{
            readonly internalType: "address";
            readonly name: "_singleton";
            readonly type: "address";
        }];
        readonly stateMutability: "nonpayable";
        readonly type: "constructor";
    }, {
        readonly stateMutability: "payable";
        readonly type: "fallback";
    }];
    static createInterface(): SafeProxyInterface;
    static connect(address: string, runner?: ContractRunner | null): SafeProxy;
}
export {};
