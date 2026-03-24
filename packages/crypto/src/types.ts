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

/**
 * KEK Provider interface — abstracts how DEKs are wrapped/unwrapped.
 *
 * Implementations:
 *   - CloudKmsProvider: GCP Cloud KMS (software keys)
 *   - CloudHsmProvider: GCP/AWS/Azure Cloud HSM (FIPS 140-2 Level 3)
 *   - MpcProvider: Shamir/FROST threshold — DEK split across N shards
 *   - LocalProvider: AES-256-GCM with local key (dev/test only)
 */
export interface KekProvider {
  /** Wrap (encrypt) a plaintext DEK using the KEK */
  wrap(plaintext: Buffer): Promise<Buffer>;
  /** Unwrap (decrypt) a wrapped DEK to plaintext */
  unwrap(ciphertext: Buffer): Promise<Buffer>;
  /** Provider name for logging/audit */
  readonly name: string;
}

/**
 * MPC shard — one piece of a threshold-split secret.
 */
export interface MpcShard {
  /** Shard index (1-based) */
  index: number;
  /** Shard data (Shamir/FROST share) */
  data: Buffer;
}

/**
 * MPC provider options for threshold secret splitting.
 */
export interface MpcProviderOptions {
  /** Total number of shards */
  totalShards: number;
  /** Minimum shards required to reconstruct (k-of-n) */
  threshold: number;
  /** Functions to store/retrieve shards from different custodians */
  shardStore: MpcShardStore;
}

/**
 * Storage interface for MPC shards — each shard can live in a different
 * location (device, KMS, HSM, custodian service).
 */
export interface MpcShardStore {
  /** Store a shard for a customer at a specific index */
  setShard(customerId: string, shard: MpcShard): Promise<void>;
  /** Retrieve shards for a customer (returns at least `threshold` shards) */
  getShards(customerId: string): Promise<MpcShard[]>;
  /** Delete all shards for a customer */
  deleteShards(customerId: string): Promise<void>;
}

/** Options for constructing a FieldEncryptor. */
export interface FieldEncryptorOptions {
  /**
   * KEK provider for wrapping/unwrapping DEKs.
   * If not provided, falls back to legacy options (kmsKeyName, localFallbackKey).
   */
  kekProvider?: KekProvider;

  /**
   * Full GCP Cloud KMS key resource name (KEK).
   * Format: projects/{project}/locations/{location}/keyRings/{keyRing}/cryptoKeys/{key}
   * If omitted, falls back to FIELD_ENCRYPTION_KEK env var.
   * @deprecated Use kekProvider instead
   */
  kmsKeyName?: string;

  /**
   * Optional KMS client instance. If omitted, one is created automatically.
   * @deprecated Use kekProvider instead
   */
  kmsClient?: import('@google-cloud/kms').KeyManagementServiceClient;

  /**
   * Store for persisted wrapped DEKs. Defaults to InMemoryDekStore.
   * In production, supply a database-backed implementation.
   */
  dekStore?: DekStore;

  /**
   * Local fallback key (hex-encoded, 64 chars = 32 bytes) for dev/test.
   * Falls back to FIELD_ENCRYPTION_KEY env var. Never use in production.
   * @deprecated Use kekProvider with LocalKekProvider instead
   */
  localFallbackKey?: string;
}

/** Encrypted field prefix for version detection. */
export const ENCRYPTED_PREFIX = 'enc:v1:';
