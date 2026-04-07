import { describe, it, expect, beforeEach, jest } from '@jest/globals';

/**
 * Tests for LuxBridge — OP_NET (Bitcoin L1) bridge contract.
 *
 * These tests mock the OP_NET runtime (Blockchain, Calldata, StoredU256, etc.)
 * to validate LuxBridge business logic without requiring a full OP_NET node.
 */

// ================================================================
// Mock OP_NET runtime
// ================================================================

class MockAddress {
    private readonly _bytes: Uint8Array;

    constructor(hex: string = '00'.repeat(32)) {
        this._bytes = Buffer.from(hex, 'hex');
    }

    equals(other: MockAddress): boolean {
        return Buffer.from(this._bytes).equals(Buffer.from(other._bytes));
    }

    isZero(): boolean {
        return this._bytes.every((b) => b === 0);
    }

    toBytes(): Uint8Array {
        return this._bytes;
    }

    static zero(): MockAddress {
        return new MockAddress();
    }

    static fromHex(hex: string): MockAddress {
        return new MockAddress(hex);
    }
}

class MockU256 {
    private readonly _value: bigint;

    constructor(value: bigint = 0n) {
        this._value = value;
    }

    isZero(): boolean {
        return this._value === 0n;
    }

    static get Zero(): MockU256 {
        return new MockU256(0n);
    }

    static get One(): MockU256 {
        return new MockU256(1n);
    }

    static fromU64(v: number): MockU256 {
        return new MockU256(BigInt(v));
    }

    static fromString(s: string): MockU256 {
        return new MockU256(BigInt(s));
    }

    get value(): bigint {
        return this._value;
    }
}

class MockStoredU256 {
    value: MockU256;
    constructor(_ptr: number, initial: MockU256) {
        this.value = initial;
    }
}

class MockStoredU64 {
    value: number;
    constructor(_ptr: number, initial: number) {
        this.value = initial;
    }
}

class MockStoredBoolean {
    value: boolean;
    constructor(_ptr: number, initial: boolean) {
        this.value = initial;
    }
}

class MockAddressMemoryMap {
    private readonly _map = new Map<string, MockU256>();

    constructor(_ptr: number) {}

    get(key: MockAddress): MockU256 {
        return this._map.get(Buffer.from(key.toBytes()).toString('hex')) ?? MockU256.Zero;
    }

    set(key: MockAddress, value: MockU256): void {
        this._map.set(Buffer.from(key.toBytes()).toString('hex'), value);
    }
}

// Mock the Blockchain global
const mockSender = MockAddress.fromHex('aa'.repeat(32));
const mockBlockTimestamp = 1700000000;

const MockBlockchain = {
    tx: { sender: mockSender },
    block: { timestamp: mockBlockTimestamp },
    nextPointer: 0,
};

class MockRevert extends Error {
    constructor(message: string) {
        super(message);
        this.name = 'Revert';
    }
}

// ================================================================
// Simplified LuxBridge for testing
// ================================================================

class TestableLuxBridge {
    readonly mpcSigner1: MockStoredU256;
    readonly mpcSigner2: MockStoredU256;
    readonly mpcSigner3: MockStoredU256;
    readonly threshold: MockStoredU64;
    readonly feeBps: MockStoredU64;
    readonly paused: MockStoredBoolean;
    readonly outboundNonce: MockStoredU64;
    readonly chainId: MockStoredU64;
    readonly dailyMintLimit: MockStoredU256;
    readonly dailyMinted: MockStoredU256;
    readonly periodStart: MockStoredU64;
    readonly totalLocked: MockStoredU256;
    readonly totalBurned: MockStoredU256;
    readonly nonceMap: MockAddressMemoryMap;
    private _custodian: MockAddress;

    constructor() {
        this.mpcSigner1 = new MockStoredU256(0, MockU256.Zero);
        this.mpcSigner2 = new MockStoredU256(1, MockU256.Zero);
        this.mpcSigner3 = new MockStoredU256(2, MockU256.Zero);
        this.threshold = new MockStoredU64(3, 2);
        this.feeBps = new MockStoredU64(4, 30);
        this.paused = new MockStoredBoolean(5, false);
        this.outboundNonce = new MockStoredU64(6, 0);
        this.chainId = new MockStoredU64(7, 4294967299);
        this.dailyMintLimit = new MockStoredU256(8, MockU256.Zero);
        this.dailyMinted = new MockStoredU256(9, MockU256.Zero);
        this.periodStart = new MockStoredU64(10, 0);
        this.totalLocked = new MockStoredU256(11, MockU256.Zero);
        this.totalBurned = new MockStoredU256(12, MockU256.Zero);
        this.nonceMap = new MockAddressMemoryMap(13);
        this._custodian = MockAddress.zero();
    }

