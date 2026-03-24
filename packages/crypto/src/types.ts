/**
 * Store interface for persisting wrapped (encrypted) DEKs.
 * Implementations may use a database, file system, or in-memory map.
 */
export interface DekStore {
  /** Retrieve wrapped DEK bytes for a customer. Returns null if none exists. */
  get(customerId: string): Promise<Buffer | null>;
  /** Persist wrapped DEK bytes for a customer. */
  set(customerId: string, wrappedDek: Buffer): Promise<void>;
  /** Delete a customer's wrapped DEK. */
  delete(customerId: string): Promise<void>;
}

/** Options for constructing a FieldEncryptor. */
export interface FieldEncryptorOptions {
  /**
   * Full GCP Cloud KMS key resource name (KEK).
   * Format: projects/{project}/locations/{location}/keyRings/{keyRing}/cryptoKeys/{key}
   * If omitted, falls back to FIELD_ENCRYPTION_KEK env var.
   */
  kmsKeyName?: string;

  /**
   * Optional KMS client instance. If omitted, one is created automatically
   * (unless running in dev mode).
   */
  kmsClient?: import('@google-cloud/kms').KeyManagementServiceClient;

  /**
   * Store for persisted wrapped DEKs. Defaults to InMemoryDekStore.
   * In production, supply a database-backed implementation.
   */
  dekStore?: DekStore;

  /**
   * Local fallback key (hex-encoded, 64 chars = 32 bytes) for dev/test
   * when KMS is unavailable. Falls back to FIELD_ENCRYPTION_KEY env var.
   * Never use in production.
   */
  localFallbackKey?: string;
}

/** Encrypted field prefix for version detection. */
export const ENCRYPTED_PREFIX = 'enc:v1:';
