import type { KekProvider } from '../types';

/**
 * HSM KEK provider — wraps/unwraps DEKs using hardware security modules.
 *
 * Bridges to lux/hsm Manager for hardware-backed key operations.
 * Supports all providers that lux/hsm supports:
 *   - AWS KMS HSM (CloudHSM or KMS with EXTERNAL_KEY_STORE)
 *   - GCP Cloud HSM (FIPS 140-2 Level 3, same API as Cloud KMS)
 *   - Azure Managed HSM (FIPS 140-2 Level 3)
 *   - Zymbit SCM (local PKCS#11 hardware)
 *   - ML-DSA post-quantum (via Cloudflare CIRCL)
 *
 * Usage with lux/hsm Go bridge (via NAPI or HTTP):
 *   const hsm = new HsmKekProvider({ endpoint: 'http://localhost:8200', keyId: 'dek-wrap-key' });
 *
 * Usage with GCP Cloud HSM directly (TypeScript):
 *   const hsm = new HsmKekProvider({ kmsKeyName: 'projects/.../locations/us-east1/.../cryptoKeys/hsm-key' });
 *   // GCP Cloud HSM keys use the same API as Cloud KMS — the protection level
 *   // is set at key creation time (HSM vs SOFTWARE). Same code, hardware-backed.
 */
export class HsmKekProvider implements KekProvider {
  readonly name = 'hsm';
  private readonly backend: HsmBackend;

  constructor(options: HsmOptions) {
    if (options.endpoint) {
      // Bridge to lux/hsm Go service via HTTP
      this.backend = new HttpHsmBackend(options.endpoint, options.keyId ?? 'default');
    } else if (options.kmsKeyName) {
      // Direct GCP Cloud HSM (same API as Cloud KMS, just HSM protection level)
      this.backend = new GcpHsmBackend(options.kmsKeyName, options.kmsClient);
    } else if (options.wrapFn && options.unwrapFn) {
      // Custom wrap/unwrap functions (for embedding in Go processes via NAPI)
      this.backend = { wrap: options.wrapFn, unwrap: options.unwrapFn };
    } else {
      throw new Error('HsmKekProvider requires endpoint, kmsKeyName, or wrap/unwrapFn');
    }
  }

  async wrap(plaintext: Buffer): Promise<Buffer> {
    return this.backend.wrap(plaintext);
  }

  async unwrap(ciphertext: Buffer): Promise<Buffer> {
    return this.backend.unwrap(ciphertext);
  }
}

interface HsmBackend {
  wrap(plaintext: Buffer): Promise<Buffer>;
  unwrap(ciphertext: Buffer): Promise<Buffer>;
}

export interface HsmOptions {
  /** HTTP endpoint for lux/hsm Go service */
  endpoint?: string;
  /** Key ID for wrap/unwrap operations */
  keyId?: string;
  /** GCP Cloud HSM key resource name (same API as Cloud KMS, hardware-backed) */
  kmsKeyName?: string;
  /** Optional GCP KMS client instance */
  kmsClient?: any;
  /** Custom wrap function (for NAPI bridge to Go HSM) */
  wrapFn?: (plaintext: Buffer) => Promise<Buffer>;
  /** Custom unwrap function (for NAPI bridge to Go HSM) */
  unwrapFn?: (ciphertext: Buffer) => Promise<Buffer>;
}

/**
 * HTTP bridge to lux/hsm Go service.
 * The Go service exposes /v1/wrap and /v1/unwrap endpoints
 * backed by the HSM Manager (AWS/GCP/Azure/Zymbit).
 */
class HttpHsmBackend implements HsmBackend {
  constructor(private endpoint: string, private keyId: string) {}

  async wrap(plaintext: Buffer): Promise<Buffer> {
    const res = await fetch(`${this.endpoint}/v1/wrap`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        key_id: this.keyId,
        plaintext: plaintext.toString('base64'),
      }),
    });
    if (!res.ok) throw new Error(`HSM wrap failed: ${res.status}`);
    const data = await res.json() as any;
    return Buffer.from(data.ciphertext, 'base64');
  }

  async unwrap(ciphertext: Buffer): Promise<Buffer> {
    const res = await fetch(`${this.endpoint}/v1/unwrap`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        key_id: this.keyId,
        ciphertext: ciphertext.toString('base64'),
      }),
    });
    if (!res.ok) throw new Error(`HSM unwrap failed: ${res.status}`);
    const data = await res.json() as any;
    return Buffer.from(data.plaintext, 'base64');
  }
}

/**
 * Direct GCP Cloud HSM backend — same as CloudKmsProvider but explicit about HSM.
 * Key must be created with protection_level=HSM in GCP.
 */
class GcpHsmBackend implements HsmBackend {
  private client: any;
  private keyName: string;

  constructor(keyName: string, client?: any) {
    this.keyName = keyName;
    if (client) {
      this.client = client;
    } else {
      const { KeyManagementServiceClient } = require('@google-cloud/kms');
      this.client = new KeyManagementServiceClient();
    }
  }

  async wrap(plaintext: Buffer): Promise<Buffer> {
    const [result] = await this.client.encrypt({ name: this.keyName, plaintext });
    return Buffer.from(result.ciphertext as Uint8Array);
  }

  async unwrap(ciphertext: Buffer): Promise<Buffer> {
    const [result] = await this.client.decrypt({ name: this.keyName, ciphertext });
    return Buffer.from(result.plaintext as Uint8Array);
  }
}