    setCustodian(addr: MockAddress): void {
        this._custodian = addr;
    }

    getCustodian(): MockAddress {
        return this._custodian;
    }

    requireNotPaused(): void {
        if (this.paused.value) throw new MockRevert('Bridge is paused');
    }

    onlyCustodian(sender: MockAddress): void {
        if (!sender.equals(this._custodian)) {
            throw new MockRevert('Not custodian');
        }
    }

    lockAndBridge(
        sender: MockAddress,
        amount: bigint,
        destChainId: number,
        recipient: bigint,
    ): { nonce: number; bridgeAmount: bigint; fee: bigint } {
        this.requireNotPaused();
        if (amount === 0n) throw new MockRevert('Amount is zero');

        const feeBps = BigInt(this.feeBps.value);
        const fee = (amount * feeBps) / 10000n;
        const bridgeAmount = amount - fee;

        this.totalLocked.value = new MockU256(this.totalLocked.value.value + bridgeAmount);

        const nonce = this.outboundNonce.value;
        this.outboundNonce.value = nonce + 1;

        return { nonce, bridgeAmount, fee };
    }

    mintBridged(
        sender: MockAddress,
        to: MockAddress,
        amount: bigint,
        sourceChainId: number,
        nonce: number,
    ): void {
        this.onlyCustodian(sender);
        this.requireNotPaused();
        if (to.equals(MockAddress.zero())) throw new MockRevert('Invalid recipient');
        if (amount === 0n) throw new MockRevert('Amount is zero');

        // Check nonce not processed (simplified)
        const nonceKey = MockAddress.fromHex(
            nonce.toString(16).padStart(16, '0') +
            sourceChainId.toString(16).padStart(16, '0') +
            '0'.repeat(32),
        );
        const val = this.nonceMap.get(nonceKey);
        if (!val.isZero()) throw new MockRevert('Nonce already processed');

        this.nonceMap.set(nonceKey, MockU256.One);
    }

    burnBridged(
        sender: MockAddress,
        amount: bigint,
        destChainId: number,
        recipient: bigint,
    ): { nonce: number } {
        this.requireNotPaused();
        if (amount === 0n) throw new MockRevert('Amount is zero');

        this.totalBurned.value = new MockU256(this.totalBurned.value.value + amount);

        const nonce = this.outboundNonce.value;
        this.outboundNonce.value = nonce + 1;

        return { nonce };
    }

    pause(sender: MockAddress): void {
        this.onlyCustodian(sender);
        this.paused.value = true;
    }

    unpause(sender: MockAddress): void {
        this.onlyCustodian(sender);
        this.paused.value = false;
    }

    updateFee(sender: MockAddress, fee: number): void {
        this.onlyCustodian(sender);
        if (fee > 500) throw new MockRevert('Fee exceeds 5% maximum');
        this.feeBps.value = fee;
    }

    updateSigners(
        sender: MockAddress,
        s1: MockU256,
        s2: MockU256,
        s3: MockU256,
        t: number,
    ): void {
        this.onlyCustodian(sender);
        if (t < 1 || t > 3) throw new MockRevert('Invalid threshold');
        this.mpcSigner1.value = s1;
        this.mpcSigner2.value = s2;
        this.mpcSigner3.value = s3;
        this.threshold.value = t;
    }

    setChainId(sender: MockAddress, newChainId: number): void {
        this.onlyCustodian(sender);
        if (newChainId === 0) throw new MockRevert('Invalid chain ID');
        this.chainId.value = newChainId;
    }
}

// ================================================================
// Tests
// ================================================================

