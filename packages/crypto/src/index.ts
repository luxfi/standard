export { FieldEncryptor } from './field-encryptor';
export { ENCRYPTED_PREFIX } from './types';
export type { DekStore, FieldEncryptorOptions } from './types';

// Stores — pick the one matching your database
export { InMemoryDekStore } from './stores/memory';
export { SqliteDekStore } from './stores/sqlite';
export { PostgresDekStore } from './stores/postgres';
export { MongoDekStore } from './stores/mongo';

// Mongoose plugin (optional — only import if using Mongoose)
export { encryptedFieldsPlugin } from './mongoose-plugin';
