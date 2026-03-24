export { FieldEncryptor } from './field-encryptor';
export { ENCRYPTED_PREFIX } from './types';
export type { DekStore, KekProvider, MpcShard, MpcShardStore, MpcProviderOptions, FieldEncryptorOptions } from './types';

// KEK Providers — pick security level
export { LocalKekProvider } from './providers/local';
export { CloudKmsProvider } from './providers/cloud-kms';
export { MpcKekProvider, shamirSplit, shamirRecombine } from './providers/mpc';

// DEK Stores — pick your database
export { InMemoryDekStore } from './stores/memory';
export { SqliteDekStore } from './stores/sqlite';
export { PostgresDekStore } from './stores/postgres';
export { MongoDekStore } from './stores/mongo';

// Mongoose plugin (optional)
export { encryptedFieldsPlugin } from './mongoose-plugin';
