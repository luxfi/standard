import type { DekStore } from '../types';

/**
 * PostgreSQL-backed DEK store — works with pg, pgx, Knex, Drizzle, or Base PostgreSQL mode.
 *
 * Creates a `customer_keys` table automatically.
 * Pass any object with a `query(sql, params)` method (pg.Pool, pg.Client, Knex raw, etc.)
 */
export class PostgresDekStore implements DekStore {
  private pool: any;
  private initialized = false;

  constructor(pool: any) {
    this.pool = pool;
  }

  private async init(): Promise<void> {
    if (this.initialized) return;
    await this.pool.query(`
      CREATE TABLE IF NOT EXISTS customer_keys (
        customer_id TEXT PRIMARY KEY,
        wrapped_dek BYTEA NOT NULL,
        created_at TIMESTAMPTZ DEFAULT NOW(),
        rotated_at TIMESTAMPTZ DEFAULT NOW()
      )
    `);
    this.initialized = true;
  }

  async get(customerId: string): Promise<Buffer | null> {
    await this.init();
    const result = await this.pool.query(
      'SELECT wrapped_dek FROM customer_keys WHERE customer_id = $1',
      [customerId]
    );
    const row = result?.rows?.[0];
    return row ? Buffer.from(row.wrapped_dek) : null;
  }

  async set(customerId: string, wrappedDek: Buffer): Promise<void> {
    await this.init();
    await this.pool.query(`
      INSERT INTO customer_keys (customer_id, wrapped_dek, rotated_at)
      VALUES ($1, $2, NOW())
      ON CONFLICT (customer_id) DO UPDATE SET wrapped_dek = $2, rotated_at = NOW()
    `, [customerId, wrappedDek]);
  }

  async delete(customerId: string): Promise<void> {
    await this.init();
    await this.pool.query(
      'DELETE FROM customer_keys WHERE customer_id = $1',
      [customerId]
    );
  }
}
