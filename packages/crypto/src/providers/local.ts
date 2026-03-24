import * as crypto from 'node:crypto';
import type { KekProvider } from '../types';

const IV_LENGTH = 12;
const AUTH_TAG_LENGTH = 16;

/**
 * Local KEK provider — AES-256-GCM with a static key.
 * For dev/test only. Same wire format as KMS/HSM providers.
 */
export class LocalKekProvider implements KekProvider {
  readonly name = 'local';
  private readonly key: Buffer;

  constructor(keyHex: string) {
    this.key = Buffer.from(keyHex, 'hex');
    if (this.key.length !== 32) {
      throw new Error('Local KEK must be 64 hex characters (32 bytes)');
    }
  }

  async wrap(plaintext: Buffer): Promise<Buffer> {
    const iv = crypto.randomBytes(IV_LENGTH);
    const cipher = crypto.createCipheriv('aes-256-gcm', this.key, iv, { authTagLength: AUTH_TAG_LENGTH });
    const encrypted = Buffer.concat([cipher.update(plaintext), cipher.final()]);
    return Buffer.concat([iv, encrypted, cipher.getAuthTag()]);
  }

  async unwrap(ciphertext: Buffer): Promise<Buffer> {
    const iv = ciphertext.subarray(0, IV_LENGTH);
    const authTag = ciphertext.subarray(ciphertext.length - AUTH_TAG_LENGTH);
    const encrypted = ciphertext.subarray(IV_LENGTH, ciphertext.length - AUTH_TAG_LENGTH);
    const decipher = crypto.createDecipheriv('aes-256-gcm', this.key, iv, { authTagLength: AUTH_TAG_LENGTH });
    decipher.setAuthTag(authTag);
    return Buffer.concat([decipher.update(encrypted), decipher.final()]);
  }
}
