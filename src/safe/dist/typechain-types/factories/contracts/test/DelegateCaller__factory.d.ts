import { ContractFactory, ContractTransactionResponse } from "ethers";
import type { Signer, ContractDeployTransaction, ContractRunner } from "ethers";
import type { NonPayableOverrides } from "../../../common";
import type { DelegateCaller, DelegateCallerInterface } from "../../../contracts/test/DelegateCaller";
type DelegateCallerConstructorParams = [signer?: Signer] | ConstructorParameters<typeof ContractFactory>;
export declare class DelegateCaller__factory extends ContractFactory {
    constructor(...args: DelegateCallerConstructorParams);
    getDeployTransaction(overrides?: NonPayableOverrides & {
        from?: string;
    }): Promise<ContractDeployTransaction>;
    deploy(overrides?: NonPayableOverrides & {
        from?: string;
    }): Promise<DelegateCaller & {
        deploymentTransaction(): ContractTransactionResponse;
    }>;
    connect(runner: ContractRunner | null): DelegateCaller__factory;
    static readonly bytecode = "0x608060405234801561001057600080fd5b50610296806100206000396000f3fe608060405234801561001057600080fd5b506004361061002b5760003560e01c8063e632e17214610030575b600080fd5b6101096004803603604081101561004657600080fd5b81019080803573ffffffffffffffffffffffffffffffffffffffff1690602001909291908035906020019064010000000081111561008357600080fd5b82018360208201111561009557600080fd5b803590602001918460018302840111640100000000831117156100b757600080fd5b91908080601f016020809104026020016040519081016040528093929190818152602001838380828437600081840152601f19601f82011690508083019250505050505050919291929050505061018d565b60405180831515815260200180602001828103825283818151815260200191508051906020019080838360005b83811015610151578082015181840152602081019050610136565b50505050905090810190601f16801561017e5780820380516001836020036101000a031916815260200191505b50935050505060405180910390f35b600060608373ffffffffffffffffffffffffffffffffffffffff16836040518082805190602001908083835b602083106101dc57805182526020820191506020810190506020830392506101b9565b6001836020036101000a038019825116818451168082178552505050505050905001915050600060405180830381855af49150503d806000811461023c576040519150601f19603f3d011682016040523d82523d6000602084013e610241565b606091505b50809250819350505081610259573d6000803e3d6000fd5b925092905056fea2646970667358221220588e0081c5d3e0cfad27619350765395f20d7d3c6598ac5f61dd4fb24aa8a67364736f6c63430007060033";
    static readonly abi: readonly [{
        readonly inputs: readonly [{
            readonly internalType: "address";
            readonly name: "_called";
            readonly type: "address";
        }, {
            readonly internalType: "bytes";
            readonly name: "_calldata";
            readonly type: "bytes";
        }];
        readonly name: "makeDelegatecall";
        readonly outputs: readonly [{
            readonly internalType: "bool";
            readonly name: "success";
            readonly type: "bool";
        }, {
            readonly internalType: "bytes";
            readonly name: "returnData";
            readonly type: "bytes";
        }];
        readonly stateMutability: "nonpayable";
        readonly type: "function";
    }];
    static createInterface(): DelegateCallerInterface;
    static connect(address: string, runner?: ContractRunner | null): DelegateCaller;
}
export {};
