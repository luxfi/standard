import * as crypto from 'node:crypto';
import {FieldEncryptor, InMemoryDekStore, ENCRYPTED_PREFIX} from '../src';

// Deterministic 32-byte hex key for tests
const TEST_KEY = crypto.randomBytes(32).toString('hex');

function makeEncryptor(store?: InMemoryDekStore): FieldEncryptor {
  return new FieldEncryptor({
    localFallbackKey: TEST_KEY,
    dekStore: store ?? new InMemoryDekStore(),
  });
}

describe('FieldEncryptor', () => {
  describe('constructor', () => {
    it('throws if no key source is provided', () => {
      // Clear env vars that might be set
      const savedKek = process.env.FIELD_ENCRYPTION_KEK;
      const savedKey = process.env.FIELD_ENCRYPTION_KEY;
      delete process.env.FIELD_ENCRYPTION_KEK;
      delete process.env.FIELD_ENCRYPTION_KEY;

      expect(() => new FieldEncryptor({})).toThrow(
        'FieldEncryptor requires a kekProvider'
      );

      // Restore
      if (savedKek) process.env.FIELD_ENCRYPTION_KEK = savedKek;
      if (savedKey) process.env.FIELD_ENCRYPTION_KEY = savedKey;
    });

    it('throws if local fallback key is wrong length', () => {
      expect(
        () => new FieldEncryptor({localFallbackKey: 'abcd'})
      ).toThrow('32 bytes');
    });

    it('accepts env var FIELD_ENCRYPTION_KEY', () => {
      const saved = process.env.FIELD_ENCRYPTION_KEY;
      process.env.FIELD_ENCRYPTION_KEY = TEST_KEY;

      expect(() => new FieldEncryptor({})).not.toThrow();

      if (saved) {
        process.env.FIELD_ENCRYPTION_KEY = saved;
      } else {
        delete process.env.FIELD_ENCRYPTION_KEY;
      }
    });
  });

  describe('encrypt / decrypt', () => {
    it('encrypts and decrypts a string', async () => {
      const enc = makeEncryptor();
      const customerId = 'cust-001';
      const plaintext = 'SSN: 123-45-6789';

      const ciphertext = await enc.encrypt(customerId, plaintext);
      expect(ciphertext).not.toBe(plaintext);
      expect(ciphertext.startsWith(ENCRYPTED_PREFIX)).toBe(true);

      const decrypted = await enc.decrypt(customerId, ciphertext);
      expect(decrypted).toBe(plaintext);
    });

    it('produces different ciphertexts for same plaintext (random IV)', async () => {
      const enc = makeEncryptor();
      const c1 = await enc.encrypt('cust-001', 'hello');
      const c2 = await enc.encrypt('cust-001', 'hello');
      expect(c1).not.toBe(c2);
    });

    it('different customers get different DEKs', async () => {
      const store = new InMemoryDekStore();
      const enc = makeEncryptor(store);

      await enc.encrypt('cust-A', 'data');
      await enc.encrypt('cust-B', 'data');

      const dekA = await store.get('cust-A');
      const dekB = await store.get('cust-B');
      expect(dekA).not.toBeNull();
      expect(dekB).not.toBeNull();
      expect(dekA!.equals(dekB!)).toBe(false);
    });

    it('handles empty string (returns as-is)', async () => {
      const enc = makeEncryptor();
      expect(await enc.encrypt('cust-001', '')).toBe('');
      expect(await enc.decrypt('cust-001', '')).toBe('');
    });

    it('handles already-encrypted value (idempotent encrypt)', async () => {
      const enc = makeEncryptor();
      const ciphertext = await enc.encrypt('cust-001', 'secret');
      const double = await enc.encrypt('cust-001', ciphertext);
      expect(double).toBe(ciphertext);
    });

    it('handles non-encrypted value on decrypt (passthrough)', async () => {
      const enc = makeEncryptor();
      const plain = 'not-encrypted';
      expect(await enc.decrypt('cust-001', plain)).toBe(plain);
    });

    it('handles unicode and multi-byte characters', async () => {
      const enc = makeEncryptor();
      const texts = [
        'Strasse 42, Munchen',
        'Tokyo district',
        'Test with emoji and accents: cafe, resume',
        '   leading/trailing whitespace   ',
      ];

      for (const text of texts) {
        const ct = await enc.encrypt('cust-001', text);
        const pt = await enc.decrypt('cust-001', ct);
        expect(pt).toBe(text);
      }
    });

    it('throws on tampered ciphertext', async () => {
      const enc = makeEncryptor();
      const ct = await enc.encrypt('cust-001', 'secret');

      // Flip a byte in the base64 payload
      const payload = Buffer.from(
        ct.slice(ENCRYPTED_PREFIX.length),
        'base64'
      );
      payload[payload.length - 1] ^= 0xff;
      const tampered =
        ENCRYPTED_PREFIX + payload.toString('base64');

      await expect(enc.decrypt('cust-001', tampered)).rejects.toThrow();
    });

    it('throws on truncated ciphertext', async () => {
      const enc = makeEncryptor();
      const short = ENCRYPTED_PREFIX + Buffer.from('abc').toString('base64');
      await expect(enc.decrypt('cust-001', short)).rejects.toThrow(
        'too short'
      );
    });

    it('cannot decrypt with wrong customer DEK', async () => {
      const enc = makeEncryptor();
      const ct = await enc.encrypt('cust-A', 'secret');

      // cust-B has a different DEK, so decryption should fail
      await expect(enc.decrypt('cust-B', ct)).rejects.toThrow();
    });
  });

  describe('rotateKey', () => {
    it('generates a new DEK and old ciphertext cannot decrypt', async () => {
      const store = new InMemoryDekStore();
      const enc = makeEncryptor(store);
      const customerId = 'cust-rotate';

      const ct = await enc.encrypt(customerId, 'before rotation');
      const wrappedBefore = await store.get(customerId);

      await enc.rotateKey(customerId);
      const wrappedAfter = await store.get(customerId);

      // Wrapped DEK must have changed
      expect(wrappedBefore!.equals(wrappedAfter!)).toBe(false);

      // Old ciphertext cannot be decrypted with new DEK
      await expect(enc.decrypt(customerId, ct)).rejects.toThrow();

      // New encrypt/decrypt works
      const ct2 = await enc.encrypt(customerId, 'after rotation');
      expect(await enc.decrypt(customerId, ct2)).toBe('after rotation');
    });
  });

  describe('destroyKey', () => {
    it('removes the DEK and makes decryption impossible', async () => {
      const store = new InMemoryDekStore();
      const enc = makeEncryptor(store);
      const customerId = 'cust-gdpr';

      const ct = await enc.encrypt(customerId, 'personal data');
      await enc.destroyKey(customerId);

      // Store should be empty for this customer
      expect(await store.get(customerId)).toBeNull();

      // A new DEK will be generated, but it won't decrypt old data
      await expect(enc.decrypt(customerId, ct)).rejects.toThrow();
    });
  });

  describe('getCustomerDek', () => {
    it('returns same DEK on repeated calls (caching)', async () => {
      const enc = makeEncryptor();
      const dek1 = await enc.getCustomerDek('cust-cache');
      const dek2 = await enc.getCustomerDek('cust-cache');
      expect(dek1.equals(dek2)).toBe(true);
    });

    it('reloads DEK from store when not in cache', async () => {
      const store = new InMemoryDekStore();

      // First encryptor creates the DEK
      const enc1 = new FieldEncryptor({
        localFallbackKey: TEST_KEY,
        dekStore: store,
      });
      const ct = await enc1.encrypt('cust-reload', 'data');

      // Second encryptor (simulating a new process) shares the store
      const enc2 = new FieldEncryptor({
        localFallbackKey: TEST_KEY,
        dekStore: store,
      });
      const pt = await enc2.decrypt('cust-reload', ct);
      expect(pt).toBe('data');
    });
  });
});
