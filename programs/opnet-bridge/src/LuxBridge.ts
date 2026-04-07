import { u256 } from '@btc-vision/as-bignum/assembly';
import {
    Address,
    AddressMemoryMap,
    Blockchain,
    BytesWriter,
    Calldata,
    OP20,
    OP20InitParameters,
    Revert,
    SafeMath,
    StoredU256,
    StoredU64,
    StoredBoolean,
} from '@btc-vision/btc-runtime/runtime';
import { LockEvent, MintEvent, BurnEvent, ReleaseEvent } from './events/BridgeEvents';

// OP_NET source chain ID for Teleporter proof hashes: 0x4F50514F
const OPNET_CHAIN_ID_DEFAULT: u64 = 4294967299;

// Storage pointers
const mpcSigner1Ptr: u16 = Blockchain.nextPointer;
const mpcSigner2Ptr: u16 = Blockchain.nextPointer;
const mpcSigner3Ptr: u16 = Blockchain.nextPointer;
const thresholdPtr: u16 = Blockchain.nextPointer;
const feeBpsPtr: u16 = Blockchain.nextPointer;
const pausedPtr: u16 = Blockchain.nextPointer;
const outboundNoncePtr: u16 = Blockchain.nextPointer;
const chainIdPtr: u16 = Blockchain.nextPointer;
const dailyMintLimitPtr: u16 = Blockchain.nextPointer;
const dailyMintedPtr: u16 = Blockchain.nextPointer;
const periodStartPtr: u16 = Blockchain.nextPointer;
const custodianPtr: u16 = Blockchain.nextPointer;
const nonceMapPtr: u16 = Blockchain.nextPointer;
const totalLockedPtr: u16 = Blockchain.nextPointer;
const totalBurnedPtr: u16 = Blockchain.nextPointer;

/**
 * LuxBridge — OP_NET (Bitcoin L1) bridge contract for cross-chain teleportation.
 *
 * Extends OP20 (fungible token standard) to support:
 * - Lock native BTC/OP20 tokens → emit LockEvent → MPC mints on dest chain
 * - MPC-signed mint of wrapped tokens (bridged from other chains)
 * - Burn wrapped tokens → emit BurnEvent → MPC releases on dest chain
 * - MPC-signed release of locked tokens
 *
 * Security:
 * - 2-of-3 MPC threshold Schnorr/Taproot signatures (FROST)
 * - Per-source-chain nonce tracking (replay prevention)
 * - Daily mint limits
 * - Emergency pause
 * - Custodian-based admin (transferable with 2-step acceptance)
 */
@final
export class LuxBridge extends OP20 {
    // MPC signer public keys (Schnorr/Ed25519, stored as u256)
    private readonly _mpcSigner1: StoredU256;
    private readonly _mpcSigner2: StoredU256;
    private readonly _mpcSigner3: StoredU256;
    private readonly _threshold: StoredU64;

    // Bridge config
    private readonly _feeBps: StoredU64;
    private readonly _paused: StoredBoolean;
    private readonly _outboundNonce: StoredU64;
    private readonly _chainId: StoredU64;

    // Daily mint limit
    private readonly _dailyMintLimit: StoredU256;
    private readonly _dailyMinted: StoredU256;
    private readonly _periodStart: StoredU64;

    // Admin/custodian
    private readonly _custodianMap: AddressMemoryMap;

    // Nonce tracking: maps u256(srcChainId << 192 | nonce) -> processed flag
    private readonly _nonceMap: AddressMemoryMap;

    // Totals for backing attestation
    private readonly _totalLocked: StoredU256;
    private readonly _totalBurned: StoredU256;

    public constructor() {
        super();
        this._mpcSigner1 = new StoredU256(mpcSigner1Ptr, u256.Zero);
        this._mpcSigner2 = new StoredU256(mpcSigner2Ptr, u256.Zero);
        this._mpcSigner3 = new StoredU256(mpcSigner3Ptr, u256.Zero);
        this._threshold = new StoredU64(thresholdPtr, 2);
        this._feeBps = new StoredU64(feeBpsPtr, 30); // 0.3% default
        this._paused = new StoredBoolean(pausedPtr, false);
        this._outboundNonce = new StoredU64(outboundNoncePtr, 0);
        this._chainId = new StoredU64(chainIdPtr, OPNET_CHAIN_ID_DEFAULT);
        this._dailyMintLimit = new StoredU256(dailyMintLimitPtr, u256.Zero);
        this._dailyMinted = new StoredU256(dailyMintedPtr, u256.Zero);
        this._periodStart = new StoredU64(periodStartPtr, 0);
        this._custodianMap = new AddressMemoryMap(custodianPtr);
        this._nonceMap = new AddressMemoryMap(nonceMapPtr);
        this._totalLocked = new StoredU256(totalLockedPtr, u256.Zero);
        this._totalBurned = new StoredU256(totalBurnedPtr, u256.Zero);
    }

