import { type ContractRunner } from "ethers";
import type { ISafe, ISafeInterface } from "../../../../contracts/test/Test4337ModuleAndHandler.sol/ISafe";
export declare class ISafe__factory {
    static readonly abi: readonly [{
        readonly inputs: readonly [{
            readonly internalType: "address";
            readonly name: "module";
            readonly type: "address";
        }];
        readonly name: "enableModule";
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
            readonly internalType: "uint8";
            readonly name: "operation";
            readonly type: "uint8";
        }];
        readonly name: "execTransactionFromModule";
        readonly outputs: readonly [{
            readonly internalType: "bool";
            readonly name: "success";
            readonly type: "bool";
        }];
        readonly stateMutability: "nonpayable";
        readonly type: "function";
    }];
    static createInterface(): ISafeInterface;
    static connect(address: string, runner?: ContractRunner | null): ISafe;
}
