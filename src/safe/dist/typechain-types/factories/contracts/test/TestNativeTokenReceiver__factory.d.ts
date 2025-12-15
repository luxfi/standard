import { ContractFactory, ContractTransactionResponse } from "ethers";
import type { Signer, ContractDeployTransaction, ContractRunner } from "ethers";
import type { NonPayableOverrides } from "../../../common";
import type { TestNativeTokenReceiver, TestNativeTokenReceiverInterface } from "../../../contracts/test/TestNativeTokenReceiver";
type TestNativeTokenReceiverConstructorParams = [signer?: Signer] | ConstructorParameters<typeof ContractFactory>;
export declare class TestNativeTokenReceiver__factory extends ContractFactory {
    constructor(...args: TestNativeTokenReceiverConstructorParams);
    getDeployTransaction(overrides?: NonPayableOverrides & {
        from?: string;
    }): Promise<ContractDeployTransaction>;
    deploy(overrides?: NonPayableOverrides & {
        from?: string;
    }): Promise<TestNativeTokenReceiver & {
        deploymentTransaction(): ContractTransactionResponse;
    }>;
    connect(runner: ContractRunner | null): TestNativeTokenReceiver__factory;
    static readonly bytecode = "0x6080604052348015600f57600080fd5b50609280601d6000396000f3fe60806040523373ffffffffffffffffffffffffffffffffffffffff167f16549311ba52796916987df5401f791fb06b998524a5a8684010010415850bb3345a604051808381526020018281526020019250505060405180910390a200fea264697066735822122035663a4184b682e3d2c1649228db3273b6a2439d885e4203ca9ef996501e7b4c64736f6c63430007060033";
    static readonly abi: readonly [{
        readonly anonymous: false;
        readonly inputs: readonly [{
            readonly indexed: true;
            readonly internalType: "address";
            readonly name: "from";
            readonly type: "address";
        }, {
            readonly indexed: false;
            readonly internalType: "uint256";
            readonly name: "amount";
            readonly type: "uint256";
        }, {
            readonly indexed: false;
            readonly internalType: "uint256";
            readonly name: "forwardedGas";
            readonly type: "uint256";
        }];
        readonly name: "BreadReceived";
        readonly type: "event";
    }, {
        readonly stateMutability: "payable";
        readonly type: "fallback";
    }];
    static createInterface(): TestNativeTokenReceiverInterface;
    static connect(address: string, runner?: ContractRunner | null): TestNativeTokenReceiver;
}
export {};
