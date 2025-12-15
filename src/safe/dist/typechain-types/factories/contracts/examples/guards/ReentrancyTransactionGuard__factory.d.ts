import { ContractFactory, ContractTransactionResponse } from "ethers";
import type { Signer, ContractDeployTransaction, ContractRunner } from "ethers";
import type { NonPayableOverrides } from "../../../../common";
import type { ReentrancyTransactionGuard, ReentrancyTransactionGuardInterface } from "../../../../contracts/examples/guards/ReentrancyTransactionGuard";
type ReentrancyTransactionGuardConstructorParams = [signer?: Signer] | ConstructorParameters<typeof ContractFactory>;
export declare class ReentrancyTransactionGuard__factory extends ContractFactory {
    constructor(...args: ReentrancyTransactionGuardConstructorParams);
    getDeployTransaction(overrides?: NonPayableOverrides & {
        from?: string;
    }): Promise<ContractDeployTransaction>;
    deploy(overrides?: NonPayableOverrides & {
        from?: string;
    }): Promise<ReentrancyTransactionGuard & {
        deploymentTransaction(): ContractTransactionResponse;
    }>;
    connect(runner: ContractRunner | null): ReentrancyTransactionGuard__factory;
    static readonly bytecode = "0x608060405234801561001057600080fd5b5061089a806100206000396000f3fe608060405234801561001057600080fd5b506004361061005b5760003560e01c806301ffc9a71461005e5780632acc37aa146100c1578063728c2972146100fb57806375f0bb521461022157806393271368146104295761005c565b5b005b6100a96004803603602081101561007457600080fd5b8101908080357bffffffffffffffffffffffffffffffffffffffffffffffffffffffff19169060200190929190505050610463565b60405180821515815260200191505060405180910390f35b6100f9600480360360408110156100d757600080fd5b810190808035906020019092919080351515906020019092919050505061059d565b005b61020b600480360360a081101561011157600080fd5b81019080803573ffffffffffffffffffffffffffffffffffffffff169060200190929190803590602001909291908035906020019064010000000081111561015857600080fd5b82018360208201111561016a57600080fd5b8035906020019184600183028401116401000000008311171561018c57600080fd5b91908080601f016020809104026020016040519081016040528093929190818152602001838380828437600081840152601f19601f820116905080830192505050505050509192919290803560ff169060200190929190803573ffffffffffffffffffffffffffffffffffffffff1690602001909291905050506105c5565b6040518082815260200191505060405180910390f35b610427600480360361016081101561023857600080fd5b81019080803573ffffffffffffffffffffffffffffffffffffffff169060200190929190803590602001909291908035906020019064010000000081111561027f57600080fd5b82018360208201111561029157600080fd5b803590602001918460018302840111640100000000831117156102b357600080fd5b91908080601f016020809104026020016040519081016040528093929190818152602001838380828437600081840152601f19601f820116905080830192505050505050509192919290803560ff169060200190929190803590602001909291908035906020019092919080359060200190929190803573ffffffffffffffffffffffffffffffffffffffff169060200190929190803573ffffffffffffffffffffffffffffffffffffffff1690602001909291908035906020019064010000000081111561038157600080fd5b82018360208201111561039357600080fd5b803590602001918460018302840111640100000000831117156103b557600080fd5b91908080601f016020809104026020016040519081016040528093929190818152602001838380828437600081840152601f19601f820116905080830192505050505050509192919290803573ffffffffffffffffffffffffffffffffffffffff169060200190929190505050610753565b005b6104616004803603604081101561043f57600080fd5b810190808035906020019092919080351515906020019092919050505061080f565b005b60007fe6d7a83a000000000000000000000000000000000000000000000000000000007bffffffffffffffffffffffffffffffffffffffffffffffffffffffff1916827bffffffffffffffffffffffffffffffffffffffffffffffffffffffff1916148061052e57507f58401ed8000000000000000000000000000000000000000000000000000000007bffffffffffffffffffffffffffffffffffffffffffffffffffffffff1916827bffffffffffffffffffffffffffffffffffffffffffffffffffffffff1916145b8061059657507f01ffc9a7000000000000000000000000000000000000000000000000000000007bffffffffffffffffffffffffffffffffffffffffffffffffffffffff1916827bffffffffffffffffffffffffffffffffffffffffffffffffffffffff1916145b9050919050565b60006105a7610837565b60000160006101000a81548160ff0219169083151502179055505050565b60008585858585604051602001808673ffffffffffffffffffffffffffffffffffffffff1660601b815260140185815260200184805190602001908083835b602083106106275780518252602082019150602081019050602083039250610604565b6001836020036101000a03801982511681845116808217855250505050505090500183600181111561065557fe5b60f81b81526001018273ffffffffffffffffffffffffffffffffffffffff1660601b81526014019550505050505060405160208183030381529060405280519060200120905060006106a5610837565b90508060000160009054906101000a900460ff161561072c576040517f08c379a00000000000000000000000000000000000000000000000000000000081526004018080602001828103825260138152602001807f5265656e7472616e63792064657465637465640000000000000000000000000081525060200191505060405180910390fd5b60018160000160006101000a81548160ff0219169083151502179055505095945050505050565b600061075d610837565b90508060000160009054906101000a900460ff16156107e4576040517f08c379a00000000000000000000000000000000000000000000000000000000081526004018080602001828103825260138152602001807f5265656e7472616e63792064657465637465640000000000000000000000000081525060200191505060405180910390fd5b60018160000160006101000a81548160ff021916908315150217905550505050505050505050505050565b6000610819610837565b60000160006101000a81548160ff0219169083151502179055505050565b6000807f7c1d45961c2d0298f999d2c3d4a7a5e0f688d137f4c32466e3056a97e673b83a9050809150509056fea2646970667358221220ba01b765d294e92c94d89361334acf7529a1e1f7b76a30ba6339347f8220fc4364736f6c63430007060033";
    static readonly abi: readonly [{
        readonly stateMutability: "nonpayable";
        readonly type: "fallback";
    }, {
        readonly inputs: readonly [{
            readonly internalType: "bytes32";
            readonly name: "";
            readonly type: "bytes32";
        }, {
            readonly internalType: "bool";
            readonly name: "";
            readonly type: "bool";
        }];
        readonly name: "checkAfterExecution";
        readonly outputs: readonly [];
        readonly stateMutability: "nonpayable";
        readonly type: "function";
    }, {
        readonly inputs: readonly [{
            readonly internalType: "bytes32";
            readonly name: "";
            readonly type: "bytes32";
        }, {
            readonly internalType: "bool";
            readonly name: "";
            readonly type: "bool";
        }];
        readonly name: "checkAfterModuleExecution";
        readonly outputs: readonly [];
        readonly stateMutability: "nonpayable";
        readonly type: "function";
    }, {
        readonly inputs: readonly [{
            readonly internalType: "address";
            readonly name: "to";
            readonly type: "address";
        }, {
            readonly internalType: "uint256";
            readonly name: "value";
            readonly type: "uint256";
        }, {
            readonly internalType: "bytes";
            readonly name: "data";
            readonly type: "bytes";
        }, {
            readonly internalType: "enum Enum.Operation";
            readonly name: "operation";
            readonly type: "uint8";
        }, {
            readonly internalType: "address";
            readonly name: "module";
            readonly type: "address";
        }];
        readonly name: "checkModuleTransaction";
        readonly outputs: readonly [{
            readonly internalType: "bytes32";
            readonly name: "moduleTxHash";
            readonly type: "bytes32";
        }];
        readonly stateMutability: "nonpayable";
        readonly type: "function";
    }, {
        readonly inputs: readonly [{
            readonly internalType: "address";
            readonly name: "";
            readonly type: "address";
        }, {
            readonly internalType: "uint256";
            readonly name: "";
            readonly type: "uint256";
        }, {
            readonly internalType: "bytes";
            readonly name: "";
            readonly type: "bytes";
        }, {
            readonly internalType: "enum Enum.Operation";
            readonly name: "";
            readonly type: "uint8";
        }, {
            readonly internalType: "uint256";
            readonly name: "";
            readonly type: "uint256";
        }, {
            readonly internalType: "uint256";
            readonly name: "";
            readonly type: "uint256";
        }, {
            readonly internalType: "uint256";
            readonly name: "";
            readonly type: "uint256";
        }, {
            readonly internalType: "address";
            readonly name: "";
            readonly type: "address";
        }, {
            readonly internalType: "address payable";
            readonly name: "";
            readonly type: "address";
        }, {
            readonly internalType: "bytes";
            readonly name: "";
            readonly type: "bytes";
        }, {
            readonly internalType: "address";
            readonly name: "";
            readonly type: "address";
        }];
        readonly name: "checkTransaction";
        readonly outputs: readonly [];
        readonly stateMutability: "nonpayable";
        readonly type: "function";
    }, {
        readonly inputs: readonly [{
            readonly internalType: "bytes4";
            readonly name: "interfaceId";
            readonly type: "bytes4";
        }];
        readonly name: "supportsInterface";
        readonly outputs: readonly [{
            readonly internalType: "bool";
            readonly name: "";
            readonly type: "bool";
        }];
        readonly stateMutability: "view";
        readonly type: "function";
    }];
    static createInterface(): ReentrancyTransactionGuardInterface;
    static connect(address: string, runner?: ContractRunner | null): ReentrancyTransactionGuard;
}
export {};
