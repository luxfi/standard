import * as crypto from 'node:crypto';
import {KeyManagementServiceClient} from '@google-cloud/kms';
import {DekStore, FieldEncryptorOptions, ENCRYPTED_PREFIX} from './types';
import {InMemoryDekStore} from './stores/memory';

const IV_LENGTH = 12; // AES-GCM standard
const AUTH_TAG_LENGTH = 16; // 128-bit auth tag
const DEK_LENGTH = 32; // AES-256

/**
 * AES-256-GCM field-level encryption with per-customer data encryption keys (DEKs).
 *
 * Architecture:
 *   KEK (in GCP Cloud KMS) wraps per-customer DEKs.
 *   Each encrypt() call uses a random 12-byte IV.
 *   Ciphertext format: "enc:v1:" + base64(IV(12) || ciphertext || authTag(16))
 *
 * Dev mode:
 *   When KMS is unavailable, uses a local key (env FIELD_ENCRYPTION_KEY) to
 *   wrap DEKs via AES-256-GCM locally. Never use this in production.
 */
export class FieldEncryptor {
  private readonly kmsClient: KeyManagementServiceClient | null;
  private readonly kmsKeyName: string | null;
  private readonly dekStore: DekStore;
  private readonly localFallbackKey: Buffer | null;

  // In-memory plaintext DEK cache (customerId -> plaintext DEK)
  // Avoids repeated KMS unwrap calls for hot paths.
  private readonly dekCache = new Map<string, Buffer>();

  constructor(options: FieldEncryptorOptions = {}) {
    const kmsKeyName =
      options.kmsKeyName ?? process.env.FIELD_ENCRYPTION_KEK ?? null;
    const localKey =
      options.localFallbackKey ?? process.env.FIELD_ENCRYPTION_KEY ?? null;

    this.dekStore = options.dekStore ?? new InMemoryDekStore();

    // Prefer KMS. Fall back to local key for dev/test only.
    if (options.kmsClient) {
      this.kmsClient = options.kmsClient;
      this.kmsKeyName = kmsKeyName;
      this.localFallbackKey = null;
    } else if (kmsKeyName) {
      this.kmsClient = new KeyManagementServiceClient();
      this.kmsKeyName = kmsKeyName;
      this.localFallbackKey = null;
    } else if (localKey) {
      this.kmsClient = null;
      this.kmsKeyName = null;
      this.localFallbackKey = Buffer.from(localKey, 'hex');
      if (this.localFallbackKey.length !== DEK_LENGTH) {
        throw new Error(
          'FIELD_ENCRYPTION_KEY must be 64 hex characters (32 bytes)'
        );
      }
    } else {
      throw new Error(
        'FieldEncryptor requires either a KMS key name (FIELD_ENCRYPTION_KEK) ' +
          'or a local fallback key (FIELD_ENCRYPTION_KEY)'
      );
    }
  }

  // ---- Public API ----

  /**
   * Encrypt a PII field value for a customer.
   * Returns the original value for null/undefined/empty strings.
   * Skips already-encrypted values (idempotent).
   */
  async encrypt(customerId: string, plaintext: string): Promise<string> {
    if (!plaintext) return plaintext;
    if (plaintext.startsWith(ENCRYPTED_PREFIX)) return plaintext;

    const dek = await this.getCustomerDek(customerId);
    const iv = crypto.randomBytes(IV_LENGTH);
    const cipher = crypto.createCipheriv('aes-256-gcm', dek, iv, {
      authTagLength: AUTH_TAG_LENGTH,
    });

    const encrypted = Buffer.concat([
      cipher.update(plaintext, 'utf8'),
      cipher.final(),
    ]);
    const authTag = cipher.getAuthTag();

    // Wire format: IV || ciphertext || authTag
    const payload = Buffer.concat([iv, encrypted, authTag]);
    return ENCRYPTED_PREFIX + payload.toString('base64');
  }

  /**
   * Decrypt a PII field value for a customer.
   * Returns the original value for null/undefined/empty strings.
   * Returns the original value if not encrypted (graceful passthrough).
   */
  async decrypt(customerId: string, ciphertext: string): Promise<string> {
    if (!ciphertext) return ciphertext;
    if (!ciphertext.startsWith(ENCRYPTED_PREFIX)) return ciphertext;

    const dek = await this.getCustomerDek(customerId);
    const payload = Buffer.from(
      ciphertext.slice(ENCRYPTED_PREFIX.length),
      'base64'
    );

    if (payload.length < IV_LENGTH + AUTH_TAG_LENGTH) {
      throw new Error('Invalid encrypted payload: too short');
    }

    const iv = payload.subarray(0, IV_LENGTH);
    const authTag = payload.subarray(payload.length - AUTH_TAG_LENGTH);
    const encrypted = payload.subarray(
      IV_LENGTH,
      payload.length - AUTH_TAG_LENGTH
    );

    const decipher = crypto.createDecipheriv('aes-256-gcm', dek, iv, {
      authTagLength: AUTH_TAG_LENGTH,
    });
    decipher.setAuthTag(authTag);

    const decrypted = Buffer.concat([
      decipher.update(encrypted),
      decipher.final(),
    ]);
    return decrypted.toString('utf8');
  }

