import { ContractFactory, ContractTransactionResponse } from "ethers";
import type { Signer, ContractDeployTransaction, ContractRunner } from "ethers";
import type { NonPayableOverrides } from "../../../common";
import type { CompatibilityFallbackHandler, CompatibilityFallbackHandlerInterface } from "../../../contracts/handler/CompatibilityFallbackHandler";
type CompatibilityFallbackHandlerConstructorParams = [signer?: Signer] | ConstructorParameters<typeof ContractFactory>;
export declare class CompatibilityFallbackHandler__factory extends ContractFactory {
    constructor(...args: CompatibilityFallbackHandlerConstructorParams);
    getDeployTransaction(overrides?: NonPayableOverrides & {
        from?: string;
    }): Promise<ContractDeployTransaction>;
    deploy(overrides?: NonPayableOverrides & {
        from?: string;
    }): Promise<CompatibilityFallbackHandler & {
        deploymentTransaction(): ContractTransactionResponse;
    }>;
    connect(runner: ContractRunner | null): CompatibilityFallbackHandler__factory;
    static readonly bytecode = "0x608060405234801561001057600080fd5b50611239806100206000396000f3fe608060405234801561001057600080fd5b50600436106100a85760003560e01c8063230316401161007157806323031640146104c35780636ac2478414610617578063b2494df314610706578063bc197c8114610765578063bd61951d146108fb578063f23a6e6114610a0d576100a8565b806223de29146100ad57806301ffc9a7146101e55780630a1028c414610248578063150b7a02146103175780631626ba7e1461040d575b600080fd5b6101e3600480360360c08110156100c357600080fd5b81019080803573ffffffffffffffffffffffffffffffffffffffff169060200190929190803573ffffffffffffffffffffffffffffffffffffffff169060200190929190803573ffffffffffffffffffffffffffffffffffffffff169060200190929190803590602001909291908035906020019064010000000081111561014a57600080fd5b82018360208201111561015c57600080fd5b8035906020019184600183028401116401000000008311171561017e57600080fd5b90919293919293908035906020019064010000000081111561019f57600080fd5b8201836020820111156101b157600080fd5b803590602001918460018302840111640100000000831117156101d357600080fd5b9091929391929390505050610b0d565b005b610230600480360360208110156101fb57600080fd5b8101908080357bffffffffffffffffffffffffffffffffffffffffffffffffffffffff19169060200190929190505050610b17565b60405180821515815260200191505060405180910390f35b6103016004803603602081101561025e57600080fd5b810190808035906020019064010000000081111561027b57600080fd5b82018360208201111561028d57600080fd5b803590602001918460018302840111640100000000831117156102af57600080fd5b91908080601f016020809104026020016040519081016040528093929190818152602001838380828437600081840152601f19601f820116905080830192505050505050509192919290505050610c51565b6040518082815260200191505060405180910390f35b6103d86004803603608081101561032d57600080fd5b81019080803573ffffffffffffffffffffffffffffffffffffffff169060200190929190803573ffffffffffffffffffffffffffffffffffffffff169060200190929190803590602001909291908035906020019064010000000081111561039457600080fd5b8201836020820111156103a657600080fd5b803590602001918460018302840111640100000000831117156103c857600080fd5b9091929391929390505050610c64565b60405180827bffffffffffffffffffffffffffffffffffffffffffffffffffffffff1916815260200191505060405180910390f35b61048e6004803603604081101561042357600080fd5b81019080803590602001909291908035906020019064010000000081111561044a57600080fd5b82018360208201111561045c57600080fd5b8035906020019184600183028401116401000000008311171561047e57600080fd5b9091929391929390505050610c79565b60405180827bffffffffffffffffffffffffffffffffffffffffffffffffffffffff1916815260200191505060405180910390f35b61059c600480360360408110156104d957600080fd5b81019080803573ffffffffffffffffffffffffffffffffffffffff1690602001909291908035906020019064010000000081111561051657600080fd5b82018360208201111561052857600080fd5b8035906020019184600183028401116401000000008311171561054a57600080fd5b91908080601f016020809104026020016040519081016040528093929190818152602001838380828437600081840152601f19601f820116905080830192505050505050509192919290505050610e7d565b6040518080602001828103825283818151815260200191508051906020019080838360005b838110156105dc5780820151818401526020810190506105c1565b50505050905090810190601f1680156106095780820380516001836020036101000a031916815260200191505b509250505060405180910390f35b6106f06004803603604081101561062d57600080fd5b81019080803573ffffffffffffffffffffffffffffffffffffffff1690602001909291908035906020019064010000000081111561066a57600080fd5b82018360208201111561067c57600080fd5b8035906020019184600183028401116401000000008311171561069e57600080fd5b91908080601f016020809104026020016040519081016040528093929190818152602001838380828437600081840152601f19601f820116905080830192505050505050509192919290505050610fe9565b6040518082815260200191505060405180910390f35b61070e611004565b6040518080602001828103825283818151815260200191508051906020019060200280838360005b83811015610751578082015181840152602081019050610736565b505050509050019250505060405180910390f35b6108c6600480360360a081101561077b57600080fd5b81019080803573ffffffffffffffffffffffffffffffffffffffff169060200190929190803573ffffffffffffffffffffffffffffffffffffffff169060200190929190803590602001906401000000008111156107d857600080fd5b8201836020820111156107ea57600080fd5b8035906020019184602083028401116401000000008311171561080c57600080fd5b90919293919293908035906020019064010000000081111561082d57600080fd5b82018360208201111561083f57600080fd5b8035906020019184602083028401116401000000008311171561086157600080fd5b90919293919293908035906020019064010000000081111561088257600080fd5b82018360208201111561089457600080fd5b803590602001918460018302840111640100000000831117156108b657600080fd5b909192939192939050505061116b565b60405180827bffffffffffffffffffffffffffffffffffffffffffffffffffffffff1916815260200191505060405180910390f35b6109926004803603604081101561091157600080fd5b81019080803573ffffffffffffffffffffffffffffffffffffffff1690602001909291908035906020019064010000000081111561094e57600080fd5b82018360208201111561096057600080fd5b8035906020019184600183028401116401000000008311171561098257600080fd5b9091929391929390505050611183565b6040518080602001828103825283818151815260200191508051906020019080838360005b838110156109d25780820151818401526020810190506109b7565b50505050905090810190601f1680156109ff5780820380516001836020036101000a031916815260200191505b509250505060405180910390f35b610ad8600480360360a0811015610a2357600080fd5b81019080803573ffffffffffffffffffffffffffffffffffffffff169060200190929190803573ffffffffffffffffffffffffffffffffffffffff169060200190929190803590602001909291908035906020019092919080359060200190640100000000811115610a9457600080fd5b820183602082011115610aa657600080fd5b80359060200191846001830284011164010000000083111715610ac857600080fd5b90919293919293905050506111ed565b60405180827bffffffffffffffffffffffffffffffffffffffffffffffffffffffff1916815260200191505060405180910390f35b5050505050505050565b60007f4e2312e0000000000000000000000000000000000000000000000000000000007bffffffffffffffffffffffffffffffffffffffffffffffffffffffff1916827bffffffffffffffffffffffffffffffffffffffffffffffffffffffff19161480610be257507f150b7a02000000000000000000000000000000000000000000000000000000007bffffffffffffffffffffffffffffffffffffffffffffffffffffffff1916827bffffffffffffffffffffffffffffffffffffffffffffffffffffffff1916145b80610c4a57507f01ffc9a7000000000000000000000000000000000000000000000000000000007bffffffffffffffffffffffffffffffffffffffffffffffffffffffff1916827bffffffffffffffffffffffffffffffffffffffffffffffffffffffff1916145b9050919050565b6000610c5d3383610fe9565b9050919050565b600063150b7a0260e01b905095945050505050565b6000803390506000610caa828760405160200180828152602001915050604051602081830303815290604052610e7d565b90506000818051906020012090506000868690501415610dcb5760008373ffffffffffffffffffffffffffffffffffffffff16635ae6bd37836040518263ffffffff1660e01b81526004018082815260200191505060206040518083038186803b158015610d1757600080fd5b505afa158015610d2b573d6000803e3d6000fd5b505050506040513d6020811015610d4157600080fd5b81019080805190602001909291905050501415610dc6576040517f08c379a00000000000000000000000000000000000000000000000000000000081526004018080602001828103825260118152602001807f48617368206e6f7420617070726f76656400000000000000000000000000000081525060200191505060405180910390fd5b610e69565b8273ffffffffffffffffffffffffffffffffffffffff1663ed516d518288886040518463ffffffff1660e01b815260040180848152602001806020018281038252848482818152602001925080828437600081840152601f19601f82011690508083019250505094505050505060006040518083038186803b158015610e5057600080fd5b505afa158015610e64573d6000803e3d6000fd5b505050505b631626ba7e60e01b93505050509392505050565b606060007f60b3cbf8b4a223d68d641b3b6ddf9a298e7f33710cf3d3a9d1146b5a6150fbca60001b83805190602001206040516020018083815260200182815260200192505050604051602081830303815290604052805190602001209050601960f81b600160f81b8573ffffffffffffffffffffffffffffffffffffffff1663f698da256040518163ffffffff1660e01b815260040160206040518083038186803b158015610f2c57600080fd5b505afa158015610f40573d6000803e3d6000fd5b505050506040513d6020811015610f5657600080fd5b81019080805190602001909291905050508360405160200180857effffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff19168152600101847effffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff1916815260010183815260200182815260200194505050505060405160208183030381529060405291505092915050565b6000610ff58383610e7d565b80519060200120905092915050565b6060600033905060008173ffffffffffffffffffffffffffffffffffffffff1663cc2f84526001600a6040518363ffffffff1660e01b8152600401808373ffffffffffffffffffffffffffffffffffffffff1681526020018281526020019250505060006040518083038186803b15801561107e57600080fd5b505afa158015611092573d6000803e3d6000fd5b505050506040513d6000823e3d601f19601f8201168201806040525060408110156110bc57600080fd5b81019080805160405193929190846401000000008211156110dc57600080fd5b838201915060208201858111156110f257600080fd5b825186602082028301116401000000008211171561110f57600080fd5b8083526020830192505050908051906020019060200280838360005b8381101561114657808201518184015260208101905061112b565b5050505090500160405260200180519060200190929190505050509050809250505090565b600063bc197c8160e01b905098975050505050505050565b60606040517fb4faba09000000000000000000000000000000000000000000000000000000008152600436036004808301376020600036836000335af15060203d036040519250808301604052806020843e6000516111e457825160208401fd5b50509392505050565b600063f23a6e6160e01b9050969550505050505056fea2646970667358221220bd5e376a60f45d44431a5f976a20e60cd1ebbd55d92b2ea18095f22e13dd380364736f6c63430007060033";
    static readonly abi: readonly [{
        readonly inputs: readonly [{
            readonly internalType: "contract ISafe";
            readonly name: "safe";
            readonly type: "address";
        }, {
            readonly internalType: "bytes";
            readonly name: "message";
            readonly type: "bytes";
        }];
        readonly name: "encodeMessageDataForSafe";
        readonly outputs: readonly [{
            readonly internalType: "bytes";
            readonly name: "";
            readonly type: "bytes";
        }];
        readonly stateMutability: "view";
        readonly type: "function";
    }, {
        readonly inputs: readonly [{
            readonly internalType: "bytes";
            readonly name: "message";
            readonly type: "bytes";
        }];
        readonly name: "getMessageHash";
        readonly outputs: readonly [{
            readonly internalType: "bytes32";
            readonly name: "";
            readonly type: "bytes32";
        }];
        readonly stateMutability: "view";
        readonly type: "function";
    }, {
        readonly inputs: readonly [{
            readonly internalType: "contract ISafe";
            readonly name: "safe";
            readonly type: "address";
        }, {
            readonly internalType: "bytes";
            readonly name: "message";
            readonly type: "bytes";
        }];
        readonly name: "getMessageHashForSafe";
        readonly outputs: readonly [{
            readonly internalType: "bytes32";
            readonly name: "";
            readonly type: "bytes32";
        }];
        readonly stateMutability: "view";
        readonly type: "function";
    }, {
        readonly inputs: readonly [];
        readonly name: "getModules";
        readonly outputs: readonly [{
            readonly internalType: "address[]";
            readonly name: "";
            readonly type: "address[]";
        }];
        readonly stateMutability: "view";
        readonly type: "function";
    }, {
        readonly inputs: readonly [{
            readonly internalType: "bytes32";
            readonly name: "_dataHash";
            readonly type: "bytes32";
        }, {
            readonly internalType: "bytes";
            readonly name: "_signature";
            readonly type: "bytes";
        }];
        readonly name: "isValidSignature";
        readonly outputs: readonly [{
            readonly internalType: "bytes4";
            readonly name: "";
            readonly type: "bytes4";
        }];
        readonly stateMutability: "view";
        readonly type: "function";
    }, {
        readonly inputs: readonly [{
            readonly internalType: "address";
            readonly name: "";
            readonly type: "address";
        }, {
            readonly internalType: "address";
            readonly name: "";
            readonly type: "address";
        }, {
            readonly internalType: "uint256[]";
            readonly name: "";
            readonly type: "uint256[]";
        }, {
            readonly internalType: "uint256[]";
            readonly name: "";
            readonly type: "uint256[]";
        }, {
            readonly internalType: "bytes";
            readonly name: "";
            readonly type: "bytes";
        }];
        readonly name: "onERC1155BatchReceived";
        readonly outputs: readonly [{
            readonly internalType: "bytes4";
            readonly name: "";
            readonly type: "bytes4";
        }];
        readonly stateMutability: "pure";
        readonly type: "function";
    }, {
        readonly inputs: readonly [{
            readonly internalType: "address";
            readonly name: "";
            readonly type: "address";
        }, {
            readonly internalType: "address";
            readonly name: "";
            readonly type: "address";
        }, {
            readonly internalType: "uint256";
            readonly name: "";
            readonly type: "uint256";
        }, {
            readonly internalType: "uint256";
            readonly name: "";
            readonly type: "uint256";
        }, {
            readonly internalType: "bytes";
            readonly name: "";
            readonly type: "bytes";
        }];
        readonly name: "onERC1155Received";
        readonly outputs: readonly [{
            readonly internalType: "bytes4";
            readonly name: "";
            readonly type: "bytes4";
        }];
        readonly stateMutability: "pure";
        readonly type: "function";
    }, {
        readonly inputs: readonly [{
            readonly internalType: "address";
            readonly name: "";
            readonly type: "address";
        }, {
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
        }];
        readonly name: "onERC721Received";
        readonly outputs: readonly [{
            readonly internalType: "bytes4";
            readonly name: "";
            readonly type: "bytes4";
        }];
        readonly stateMutability: "pure";
        readonly type: "function";
    }, {
        readonly inputs: readonly [{
            readonly internalType: "address";
            readonly name: "targetContract";
            readonly type: "address";
        }, {
            readonly internalType: "bytes";
            readonly name: "calldataPayload";
            readonly type: "bytes";
        }];
        readonly name: "simulate";
        readonly outputs: readonly [{
            readonly internalType: "bytes";
            readonly name: "response";
            readonly type: "bytes";
        }];
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
            readonly internalType: "address";
            readonly name: "";
            readonly type: "address";
        }, {
            readonly internalType: "address";
            readonly name: "";
            readonly type: "address";
        }, {
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
            readonly internalType: "bytes";
            readonly name: "";
            readonly type: "bytes";
        }];
        readonly name: "tokensReceived";
        readonly outputs: readonly [];
        readonly stateMutability: "pure";
        readonly type: "function";
    }];
    static createInterface(): CompatibilityFallbackHandlerInterface;
    static connect(address: string, runner?: ContractRunner | null): CompatibilityFallbackHandler;
}
export {};