describe('LuxBridge', () => {
    let bridge: TestableLuxBridge;
    let custodian: MockAddress;
    let user: MockAddress;

    beforeEach(() => {
        bridge = new TestableLuxBridge();
        custodian = MockAddress.fromHex('cc'.repeat(32));
        user = MockAddress.fromHex('dd'.repeat(32));
        bridge.setCustodian(custodian);
    });

    // ============================================================
    // Initial state
    // ============================================================

    describe('initial state', () => {
        it('starts unpaused', () => {
            expect(bridge.paused.value).toBe(false);
        });

        it('starts with zero total locked', () => {
            expect(bridge.totalLocked.value.isZero()).toBe(true);
        });

        it('starts with zero total burned', () => {
            expect(bridge.totalBurned.value.isZero()).toBe(true);
        });

        it('starts with nonce 0', () => {
            expect(bridge.outboundNonce.value).toBe(0);
        });

        it('starts with default fee of 30 bps', () => {
            expect(bridge.feeBps.value).toBe(30);
        });

        it('starts with default chain ID', () => {
            expect(bridge.chainId.value).toBe(4294967299);
        });

        it('starts with threshold of 2', () => {
            expect(bridge.threshold.value).toBe(2);
        });
    });

    // ============================================================
    // Pause / Unpause
    // ============================================================

    describe('pause / unpause', () => {
        it('custodian can pause', () => {
            bridge.pause(custodian);
            expect(bridge.paused.value).toBe(true);
        });

        it('custodian can unpause', () => {
            bridge.pause(custodian);
            bridge.unpause(custodian);
            expect(bridge.paused.value).toBe(false);
        });

        it('non-custodian cannot pause', () => {
            expect(() => bridge.pause(user)).toThrow('Not custodian');
        });

        it('non-custodian cannot unpause', () => {
            bridge.pause(custodian);
            expect(() => bridge.unpause(user)).toThrow('Not custodian');
        });
    });

    // ============================================================
    // Update Fee
    // ============================================================

    describe('updateFee', () => {
        it('custodian can set fee', () => {
            bridge.updateFee(custodian, 100);
            expect(bridge.feeBps.value).toBe(100);
        });

        it('accepts max fee of 500 bps', () => {
            bridge.updateFee(custodian, 500);
            expect(bridge.feeBps.value).toBe(500);
        });

        it('rejects fee above 500 bps', () => {
            expect(() => bridge.updateFee(custodian, 501)).toThrow('Fee exceeds 5% maximum');
        });

        it('non-custodian cannot set fee', () => {
            expect(() => bridge.updateFee(user, 100)).toThrow('Not custodian');
        });
    });

    // ============================================================
    // Update Signers
    // ============================================================

    describe('updateSigners', () => {
        it('custodian can update signers', () => {
            const s = new MockU256(42n);
            bridge.updateSigners(custodian, s, s, s, 2);
            expect(bridge.mpcSigner1.value.value).toBe(42n);
            expect(bridge.threshold.value).toBe(2);
        });

        it('rejects threshold 0', () => {
            const s = new MockU256(42n);
            expect(() => bridge.updateSigners(custodian, s, s, s, 0)).toThrow('Invalid threshold');
        });

        it('rejects threshold above 3', () => {
            const s = new MockU256(42n);
            expect(() => bridge.updateSigners(custodian, s, s, s, 4)).toThrow('Invalid threshold');
        });

        it('non-custodian cannot update signers', () => {
            const s = new MockU256(42n);
            expect(() => bridge.updateSigners(user, s, s, s, 2)).toThrow('Not custodian');
        });
    });

    // ============================================================
    // Set Chain ID
    // ============================================================

    describe('setChainId', () => {
        it('custodian can set chain ID', () => {
            bridge.setChainId(custodian, 96369);
            expect(bridge.chainId.value).toBe(96369);
        });

        it('rejects zero chain ID', () => {
            expect(() => bridge.setChainId(custodian, 0)).toThrow('Invalid chain ID');
        });

        it('non-custodian cannot set chain ID', () => {
            expect(() => bridge.setChainId(user, 96369)).toThrow('Not custodian');
        });
    });

    // ============================================================
    // Lock and Bridge
    // ============================================================

    describe('lockAndBridge', () => {
        it('returns nonce starting at 0', () => {
            const result = bridge.lockAndBridge(user, 1000n, 96369, 0xCAFEn);
            expect(result.nonce).toBe(0);
        });

        it('increments nonce', () => {
            const r1 = bridge.lockAndBridge(user, 1000n, 96369, 0xCAFEn);
            const r2 = bridge.lockAndBridge(user, 2000n, 96369, 0xCAFEn);
            expect(r1.nonce).toBe(0);
            expect(r2.nonce).toBe(1);
        });

        it('updates total locked with zero fee', () => {
            bridge.updateFee(custodian, 0);
            bridge.lockAndBridge(user, 5000n, 96369, 0xCAFEn);
            expect(bridge.totalLocked.value.value).toBe(5000n);
        });

        it('deducts fee from locked amount', () => {
            bridge.updateFee(custodian, 100); // 1%
            const result = bridge.lockAndBridge(user, 10000n, 96369, 0xCAFEn);
            // fee = 10000 * 100 / 10000 = 100
            expect(result.fee).toBe(100n);
            expect(result.bridgeAmount).toBe(9900n);
            expect(bridge.totalLocked.value.value).toBe(9900n);
        });

        it('rejects zero amount', () => {
            expect(() => bridge.lockAndBridge(user, 0n, 96369, 0xCAFEn)).toThrow('Amount is zero');
        });

        it('rejects when paused', () => {
            bridge.pause(custodian);
            expect(() => bridge.lockAndBridge(user, 1000n, 96369, 0xCAFEn)).toThrow(
                'Bridge is paused',
            );
        });
    });

    // ============================================================
    // Burn Bridged
    // ============================================================

    describe('burnBridged', () => {
        it('returns nonce starting at 0', () => {
            const result = bridge.burnBridged(user, 500n, 96369, 0xBEEFn);
            expect(result.nonce).toBe(0);
        });

        it('updates total burned', () => {
            bridge.burnBridged(user, 500n, 96369, 0xBEEFn);
            expect(bridge.totalBurned.value.value).toBe(500n);
        });

        it('accumulates total burned', () => {
            bridge.burnBridged(user, 500n, 96369, 0xBEEFn);
            bridge.burnBridged(user, 300n, 96369, 0xBEEFn);
            expect(bridge.totalBurned.value.value).toBe(800n);
        });

        it('rejects zero amount', () => {
            expect(() => bridge.burnBridged(user, 0n, 96369, 0xBEEFn)).toThrow('Amount is zero');
        });

        it('rejects when paused', () => {
            bridge.pause(custodian);
            expect(() => bridge.burnBridged(user, 500n, 96369, 0xBEEFn)).toThrow(
                'Bridge is paused',
            );
        });
    });

    // ============================================================
    // Mint Bridged
    // ============================================================

    describe('mintBridged', () => {
        it('custodian can mint', () => {
            const recipient = MockAddress.fromHex('ee'.repeat(32));
            expect(() => bridge.mintBridged(custodian, recipient, 1000n, 1, 1)).not.toThrow();
        });

        it('non-custodian cannot mint', () => {
            const recipient = MockAddress.fromHex('ee'.repeat(32));
            expect(() => bridge.mintBridged(user, recipient, 1000n, 1, 1)).toThrow(
                'Not custodian',
            );
        });

        it('rejects zero address recipient', () => {
            expect(() =>
                bridge.mintBridged(custodian, MockAddress.zero(), 1000n, 1, 1),
            ).toThrow('Invalid recipient');
        });

        it('rejects zero amount', () => {
            const recipient = MockAddress.fromHex('ee'.repeat(32));
            expect(() => bridge.mintBridged(custodian, recipient, 0n, 1, 1)).toThrow(
                'Amount is zero',
            );
        });

        it('rejects when paused', () => {
            bridge.pause(custodian);
            const recipient = MockAddress.fromHex('ee'.repeat(32));
            expect(() => bridge.mintBridged(custodian, recipient, 1000n, 1, 1)).toThrow(
                'Bridge is paused',
            );
        });

        it('rejects duplicate nonce', () => {
            const recipient = MockAddress.fromHex('ee'.repeat(32));
            bridge.mintBridged(custodian, recipient, 1000n, 1, 1);
            expect(() => bridge.mintBridged(custodian, recipient, 1000n, 1, 1)).toThrow(
                'Nonce already processed',
            );
        });

        it('allows same nonce from different source chains', () => {
            const recipient = MockAddress.fromHex('ee'.repeat(32));
            bridge.mintBridged(custodian, recipient, 1000n, 1, 1); // chain 1, nonce 1
            expect(() =>
                bridge.mintBridged(custodian, recipient, 1000n, 2, 1),
            ).not.toThrow(); // chain 2, nonce 1
        });
    });

    // ============================================================
    // Shared nonce counter
    // ============================================================

    describe('shared nonce counter', () => {
        it('lock and burn share the same counter', () => {
            const n1 = bridge.lockAndBridge(user, 1000n, 96369, 0xCAFEn);
            const n2 = bridge.burnBridged(user, 500n, 96369, 0xBEEFn);
            const n3 = bridge.lockAndBridge(user, 2000n, 96369, 0xCAFEn);

            expect(n1.nonce).toBe(0);
            expect(n2.nonce).toBe(1);
            expect(n3.nonce).toBe(2);
        });
    });

    // ============================================================
    // Fee arithmetic
    // ============================================================

    describe('fee arithmetic', () => {
        it('zero fee means full amount locked', () => {
            bridge.updateFee(custodian, 0);
            const result = bridge.lockAndBridge(user, 10000n, 96369, 0xCAFEn);
            expect(result.fee).toBe(0n);
            expect(result.bridgeAmount).toBe(10000n);
        });

        it('max fee of 500 bps takes 5%', () => {
            bridge.updateFee(custodian, 500);
            const result = bridge.lockAndBridge(user, 10000n, 96369, 0xCAFEn);
            expect(result.fee).toBe(500n);
            expect(result.bridgeAmount).toBe(9500n);
        });

        it('fee on small amount rounds down', () => {
            bridge.updateFee(custodian, 1); // 0.01%
            const result = bridge.lockAndBridge(user, 99n, 96369, 0xCAFEn);
            // 99 * 1 / 10000 = 0 (integer division)
            expect(result.fee).toBe(0n);
            expect(result.bridgeAmount).toBe(99n);
        });
    });
});
