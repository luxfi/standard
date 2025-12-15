import { ContractFactory, ContractTransactionResponse } from "ethers";
import type { Signer, ContractDeployTransaction, ContractRunner } from "ethers";
import type { NonPayableOverrides } from "../../../common";
import type { MultiSendCallOnly, MultiSendCallOnlyInterface } from "../../../contracts/libraries/MultiSendCallOnly";
type MultiSendCallOnlyConstructorParams = [signer?: Signer] | ConstructorParameters<typeof ContractFactory>;
export declare class MultiSendCallOnly__factory extends ContractFactory {
    constructor(...args: MultiSendCallOnlyConstructorParams);
    getDeployTransaction(overrides?: NonPayableOverrides & {
        from?: string;
    }): Promise<ContractDeployTransaction>;
    deploy(overrides?: NonPayableOverrides & {
        from?: string;
    }): Promise<MultiSendCallOnly & {
        deploymentTransaction(): ContractTransactionResponse;
    }>;
    connect(runner: ContractRunner | null): MultiSendCallOnly__factory;
    static readonly bytecode = "0x608060405234801561001057600080fd5b506101a7806100206000396000f3fe60806040526004361061001e5760003560e01c80638d80ff0a14610023575b600080fd5b6100dc6004803603602081101561003957600080fd5b810190808035906020019064010000000081111561005657600080fd5b82018360208201111561006857600080fd5b8035906020019184600183028401116401000000008311171561008a57600080fd5b91908080601f016020809104026020016040519081016040528093929190818152602001838380828437600081840152601f19601f8201169050808301925050505050505091929192905050506100de565b005b805160205b8181101561016c578083015160f81c6001820184015160601c3081150281179050601583018501516035840186015160558501870160008560008114610130576001811461014057610145565b6000808585888a5af19150610145565b600080fd5b506000811415610159573d6000803e3d6000fd5b82605501870196505050505050506100e3565b50505056fea264697066735822122000250349ea75d699aeb18c12c69612fd1acc8c66ad1710a840b49574ece9b09364736f6c63430007060033";
    static readonly abi: readonly [{
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
    static createInterface(): MultiSendCallOnlyInterface;
    static connect(address: string, runner?: ContractRunner | null): MultiSendCallOnly;
}
export {};
