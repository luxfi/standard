import * as crypto from 'node:crypto';
import { DekStore, KekProvider, FieldEncryptorOptions, ENCRYPTED_PREFIX } from './types';
import { InMemoryDekStore } from './stores/memory';
import { LocalKekProvider } from './providers/local';
import { CloudKmsProvider } from './providers/cloud-kms';

const IV_LENGTH = 12;
const AUTH_TAG_LENGTH = 16;
const DEK_LENGTH = 32;

/**
 * AES-256-GCM field-level encryption with per-customer DEKs.
 *
 * Architecture:
 *   KekProvider (KMS / Cloud HSM / MPC / local) wraps per-customer DEKs.
 *   Each encrypt() call uses a random 12-byte IV.
 *   Ciphertext format: "enc:v1:" + base64(IV(12) || ciphertext || authTag(16))
 *
 * Security levels (via KekProvider):
 *   LocalKekProvider   — AES-256-GCM with static key (dev/test only)
 *   CloudKmsProvider    — GCP Cloud KMS software keys
 *   CloudKmsProvider    — GCP Cloud HSM (same API, key created with HSM protection)
 *   MpcKekProvider      — Shamir K-of-N threshold (shards across custodians)
 */
export class FieldEncryptor {
  private readonly kekProvider: KekProvider;
  private readonly dekStore: DekStore;
  private readonly dekCache = new Map<string, Buffer>();

  constructor(options: FieldEncryptorOptions = {}) {
    this.dekStore = options.dekStore ?? new InMemoryDekStore();

    // New: KekProvider interface (preferred)
    if (options.kekProvider) {
      this.kekProvider = options.kekProvider;
      return;
    }

    // Legacy: direct KMS options
    const kmsKeyName = options.kmsKeyName ?? process.env.FIELD_ENCRYPTION_KEK ?? null;
    const localKey = options.localFallbackKey ?? process.env.FIELD_ENCRYPTION_KEY ?? null;

    if (options.kmsClient && kmsKeyName) {
      this.kekProvider = new CloudKmsProvider(kmsKeyName, options.kmsClient);
    } else if (kmsKeyName) {
      this.kekProvider = new CloudKmsProvider(kmsKeyName);
    } else if (localKey) {
      this.kekProvider = new LocalKekProvider(localKey);
    } else {
      throw new Error(
        'FieldEncryptor requires a kekProvider, KMS key (FIELD_ENCRYPTION_KEK), ' +
        'or local fallback key (FIELD_ENCRYPTION_KEY)'
      );
    }
  }

  /** Which KEK provider is active */
  get providerName(): string {
    return this.kekProvider.name;
  }

  /**
   * Encrypt a PII field value for a customer.
   * Idempotent — skips already-encrypted values.
   */
  async encrypt(customerId: string, plaintext: string): Promise<string> {
    if (!plaintext) return plaintext;
    if (plaintext.startsWith(ENCRYPTED_PREFIX)) return plaintext;

    const dek = await this.getCustomerDek(customerId);
    const iv = crypto.randomBytes(IV_LENGTH);
    const cipher = crypto.createCipheriv('aes-256-gcm', dek, iv, { authTagLength: AUTH_TAG_LENGTH });
    const encrypted = Buffer.concat([cipher.update(plaintext, 'utf8'), cipher.final()]);
    const payload = Buffer.concat([iv, encrypted, cipher.getAuthTag()]);
    return ENCRYPTED_PREFIX + payload.toString('base64');
  }

  /**
   * Decrypt a PII field value for a customer.
   * Graceful passthrough for non-encrypted values.
   */
  async decrypt(customerId: string, ciphertext: string): Promise<string> {
    if (!ciphertext) return ciphertext;
    if (!ciphertext.startsWith(ENCRYPTED_PREFIX)) return ciphertext;

    const dek = await this.getCustomerDek(customerId);
    const payload = Buffer.from(ciphertext.slice(ENCRYPTED_PREFIX.length), 'base64');
    if (payload.length < IV_LENGTH + AUTH_TAG_LENGTH) {
      throw new Error('Invalid encrypted payload: too short');
    }

    const iv = payload.subarray(0, IV_LENGTH);
    const authTag = payload.subarray(payload.length - AUTH_TAG_LENGTH);
    const encrypted = payload.subarray(IV_LENGTH, payload.length - AUTH_TAG_LENGTH);

    const decipher = crypto.createDecipheriv('aes-256-gcm', dek, iv, { authTagLength: AUTH_TAG_LENGTH });
    decipher.setAuthTag(authTag);
    return Buffer.concat([decipher.update(encrypted), decipher.final()]).toString('utf8');
  }

  /** Rotate DEK — generates new key, wraps with current KekProvider. Caller must re-encrypt fields. */
  async rotateKey(customerId: string): Promise<void> {
    this.dekCache.delete(customerId);
    const plainDek = crypto.randomBytes(DEK_LENGTH);
    const wrappedDek = await this.kekProvider.wrap(plainDek);
    await this.dekStore.set(customerId, wrappedDek);
    this.dekCache.set(customerId, plainDek);
  }

  /** Destroy DEK — GDPR Article 17. Data becomes irrecoverable. */
  async destroyKey(customerId: string): Promise<void> {
    this.dekCache.delete(customerId);
    await this.dekStore.delete(customerId);
  }

  /** Get or create the plaintext DEK for a customer. */
  async getCustomerDek(customerId: string): Promise<Buffer> {
    const cached = this.dekCache.get(customerId);
    if (cached) return cached;

    const wrappedDek = await this.dekStore.get(customerId);
    if (wrappedDek) {
      const plainDek = await this.kekProvider.unwrap(wrappedDek);
      this.dekCache.set(customerId, plainDek);
      return plainDek;
    }

    const plainDek = crypto.randomBytes(DEK_LENGTH);
    const newWrappedDek = await this.kekProvider.wrap(plainDek);
    await this.dekStore.set(customerId, newWrappedDek);
    this.dekCache.set(customerId, plainDek);
    return plainDek;
  }
}
