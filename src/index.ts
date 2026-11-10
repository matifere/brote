import http from "node:http";
import { config } from "./config.js";
import { testPostgres, closePostgres } from "./services/postgres.js";
import { testStorage } from "./services/storage.js";
import { testAuth } from "./services/auth.js";
import { testFunctions } from "./services/functions.js";
import { testRealtime } from "./services/realtime.js";

export async function runAllTests() {
  const results: Record<string, any> = {};

  // 1. Postgres
  try {
    results.postgres = await testPostgres();
  } catch (err: any) {
    results.postgres = { success: false, error: err.message };
  }

  // 2. Storage
  try {
    results.storage = await testStorage();
  } catch (err: any) {
    results.storage = { success: false, error: err.message };
  }

  // 3. Auth
  try {
    results.auth = await testAuth();
  } catch (err: any) {
    results.auth = { success: false, error: err.message };
  }

  // 4. Functions
  try {
    results.functions = await testFunctions();
  } catch (err: any) {
    results.functions = { success: false, error: err.message };
  }

  // 5. Realtime
  try {
    results.realtime = await testRealtime();
  } catch (err: any) {
    results.realtime = { success: false, error: err.message };
  }

  const allPassed = Object.values(results).every((r) => r.success === true);

  return {
    allPassed,
    timestamp: new Date().toISOString(),
    services: results,
  };
}

export function createServer() {
  return http.createServer(async (req, res) => {
    const url = new URL(req.url || "/", `http://${req.headers.host || "localhost"}`);
    res.setHeader("Content-Type", "application/json");

    try {
      if (url.pathname === "/" || url.pathname === "/api/health") {
        res.statusCode = 200;
        res.end(
          JSON.stringify({
            status: "ok",
            app: "Brote Neon Backend",
            branch: config.neonBranch,
            routes: [
              "/api/health",
              "/api/postgres",
              "/api/storage",
              "/api/auth",
              "/api/functions",
              "/api/realtime",
              "/api/test-all",
            ],
          })
        );
        return;
      }

      if (url.pathname === "/api/postgres") {
        const data = await testPostgres();
        res.statusCode = 200;
        res.end(JSON.stringify(data));
        return;
      }

      if (url.pathname === "/api/storage") {
        const data = await testStorage();
        res.statusCode = 200;
        res.end(JSON.stringify(data));
        return;
      }

      if (url.pathname === "/api/auth") {
        const data = await testAuth();
        res.statusCode = 200;
        res.end(JSON.stringify(data));
        return;
      }

      if (url.pathname === "/api/functions") {
        const data = await testFunctions();
        res.statusCode = 200;
        res.end(JSON.stringify(data));
        return;
      }

      if (url.pathname === "/api/realtime") {
        const data = await testRealtime();
        res.statusCode = 200;
        res.end(JSON.stringify(data));
        return;
      }

      if (url.pathname === "/api/test-all") {
        const data = await runAllTests();
        res.statusCode = data.allPassed ? 200 : 500;
        res.end(JSON.stringify(data, null, 2));
        return;
      }

      res.statusCode = 404;
      res.end(JSON.stringify({ error: "Not Found", path: url.pathname }));
    } catch (err: any) {
      res.statusCode = 500;
      res.end(JSON.stringify({ error: err.message || "Internal Server Error" }));
    }
  });
}

// Start server if run directly
const isMain = process.argv[1]?.endsWith("index.js") || process.argv[1]?.endsWith("index.ts");
if (isMain) {
  const server = createServer();
  server.listen(config.port, () => {
    console.log(`[Brote Neon Backend] Server listening on http://localhost:${config.port}`);
  });

  const cleanup = async () => {
    console.log("\nShutting down server...");
    await closePostgres();
    server.close(() => {
      process.exit(0);
    });
  };

  process.on("SIGINT", cleanup);
  process.on("SIGTERM", cleanup);
}
