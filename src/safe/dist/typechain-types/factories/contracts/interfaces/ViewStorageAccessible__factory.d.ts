import { type ContractRunner } from "ethers";
import type { ViewStorageAccessible, ViewStorageAccessibleInterface } from "../../../contracts/interfaces/ViewStorageAccessible";
export declare class ViewStorageAccessible__factory {
    static readonly abi: readonly [{
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
            readonly name: "";
            readonly type: "bytes";
        }];
        readonly stateMutability: "view";
        readonly type: "function";
    }];
    static createInterface(): ViewStorageAccessibleInterface;
    static connect(address: string, runner?: ContractRunner | null): ViewStorageAccessible;
}
