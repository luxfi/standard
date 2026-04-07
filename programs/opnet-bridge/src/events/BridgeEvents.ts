import { Address, NetEvent } from '@btc-vision/btc-runtime/runtime';
import { u256 } from '@btc-vision/as-bignum/assembly';

/**
 * All events encode fields needed for Teleporter.sol proof reconstruction.
 * MPC watchers use these fields to build:
 *   keccak256(abi.encodePacked("DEPOSIT", srcChainId, depositNonce, recipient, amount))
 *
 * u64 fields (chainId, nonce) are wrapped as u256 so they appear in the event data array.
 */

export class LockEvent extends NetEvent {
    constructor(
        public readonly sender: Address,
        public readonly srcChainId: u64,
        public readonly destChainId: u64,
        public readonly nonce: u64,
        public readonly recipient: u256, // 32-byte dest address (EVM, Solana, TON, etc.)
        public readonly amount: u256,
    ) {
        super('Lock', [
            sender,
            u256.fromU64(srcChainId),
            u256.fromU64(destChainId),
            u256.fromU64(nonce),
            recipient,
            amount,
        ]);
    }
}

export class MintEvent extends NetEvent {
    constructor(
        public readonly recipient: Address,
        public readonly sourceChainId: u64,
        public readonly nonce: u64,
        public readonly amount: u256,
    ) {
        super('Minted', [
            recipient,
            u256.fromU64(sourceChainId),
            u256.fromU64(nonce),
            amount,
        ]);
    }
}

export class BurnEvent extends NetEvent {
    constructor(
        public readonly sender: Address,
        public readonly srcChainId: u64,
        public readonly destChainId: u64,
        public readonly nonce: u64,
        public readonly recipient: u256,
        public readonly amount: u256,
    ) {
        super('Burned', [
            sender,
            u256.fromU64(srcChainId),
            u256.fromU64(destChainId),
            u256.fromU64(nonce),
            recipient,
            amount,
        ]);
    }
}

export class ReleaseEvent extends NetEvent {
    constructor(
        public readonly recipient: Address,
        public readonly sourceChainId: u64,
        public readonly nonce: u64,
        public readonly amount: u256,
    ) {
        super('Released', [
            recipient,
            u256.fromU64(sourceChainId),
            u256.fromU64(nonce),
            amount,
        ]);
    }
}
