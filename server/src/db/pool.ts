import { Pool, PoolClient, QueryResultRow } from 'pg';
import { config } from '../config';

export const pool = new Pool({
  host: config.db.host,
  port: config.db.port,
  database: config.db.database,
  user: config.db.user,
  password: config.db.password,
  max: config.db.maxConnections,
  idleTimeoutMillis: 30_000,
  // Resolve every unqualified table/query against the app's own schema first,
  // then public (so built-in/extension functions still resolve). Applied at
  // connection start so it holds for every pooled connection.
  options: `-c search_path=${config.db.schema},public`,
});

/**
 * Wait until the database is reachable before proceeding. On a fresh deploy the
 * app can start before Docker's embedded DNS / an external network attachment
 * (e.g. reaching Supabase's `supabase-db` across the shared network) is ready,
 * so the first connection can fail transiently with EAI_AGAIN/ENOTFOUND/
 * ECONNREFUSED. Retry with a short delay instead of crashing on the first try.
 */
export async function waitForDatabase(retries = 20, delayMs = 2000): Promise<void> {
  for (let attempt = 1; ; attempt++) {
    try {
      await pool.query('SELECT 1');
      if (attempt > 1) console.log(`[db] connected after ${attempt} attempts`);
      return;
    } catch (err) {
      const e = err as Error & { code?: string };
      if (attempt >= retries) throw err;
      console.warn(
        `[db] not ready (attempt ${attempt}/${retries}): ${e.code ?? e.message} — retrying in ${delayMs}ms`,
      );
      await new Promise((resolve) => setTimeout(resolve, delayMs));
    }
  }
}

export async function query<T extends QueryResultRow = QueryResultRow>(
  text: string,
  params: unknown[] = [],
): Promise<T[]> {
  const result = await pool.query<T>(text, params);
  return result.rows;
}

export async function queryOne<T extends QueryResultRow = QueryResultRow>(
  text: string,
  params: unknown[] = [],
): Promise<T | null> {
  const rows = await query<T>(text, params);
  return rows[0] ?? null;
}

/** Run `fn` inside a transaction; rolls back on any thrown error. */
export async function withTransaction<T>(fn: (client: PoolClient) => Promise<T>): Promise<T> {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    const result = await fn(client);
    await client.query('COMMIT');
    return result;
  } catch (err) {
    await client.query('ROLLBACK');
    throw err;
  } finally {
    client.release();
  }
}
