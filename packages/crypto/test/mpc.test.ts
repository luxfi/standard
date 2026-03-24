import * as crypto from 'node:crypto';
import { MpcKekProvider, shamirSplit, shamirRecombine, FieldEncryptor, InMemoryDekStore } from '../src';
import type { MpcShard, MpcShardStore } from '../src';

class InMemoryShardStore implements MpcShardStore {
  private shards = new Map<string, MpcShard[]>();

  async setShard(customerId: string, shard: MpcShard): Promise<void> {
    const existing = this.shards.get(customerId) ?? [];
    existing.push(shard);
    this.shards.set(customerId, existing);
  }

  async getShards(customerId: string): Promise<MpcShard[]> {
    return this.shards.get(customerId) ?? [];
  }

  async deleteShards(customerId: string): Promise<void> {
    this.shards.delete(customerId);
  }
}

describe('Shamir Secret Sharing', () => {
  it('splits and recombines a 32-byte secret (2-of-3)', () => {
    const secret = crypto.randomBytes(32);
    const shards = shamirSplit(secret, 3, 2);
    expect(shards).toHaveLength(3);

    // Any 2 shards can reconstruct
    const reconstructed = shamirRecombine([shards[0], shards[1]]);
    expect(reconstructed.equals(secret)).toBe(true);

    const reconstructed2 = shamirRecombine([shards[1], shards[2]]);
    expect(reconstructed2.equals(secret)).toBe(true);

    const reconstructed3 = shamirRecombine([shards[0], shards[2]]);
    expect(reconstructed3.equals(secret)).toBe(true);
  });

  it('splits and recombines (3-of-5)', () => {
    const secret = crypto.randomBytes(32);
    const shards = shamirSplit(secret, 5, 3);
    expect(shards).toHaveLength(5);

    const reconstructed = shamirRecombine([shards[0], shards[2], shards[4]]);
    expect(reconstructed.equals(secret)).toBe(true);
  });

  it('fails with fewer than threshold shards', () => {
    const secret = crypto.randomBytes(32);
    const shards = shamirSplit(secret, 3, 2);

    // 1 shard is not enough for k=2
    const wrong = shamirRecombine([shards[0]]);
    // With only 1 share, interpolation gives wrong result (not an error, just wrong data)
    expect(wrong.equals(secret)).toBe(false);
  });

  it('each shard is different', () => {
    const secret = crypto.randomBytes(32);
    const shards = shamirSplit(secret, 3, 2);
    expect(shards[0].data.equals(shards[1].data)).toBe(false);
    expect(shards[1].data.equals(shards[2].data)).toBe(false);
  });
});

describe('MpcKekProvider', () => {
  it('wraps and unwraps a DEK via 2-of-3 threshold', async () => {
    const shardStore = new InMemoryShardStore();
    const mpc = new MpcKekProvider({
      totalShards: 3,
      threshold: 2,
      shardStore,
    });

    const plainDek = crypto.randomBytes(32);
    const wrapped = await mpc.wrap(plainDek);
    expect(wrapped.length).toBeGreaterThan(plainDek.length);

    const unwrapped = await mpc.unwrap(wrapped);
    expect(unwrapped.equals(plainDek)).toBe(true);
  });

  it('works with 3-of-5 threshold', async () => {
    const shardStore = new InMemoryShardStore();
    const mpc = new MpcKekProvider({
      totalShards: 5,
      threshold: 3,
      shardStore,
    });

    const plainDek = crypto.randomBytes(32);
    const wrapped = await mpc.wrap(plainDek);
    const unwrapped = await mpc.unwrap(wrapped);
    expect(unwrapped.equals(plainDek)).toBe(true);
  });

  it('rejects threshold < 2', () => {
    expect(() => new MpcKekProvider({
      totalShards: 3,
      threshold: 1,
      shardStore: new InMemoryShardStore(),
    })).toThrow('threshold must be >= 2');
  });

  it('rejects threshold > totalShards', () => {
    expect(() => new MpcKekProvider({
      totalShards: 2,
      threshold: 3,
      shardStore: new InMemoryShardStore(),
    })).toThrow('threshold > totalShards');
  });
});

describe('FieldEncryptor with MPC provider', () => {
  it('encrypts and decrypts PII using MPC-wrapped DEKs', async () => {
    const shardStore = new InMemoryShardStore();
    const mpcProvider = new MpcKekProvider({
      totalShards: 3,
      threshold: 2,
      shardStore,
    });

    const encryptor = new FieldEncryptor({
      kekProvider: mpcProvider,
      dekStore: new InMemoryDekStore(),
    });

    expect(encryptor.providerName).toBe('mpc-shamir');

    const ct = await encryptor.encrypt('customer-mpc', '123-45-6789');
    expect(ct.startsWith('enc:v1:')).toBe(true);

    const pt = await encryptor.decrypt('customer-mpc', ct);
    expect(pt).toBe('123-45-6789');
  });

  it('different customers get different DEKs with MPC', async () => {
    const shardStore = new InMemoryShardStore();
    const mpcProvider = new MpcKekProvider({
      totalShards: 3,
      threshold: 2,
      shardStore,
    });

    const dekStore = new InMemoryDekStore();
    const encryptor = new FieldEncryptor({
      kekProvider: mpcProvider,
      dekStore,
    });

    await encryptor.encrypt('cust-A', 'data');
    await encryptor.encrypt('cust-B', 'data');

    const dekA = await dekStore.get('cust-A');
    const dekB = await dekStore.get('cust-B');
    expect(dekA!.equals(dekB!)).toBe(false);
  });

  it('cannot cross-decrypt between customers with MPC', async () => {
    const shardStore = new InMemoryShardStore();
    const encryptor = new FieldEncryptor({
      kekProvider: new MpcKekProvider({ totalShards: 3, threshold: 2, shardStore }),
      dekStore: new InMemoryDekStore(),
    });

    const ct = await encryptor.encrypt('cust-X', 'secret');
    await expect(encryptor.decrypt('cust-Y', ct)).rejects.toThrow();
  });
});
