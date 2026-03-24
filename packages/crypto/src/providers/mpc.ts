import * as crypto from 'node:crypto';
import type { KekProvider, MpcProviderOptions, MpcShard, MpcShardStore } from '../types';

/**
 * MPC KEK provider — splits DEK wrapping key across N shards using
 * Shamir's Secret Sharing over GF(256). Requires K-of-N shards to
 * reconstruct and unwrap.
 *
 * Use cases:
 *   - Customer wallet keys: shard1 on device, shard2 in KMS, shard3 with custodian
 *   - PII encryption: split DEK across compliance officer + system + HSM
 *   - High-value accounts: 3-of-5 threshold with geographic distribution
 *
 * The wrapped DEK format includes a header with threshold params so
 * the unwrap side knows the reconstruction requirements.
 *
 * Wire format: [version(1) | threshold(1) | totalShards(1) | wrappedDek...]
 *   where wrappedDek is AES-256-GCM encrypted with the reconstructed secret
 */
export class MpcKekProvider implements KekProvider {
  readonly name = 'mpc-shamir';
  private readonly threshold: number;
  private readonly totalShards: number;
  private readonly shardStore: MpcShardStore;

  constructor(options: MpcProviderOptions) {
    if (options.threshold < 2) throw new Error('MPC threshold must be >= 2');
    if (options.threshold > options.totalShards) throw new Error('threshold > totalShards');
    if (options.totalShards > 255) throw new Error('totalShards max 255');

    this.threshold = options.threshold;
    this.totalShards = options.totalShards;
    this.shardStore = options.shardStore;
  }

  /**
   * Wrap a DEK:
   *   1. Generate a random 32-byte wrapping key
   *   2. Split wrapping key into N Shamir shards
   *   3. Store shards via shardStore (each goes to a different custodian)
   *   4. Encrypt DEK with wrapping key (AES-256-GCM)
   *   5. Return header + encrypted DEK
   */
  async wrap(plaintext: Buffer): Promise<Buffer> {
    // Generate wrapping key and split
    const wrappingKey = crypto.randomBytes(32);
    const shards = shamirSplit(wrappingKey, this.totalShards, this.threshold);

    // Store shards (caller's shardStore puts them in different locations)
    const storeId = crypto.randomBytes(16).toString('hex');
    for (const shard of shards) {
      await this.shardStore.setShard(storeId, shard);
    }

    // Encrypt DEK with wrapping key
    const iv = crypto.randomBytes(12);
    const cipher = crypto.createCipheriv('aes-256-gcm', wrappingKey, iv, { authTagLength: 16 });
    const encrypted = Buffer.concat([cipher.update(plaintext), cipher.final()]);
    const authTag = cipher.getAuthTag();

    // Header: version(1) + threshold(1) + totalShards(1) + storeIdLen(1) + storeId(32)
    const storeIdBuf = Buffer.from(storeId, 'hex');
    const header = Buffer.from([0x01, this.threshold, this.totalShards, storeIdBuf.length]);

    return Buffer.concat([header, storeIdBuf, iv, encrypted, authTag]);

  }

  /**
   * Unwrap a DEK:
   *   1. Parse header to get threshold, storeId
   *   2. Retrieve >= threshold shards from shardStore
   *   3. Reconstruct wrapping key via Shamir interpolation
   *   4. Decrypt DEK
   */
  async unwrap(ciphertext: Buffer): Promise<Buffer> {
    // Parse header
    const version = ciphertext[0];
    if (version !== 0x01) throw new Error(`Unknown MPC wrap version: ${version}`);
    const threshold = ciphertext[1];
    const storeIdLen = ciphertext[3];
    const storeId = ciphertext.subarray(4, 4 + storeIdLen).toString('hex');

    const payload = ciphertext.subarray(4 + storeIdLen);
    const iv = payload.subarray(0, 12);
    const authTag = payload.subarray(payload.length - 16);
    const encrypted = payload.subarray(12, payload.length - 16);

    // Retrieve shards
    const shards = await this.shardStore.getShards(storeId);
    if (shards.length < threshold) {
      throw new Error(`Need ${threshold} shards, got ${shards.length}`);
    }

    // Reconstruct wrapping key
    const wrappingKey = shamirRecombine(shards.slice(0, threshold));

    // Decrypt DEK
    const decipher = crypto.createDecipheriv('aes-256-gcm', wrappingKey, iv, { authTagLength: 16 });
    decipher.setAuthTag(authTag);
    return Buffer.concat([decipher.update(encrypted), decipher.final()]);
  }
}

