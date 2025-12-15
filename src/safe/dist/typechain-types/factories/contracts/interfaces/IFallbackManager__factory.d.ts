import { type ContractRunner } from "ethers";
import type { IFallbackManager, IFallbackManagerInterface } from "../../../contracts/interfaces/IFallbackManager";
export declare class IFallbackManager__factory {
    static readonly abi: readonly [{
        readonly anonymous: false;
        readonly inputs: readonly [{
            readonly indexed: true;
            readonly internalType: "address";
            readonly name: "handler";
            readonly type: "address";
        }];
        readonly name: "ChangedFallbackHandler";
        readonly type: "event";
    }, {
        readonly inputs: readonly [{
            readonly internalType: "address";
            readonly name: "handler";
            readonly type: "address";
        }];
        readonly name: "setFallbackHandler";
        readonly outputs: readonly [];
        readonly stateMutability: "nonpayable";
        readonly type: "function";
    }];
    static createInterface(): IFallbackManagerInterface;
    static connect(address: string, runner?: ContractRunner | null): IFallbackManager;
}
