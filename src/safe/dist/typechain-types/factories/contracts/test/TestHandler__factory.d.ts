import { ContractFactory, ContractTransactionResponse } from "ethers";
import type { Signer, ContractDeployTransaction, ContractRunner } from "ethers";
import type { NonPayableOverrides } from "../../../common";
import type { TestHandler, TestHandlerInterface } from "../../../contracts/test/TestHandler";
type TestHandlerConstructorParams = [signer?: Signer] | ConstructorParameters<typeof ContractFactory>;
export declare class TestHandler__factory extends ContractFactory {
    constructor(...args: TestHandlerConstructorParams);
    getDeployTransaction(overrides?: NonPayableOverrides & {
        from?: string;
    }): Promise<ContractDeployTransaction>;
    deploy(overrides?: NonPayableOverrides & {
        from?: string;
    }): Promise<TestHandler & {
        deploymentTransaction(): ContractTransactionResponse;
    }>;
    connect(runner: ContractRunner | null): TestHandler__factory;
    static readonly bytecode = "0x608060405234801561001057600080fd5b5060e08061001f6000396000f3fe6080604052348015600f57600080fd5b506004361060285760003560e01c806354955e5914602d575b600080fd5b6033607c565b604051808373ffffffffffffffffffffffffffffffffffffffff1681526020018273ffffffffffffffffffffffffffffffffffffffff1681526020019250505060405180910390f35b60008060856093565b608b60a2565b915091509091565b6000601436033560601c905090565b60003390509056fea26469706673582212203bb05fdff8e545f51a34df027dbc60c2153b635de1cfa5db672db08e62d4823364736f6c63430007060033";
    static readonly abi: readonly [{
        readonly inputs: readonly [];
        readonly name: "dudududu";
        readonly outputs: readonly [{
            readonly internalType: "address";
            readonly name: "sender";
            readonly type: "address";
        }, {
            readonly internalType: "address";
            readonly name: "manager";
            readonly type: "address";
        }];
        readonly stateMutability: "view";
        readonly type: "function";
    }];
    static createInterface(): TestHandlerInterface;
    static connect(address: string, runner?: ContractRunner | null): TestHandler;
}
export {};
