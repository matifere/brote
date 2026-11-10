import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { Pool } from "pg";
import { config } from "../config.js";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

export async function runMigrations() {
  const connectionString = (config.databaseUrlUnpooled || config.databaseUrl).replace(
    "sslmode=require",
    "sslmode=verify-full"
  );

  console.log("Connecting to Postgres for migration...");
  const pool = new Pool({
    connectionString,
    ssl: { rejectUnauthorized: false },
    max: 1,
  });

  const client = await pool.connect();
  try {
    const migrationFile = path.resolve(__dirname, "../../migrations/0001_initial_schema.sql");
    console.log(`Reading migration: ${migrationFile}`);
    const sql = fs.readFileSync(migrationFile, "utf8");

    console.log("Applying migration 0001_initial_schema.sql...");
    await client.query(sql);
    console.log("✓ Migration executed successfully!");
  } finally {
    client.release();
    await pool.end();
  }
}

// If run directly
const isMain = process.argv[1]?.endsWith("migrate.ts") || process.argv[1]?.endsWith("migrate.js");
if (isMain) {
  runMigrations()
    .then(() => {
      console.log("Database schema is up to date.");
      process.exit(0);
    })
    .catch((err) => {
      console.error("Migration failed:", err);
      process.exit(1);
    });
}
