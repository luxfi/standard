import { ContractFactory, ContractTransactionResponse } from "ethers";
import type { Signer, AddressLike, ContractDeployTransaction, ContractRunner } from "ethers";
import type { NonPayableOverrides } from "../../../../../common";
import type { Migration, MigrationInterface } from "../../../../../contracts/examples/libraries/Migrate_1_3_0_to_1_2_0.sol/Migration";
type MigrationConstructorParams = [signer?: Signer] | ConstructorParameters<typeof ContractFactory>;
export declare class Migration__factory extends ContractFactory {
    constructor(...args: MigrationConstructorParams);
    getDeployTransaction(targetSingleton: AddressLike, overrides?: NonPayableOverrides & {
        from?: string;
    }): Promise<ContractDeployTransaction>;
    deploy(targetSingleton: AddressLike, overrides?: NonPayableOverrides & {
        from?: string;
    }): Promise<Migration & {
        deploymentTransaction(): ContractTransactionResponse;
    }>;
    connect(runner: ContractRunner | null): Migration__factory;
    static readonly bytecode = "0x60c060405234801561001057600080fd5b506040516104d43803806104d48339818101604052602081101561003357600080fd5b8101908080519060200190929190505050600073ffffffffffffffffffffffffffffffffffffffff168173ffffffffffffffffffffffffffffffffffffffff1614156100ca576040517f08c379a00000000000000000000000000000000000000000000000000000000081526004018080602001828103825260228152602001806104b26022913960400191505060405180910390fd5b8073ffffffffffffffffffffffffffffffffffffffff1660a08173ffffffffffffffffffffffffffffffffffffffff1660601b815250503073ffffffffffffffffffffffffffffffffffffffff1660808173ffffffffffffffffffffffffffffffffffffffff1660601b815250505060805160601c60a05160601c61034861016a6000398060ba52806101a752508060de528061010252506103486000f3fe608060405234801561001057600080fd5b50600436106100415760003560e01c806310dfd5061461004657806372f7a9561461007a5780638fd3ab80146100ae575b600080fd5b61004e6100b8565b604051808273ffffffffffffffffffffffffffffffffffffffff16815260200191505060405180910390f35b6100826100dc565b604051808273ffffffffffffffffffffffffffffffffffffffff16815260200191505060405180910390f35b6100b6610100565b005b7f000000000000000000000000000000000000000000000000000000000000000081565b7f000000000000000000000000000000000000000000000000000000000000000081565b7f000000000000000000000000000000000000000000000000000000000000000073ffffffffffffffffffffffffffffffffffffffff163073ffffffffffffffffffffffffffffffffffffffff1614156101a5576040517f08c379a00000000000000000000000000000000000000000000000000000000081526004018080602001828103825260308152602001806102e36030913960400191505060405180910390fd5b7f00000000000000000000000000000000000000000000000000000000000000006000806101000a81548173ffffffffffffffffffffffffffffffffffffffff021916908373ffffffffffffffffffffffffffffffffffffffff1602179055507f035aff83d86937d35b32e04f0ddc6ff469290eef2f1b692d8a815c89404d474960001b30604051602001808381526020018273ffffffffffffffffffffffffffffffffffffffff16815260200192505050604051602081830303815290604052805190602001206006819055507f75e41bc35ff1bf14d81d1d2f649c0084a0f974f9289c803ec9898eeec4c8d0b860008054906101000a900473ffffffffffffffffffffffffffffffffffffffff16604051808273ffffffffffffffffffffffffffffffffffffffff16815260200191505060405180910390a156fe4d6967726174696f6e2073686f756c64206f6e6c792062652063616c6c6564207669612064656c656761746563616c6ca2646970667358221220439513640813d1fe3090885dc04f84edfee78da22daa5a884a788199408ed1ad64736f6c63430007060033496e76616c69642073696e676c65746f6e20616464726573732070726f7669646564";
    static readonly abi: readonly [{
        readonly inputs: readonly [{
            readonly internalType: "address";
            readonly name: "targetSingleton";
            readonly type: "address";
        }];
        readonly stateMutability: "nonpayable";
        readonly type: "constructor";
    }, {
        readonly anonymous: false;
        readonly inputs: readonly [{
            readonly indexed: false;
            readonly internalType: "address";
            readonly name: "singleton";
            readonly type: "address";
        }];
        readonly name: "ChangedMasterCopy";
        readonly type: "event";
    }, {
        readonly inputs: readonly [];
        readonly name: "MIGRATION_SINGLETON";
        readonly outputs: readonly [{
            readonly internalType: "address";
            readonly name: "";
            readonly type: "address";
        }];
        readonly stateMutability: "view";
        readonly type: "function";
    }, {
        readonly inputs: readonly [];
        readonly name: "SAFE_120_SINGLETON";
        readonly outputs: readonly [{
            readonly internalType: "address";
            readonly name: "";
            readonly type: "address";
        }];
        readonly stateMutability: "view";
        readonly type: "function";
    }, {
        readonly inputs: readonly [];
        readonly name: "migrate";
        readonly outputs: readonly [];
        readonly stateMutability: "nonpayable";
        readonly type: "function";
    }];
    static createInterface(): MigrationInterface;
    static connect(address: string, runner?: ContractRunner | null): Migration;
}
export {};
