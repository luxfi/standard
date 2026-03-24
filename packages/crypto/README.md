# @luxfi/crypto

Per-customer field-level encryption for PII data. AES-256-GCM with KMS-wrapped DEKs (Data Encryption Keys).

## Architecture

```
GCP Cloud KMS (KEK)  ─or─  Hanzo KMS  ─or─  MPC Safe wallet
       │
       │  wraps/unwraps
       ▼
┌─────────────────┐
│ Customer DEK    │  ← unique AES-256 key per customer
│ (in DekStore)   │     stored wrapped (encrypted by KEK)
└─────────────────┘
       │
       │  AES-256-GCM + random IV per field
       ▼
 ssn: "enc:v1:base64(IV|ciphertext|authTag)"
 dob: "enc:v1:base64(IV|ciphertext|authTag)"
```

## Install

```bash
npm install @luxfi/crypto
```

## Usage

```typescript
import { FieldEncryptor, SqliteDekStore } from '@luxfi/crypto';

// With Base (SQLite production mode)
const encryptor = new FieldEncryptor({
  kmsKeyName: 'projects/xxx/locations/global/keyRings/xxx/cryptoKeys/xxx',
  dekStore: new SqliteDekStore(app.dataDB()),
});

// Encrypt PII
const encrypted = await encryptor.encrypt('customer-123', '123-45-6789');
// → "enc:v1:base64(...)"

// Decrypt PII
const ssn = await encryptor.decrypt('customer-123', encrypted);
// → "123-45-6789"

// GDPR erasure — destroy DEK, data irrecoverable
await encryptor.destroyKey('customer-123');
```

## DekStore Backends

| Store | Import | Use With |
|-------|--------|----------|
| `SqliteDekStore` | `@luxfi/crypto` | Base (SQLite + PostgreSQL), better-sqlite3 |
| `PostgresDekStore` | `@luxfi/crypto` | pg, pgx, Knex, Drizzle |
| `MongoDekStore` | `@luxfi/crypto` | MongoDB native driver, Mongoose |
| `InMemoryDekStore` | `@luxfi/crypto` | Tests, dev only |

### Base Integration (Go → TypeScript bridge via JSVM plugin)

```typescript
// In Base JSVM plugin
const store = new SqliteDekStore($app.dao().db());
const encryptor = new FieldEncryptor({ dekStore: store });
```

### With IAM + Web3

The encryptor integrates with the identity stack:
- **Hanzo IAM**: OAuth2/OIDC user ID → `customerId` for DEK lookup
- **Hanzo KMS**: Alternative to GCP Cloud KMS for key wrapping
- **MPC Safe**: Threshold signatures can authorize key rotation/destruction
- **On-chain ComplianceRegistry**: KYC status gates who can have DEKs created

## Key Properties

- **Dedicated DEK per customer** — cryptographic isolation between customers
- **AES-256-GCM** — authenticated encryption (tamper detection)
- **Random IV per field per write** — no ciphertext correlation
- **Idempotent** — encrypt() skips already-encrypted, decrypt() passes through plaintext
- **GDPR Article 17** — `destroyKey()` makes all customer data irrecoverable
- **Key rotation** — `rotateKey()` generates new DEK (caller re-encrypts fields)

## Encrypted Field Format

```
"enc:v1:" + base64( IV(12 bytes) || ciphertext || authTag(16 bytes) )
```

Version prefix enables future algorithm migration (e.g., `enc:v2:` for post-quantum).
