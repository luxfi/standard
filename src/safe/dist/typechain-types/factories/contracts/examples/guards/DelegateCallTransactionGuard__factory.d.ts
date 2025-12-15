import { ContractFactory, ContractTransactionResponse } from "ethers";
import type { Signer, AddressLike, ContractDeployTransaction, ContractRunner } from "ethers";
import type { NonPayableOverrides } from "../../../../common";
import type { DelegateCallTransactionGuard, DelegateCallTransactionGuardInterface } from "../../../../contracts/examples/guards/DelegateCallTransactionGuard";
type DelegateCallTransactionGuardConstructorParams = [signer?: Signer] | ConstructorParameters<typeof ContractFactory>;
export declare class DelegateCallTransactionGuard__factory extends ContractFactory {
    constructor(...args: DelegateCallTransactionGuardConstructorParams);
    getDeployTransaction(target: AddressLike, overrides?: NonPayableOverrides & {
        from?: string;
    }): Promise<ContractDeployTransaction>;
    deploy(target: AddressLike, overrides?: NonPayableOverrides & {
        from?: string;
    }): Promise<DelegateCallTransactionGuard & {
        deploymentTransaction(): ContractTransactionResponse;
    }>;
    connect(runner: ContractRunner | null): DelegateCallTransactionGuard__factory;
    static readonly bytecode = "0x60a060405234801561001057600080fd5b506040516109913803806109918339818101604052602081101561003357600080fd5b81019080805190602001909291905050508073ffffffffffffffffffffffffffffffffffffffff1660808173ffffffffffffffffffffffffffffffffffffffff1660601b815250505060805160601c6108ee6100a3600039806105de528061062852806107e752506108ee6000f3fe608060405234801561001057600080fd5b50600436106100665760003560e01c806301ffc9a714610069578063250d6a91146100cc5780632acc37aa14610100578063728c29721461013a57806375f0bb5214610260578063932713681461046857610067565b5b005b6100b46004803603602081101561007f57600080fd5b8101908080357bffffffffffffffffffffffffffffffffffffffffffffffffffffffff191690602001909291905050506104a2565b60405180821515815260200191505060405180910390f35b6100d46105dc565b604051808273ffffffffffffffffffffffffffffffffffffffff16815260200191505060405180910390f35b6101386004803603604081101561011657600080fd5b8101908080359060200190929190803515159060200190929190505050610600565b005b61024a600480360360a081101561015057600080fd5b81019080803573ffffffffffffffffffffffffffffffffffffffff169060200190929190803590602001909291908035906020019064010000000081111561019757600080fd5b8201836020820111156101a957600080fd5b803590602001918460018302840111640100000000831117156101cb57600080fd5b91908080601f016020809104026020016040519081016040528093929190818152602001838380828437600081840152601f19601f820116905080830192505050505050509192919290803560ff169060200190929190803573ffffffffffffffffffffffffffffffffffffffff169060200190929190505050610604565b6040518082815260200191505060405180910390f35b610466600480360361016081101561027757600080fd5b81019080803573ffffffffffffffffffffffffffffffffffffffff16906020019092919080359060200190929190803590602001906401000000008111156102be57600080fd5b8201836020820111156102d057600080fd5b803590602001918460018302840111640100000000831117156102f257600080fd5b91908080601f016020809104026020016040519081016040528093929190818152602001838380828437600081840152601f19601f820116905080830192505050505050509192919290803560ff169060200190929190803590602001909291908035906020019092919080359060200190929190803573ffffffffffffffffffffffffffffffffffffffff169060200190929190803573ffffffffffffffffffffffffffffffffffffffff169060200190929190803590602001906401000000008111156103c057600080fd5b8201836020820111156103d257600080fd5b803590602001918460018302840111640100000000831117156103f457600080fd5b91908080601f016020809104026020016040519081016040528093929190818152602001838380828437600081840152601f19601f820116905080830192505050505050509192919290803573ffffffffffffffffffffffffffffffffffffffff1690602001909291905050506107c5565b005b6104a06004803603604081101561047e57600080fd5b81019080803590602001909291908035151590602001909291905050506108b4565b005b60007fe6d7a83a000000000000000000000000000000000000000000000000000000007bffffffffffffffffffffffffffffffffffffffffffffffffffffffff1916827bffffffffffffffffffffffffffffffffffffffffffffffffffffffff1916148061056d57507f58401ed8000000000000000000000000000000000000000000000000000000007bffffffffffffffffffffffffffffffffffffffffffffffffffffffff1916827bffffffffffffffffffffffffffffffffffffffffffffffffffffffff1916145b806105d557507f01ffc9a7000000000000000000000000000000000000000000000000000000007bffffffffffffffffffffffffffffffffffffffffffffffffffffffff1916827bffffffffffffffffffffffffffffffffffffffffffffffffffffffff1916145b9050919050565b7f000000000000000000000000000000000000000000000000000000000000000081565b5050565b600060018081111561061257fe5b83600181111561061e57fe5b14158061067657507f000000000000000000000000000000000000000000000000000000000000000073ffffffffffffffffffffffffffffffffffffffff168673ffffffffffffffffffffffffffffffffffffffff16145b6106e8576040517f08c379a00000000000000000000000000000000000000000000000000000000081526004018080602001828103825260178152602001807f546869732063616c6c206973207265737472696374656400000000000000000081525060200191505060405180910390fd5b8585858585604051602001808673ffffffffffffffffffffffffffffffffffffffff1660601b815260140185815260200184805190602001908083835b602083106107485780518252602082019150602081019050602083039250610725565b6001836020036101000a03801982511681845116808217855250505050505090500183600181111561077657fe5b60f81b81526001018273ffffffffffffffffffffffffffffffffffffffff1660601b81526014019550505050505060405160208183030381529060405280519060200120905095945050505050565b6001808111156107d157fe5b8860018111156107dd57fe5b14158061083557507f000000000000000000000000000000000000000000000000000000000000000073ffffffffffffffffffffffffffffffffffffffff168b73ffffffffffffffffffffffffffffffffffffffff16145b6108a7576040517f08c379a00000000000000000000000000000000000000000000000000000000081526004018080602001828103825260178152602001807f546869732063616c6c206973207265737472696374656400000000000000000081525060200191505060405180910390fd5b5050505050505050505050565b505056fea26469706673582212209f05068974202ecdd37c7ecc0dff1fb1af5970e2611b6df38bf0ae9113a1a3ad64736f6c63430007060033";
    static readonly abi: readonly [{
        readonly inputs: readonly [{
            readonly internalType: "address";
            readonly name: "target";
            readonly type: "address";
        }];
        readonly stateMutability: "nonpayable";
        readonly type: "constructor";
    }, {
        readonly stateMutability: "nonpayable";
        readonly type: "fallback";
    }, {
        readonly inputs: readonly [];
        readonly name: "ALLOWED_TARGET";
        readonly outputs: readonly [{
            readonly internalType: "address";
            readonly name: "";
            readonly type: "address";
        }];
        readonly stateMutability: "view";
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
        readonly name: "checkAfterExecution";
        readonly outputs: readonly [];
        readonly stateMutability: "view";
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
        readonly stateMutability: "view";
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
        readonly stateMutability: "view";
        readonly type: "function";
    }, {
        readonly inputs: readonly [{
            readonly internalType: "address";
            readonly name: "to";
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
            readonly name: "operation";
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
        readonly stateMutability: "view";
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
    static createInterface(): DelegateCallTransactionGuardInterface;
    static connect(address: string, runner?: ContractRunner | null): DelegateCallTransactionGuard;
}
export {};