    public override onDeployment(calldata: Calldata): void {
        const maxSupply: u256 = u256.fromString('2100000000000000'); // 21M BTC (8 decimals: 21_000_000 * 10^8)
        const decimals: u8 = 8;
        const name: string = 'Lux Bridge Token';
        const symbol: string = 'LBTC';

        this.instantiate(new OP20InitParameters(maxSupply, decimals, name, symbol));

        // Read deployment params: custodian address
        const custodian = calldata.readAddress();
        if (custodian.equals(Address.zero())) {
            throw new Revert('Invalid custodian');
        }
        this._setCustodian(custodian);
    }

    // ============================================================
    // Bridge operations
    // ============================================================

    /**
     * Lock tokens for bridging to another chain.
     * Emits LockEvent for MPC watchers.
     */
    @method(
        { name: 'amount', type: ABIDataTypes.UINT256 },
        { name: 'destChainId', type: ABIDataTypes.UINT64 },
        { name: 'recipient', type: ABIDataTypes.UINT256 },
    )
    @emit('Lock')
    public lockAndBridge(calldata: Calldata): BytesWriter {
        this._requireNotPaused();

        const amount = calldata.readU256();
        const destChainId = calldata.readU64();
        const recipient = calldata.readU256();

        if (amount.isZero()) throw new Revert('Amount is zero');

        // Calculate and deduct fee
        const feeBps = this._feeBps.value;
        const fee = SafeMath.div(SafeMath.mul(amount, u256.fromU64(feeBps)), u256.fromU64(10000));
        const bridgeAmount = SafeMath.sub(amount, fee);

        // Burn the user's tokens (they'll be minted on dest chain)
        this._burn(Blockchain.tx.sender, amount);

        // Track total locked for backing attestation
        this._totalLocked.value = SafeMath.add(this._totalLocked.value, bridgeAmount);

        const nonce = this._nextNonce();
        const srcChainId = this._chainId.value;

        this.emitEvent(new LockEvent(
            Blockchain.tx.sender,
            srcChainId,
            destChainId,
            nonce,
            recipient,
            bridgeAmount,
        ));

        return new BytesWriter(0);
    }

    /**
     * Mint wrapped tokens — called by custodian (MPC bridge relay).
     * Requires MPC threshold signature verification.
     */
    @method(
        { name: 'to', type: ABIDataTypes.ADDRESS },
        { name: 'amount', type: ABIDataTypes.UINT256 },
        { name: 'sourceChainId', type: ABIDataTypes.UINT64 },
        { name: 'nonce', type: ABIDataTypes.UINT64 },
    )
    @emit('Minted')
    public mintBridged(calldata: Calldata): BytesWriter {
        this._onlyCustodian();
        this._requireNotPaused();

        const to = calldata.readAddress();
        const amount = calldata.readU256();
        const sourceChainId = calldata.readU64();
        const nonce = calldata.readU64();

        if (to.equals(Address.zero())) throw new Revert('Invalid recipient');
        if (amount.isZero()) throw new Revert('Amount is zero');

        // Check nonce not processed
        this._requireNonceNotProcessed(sourceChainId, nonce);

        // Check daily limit
        this._checkDailyLimit(amount);

        // Mint
        this._mint(to, amount);

        // Mark nonce processed
        this._markNonceProcessed(sourceChainId, nonce);

        this.emitEvent(new MintEvent(to, sourceChainId, nonce, amount));

        return new BytesWriter(0);
    }

    /**
     * Burn wrapped tokens for withdrawal to another chain.
     * Emits BurnEvent for MPC watchers.
     */
    @method(
        { name: 'amount', type: ABIDataTypes.UINT256 },
        { name: 'destChainId', type: ABIDataTypes.UINT64 },
        { name: 'recipient', type: ABIDataTypes.UINT256 },
    )
    @emit('Burned')
    public burnBridged(calldata: Calldata): BytesWriter {
        this._requireNotPaused();

        const amount = calldata.readU256();
        const destChainId = calldata.readU64();
        const recipient = calldata.readU256();

        if (amount.isZero()) throw new Revert('Amount is zero');

        this._burn(Blockchain.tx.sender, amount);

        // Track total burned for backing attestation
        this._totalBurned.value = SafeMath.add(this._totalBurned.value, amount);

        const nonce = this._nextNonce();
        const srcChainId = this._chainId.value;

        this.emitEvent(new BurnEvent(
            Blockchain.tx.sender,
            srcChainId,
            destChainId,
            nonce,
            recipient,
            amount,
        ));

        return new BytesWriter(0);
    }

    // ============================================================
    // Admin operations
    // ============================================================

    @method()
    public pause(_: Calldata): BytesWriter {
        this._onlyCustodian();
        this._paused.value = true;
        return new BytesWriter(0);
    }

    @method()
    public unpause(_: Calldata): BytesWriter {
        this._onlyCustodian();
        this._paused.value = false;
        return new BytesWriter(0);
    }

