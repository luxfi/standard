import { type ContractRunner } from "ethers";
import type { NativeCurrencyPaymentFallback, NativeCurrencyPaymentFallbackInterface } from "../../../contracts/common/NativeCurrencyPaymentFallback";
export declare class NativeCurrencyPaymentFallback__factory {
    static readonly abi: readonly [{
        readonly anonymous: false;
        readonly inputs: readonly [{
            readonly indexed: true;
            readonly internalType: "address";
            readonly name: "sender";
            readonly type: "address";
        }, {
            readonly indexed: false;
            readonly internalType: "uint256";
            readonly name: "value";
            readonly type: "uint256";
        }];
        readonly name: "SafeReceived";
        readonly type: "event";
    }, {
        readonly stateMutability: "payable";
        readonly type: "receive";
    }];
    static createInterface(): NativeCurrencyPaymentFallbackInterface;
    static connect(address: string, runner?: ContractRunner | null): NativeCurrencyPaymentFallback;
}
