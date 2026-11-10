import { Pool } from "pg";
import { config } from "../config.js";

let pool: Pool | null = null;

export function getPostgresPool(): Pool {
  if (!pool) {
    if (!config.databaseUrl) {
      throw new Error("DATABASE_URL is not set in environment.");
    }
    pool = new Pool({
      connectionString: config.databaseUrl,
      ssl: { rejectUnauthorized: false },
      max: 10,
      idleTimeoutMillis: 30000,
    });
    // Prevent idle connection errors (e.g. when compute scales to zero) from crashing process
    pool.on("error", (err: Error) => {
      console.error("Unexpected error on idle Postgres client:", err.message);
    });
  }
  return pool;
}

export async function testPostgres(): Promise<{
  success: boolean;
  database: string;
  user: string;
  version: string;
  currentTime: string;
}> {
  const p = getPostgresPool();
  const client = await p.connect();
  try {
    const res = await client.query(
      "SELECT current_database() as db, current_user as usr, version(), now() as current_time"
    );
    const row = res.rows[0];
    return {
      success: true,
      database: row.db,
      user: row.usr,
      version: row.version,
      currentTime: row.current_time.toISOString(),
    };
  } finally {
    client.release();
  }
}

export async function closePostgres(): Promise<void> {
  if (pool) {
    await pool.end();
    pool = null;
  }
}
