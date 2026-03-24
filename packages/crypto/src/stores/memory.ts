import {DekStore} from '../types';

/**
 * In-memory DEK store. Suitable for tests and single-process dev.
 * In production, use a database-backed DekStore.
 */
export class InMemoryDekStore implements DekStore {
  private readonly store = new Map<string, Buffer>();

  async get(customerId: string): Promise<Buffer | null> {
    return this.store.get(customerId) ?? null;
  }

  async set(customerId: string, wrappedDek: Buffer): Promise<void> {
    this.store.set(customerId, wrappedDek);
  }

  async delete(customerId: string): Promise<void> {
    this.store.delete(customerId);
  }
}
