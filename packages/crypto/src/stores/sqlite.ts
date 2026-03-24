import type { DekStore } from '../types';

/**
 * SQLite-backed DEK store — works with Base (all modes) and standalone better-sqlite3.
 *
 * Creates a `customer_keys` table automatically on first use.
 * Compatible with:
 *   - Base SQLite mode (production + dev)
 *   - Base PostgreSQL mode (uses the same SQL, dialect-compatible)
 *   - Standalone better-sqlite3 / sql.js
 *
 * Expects a `db` object with exec/prepare or query methods.
 * Pass the raw better-sqlite3 Database instance or a Base dbx.Builder.
 */
export class SqliteDekStore implements DekStore {
  private db: any;
  private initialized = false;

  constructor(db: any) {
    this.db = db;
  }

  private async init(): Promise<void> {
    if (this.initialized) return;
    // Works for both SQLite and PostgreSQL (BLOB = BYTEA in PG)
    const sql = `
      CREATE TABLE IF NOT EXISTS customer_keys (
        customer_id TEXT PRIMARY KEY,
        wrapped_dek BLOB NOT NULL,
        created_at TEXT DEFAULT (datetime('now')),
        rotated_at TEXT DEFAULT (datetime('now'))
      )
    `;

    if (typeof this.db.exec === 'function') {
      // better-sqlite3 sync API
      this.db.exec(sql);
    } else if (typeof this.db.run === 'function') {
      // async driver (e.g., Base dbx)
      await this.db.run(sql);
    } else if (typeof this.db.query === 'function') {
      // node-postgres / pgx style
      await this.db.query(sql);
    }
    this.initialized = true;
  }

  async get(customerId: string): Promise<Buffer | null> {
    await this.init();

    if (typeof this.db.prepare === 'function') {
      // better-sqlite3 sync
      const stmt = this.db.prepare('SELECT wrapped_dek FROM customer_keys WHERE customer_id = ?');
      const row = stmt.get(customerId) as any;
      return row ? Buffer.from(row.wrapped_dek) : null;
    }

    // async driver
    const result = await this.db.query(
      'SELECT wrapped_dek FROM customer_keys WHERE customer_id = $1',
      [customerId]
    );
    const row = result?.rows?.[0] ?? result?.[0];
    return row ? Buffer.from(row.wrapped_dek) : null;
  }

  async set(customerId: string, wrappedDek: Buffer): Promise<void> {
    await this.init();

    const sql = `
      INSERT INTO customer_keys (customer_id, wrapped_dek, rotated_at)
      VALUES ($1, $2, datetime('now'))
      ON CONFLICT (customer_id) DO UPDATE SET wrapped_dek = $2, rotated_at = datetime('now')
    `;

    if (typeof this.db.prepare === 'function') {
      // better-sqlite3 — uses ? placeholders
      const syncSql = sql.replace(/\$1/g, '?').replace(/\$2/g, '?');
      this.db.prepare(syncSql).run(customerId, wrappedDek);
      return;
    }

    await this.db.query(sql, [customerId, wrappedDek]);
  }

  async delete(customerId: string): Promise<void> {
    await this.init();

    if (typeof this.db.prepare === 'function') {
      this.db.prepare('DELETE FROM customer_keys WHERE customer_id = ?').run(customerId);
      return;
    }

    await this.db.query('DELETE FROM customer_keys WHERE customer_id = $1', [customerId]);
  }
}
