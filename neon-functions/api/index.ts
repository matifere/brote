import { Hono } from "hono";
import { cors } from "hono/cors";
import { Pool } from "pg";

const app = new Hono();

app.use(
  "*",
  cors({
    origin: "*",
    allowHeaders: ["authorization", "content-type", "x-requested-with"],
    allowMethods: ["GET", "POST", "PUT", "DELETE", "OPTIONS"],
  })
);

let pool: Pool | null = null;
function getPool(): Pool {
  if (!pool) {
    const connStr = (process.env.DATABASE_URL || "").replace("sslmode=require", "sslmode=verify-full");
    pool = new Pool({
      connectionString: connStr,
      ssl: { rejectUnauthorized: false },
      max: 5,
    });
    pool.on("error", (err) => console.error("Postgres pool error:", err.message));
  }
  return pool;
}

const getAuthBaseUrl = () => {
  return (
    process.env.NEON_AUTH_BASE_URL ||
    "https://ep-nameless-salad-bei0ptj4.neonauth.c-9.us-east-2.aws.neon.tech/neondb/auth"
  );
};

// Health checks
app.get("/", (c) => c.json({ status: "ok", service: "Brote API (Neon Functions)" }));
app.get("/api/health", (c) => c.json({ status: "ok", service: "Brote API (Neon Functions)" }));

// Register endpoint
app.post("/api/auth/register", async (c) => {
  try {
    const body = await c.req.json();
    const username = (body.username || "").trim().toLowerCase();
    const displayName = (body.displayName || body.username || "").trim();
    const password = body.password;

    if (!username || username.length < 3) {
      return c.json({ success: false, error: "El nombre de usuario debe tener al menos 3 caracteres." }, 400);
    }
    if (!/^[a-z0-9_]+$/.test(username)) {
      return c.json({ success: false, error: "El nombre de usuario solo puede contener letras, números y guión bajo." }, 400);
    }
    if (!displayName) {
      return c.json({ success: false, error: "El nombre a mostrar es obligatorio." }, 400);
    }
    if (!password || password.length < 6) {
      return c.json({ success: false, error: "La contraseña debe tener al menos 6 caracteres." }, 400);
    }

    const p = getPool();
    const existing = await p.query(
      "SELECT id FROM public.profiles WHERE lower(username) = $1 LIMIT 1",
      [username]
    );
    if (existing.rows.length > 0) {
      return c.json({ success: false, error: "El nombre de usuario ya está registrado." }, 400);
    }

    const email = (body.email?.trim() || `${username}@brote.app`).toLowerCase();
    const authBaseUrl = getAuthBaseUrl();

    const authRes = await fetch(`${authBaseUrl}/sign-up/email`, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Origin: "https://brote.app",
      },
      body: JSON.stringify({
        email,
        password,
        name: displayName,
      }),
    });

    const authData = (await authRes.json()) as any;
    if (!authRes.ok) {
      return c.json({ success: false, error: authData.message || "Error al registrar en Neon Auth." }, 400);
    }

    const userId = authData.user.id;
    const token = authData.token;

    await p.query(
      `INSERT INTO public.profiles (id, username, display_name)
       VALUES ($1, $2, $3)
       ON CONFLICT (id) DO UPDATE
       SET username = EXCLUDED.username, display_name = EXCLUDED.display_name, updated_at = now()`,
      [userId, username, displayName]
    );

    const profileRes = await p.query(
      "SELECT id, username, display_name, bio, avatar_url FROM public.profiles WHERE id = $1",
      [userId]
    );
    const profile = profileRes.rows[0];

    return c.json({
      success: true,
      token,
      user: { id: userId, email: authData.user.email, name: authData.user.name },
      profile: {
        id: profile.id,
        username: profile.username,
        displayName: profile.display_name,
        bio: profile.bio,
        avatarUrl: profile.avatar_url,
      },
    }, 201);
  } catch (err: any) {
    return c.json({ success: false, error: err.message || "Error en el servidor" }, 500);
  }
});

// Login endpoint
app.post("/api/auth/login", async (c) => {
  try {
    const body = await c.req.json();
    const queryParam = (body.username || body.email || "").trim();
    const password = body.password;

    if (!queryParam) {
      return c.json({ success: false, error: "Debes ingresar tu usuario o email." }, 400);
    }
    if (!password) {
      return c.json({ success: false, error: "Debes ingresar la contraseña." }, 400);
    }

    const p = getPool();
    let email = queryParam.toLowerCase();

    if (!queryParam.includes("@")) {
      const userRes = await p.query(
        `SELECT u.email, p.id, p.username, p.display_name, p.bio, p.avatar_url
         FROM public.profiles p
         INNER JOIN neon_auth.user u ON p.id = u.id
         WHERE lower(p.username) = lower($1)
         LIMIT 1`,
        [queryParam]
      );
      if (userRes.rows.length === 0) {
        return c.json({ success: false, error: "Usuario o contraseña incorrectos." }, 400);
      }
      email = userRes.rows[0].email;
    }

    const authBaseUrl = getAuthBaseUrl();
    const authRes = await fetch(`${authBaseUrl}/sign-in/email`, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Origin: "https://brote.app",
      },
      body: JSON.stringify({ email, password }),
    });

    const authData = (await authRes.json()) as any;
    if (!authRes.ok) {
      return c.json({ success: false, error: "Usuario o contraseña incorrectos." }, 400);
    }

    const userId = authData.user.id;
    const token = authData.token;

    const profileRes = await p.query(
      "SELECT id, username, display_name, bio, avatar_url FROM public.profiles WHERE id = $1",
      [userId]
    );
    const profile = profileRes.rows[0] || {
      id: userId,
      username: queryParam,
      display_name: authData.user.name,
      bio: null,
      avatarUrl: null,
    };

    return c.json({
      success: true,
      token,
      user: { id: userId, email: authData.user.email, name: authData.user.name },
      profile: {
        id: profile.id,
        username: profile.username,
        displayName: profile.display_name,
        bio: profile.bio,
        avatarUrl: profile.avatar_url,
      },
    }, 200);
  } catch (err: any) {
    return c.json({ success: false, error: err.message || "Error en el servidor" }, 500);
  }
});

// Current user session validation endpoint
app.get("/api/auth/me", async (c) => {
  try {
    const authHeader = c.req.header("authorization") || "";
    const token = authHeader.replace(/^Bearer\s+/i, "") || c.req.query("token");

    if (!token) {
      return c.json({ success: false, error: "No se proporcionó token de sesión" }, 401);
    }

    const p = getPool();
    const res = await p.query(
      `SELECT s.token, u.id, u.email, u.name, p.username, p.display_name, p.bio, p.avatar_url
       FROM neon_auth.session s
       INNER JOIN neon_auth.user u ON s."userId" = u.id
       INNER JOIN public.profiles p ON u.id = p.id
       WHERE s.token = $1 AND s."expiresAt" > now()
       LIMIT 1`,
      [token]
    );

    if (res.rows.length === 0) {
      return c.json({ success: false, error: "Sesión inválida o expirada" }, 401);
    }

    const row = res.rows[0];
    return c.json({
      success: true,
      token: row.token,
      user: { id: row.id, email: row.email, name: row.name },
      profile: {
        id: row.id,
        username: row.username,
        displayName: row.display_name,
        bio: row.bio,
        avatarUrl: row.avatar_url,
      },
    });
  } catch (err: any) {
    return c.json({ success: false, error: err.message || "Error en el servidor" }, 500);
  }
});

export default app;
