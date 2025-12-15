import { type ContractRunner } from "ethers";
import type { IProxy, IProxyInterface } from "../../../../contracts/proxies/SafeProxy.sol/IProxy";
export declare class IProxy__factory {
    static readonly abi: readonly [{
        readonly inputs: readonly [];
        readonly name: "masterCopy";
        readonly outputs: readonly [{
            readonly internalType: "address";
            readonly name: "";
            readonly type: "address";
        }];
        readonly stateMutability: "view";
        readonly type: "function";
    }];
    static createInterface(): IProxyInterface;
    static connect(address: string, runner?: ContractRunner | null): IProxy;
}
