import type { KekProvider } from '../types';

/**
 * GCP Cloud KMS KEK provider — wraps/unwraps DEKs via Cloud KMS.
 *
 * Works with both software keys and Cloud HSM keys:
 *   - Software: projects/x/locations/global/keyRings/y/cryptoKeys/z
 *   - HSM:      projects/x/locations/us-east1/keyRings/y/cryptoKeys/z
 *               (key must be created with protection level HSM)
 *
 * Cloud HSM keys are FIPS 140-2 Level 3 certified. Same API, same code —
 * the only difference is the key's protection level set at creation time.
 */
export class CloudKmsProvider implements KekProvider {
  readonly name: string;
  private readonly client: any; // KeyManagementServiceClient
  private readonly keyName: string;

  /**
   * @param keyName Full resource name of the KMS key
   * @param client Optional KMS client (auto-created if omitted)
   */
  constructor(keyName: string, client?: any) {
    this.keyName = keyName;
    this.name = keyName.includes('/locations/global/') ? 'cloud-kms' : 'cloud-hsm';

    if (client) {
      this.client = client;
    } else {
      // Lazy import to avoid requiring @google-cloud/kms when not used
      const { KeyManagementServiceClient } = require('@google-cloud/kms');
      this.client = new KeyManagementServiceClient();
    }
  }

  async wrap(plaintext: Buffer): Promise<Buffer> {
    const [result] = await this.client.encrypt({
      name: this.keyName,
      plaintext,
    });
    if (!result.ciphertext) throw new Error('KMS encrypt returned empty');
    return Buffer.from(result.ciphertext as Uint8Array);
  }

  async unwrap(ciphertext: Buffer): Promise<Buffer> {
    const [result] = await this.client.decrypt({
      name: this.keyName,
      ciphertext,
    });
    if (!result.plaintext) throw new Error('KMS decrypt returned empty');
    return Buffer.from(result.plaintext as Uint8Array);
  }
}