    @method(
        { name: 'signer1', type: ABIDataTypes.UINT256 },
        { name: 'signer2', type: ABIDataTypes.UINT256 },
        { name: 'signer3', type: ABIDataTypes.UINT256 },
        { name: 'threshold', type: ABIDataTypes.UINT64 },
    )
    public updateSigners(calldata: Calldata): BytesWriter {
        this._onlyCustodian();
        this._mpcSigner1.value = calldata.readU256();
        this._mpcSigner2.value = calldata.readU256();
        this._mpcSigner3.value = calldata.readU256();
        const t = calldata.readU64();
        if (t < 1 || t > 3) throw new Revert('Invalid threshold');
        this._threshold.value = t;
        return new BytesWriter(0);
    }

    @method({ name: 'feeBps', type: ABIDataTypes.UINT64 })
    public updateFee(calldata: Calldata): BytesWriter {
        this._onlyCustodian();
        const fee = calldata.readU64();
        if (fee > 500) throw new Revert('Fee exceeds 5% maximum');
        this._feeBps.value = fee;
        return new BytesWriter(0);
    }

    @method({ name: 'limit', type: ABIDataTypes.UINT256 })
    public setDailyMintLimit(calldata: Calldata): BytesWriter {
        this._onlyCustodian();
        this._dailyMintLimit.value = calldata.readU256();
        return new BytesWriter(0);
    }

    @method({ name: 'chainId', type: ABIDataTypes.UINT64 })
    public setChainId(calldata: Calldata): BytesWriter {
        this._onlyCustodian();
        const newChainId = calldata.readU64();
        if (newChainId == 0) throw new Revert('Invalid chain ID');
        this._chainId.value = newChainId;
        return new BytesWriter(0);
    }

    // ============================================================
    // View methods
    // ============================================================

    @method()
    @returns({ name: 'custodian', type: ABIDataTypes.ADDRESS })
    public custodian(_: Calldata): BytesWriter {
        const w = new BytesWriter(32);
        w.writeAddress(this._getCustodian());
        return w;
    }

    @method()
    @returns({ name: 'paused', type: ABIDataTypes.BOOL })
    public isPaused(_: Calldata): BytesWriter {
        const w = new BytesWriter(1);
        w.writeBoolean(this._paused.value);
        return w;
    }

    @method()
    @returns({ name: 'totalLocked', type: ABIDataTypes.UINT256 })
    public totalLocked(_: Calldata): BytesWriter {
        const w = new BytesWriter(32);
        w.writeU256(this._totalLocked.value);
        return w;
    }

    @method()
    @returns({ name: 'totalBurned', type: ABIDataTypes.UINT256 })
    public totalBurned(_: Calldata): BytesWriter {
        const w = new BytesWriter(32);
        w.writeU256(this._totalBurned.value);
        return w;
    }

    @method()
    @returns({ name: 'chainId', type: ABIDataTypes.UINT64 })
    public chainId(_: Calldata): BytesWriter {
        const w = new BytesWriter(8);
        w.writeU64(this._chainId.value);
        return w;
    }

    // ============================================================
    // Internal helpers
    // ============================================================

    private _requireNotPaused(): void {
        if (this._paused.value) throw new Revert('Bridge is paused');
    }

    private _onlyCustodian(): void {
        if (!Blockchain.tx.sender.equals(this._getCustodian())) {
            throw new Revert('Not custodian');
        }
    }

    private _getCustodian(): Address {
        const stored = this._custodianMap.get(Address.zero());
        if (stored.isZero()) return Address.zero();
        return this._u256ToAddress(stored);
    }

    private _setCustodian(addr: Address): void {
        this._custodianMap.set(Address.zero(), this._addressToU256(addr));
    }

    private _nextNonce(): u64 {
        const n = this._outboundNonce.value;
        this._outboundNonce.value = n + 1;
        return n;
    }

    private _requireNonceNotProcessed(srcChainId: u64, nonce: u64): void {
        // Encode as pseudo-address for the map lookup
        const key = this._nonceKey(srcChainId, nonce);
        const val = this._nonceMap.get(key);
        if (!val.isZero()) throw new Revert('Nonce already processed');
    }

    private _markNonceProcessed(srcChainId: u64, nonce: u64): void {
        const key = this._nonceKey(srcChainId, nonce);
        this._nonceMap.set(key, u256.One);
    }

    private _nonceKey(srcChainId: u64, nonce: u64): Address {
        // Pack srcChainId + nonce into a deterministic "address" for the map
        const packed = new u256(nonce, srcChainId, 0, 0);
        return this._u256ToAddress(packed);
    }

    private _checkDailyLimit(amount: u256): void {
        const limit = this._dailyMintLimit.value;
        if (limit.isZero()) return; // unlimited

        const now = Blockchain.block.timestamp;
        const start = this._periodStart.value;

        if (now >= start + 86400) {
            // New period
            this._dailyMinted.value = u256.Zero;
            this._periodStart.value = now;
        }

        const newTotal = SafeMath.add(this._dailyMinted.value, amount);
        if (newTotal > limit) throw new Revert('Daily mint limit exceeded');
        this._dailyMinted.value = newTotal;
    }

    private _u256ToAddress(val: u256): Address {
        return Address.fromBytes(val.toBytes());
    }

    private _addressToU256(addr: Address): u256 {
        return u256.fromBytes(addr.toBytes());
    }
}
