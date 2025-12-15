import { type ContractRunner } from "ethers";
import type { IGuardManager, IGuardManagerInterface } from "../../../contracts/interfaces/IGuardManager";
export declare class IGuardManager__factory {
    static readonly abi: readonly [{
        readonly anonymous: false;
        readonly inputs: readonly [{
            readonly indexed: true;
            readonly internalType: "address";
            readonly name: "guard";
            readonly type: "address";
        }];
        readonly name: "ChangedGuard";
        readonly type: "event";
    }, {
        readonly inputs: readonly [{
            readonly internalType: "address";
            readonly name: "guard";
            readonly type: "address";
        }];
        readonly name: "setGuard";
        readonly outputs: readonly [];
        readonly stateMutability: "nonpayable";
        readonly type: "function";
    }];
    static createInterface(): IGuardManagerInterface;
    static connect(address: string, runner?: ContractRunner | null): IGuardManager;
}
