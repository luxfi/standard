import { ContractFactory, ContractTransactionResponse } from "ethers";
import type { Signer, ContractDeployTransaction, ContractRunner } from "ethers";
import type { NonPayableOverrides } from "../../../common";
import type { CreateCall, CreateCallInterface } from "../../../contracts/libraries/CreateCall";
type CreateCallConstructorParams = [signer?: Signer] | ConstructorParameters<typeof ContractFactory>;
export declare class CreateCall__factory extends ContractFactory {
    constructor(...args: CreateCallConstructorParams);
    getDeployTransaction(overrides?: NonPayableOverrides & {
        from?: string;
    }): Promise<ContractDeployTransaction>;
    deploy(overrides?: NonPayableOverrides & {
        from?: string;
    }): Promise<CreateCall & {
        deploymentTransaction(): ContractTransactionResponse;
    }>;
    connect(runner: ContractRunner | null): CreateCall__factory;
    static readonly bytecode = "0x608060405234801561001057600080fd5b5061044b806100206000396000f3fe608060405234801561001057600080fd5b50600436106100365760003560e01c80634847be6f1461003b5780634c8c9ea114610134575b600080fd5b6101086004803603606081101561005157600080fd5b81019080803590602001909291908035906020019064010000000081111561007857600080fd5b82018360208201111561008a57600080fd5b803590602001918460018302840111640100000000831117156100ac57600080fd5b91908080601f016020809104026020016040519081016040528093929190818152602001838380828437600081840152601f19601f82011690508083019250505050505050919291929080359060200190929190505050610223565b604051808273ffffffffffffffffffffffffffffffffffffffff16815260200191505060405180910390f35b6101f76004803603604081101561014a57600080fd5b81019080803590602001909291908035906020019064010000000081111561017157600080fd5b82018360208201111561018357600080fd5b803590602001918460018302840111640100000000831117156101a557600080fd5b91908080601f016020809104026020016040519081016040528093929190818152602001838380828437600081840152601f19601f82011690508083019250505050505050919291929050505061031d565b604051808273ffffffffffffffffffffffffffffffffffffffff16815260200191505060405180910390f35b60008183518460200186f59050600073ffffffffffffffffffffffffffffffffffffffff168173ffffffffffffffffffffffffffffffffffffffff1614156102d3576040517f08c379a00000000000000000000000000000000000000000000000000000000081526004018080602001828103825260198152602001807f436f756c64206e6f74206465706c6f7920636f6e74726163740000000000000081525060200191505060405180910390fd5b8073ffffffffffffffffffffffffffffffffffffffff167f4db17dd5e4732fb6da34a148104a592783ca119a1e7bb8829eba6cbadef0b51160405160405180910390a29392505050565b600081516020830184f09050600073ffffffffffffffffffffffffffffffffffffffff168173ffffffffffffffffffffffffffffffffffffffff1614156103cc576040517f08c379a00000000000000000000000000000000000000000000000000000000081526004018080602001828103825260198152602001807f436f756c64206e6f74206465706c6f7920636f6e74726163740000000000000081525060200191505060405180910390fd5b8073ffffffffffffffffffffffffffffffffffffffff167f4db17dd5e4732fb6da34a148104a592783ca119a1e7bb8829eba6cbadef0b51160405160405180910390a29291505056fea2646970667358221220153dfbb31f5824b1a17183b88443b5d0771b935e8acd92186d58555a02e4b41f64736f6c63430007060033";
    static readonly abi: readonly [{
        readonly anonymous: false;
        readonly inputs: readonly [{
            readonly indexed: true;
            readonly internalType: "address";
            readonly name: "newContract";
            readonly type: "address";
        }];
        readonly name: "ContractCreation";
        readonly type: "event";
    }, {
        readonly inputs: readonly [{
            readonly internalType: "uint256";
            readonly name: "value";
            readonly type: "uint256";
        }, {
            readonly internalType: "bytes";
            readonly name: "deploymentData";
            readonly type: "bytes";
        }];
        readonly name: "performCreate";
        readonly outputs: readonly [{
            readonly internalType: "address";
            readonly name: "newContract";
            readonly type: "address";
        }];
        readonly stateMutability: "nonpayable";
        readonly type: "function";
    }, {
        readonly inputs: readonly [{
            readonly internalType: "uint256";
            readonly name: "value";
            readonly type: "uint256";
        }, {
            readonly internalType: "bytes";
            readonly name: "deploymentData";
            readonly type: "bytes";
        }, {
            readonly internalType: "bytes32";
            readonly name: "salt";
            readonly type: "bytes32";
        }];
        readonly name: "performCreate2";
        readonly outputs: readonly [{
            readonly internalType: "address";
            readonly name: "newContract";
            readonly type: "address";
        }];
        readonly stateMutability: "nonpayable";
        readonly type: "function";
    }];
    static createInterface(): CreateCallInterface;
    static connect(address: string, runner?: ContractRunner | null): CreateCall;
}
export {};
