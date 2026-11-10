import http from "node:http";
import { config } from "./config.js";
import { testPostgres, closePostgres } from "./services/postgres.js";
import { testStorage } from "./services/storage.js";
import { testAuth, registerUser, loginUser, validateSession } from "./services/auth.js";
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

async function parseJsonBody(req: http.IncomingMessage): Promise<any> {
  return new Promise((resolve, reject) => {
    let body = "";
    req.on("data", (chunk) => {
      body += chunk;
      if (body.length > 1e6) {
        // 1MB max body limit
        req.destroy();
        reject(new Error("Request payload too large"));
      }
    });
    req.on("end", () => {
      if (!body) {
        resolve({});
        return;
      }
      try {
        resolve(JSON.parse(body));
      } catch (e: any) {
        reject(new Error("Invalid JSON body"));
      }
    });
    req.on("error", reject);
  });
}

export function createServer() {
  return http.createServer(async (req, res) => {
    // CORS headers for Web and mobile
    res.setHeader("Access-Control-Allow-Origin", "*");
    res.setHeader("Access-Control-Allow-Methods", "GET, POST, PUT, DELETE, OPTIONS");
    res.setHeader("Access-Control-Allow-Headers", "Content-Type, Authorization, Origin");

    if (req.method === "OPTIONS") {
      res.statusCode = 204;
      res.end();
      return;
    }

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
              "/api/auth/register",
              "/api/auth/login",
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

      // User Registration
      if (url.pathname === "/api/auth/register" && req.method === "POST") {
        const body = await parseJsonBody(req);
        const result = await registerUser({
          username: body.username,
          password: body.password,
          displayName: body.displayName || body.username,
          email: body.email,
        });
        res.statusCode = 201;
        res.end(JSON.stringify({ success: true, ...result }));
        return;
      }

      // User Login
      if (url.pathname === "/api/auth/login" && req.method === "POST") {
        const body = await parseJsonBody(req);
        const result = await loginUser(body.username || body.email, body.password);
        res.statusCode = 200;
        res.end(JSON.stringify({ success: true, ...result }));
        return;
      }

      // Validate session / Current user
      if (url.pathname === "/api/auth/me" && req.method === "GET") {
        const authHeader = req.headers["authorization"] || "";
        const token = authHeader.replace(/^Bearer\s+/i, "") || (url.searchParams.get("token") || "");
        if (!token) {
          res.statusCode = 401;
          res.end(JSON.stringify({ success: false, error: "No se proporcionó token de sesión" }));
          return;
        }
        const result = await validateSession(token);
        if (!result) {
          res.statusCode = 401;
          res.end(JSON.stringify({ success: false, error: "Sesión inválida o expirada" }));
          return;
        }
        res.statusCode = 200;
        res.end(JSON.stringify({ success: true, ...result }));
        return;
      }

      // Service Tests
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
      res.statusCode = 400;
      res.end(JSON.stringify({ success: false, error: err.message || "Error en la solicitud" }));
    }
  });
}

// Start server if run directly
const isMain = process.argv[1]?.endsWith("index.js") || process.argv[1]?.endsWith("index.ts");
if (isMain) {
  const server = createServer();
  server.listen(config.port, "0.0.0.0", () => {
    console.log(`[Brote Neon Backend] Server listening on http://0.0.0.0:${config.port}`);
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