// ──────────────────────────────────────────────────────────────────────────
// Shamir's Secret Sharing over GF(256)
// ──────────────────────────────────────────────────────────────────────────

// GF(256) with irreducible polynomial x^8 + x^4 + x^3 + x + 1 (0x11B)
const EXP = new Uint8Array(256);
const LOG = new Uint8Array(256);

(function initGF256() {
  // Generator 3, irreducible polynomial 0x11d (x^8 + x^4 + x^3 + x^2 + 1)
  // This generates all 255 non-zero elements of GF(256)
  let x = 1;
  for (let i = 0; i < 255; i++) {
    EXP[i] = x;
    LOG[x] = i;
    x = ((x << 1) ^ (x & 0x80 ? 0x1d : 0)) & 0xff;
  }
  EXP[255] = 1;
})();

function gfMul(a: number, b: number): number {
  if (a === 0 || b === 0) return 0;
  return EXP[(LOG[a] + LOG[b]) % 255];
}

function gfDiv(a: number, b: number): number {
  if (b === 0) throw new Error('Division by zero in GF(256)');
  if (a === 0) return 0;
  return EXP[(LOG[a] - LOG[b] + 255) % 255];
}

/**
 * Split a secret into N shares with threshold K using Shamir's Secret Sharing.
 */
function shamirSplit(secret: Buffer, n: number, k: number): MpcShard[] {
  const shares: MpcShard[] = [];

  for (let i = 1; i <= n; i++) {
    shares.push({ index: i, data: Buffer.alloc(secret.length) });
  }

  for (let byteIdx = 0; byteIdx < secret.length; byteIdx++) {
    // Random polynomial: coefficients[0] = secret byte, rest random
    const coeffs = new Uint8Array(k);
    coeffs[0] = secret[byteIdx];
    for (let j = 1; j < k; j++) {
      coeffs[j] = crypto.randomBytes(1)[0];
    }

    // Evaluate polynomial at x = 1..n
    for (let i = 0; i < n; i++) {
      const x = i + 1;
      let y = 0;
      for (let j = k - 1; j >= 0; j--) {
        y = gfMul(y, x) ^ coeffs[j];
      }
      shares[i].data[byteIdx] = y;
    }
  }

  return shares;
}

/**
 * Reconstruct a secret from K shares using Lagrange interpolation in GF(256).
 */
function shamirRecombine(shares: MpcShard[]): Buffer {
  const k = shares.length;
  const secretLen = shares[0].data.length;
  const result = Buffer.alloc(secretLen);

  for (let byteIdx = 0; byteIdx < secretLen; byteIdx++) {
    let secret = 0;

    for (let i = 0; i < k; i++) {
      const xi = shares[i].index;
      const yi = shares[i].data[byteIdx];

      // Lagrange basis polynomial
      let basis = 1;
      for (let j = 0; j < k; j++) {
        if (i === j) continue;
        const xj = shares[j].index;
        // basis *= xj / (xj ^ xi) in GF(256)
        basis = gfMul(basis, gfDiv(xj, xi ^ xj));
      }

      secret ^= gfMul(yi, basis);
    }

    result[byteIdx] = secret;
  }

  return result;
}

// Export for testing
export { shamirSplit, shamirRecombine };
