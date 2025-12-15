import { type ContractRunner } from "ethers";
import type { ISignatureValidator, ISignatureValidatorInterface } from "../../../contracts/interfaces/ISignatureValidator";
export declare class ISignatureValidator__factory {
    static readonly abi: readonly [{
        readonly inputs: readonly [{
            readonly internalType: "bytes32";
            readonly name: "_hash";
            readonly type: "bytes32";
        }, {
            readonly internalType: "bytes";
            readonly name: "_signature";
            readonly type: "bytes";
        }];
        readonly name: "isValidSignature";
        readonly outputs: readonly [{
            readonly internalType: "bytes4";
            readonly name: "";
            readonly type: "bytes4";
        }];
        readonly stateMutability: "view";
        readonly type: "function";
    }];
    static createInterface(): ISignatureValidatorInterface;
    static connect(address: string, runner?: ContractRunner | null): ISignatureValidator;
}
