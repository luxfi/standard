import { Signer, BigNumberish, BaseContract } from "ethers";
import { Safe } from "../../typechain-types";
export declare const EIP_DOMAIN: {
    EIP712Domain: {
        type: string;
        name: string;
    }[];
};
export declare const EIP712_SAFE_TX_TYPE: {
    SafeTx: {
        type: string;
        name: string;
    }[];
};
export declare const EIP712_SAFE_MESSAGE_TYPE: {
    SafeMessage: {
        type: string;
        name: string;
    }[];
};
export interface MetaTransaction {
    to: string;
    value: BigNumberish;
    data: string;
    operation: number;
}
export interface SafeTransaction extends MetaTransaction {
    safeTxGas: BigNumberish;
    baseGas: BigNumberish;
    gasPrice: BigNumberish;
    gasToken: string;
    refundReceiver: string;
    nonce: BigNumberish;
}
export interface SafeSignature {
    signer: string;
    data: string;
    dynamic?: true;
}
export declare const calculateSafeDomainSeparator: (safeAddress: string, chainId: BigNumberish) => string;
export declare const preimageSafeTransactionHash: (safeAddress: string, safeTx: SafeTransaction, chainId: BigNumberish) => string;
export declare const calculateSafeTransactionHash: (safeAddress: string, safeTx: SafeTransaction, chainId: BigNumberish) => string;
export declare const preimageSafeMessageHash: (safeAddress: string, message: string, chainId: BigNumberish) => string;
export declare const calculateSafeMessageHash: (safeAddress: string, message: string, chainId: BigNumberish) => string;
export declare const safeApproveHash: (signer: Signer, safe: Safe, safeTx: SafeTransaction, skipOnChainApproval?: boolean) => Promise<SafeSignature>;
export declare const safeSignTypedData: (signer: Signer, safeAddress: string, safeTx: SafeTransaction, chainId?: BigNumberish) => Promise<SafeSignature>;
export declare const signHash: (signer: Signer, hash: string) => Promise<SafeSignature>;
export declare const safeSignMessage: (signer: Signer, safeAddress: string, safeTx: SafeTransaction, chainId?: BigNumberish) => Promise<SafeSignature>;
export declare const buildContractSignature: (signerAddress: string, signature: string) => SafeSignature;
export declare const buildSignatureBytes: (signatures: SafeSignature[]) => string;
export declare const logGas: (message: string, tx: Promise<any>, skip?: boolean) => Promise<any>;
export declare const executeTx: (safe: Safe, safeTx: SafeTransaction, signatures: SafeSignature[], overrides?: any) => Promise<any>;
export declare const buildContractCall: (contract: BaseContract, method: string, params: any[], nonce: BigNumberish, delegateCall?: boolean, overrides?: Partial<SafeTransaction>) => Promise<SafeTransaction>;
export declare const executeTxWithSigners: (safe: Safe, tx: SafeTransaction, signers: Signer[], overrides?: any) => Promise<any>;
export declare const executeContractCallWithSigners: (safe: Safe, contract: BaseContract, method: string, params: any[], signers: Signer[], delegateCall?: boolean, overrides?: Partial<SafeTransaction>) => Promise<any>;
export declare const buildSafeTransaction: (template: {
    to: string;
    value?: BigNumberish;
    data?: string;
    operation?: number;
    safeTxGas?: BigNumberish;
    baseGas?: BigNumberish;
    gasPrice?: BigNumberish;
    gasToken?: string;
    refundReceiver?: string;
    nonce: BigNumberish;
}) => SafeTransaction;
