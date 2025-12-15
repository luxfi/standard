import { ContractFactory, ContractTransactionResponse } from "ethers";
import type { Signer, ContractDeployTransaction, ContractRunner } from "ethers";
import type { NonPayableOverrides } from "../../../../common";
import type { DebugTransactionGuard, DebugTransactionGuardInterface } from "../../../../contracts/examples/guards/DebugTransactionGuard";
type DebugTransactionGuardConstructorParams = [signer?: Signer] | ConstructorParameters<typeof ContractFactory>;
export declare class DebugTransactionGuard__factory extends ContractFactory {
    constructor(...args: DebugTransactionGuardConstructorParams);
    getDeployTransaction(overrides?: NonPayableOverrides & {
        from?: string;
    }): Promise<ContractDeployTransaction>;
    deploy(overrides?: NonPayableOverrides & {
        from?: string;
    }): Promise<DebugTransactionGuard & {
        deploymentTransaction(): ContractTransactionResponse;
    }>;
    connect(runner: ContractRunner | null): DebugTransactionGuard__factory;
    static readonly bytecode = "0x608060405234801561001057600080fd5b50610cde806100206000396000f3fe608060405234801561001057600080fd5b50600436106100665760003560e01c806301ffc9a7146100695780632acc37aa146100cc578063728c29721461010657806375f0bb521461022c5780639327136814610434578063ddbdba631461046e57610067565b5b005b6100b46004803603602081101561007f57600080fd5b8101908080357bffffffffffffffffffffffffffffffffffffffffffffffffffffffff191690602001909291905050506104b0565b60405180821515815260200191505060405180910390f35b610104600480360360408110156100e257600080fd5b81019080803590602001909291908035151590602001909291905050506105ea565b005b610216600480360360a081101561011c57600080fd5b81019080803573ffffffffffffffffffffffffffffffffffffffff169060200190929190803590602001909291908035906020019064010000000081111561016357600080fd5b82018360208201111561017557600080fd5b8035906020019184600183028401116401000000008311171561019757600080fd5b91908080601f016020809104026020016040519081016040528093929190818152602001838380828437600081840152601f19601f820116905080830192505050505050509192919290803560ff169060200190929190803573ffffffffffffffffffffffffffffffffffffffff1690602001909291905050506105ee565b6040518082815260200191505060405180910390f35b610432600480360361016081101561024357600080fd5b81019080803573ffffffffffffffffffffffffffffffffffffffff169060200190929190803590602001909291908035906020019064010000000081111561028a57600080fd5b82018360208201111561029c57600080fd5b803590602001918460018302840111640100000000831117156102be57600080fd5b91908080601f016020809104026020016040519081016040528093929190818152602001838380828437600081840152601f19601f820116905080830192505050505050509192919290803560ff169060200190929190803590602001909291908035906020019092919080359060200190929190803573ffffffffffffffffffffffffffffffffffffffff169060200190929190803573ffffffffffffffffffffffffffffffffffffffff1690602001909291908035906020019064010000000081111561038c57600080fd5b82018360208201111561039e57600080fd5b803590602001918460018302840111640100000000831117156103c057600080fd5b91908080601f016020809104026020016040519081016040528093929190818152602001838380828437600081840152601f19601f820116905080830192505050505050509192919290803573ffffffffffffffffffffffffffffffffffffffff1690602001909291905050506107c1565b005b61046c6004803603604081101561044a57600080fd5b8101908080359060200190929190803515159060200190929190505050610b93565b005b61049a6004803603602081101561048457600080fd5b8101908080359060200190929190505050610c90565b6040518082815260200191505060405180910390f35b60007fe6d7a83a000000000000000000000000000000000000000000000000000000007bffffffffffffffffffffffffffffffffffffffffffffffffffffffff1916827bffffffffffffffffffffffffffffffffffffffffffffffffffffffff1916148061057b57507f58401ed8000000000000000000000000000000000000000000000000000000007bffffffffffffffffffffffffffffffffffffffffffffffffffffffff1916827bffffffffffffffffffffffffffffffffffffffffffffffffffffffff1916145b806105e357507f01ffc9a7000000000000000000000000000000000000000000000000000000007bffffffffffffffffffffffffffffffffffffffffffffffffffffffff1916827bffffffffffffffffffffffffffffffffffffffffffffffffffffffff1916145b9050919050565b5050565b60008585858585604051602001808673ffffffffffffffffffffffffffffffffffffffff1660601b815260140185815260200184805190602001908083835b60208310610650578051825260208201915060208101905060208303925061062d565b6001836020036101000a03801982511681845116808217855250505050505090500183600181111561067e57fe5b60f81b81526001018273ffffffffffffffffffffffffffffffffffffffff1660601b815260140195505050505050604051602081830303815290604052805190602001209050807f1725771f9d6c4dbc65eb80aabd07685699bb88d63af391840cf6749871bfb43f8787878787604051808673ffffffffffffffffffffffffffffffffffffffff1681526020018581526020018060200184600181111561072157fe5b81526020018373ffffffffffffffffffffffffffffffffffffffff168152602001828103825285818151815260200191508051906020019080838360005b8381101561077a57808201518184015260208101905061075f565b50505050905090810190601f1680156107a75780820380516001836020036101000a031916815260200191505b50965050505050505060405180910390a295945050505050565b600080600033905060018173ffffffffffffffffffffffffffffffffffffffff1663affed0e06040518163ffffffff1660e01b815260040160206040518083038186803b15801561081157600080fd5b505afa158015610825573d6000803e3d6000fd5b505050506040513d602081101561083b57600080fd5b81019080805190602001909291905050500392508073ffffffffffffffffffffffffffffffffffffffff1663d8d11f788f8f8f8f8f8f8f8f8f8d6040518b63ffffffff1660e01b8152600401808b73ffffffffffffffffffffffffffffffffffffffff1681526020018a8152602001806020018960018111156108ba57fe5b81526020018881526020018781526020018681526020018573ffffffffffffffffffffffffffffffffffffffff1681526020018473ffffffffffffffffffffffffffffffffffffffff16815260200183815260200182810382528a818151815260200191508051906020019080838360005b8381101561094757808201518184015260208101905061092c565b50505050905090810190601f1680156109745780820380516001836020036101000a031916815260200191505b509b50505050505050505050505060206040518083038186803b15801561099a57600080fd5b505afa1580156109ae573d6000803e3d6000fd5b505050506040513d60208110156109c457600080fd5b8101908080519060200190929190505050915050803373ffffffffffffffffffffffffffffffffffffffff167fa65fef32cd19a6639a4bf7a6d196f132c151e4f0bbd2706f7f831b3a778e1ac08f8f8f8f8f60008f118a8d8d604051808a73ffffffffffffffffffffffffffffffffffffffff16815260200189815260200180602001886001811115610a5357fe5b81526020018781526020018615158152602001858152602001806020018473ffffffffffffffffffffffffffffffffffffffff16815260200183810383528a818151815260200191508051906020019080838360005b83811015610ac4578082015181840152602081019050610aa9565b50505050905090810190601f168015610af15780820380516001836020036101000a031916815260200191505b50838103825285818151815260200191508051906020019080838360005b83811015610b2a578082015181840152602081019050610b0f565b50505050905090810190601f168015610b575780820380516001836020036101000a031916815260200191505b509b50505050505050505050505060405180910390a3816000808381526020019081526020016000208190555050505050505050505050505050565b60008060008481526020019081526020016000205490506000811415610c21576040517f08c379a00000000000000000000000000000000000000000000000000000000081526004018080602001828103825260138152602001807f436f756c64206e6f7420676574206e6f6e63650000000000000000000000000081525060200191505060405180910390fd5b60008060008581526020019081526020016000208190555080833373ffffffffffffffffffffffffffffffffffffffff167f0dcc0fb56a30b6fe6b188f45b47369bc7f3c928a9748e245a79fc3f54ddd05688560405180821515815260200191505060405180910390a4505050565b6000602052806000526040600020600091509050548156fea26469706673582212207d71cd0454e6c92f71fe4e502533130f3fca5ae3780fea80f73891cda7f70bba64736f6c63430007060033";
    static readonly abi: readonly [{
        readonly anonymous: false;
        readonly inputs: readonly [{
            readonly indexed: true;
            readonly internalType: "address";
            readonly name: "safe";
            readonly type: "address";
        }, {
            readonly indexed: true;
            readonly internalType: "bytes32";
            readonly name: "txHash";
            readonly type: "bytes32";
        }, {
            readonly indexed: true;
            readonly internalType: "uint256";
            readonly name: "nonce";
            readonly type: "uint256";
        }, {
            readonly indexed: false;
            readonly internalType: "bool";
            readonly name: "success";
            readonly type: "bool";
        }];
        readonly name: "GasUsage";
        readonly type: "event";
    }, {
        readonly anonymous: false;
        readonly inputs: readonly [{
            readonly indexed: true;
            readonly internalType: "bytes32";
            readonly name: "txHash";
            readonly type: "bytes32";
        }, {
            readonly indexed: false;
            readonly internalType: "address";
            readonly name: "to";
            readonly type: "address";
        }, {
            readonly indexed: false;
            readonly internalType: "uint256";
            readonly name: "value";
            readonly type: "uint256";
        }, {
            readonly indexed: false;
            readonly internalType: "bytes";
            readonly name: "data";
            readonly type: "bytes";
        }, {
            readonly indexed: false;
            readonly internalType: "enum Enum.Operation";
            readonly name: "operation";
            readonly type: "uint8";
        }, {
            readonly indexed: false;
            readonly internalType: "address";
            readonly name: "module";
            readonly type: "address";
        }];
        readonly name: "ModuleTransactionDetails";
        readonly type: "event";
    }, {
        readonly anonymous: false;
        readonly inputs: readonly [{
            readonly indexed: true;
            readonly internalType: "address";
            readonly name: "safe";
            readonly type: "address";
        }, {
            readonly indexed: true;
            readonly internalType: "bytes32";
            readonly name: "txHash";
            readonly type: "bytes32";
        }, {
            readonly indexed: false;
            readonly internalType: "address";
            readonly name: "to";
            readonly type: "address";
        }, {
            readonly indexed: false;
            readonly internalType: "uint256";
            readonly name: "value";
            readonly type: "uint256";
        }, {
            readonly indexed: false;
            readonly internalType: "bytes";
            readonly name: "data";
            readonly type: "bytes";
        }, {
            readonly indexed: false;
            readonly internalType: "enum Enum.Operation";
            readonly name: "operation";
            readonly type: "uint8";
        }, {
            readonly indexed: false;
            readonly internalType: "uint256";
            readonly name: "safeTxGas";
            readonly type: "uint256";
        }, {
            readonly indexed: false;
            readonly internalType: "bool";
            readonly name: "usesRefund";
            readonly type: "bool";
        }, {
            readonly indexed: false;
            readonly internalType: "uint256";
            readonly name: "nonce";
            readonly type: "uint256";
        }, {
            readonly indexed: false;
            readonly internalType: "bytes";
            readonly name: "signatures";
            readonly type: "bytes";
        }, {
            readonly indexed: false;
            readonly internalType: "address";
            readonly name: "executor";
            readonly type: "address";
        }];
        readonly name: "TransactionDetails";
        readonly type: "event";
    }, {
        readonly stateMutability: "nonpayable";
        readonly type: "fallback";
    }, {
        readonly inputs: readonly [{
            readonly internalType: "bytes32";
            readonly name: "txHash";
            readonly type: "bytes32";
        }, {
            readonly internalType: "bool";
            readonly name: "success";
            readonly type: "bool";
        }];
        readonly name: "checkAfterExecution";
        readonly outputs: readonly [];
        readonly stateMutability: "nonpayable";
        readonly type: "function";
    }, {
        readonly inputs: readonly [{
            readonly internalType: "bytes32";
            readonly name: "txHash";
            readonly type: "bytes32";
        }, {
            readonly internalType: "bool";
            readonly name: "success";
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
            readonly internalType: "uint256";
            readonly name: "safeTxGas";
            readonly type: "uint256";
        }, {
            readonly internalType: "uint256";
            readonly name: "baseGas";
            readonly type: "uint256";
        }, {
            readonly internalType: "uint256";
            readonly name: "gasPrice";
            readonly type: "uint256";
        }, {
            readonly internalType: "address";
            readonly name: "gasToken";
            readonly type: "address";
        }, {
            readonly internalType: "address payable";
            readonly name: "refundReceiver";
            readonly type: "address";
        }, {
            readonly internalType: "bytes";
            readonly name: "signatures";
            readonly type: "bytes";
        }, {
            readonly internalType: "address";
            readonly name: "executor";
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
    }, {
        readonly inputs: readonly [{
            readonly internalType: "bytes32";
            readonly name: "";
            readonly type: "bytes32";
        }];
        readonly name: "txNonces";
        readonly outputs: readonly [{
            readonly internalType: "uint256";
            readonly name: "";
            readonly type: "uint256";
        }];
        readonly stateMutability: "view";
        readonly type: "function";
    }];
    static createInterface(): DebugTransactionGuardInterface;
    static connect(address: string, runner?: ContractRunner | null): DebugTransactionGuard;
}
export {};
