import { BigNumberish } from "ethers";
import { MetaTransaction, SafeTransaction } from "./execution";
import { MultiSend } from "../../typechain-types";
export declare const encodeMultiSend: (txs: MetaTransaction[]) => string;
export declare const buildMultiSendSafeTx: (multiSend: MultiSend, txs: MetaTransaction[], nonce: BigNumberish, overrides?: Partial<SafeTransaction>) => Promise<SafeTransaction>;
