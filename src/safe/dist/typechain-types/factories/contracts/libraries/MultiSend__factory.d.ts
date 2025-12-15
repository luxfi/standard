import { ContractFactory, ContractTransactionResponse } from "ethers";
import type { Signer, ContractDeployTransaction, ContractRunner } from "ethers";
import type { NonPayableOverrides } from "../../../common";
import type { MultiSend, MultiSendInterface } from "../../../contracts/libraries/MultiSend";
type MultiSendConstructorParams = [signer?: Signer] | ConstructorParameters<typeof ContractFactory>;
export declare class MultiSend__factory extends ContractFactory {
    constructor(...args: MultiSendConstructorParams);
    getDeployTransaction(overrides?: NonPayableOverrides & {
        from?: string;
    }): Promise<ContractDeployTransaction>;
    deploy(overrides?: NonPayableOverrides & {
        from?: string;
    }): Promise<MultiSend & {
        deploymentTransaction(): ContractTransactionResponse;
    }>;
    connect(runner: ContractRunner | null): MultiSend__factory;
    static readonly bytecode = "0x60a060405234801561001057600080fd5b503073ffffffffffffffffffffffffffffffffffffffff1660808173ffffffffffffffffffffffffffffffffffffffff1660601b8152505060805160601c6102826100646000398060e052506102826000f3fe60806040526004361061001e5760003560e01c80638d80ff0a14610023575b600080fd5b6100dc6004803603602081101561003957600080fd5b810190808035906020019064010000000081111561005657600080fd5b82018360208201111561006857600080fd5b8035906020019184600183028401116401000000008311171561008a57600080fd5b91908080601f016020809104026020016040519081016040528093929190818152602001838380828437600081840152601f19601f8201169050808301925050505050505091929192905050506100de565b005b7f000000000000000000000000000000000000000000000000000000000000000073ffffffffffffffffffffffffffffffffffffffff163073ffffffffffffffffffffffffffffffffffffffff161415610183576040517f08c379a000000000000000000000000000000000000000000000000000000000815260040180806020018281038252603081526020018061021d6030913960400191505060405180910390fd5b805160205b81811015610217578083015160f81c6001820184015160601c30811502811790506015830185015160358401860151605585018701600085600081146101d557600181146101e5576101f0565b6000808585888a5af191506101f0565b6000808585895af491505b506000811415610204573d6000803e3d6000fd5b8260550187019650505050505050610188565b50505056fe4d756c746953656e642073686f756c64206f6e6c792062652063616c6c6564207669612064656c656761746563616c6ca2646970667358221220e9247725ae02281aece4e1adb50750a16d7263291351569be0013fc5e27ba8e364736f6c63430007060033";
    static readonly abi: readonly [{
        readonly inputs: readonly [];
        readonly stateMutability: "nonpayable";
        readonly type: "constructor";
    }, {
        readonly inputs: readonly [{
            readonly internalType: "bytes";
            readonly name: "transactions";
            readonly type: "bytes";
        }];
        readonly name: "multiSend";
        readonly outputs: readonly [];
        readonly stateMutability: "payable";
        readonly type: "function";
    }];
    static createInterface(): MultiSendInterface;
    static connect(address: string, runner?: ContractRunner | null): MultiSend;
}
export {};
