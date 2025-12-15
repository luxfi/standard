import { ContractFactory, ContractTransactionResponse } from "ethers";
import type { Signer, ContractDeployTransaction, ContractRunner } from "ethers";
import type { NonPayableOverrides } from "../../../common";
import type { SimulateTxAccessor, SimulateTxAccessorInterface } from "../../../contracts/accessors/SimulateTxAccessor";
type SimulateTxAccessorConstructorParams = [signer?: Signer] | ConstructorParameters<typeof ContractFactory>;
export declare class SimulateTxAccessor__factory extends ContractFactory {
    constructor(...args: SimulateTxAccessorConstructorParams);
    getDeployTransaction(overrides?: NonPayableOverrides & {
        from?: string;
    }): Promise<ContractDeployTransaction>;
    deploy(overrides?: NonPayableOverrides & {
        from?: string;
    }): Promise<SimulateTxAccessor & {
        deploymentTransaction(): ContractTransactionResponse;
    }>;
    connect(runner: ContractRunner | null): SimulateTxAccessor__factory;
    static readonly bytecode = "0x60a060405234801561001057600080fd5b503073ffffffffffffffffffffffffffffffffffffffff1660808173ffffffffffffffffffffffffffffffffffffffff1660601b8152505060805160601c6103526100656000398061017052506103526000f3fe608060405234801561001057600080fd5b506004361061002b5760003560e01c80631c5fb21114610030575b600080fd5b6100de6004803603608081101561004657600080fd5b81019080803573ffffffffffffffffffffffffffffffffffffffff169060200190929190803590602001909291908035906020019064010000000081111561008d57600080fd5b82018360208201111561009f57600080fd5b803590602001918460018302840111640100000000831117156100c157600080fd5b9091929391929390803560ff169060200190929190505050610169565b60405180848152602001831515815260200180602001828103825283818151815260200191508051906020019080838360005b8381101561012c578082015181840152602081019050610111565b50505050905090810190601f1680156101595780820380516001836020036101000a031916815260200191505b5094505050505060405180910390f35b60008060607f000000000000000000000000000000000000000000000000000000000000000073ffffffffffffffffffffffffffffffffffffffff163073ffffffffffffffffffffffffffffffffffffffff161415610213576040517f08c379a00000000000000000000000000000000000000000000000000000000081526004018080602001828103825260398152602001806102e46039913960400191505060405180910390fd5b60005a9050610269898989898080601f016020809104026020016040519081016040528093929190818152602001838380828437600081840152601f19601f82011690508083019250505050505050885a610297565b92505a8103935060405160203d0181016040523d81523d6000602083013e8092505050955095509592505050565b60006001808111156102a557fe5b8360018111156102b157fe5b14156102ca576000808551602087018986f490506102da565b600080855160208701888a87f190505b9594505050505056fe53696d756c61746554784163636573736f722073686f756c64206f6e6c792062652063616c6c6564207669612064656c656761746563616c6ca2646970667358221220fd430144adb49f3c41232dfb6304536647edd8ba193872e74bf6864e1b781cca64736f6c63430007060033";
    static readonly abi: readonly [{
        readonly inputs: readonly [];
        readonly stateMutability: "nonpayable";
        readonly type: "constructor";
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
        }];
        readonly name: "simulate";
        readonly outputs: readonly [{
            readonly internalType: "uint256";
            readonly name: "estimate";
            readonly type: "uint256";
        }, {
            readonly internalType: "bool";
            readonly name: "success";
            readonly type: "bool";
        }, {
            readonly internalType: "bytes";
            readonly name: "returnData";
            readonly type: "bytes";
        }];
        readonly stateMutability: "nonpayable";
        readonly type: "function";
    }];
    static createInterface(): SimulateTxAccessorInterface;
    static connect(address: string, runner?: ContractRunner | null): SimulateTxAccessor;
}
export {};
