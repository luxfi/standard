import type { FieldEncryptor } from './field-encryptor';

interface PluginOptions {
  fields: string[];
  encryptor: FieldEncryptor;
  customerIdField: string;
}

/**
 * Mongoose plugin that auto-encrypts PII fields on save and auto-decrypts on find.
 *
 * Usage:
 *   schema.plugin(encryptedFieldsPlugin, {
 *     fields: ['ssn', 'dateOfBirth', 'bankAccountNumber'],
 *     encryptor: fieldEncryptor,
 *     customerIdField: 'userId',
 *   });
 */
export function encryptedFieldsPlugin(schema: any, options: PluginOptions): void {
  const { fields, encryptor, customerIdField } = options;

  schema.pre('save', async function (this: any) {
    const customerId = this[customerIdField];
    if (!customerId) return;
    for (const field of fields) {
      if (this.isModified(field) && this[field]) {
        this[field] = await encryptor.encrypt(customerId, this[field]);
      }
    }
  });

  schema.post('findOne', async function (_query: any, doc: any) {
    if (!doc) return;
    const customerId = doc[customerIdField];
    if (!customerId) return;
    for (const field of fields) {
      if (doc[field]) {
        doc[field] = await encryptor.decrypt(customerId, doc[field]);
      }
    }
  });

  schema.post('find', async function (_query: any, docs: any[]) {
    for (const doc of docs) {
      const customerId = doc[customerIdField];
      if (!customerId) continue;
      for (const field of fields) {
        if (doc[field]) {
          doc[field] = await encryptor.decrypt(customerId, doc[field]);
        }
      }
    }
  });
}