  /**
   * Rotate the DEK for a customer. Generates a new DEK, wraps it,
   * and stores it. Clears the cached plaintext DEK.
   *
   * IMPORTANT: Callers must re-encrypt all existing ciphertext fields
   * for this customer after rotation.
   */
  async rotateKey(customerId: string): Promise<void> {
    this.dekCache.delete(customerId);
    const plainDek = crypto.randomBytes(DEK_LENGTH);
    const wrappedDek = await this.wrapDek(plainDek);
    await this.dekStore.set(customerId, wrappedDek);
    this.dekCache.set(customerId, plainDek);
  }

  /**
   * Destroy the DEK for a customer (GDPR Article 17 — right to erasure).
   * After this, data encrypted with this customer's DEK is unrecoverable.
   */
  async destroyKey(customerId: string): Promise<void> {
    this.dekCache.delete(customerId);
    await this.dekStore.delete(customerId);
  }

  /**
   * Get or create the plaintext DEK for a customer.
   * Checks in-memory cache first, then the DEK store.
   * Creates + wraps a new DEK if none exists.
   */
  async getCustomerDek(customerId: string): Promise<Buffer> {
    // 1. Check memory cache
    const cached = this.dekCache.get(customerId);
    if (cached) return cached;

    // 2. Check persistent store
    const wrappedDek = await this.dekStore.get(customerId);
    if (wrappedDek) {
      const plainDek = await this.unwrapDek(wrappedDek);
      this.dekCache.set(customerId, plainDek);
      return plainDek;
    }

    // 3. Generate new DEK
    const plainDek = crypto.randomBytes(DEK_LENGTH);
    const newWrappedDek = await this.wrapDek(plainDek);
    await this.dekStore.set(customerId, newWrappedDek);
    this.dekCache.set(customerId, plainDek);
    return plainDek;
  }

  // ---- KEK operations (KMS or local fallback) ----

  private async wrapDek(plainDek: Buffer): Promise<Buffer> {
    if (this.kmsClient && this.kmsKeyName) {
      const [result] = await this.kmsClient.encrypt({
        name: this.kmsKeyName,
        plaintext: plainDek,
      });
      if (!result.ciphertext) {
        throw new Error('KMS encrypt returned empty ciphertext');
      }
      return Buffer.from(result.ciphertext as Uint8Array);
    }

    // Local fallback: AES-256-GCM with the fallback key
    return this.localWrap(plainDek);
  }

  private async unwrapDek(wrappedDek: Buffer): Promise<Buffer> {
    if (this.kmsClient && this.kmsKeyName) {
      const [result] = await this.kmsClient.decrypt({
        name: this.kmsKeyName,
        ciphertext: wrappedDek,
      });
      if (!result.plaintext) {
        throw new Error('KMS decrypt returned empty plaintext');
      }
      return Buffer.from(result.plaintext as Uint8Array);
    }

    // Local fallback
    return this.localUnwrap(wrappedDek);
  }

  private localWrap(plainDek: Buffer): Buffer {
    if (!this.localFallbackKey) {
      throw new Error('No local fallback key configured');
    }
    const iv = crypto.randomBytes(IV_LENGTH);
    const cipher = crypto.createCipheriv(
      'aes-256-gcm',
      this.localFallbackKey,
      iv,
      {authTagLength: AUTH_TAG_LENGTH}
    );
    const encrypted = Buffer.concat([
      cipher.update(plainDek),
      cipher.final(),
    ]);
    const authTag = cipher.getAuthTag();
    return Buffer.concat([iv, encrypted, authTag]);
  }

  private localUnwrap(wrappedDek: Buffer): Buffer {
    if (!this.localFallbackKey) {
      throw new Error('No local fallback key configured');
    }
    if (wrappedDek.length < IV_LENGTH + AUTH_TAG_LENGTH) {
      throw new Error('Invalid wrapped DEK: too short');
    }
    const iv = wrappedDek.subarray(0, IV_LENGTH);
    const authTag = wrappedDek.subarray(wrappedDek.length - AUTH_TAG_LENGTH);
    const encrypted = wrappedDek.subarray(
      IV_LENGTH,
      wrappedDek.length - AUTH_TAG_LENGTH
    );

    const decipher = crypto.createDecipheriv(
      'aes-256-gcm',
      this.localFallbackKey,
      iv,
      {authTagLength: AUTH_TAG_LENGTH}
    );
    decipher.setAuthTag(authTag);
    return Buffer.concat([decipher.update(encrypted), decipher.final()]);
  }
}
