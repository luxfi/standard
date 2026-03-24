import type { DekStore } from '../types';

/**
 * MongoDB-backed DEK store — works with native MongoDB driver or Mongoose.
 *
 * Pass a MongoDB Collection instance (db.collection('customer_keys')).
 * Creates an index on customer_id automatically.
 */
export class MongoDekStore implements DekStore {
  private collection: any;
  private initialized = false;

  constructor(collection: any) {
    this.collection = collection;
  }

  private async init(): Promise<void> {
    if (this.initialized) return;
    await this.collection.createIndex(
      { customer_id: 1 },
      { unique: true, background: true }
    );
    this.initialized = true;
  }

  async get(customerId: string): Promise<Buffer | null> {
    await this.init();
    const doc = await this.collection.findOne({ customer_id: customerId });
    if (!doc?.wrapped_dek) return null;
    // Handle both Buffer and Binary types
    return Buffer.from(doc.wrapped_dek.buffer ?? doc.wrapped_dek);
  }

  async set(customerId: string, wrappedDek: Buffer): Promise<void> {
    await this.init();
    await this.collection.updateOne(
      { customer_id: customerId },
      {
        $set: {
          wrapped_dek: wrappedDek,
          rotated_at: new Date(),
        },
        $setOnInsert: {
          created_at: new Date(),
        },
      },
      { upsert: true }
    );
  }

  async delete(customerId: string): Promise<void> {
    await this.init();
    await this.collection.deleteOne({ customer_id: customerId });
  }
}
