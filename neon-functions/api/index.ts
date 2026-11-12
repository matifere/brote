import crypto from "node:crypto";
import { Hono } from "hono";
import { cors } from "hono/cors";
import { Pool } from "pg";
import { S3Client, PutObjectCommand, GetObjectCommand } from "@aws-sdk/client-s3";

const app = new Hono();

app.use(
  "*",
  cors({
    origin: "*",
    allowHeaders: ["authorization", "content-type", "x-requested-with"],
    allowMethods: ["GET", "POST", "PUT", "DELETE", "OPTIONS"],
  })
);

let s3Client: S3Client | null = null;
function getS3(): S3Client {
  if (!s3Client) {
    const endpoint = process.env.AWS_ENDPOINT_URL_S3;
    const region = process.env.AWS_REGION || "us-east-2";
    const accessKeyId = process.env.AWS_ACCESS_KEY_ID || "";
    const secretAccessKey = process.env.AWS_SECRET_ACCESS_KEY || "";
    s3Client = new S3Client({
      forcePathStyle: true,
      region,
      endpoint,
      credentials: {
        accessKeyId,
        secretAccessKey,
      },
    });
  }
  return s3Client;
}

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
      "SELECT id, username, display_name, bio, avatar_url, COALESCE(banner_url, header_url) as banner_url, role, is_suspended FROM public.profiles WHERE id = $1",
      [userId]
    );
    const profile = profileRes.rows[0] || {
      id: userId,
      username: queryParam,
      display_name: authData.user.name,
      bio: null,
      avatarUrl: null,
      bannerUrl: null,
      role: "user",
      is_suspended: false,
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
        bannerUrl: profile.banner_url,
        role: profile.role || "user",
        isSuspended: Boolean(profile.is_suspended),
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
      `SELECT s.token, u.id, u.email, u.name, p.username, p.display_name, p.bio, p.avatar_url, COALESCE(p.banner_url, p.header_url) as banner_url, p.role, p.is_suspended
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
        bannerUrl: row.banner_url,
        role: row.role || "user",
        isSuspended: Boolean(row.is_suspended),
      },
    });
  } catch (err: any) {
    return c.json({ success: false, error: err.message || "Error en el servidor" }, 500);
  }
});

// Helper for session token verification
async function getAuthenticatedUser(c: any): Promise<{ userId: string; email: string; token: string } | null> {
  const authHeader = c.req.header("authorization") || "";
  const token = authHeader.replace(/^Bearer\s+/i, "") || c.req.query("token");
  if (!token) return null;

  const p = getPool();
  const res = await p.query(
    `SELECT s.token, u.id, u.email
     FROM neon_auth.session s
     INNER JOIN neon_auth.user u ON s."userId" = u.id
     WHERE s.token = $1 AND s."expiresAt" > now()
     LIMIT 1`,
    [token]
  );
  if (res.rows.length === 0) return null;
  return {
    userId: res.rows[0].id,
    email: res.rows[0].email,
    token: res.rows[0].token,
  };
}

// --- MODERATION HEURISTICS & RULES ---
function normalizeModerationText(text: string): string {
  if (!text) return "";
  let s = text.toLowerCase().normalize("NFD").replace(/[\u0300-\u036f]/g, "");
  const leetMap: Record<string, string> = {
    "0": "o",
    "1": "i",
    "!": "i",
    "|": "i",
    "3": "e",
    "4": "a",
    "@": "a",
    "5": "s",
    "$": "s",
    "7": "t",
    "+": "t",
    "8": "b",
    "9": "g",
  };
  s = s.replace(/[01!|34@5$7+89]/g, (m) => leetMap[m] || m);
  return s;
}

function checkContentModeration(rawText: string): { allowed: boolean; reason?: string } {
  if (!rawText) return { allowed: true };
  const normalized = normalizeModerationText(rawText);
  const compressed = normalized.replace(/[^a-z0-9]/g, "");

  // Critical harmful patterns: CSAM / Child exploitation (Zero tolerance)
  const criticalHarms = [
    /p[e3]d[o0]f[i1l]/i,
    /pornografiainfantil/i,
    /childporn/i,
    /\bcp\s*(link|mega|drive|pack|descarga)\b/i,
    /violacioninfantil/i,
    /abuso.*menor/i,
    /abuso.*infantil/i,
  ];

  for (const pattern of criticalHarms) {
    if (pattern.test(normalized) || pattern.test(compressed)) {
      return {
        allowed: false,
        reason: "Tu contenido fue rechazado por infringir las políticas de seguridad infantil.",
      };
    }
  }

  // Violence, terrorism, suicide incitement
  const violencePatterns = [
    /\b(matate|suicidate)\b/i,
    /\b(tiroteo\s+escolar|school\s+shooting)\b/i,
    /\b(fabricar\s+bomba|hacer\s+bomba|fabricar\s+explosivos)\b/i,
    /\b(atentado\s+terrorista|isis\s+execution)\b/i,
  ];

  for (const pattern of violencePatterns) {
    if (pattern.test(normalized)) {
      return {
        allowed: false,
        reason: "Tu publicación contiene incitación a la violencia o daño físico.",
      };
    }
  }

  // Phishing / Scam / Crypto spam
  const scamPatterns = [
    /\b(gana|ganar)\s+dinero\s+(facil|rapido|sin\s+esfuerzo)\b/i,
    /\b(inversion|ganancia)\s+garantizada\b/i,
    /\b(duplica|multiplica)\s+tus\s+(usdt|cripto|btc|dolares)\b/i,
    /\b(t\.me\/|wa\.me\/|telegram\s*:\s*@)/i,
    /\b(free\s+crypto|claim\s+airdrop)\b/i,
    /\b(onlyfans\s+leaked|hacks?\s+de\s+cuentas)\b/i,
  ];

  for (const pattern of scamPatterns) {
    if (pattern.test(normalized)) {
      return {
        allowed: false,
        reason: "El contenido parece spam o intento de estafa financiera / enlaces no permitidos.",
      };
    }
  }

  return { allowed: true };
}

async function verifyUserPostPermission(p: Pool, userId: string, type: "post" | "comment"): Promise<{ allowed: boolean; error?: string }> {
  const profRes = await p.query(
    "SELECT is_suspended, role FROM public.profiles WHERE id = $1",
    [userId]
  );
  if (profRes.rows.length === 0) {
    return { allowed: false, error: "Usuario no encontrado" };
  }
  const row = profRes.rows[0];
  if (row.is_suspended) {
    return { allowed: false, error: "Tu cuenta ha sido suspendida por infringir las normas comunitarias." };
  }
  if (row.role === "admin") {
    return { allowed: true };
  }

  if (type === "post") {
    const rateRes = await p.query(
      "SELECT COUNT(*)::int as cnt FROM public.posts WHERE author_id = $1 AND created_at > now() - interval '1 minute'",
      [userId]
    );
    if ((rateRes.rows[0]?.cnt ?? 0) >= 5) {
      return { allowed: false, error: "Estás publicando demasiado rápido. Esperá un momento." };
    }
  } else {
    const rateRes = await p.query(
      "SELECT COUNT(*)::int as cnt FROM public.post_comments WHERE author_id = $1 AND created_at > now() - interval '1 minute'",
      [userId]
    );
    if ((rateRes.rows[0]?.cnt ?? 0) >= 10) {
      return { allowed: false, error: "Estás comentando demasiado rápido. Esperá un momento." };
    }
  }

  return { allowed: true };
}

async function requireAdminUser(c: any): Promise<{ userId: string; role: string; p: Pool } | null> {
  const auth = await getAuthenticatedUser(c);
  if (!auth) return null;
  const p = getPool();
  const res = await p.query("SELECT role FROM public.profiles WHERE id = $1", [auth.userId]);
  const role = res.rows[0]?.role || "user";
  if (role !== "admin" && role !== "moderator") return null;
  return { userId: auth.userId, role, p };
}

// Helper to construct rich profile payload with follow counts and privacy status
async function buildProfilePayload(p: any, profileRow: any, viewerId?: string | null) {
  if (!profileRow) return null;
  const profileId = profileRow.id;

  const countsRes = await p.query(
    `SELECT
      (SELECT COUNT(*)::int FROM public.follows WHERE following_id = $1 AND status = 'accepted') as followers_count,
      (SELECT COUNT(*)::int FROM public.follows WHERE follower_id = $1 AND status = 'accepted') as following_count`,
    [profileId]
  );
  const followersCount = countsRes.rows[0]?.followers_count ?? 0;
  const followingCount = countsRes.rows[0]?.following_count ?? 0;

  let followStatus: "none" | "pending" | "accepted" = "none";
  let isFollowedBy = false;
  let canViewContent = true;

  const isOwner = Boolean(viewerId && viewerId === profileId);
  const isPrivate = Boolean(profileRow.is_private);

  let pendingRequestsCount = 0;
  if (isOwner) {
    const reqRes = await p.query(
      `SELECT COUNT(*)::int as count FROM public.follows WHERE following_id = $1 AND status = 'pending'`,
      [profileId]
    );
    pendingRequestsCount = reqRes.rows[0]?.count ?? 0;
  }

  let isBlocked = false;
  if (viewerId && !isOwner) {
    const blockRes = await p.query(
      `SELECT 1 FROM public.blocks
       WHERE (blocker_id = $1 AND blocked_id = $2)
          OR (blocker_id = $2 AND blocked_id = $1)
       LIMIT 1`,
      [viewerId, profileId]
    );
    if (blockRes.rows.length > 0) {
      isBlocked = true;
      canViewContent = false;
    }

    const relRes = await p.query(
      `SELECT
        (SELECT status FROM public.follows WHERE follower_id = $1 AND following_id = $2) as my_status,
        (SELECT 1 FROM public.follows WHERE follower_id = $2 AND following_id = $1 AND status = 'accepted') as their_status`,
      [viewerId, profileId]
    );
    const relRow = relRes.rows[0];
    if (relRow?.my_status) {
      followStatus = relRow.my_status;
    }
    if (relRow?.their_status) {
      isFollowedBy = true;
    }
  }

  if (isPrivate && !isOwner && followStatus !== "accepted") {
    canViewContent = false;
  }

  return {
    id: profileRow.id,
    username: profileRow.username,
    displayName: profileRow.display_name,
    bio: profileRow.bio,
    avatarUrl: profileRow.avatar_url,
    bannerUrl: profileRow.banner_url,
    role: profileRow.role || "user",
    isSuspended: Boolean(profileRow.is_suspended),
    isPrivate,
    isVerified: Boolean(profileRow.is_verified),
    followersCount,
    followingCount,
    pendingRequestsCount,
    followStatus,
    isFollowedBy,
    canViewContent,
    isBlocked,
  };
}

// Read own profile
app.get("/api/profile/me", async (c) => {
  try {
    const auth = await getAuthenticatedUser(c);
    if (!auth) {
      return c.json({ success: false, error: "No autorizado o sesión expirada" }, 401);
    }

    const p = getPool();
    const profileRes = await p.query(
      "SELECT id, username, display_name, bio, avatar_url, COALESCE(banner_url, header_url) as banner_url, is_private, is_verified, role, is_suspended FROM public.profiles WHERE id = $1",
      [auth.userId]
    );
    if (profileRes.rows.length === 0) {
      return c.json({ success: false, error: "Perfil no encontrado" }, 404);
    }
    const profile = await buildProfilePayload(p, profileRes.rows[0], auth.userId);

    return c.json({
      success: true,
      profile,
    });
  } catch (err: any) {
    return c.json({ success: false, error: err.message || "Error al obtener perfil" }, 500);
  }
});

// Update own profile
const updateProfileHandler = async (c: any) => {
  try {
    const auth = await getAuthenticatedUser(c);
    if (!auth) {
      return c.json({ success: false, error: "No autorizado o sesión expirada" }, 401);
    }

    const body = await c.req.json();
    const displayName = (body.displayName ?? "").trim();
    if (!displayName) {
      return c.json({ success: false, error: "El nombre no puede estar vacío." }, 400);
    }
    if (displayName.length > 60) {
      return c.json({ success: false, error: "El nombre no puede superar los 60 caracteres." }, 400);
    }
    if (body.bio && body.bio.length > 300) {
      return c.json({ success: false, error: "La descripción no puede superar los 300 caracteres." }, 400);
    }

    const p = getPool();
    const updates: string[] = ["display_name = $1", "updated_at = now()"];
    const values: any[] = [displayName];
    let paramIndex = 2;

    if (body.bio !== undefined) {
      updates.push(`bio = $${paramIndex++}`);
      values.push(body.bio && body.bio.trim().length > 0 ? body.bio.trim() : null);
    }

    if (body.avatarUrl !== undefined) {
      updates.push(`avatar_url = $${paramIndex++}`);
      values.push(body.avatarUrl && body.avatarUrl.trim().length > 0 ? body.avatarUrl.trim() : null);
    }

    if (body.bannerUrl !== undefined) {
      updates.push(`banner_url = $${paramIndex}`, `header_url = $${paramIndex}`);
      paramIndex++;
      values.push(body.bannerUrl && body.bannerUrl.trim().length > 0 ? body.bannerUrl.trim() : null);
    }

    if (body.isPrivate !== undefined) {
      updates.push(`is_private = $${paramIndex++}`);
      values.push(Boolean(body.isPrivate));
    }

    values.push(auth.userId);
    const sql = `UPDATE public.profiles SET ${updates.join(", ")} WHERE id = $${paramIndex} RETURNING id, username, display_name, bio, avatar_url, COALESCE(banner_url, header_url) as banner_url, is_private, is_verified, role, is_suspended`;
    const updateRes = await p.query(sql, values);

    // Keep auth user name synced
    await p.query(
      `UPDATE neon_auth.user SET name = $1, "updatedAt" = now() WHERE id = $2`,
      [displayName, auth.userId]
    );

    const profile = await buildProfilePayload(p, updateRes.rows[0], auth.userId);
    return c.json({
      success: true,
      profile,
    });
  } catch (err: any) {
    return c.json({ success: false, error: err.message || "Error al actualizar perfil" }, 500);
  }
};

app.put("/api/profile/me", updateProfileHandler);
app.patch("/api/profile/me", updateProfileHandler);

// Upload avatar from device to Neon Object Storage
app.post("/api/profile/avatar", async (c) => {
  try {
    const auth = await getAuthenticatedUser(c);
    if (!auth) {
      return c.json({ success: false, error: "No autorizado o sesión expirada" }, 401);
    }

    let fileBuffer: Buffer | null = null;
    let contentType = "image/jpeg";
    let fileExt = "jpg";

    const reqContentType = c.req.header("content-type") || "";

    if (reqContentType.includes("multipart/form-data")) {
      const body = await c.req.parseBody();
      const file = body["file"] || body["avatar"] || body["image"];
      if (file && typeof file === "object" && "arrayBuffer" in file) {
        const ab = await (file as any).arrayBuffer();
        fileBuffer = Buffer.from(ab);
        contentType = (file as any).type || "image/jpeg";
      }
    } else if (reqContentType.includes("application/json")) {
      const body = await c.req.json();
      if (body.image) {
        const raw = body.image.replace(/^data:image\/\w+;base64,/, "");
        fileBuffer = Buffer.from(raw, "base64");
        contentType = body.mimeType || "image/jpeg";
      }
    } else if (reqContentType.startsWith("image/")) {
      const ab = await c.req.arrayBuffer();
      fileBuffer = Buffer.from(ab);
      contentType = reqContentType;
    }

    if (!fileBuffer || fileBuffer.length === 0) {
      return c.json({ success: false, error: "No se recibió ninguna imagen válida." }, 400);
    }

    // Determine extension
    if (contentType.includes("png")) fileExt = "png";
    else if (contentType.includes("webp")) fileExt = "webp";
    else if (contentType.includes("gif")) fileExt = "gif";
    else fileExt = "jpg";

    const objectKey = `${auth.userId}-${Date.now()}.${fileExt}`;
    const s3 = getS3();

    // Store in Neon Object Storage
    await s3.send(
      new PutObjectCommand({
        Bucket: "avatars",
        Key: objectKey,
        Body: fileBuffer,
        ContentType: contentType,
      })
    );

    // Form public avatar URL via the API proxy
    const host = c.req.header("host") || "br-spring-base-betng0ba-api.compute.c-9.us-east-2.aws.neon.tech";
    const proto = host.includes("localhost") ? "http" : "https";
    const avatarUrl = `${proto}://${host}/api/avatar/${objectKey}`;

    // Update profile in PostgreSQL
    const p = getPool();
    const updateRes = await p.query(
      `UPDATE public.profiles
       SET avatar_url = $1, updated_at = now()
       WHERE id = $2
       RETURNING id, username, display_name, bio, avatar_url, COALESCE(banner_url, header_url) as banner_url`,
      [avatarUrl, auth.userId]
    );

    const profile = updateRes.rows[0];

    return c.json({
      success: true,
      avatarUrl,
      profile: {
        id: profile.id,
        username: profile.username,
        displayName: profile.display_name,
        bio: profile.bio,
        avatarUrl: profile.avatar_url,
        bannerUrl: profile.banner_url,
      },
    }, 200);
  } catch (err: any) {
    console.error("Avatar upload error:", err);
    return c.json({ success: false, error: err.message || "Error al subir la imagen" }, 500);
  }
});

// Serve avatar image from Neon Object Storage
app.get("/api/avatar/:key", async (c) => {
  try {
    const key = c.req.param("key");
    const s3 = getS3();
    const res = await s3.send(
      new GetObjectCommand({
        Bucket: "avatars",
        Key: key,
      })
    );
    const body = await res.Body?.transformToByteArray();
    if (!body) return c.text("Avatar not found", 404);
    return c.body(body, 200, {
      "Content-Type": res.ContentType || "image/jpeg",
      "Cache-Control": "public, max-age=31536000, immutable",
    });
  } catch (err: any) {
    return c.text("Avatar not found", 404);
  }
});

// Upload banner from device to Neon Object Storage
app.post("/api/profile/banner", async (c) => {
  try {
    const auth = await getAuthenticatedUser(c);
    if (!auth) {
      return c.json({ success: false, error: "No autorizado o sesión expirada" }, 401);
    }

    let fileBuffer: Buffer | null = null;
    let contentType = "image/jpeg";
    let fileExt = "jpg";

    const reqContentType = c.req.header("content-type") || "";

    if (reqContentType.includes("multipart/form-data")) {
      const body = await c.req.parseBody();
      const file = body["file"] || body["banner"] || body["image"];
      if (file && typeof file === "object" && "arrayBuffer" in file) {
        const ab = await (file as any).arrayBuffer();
        fileBuffer = Buffer.from(ab);
        contentType = (file as any).type || "image/jpeg";
      }
    } else if (reqContentType.includes("application/json")) {
      const body = await c.req.json();
      if (body.image) {
        const raw = body.image.replace(/^data:image\/\w+;base64,/, "");
        fileBuffer = Buffer.from(raw, "base64");
        contentType = body.mimeType || "image/jpeg";
      }
    } else if (reqContentType.startsWith("image/")) {
      const ab = await c.req.arrayBuffer();
      fileBuffer = Buffer.from(ab);
      contentType = reqContentType;
    }

    if (!fileBuffer || fileBuffer.length === 0) {
      return c.json({ success: false, error: "No se recibió ninguna imagen de banner válida." }, 400);
    }

    if (contentType.includes("png")) fileExt = "png";
    else if (contentType.includes("webp")) fileExt = "webp";
    else if (contentType.includes("gif")) fileExt = "gif";
    else fileExt = "jpg";

    const objectKey = `${auth.userId}-${Date.now()}.${fileExt}`;
    const s3 = getS3();

    // Store in Neon Object Storage
    await s3.send(
      new PutObjectCommand({
        Bucket: "banners",
        Key: objectKey,
        Body: fileBuffer,
        ContentType: contentType,
      })
    );

    const host = c.req.header("host") || "br-spring-base-betng0ba-api.compute.c-9.us-east-2.aws.neon.tech";
    const proto = host.includes("localhost") ? "http" : "https";
    const bannerUrl = `${proto}://${host}/api/banner/${objectKey}`;

    // Update profile in PostgreSQL (setting both banner_url and header_url)
    const p = getPool();
    const updateRes = await p.query(
      `UPDATE public.profiles
       SET banner_url = $1, header_url = $1, updated_at = now()
       WHERE id = $2
       RETURNING id, username, display_name, bio, avatar_url, COALESCE(banner_url, header_url) as banner_url`,
      [bannerUrl, auth.userId]
    );

    const profile = updateRes.rows[0];

    return c.json({
      success: true,
      bannerUrl,
      profile: {
        id: profile.id,
        username: profile.username,
        displayName: profile.display_name,
        bio: profile.bio,
        avatarUrl: profile.avatar_url,
        bannerUrl: profile.banner_url,
      },
    }, 200);
  } catch (err: any) {
    console.error("Banner upload error:", err);
    return c.json({ success: false, error: err.message || "Error al subir el banner" }, 500);
  }
});

// Serve banner image from Neon Object Storage
app.get("/api/banner/:key", async (c) => {
  try {
    const key = c.req.param("key");
    const s3 = getS3();
    const res = await s3.send(
      new GetObjectCommand({
        Bucket: "banners",
        Key: key,
      })
    );
    const body = await res.Body?.transformToByteArray();
    if (!body) return c.text("Banner not found", 404);
    return c.body(body, 200, {
      "Content-Type": res.ContentType || "image/jpeg",
      "Cache-Control": "public, max-age=31536000, immutable",
    });
  } catch (err: any) {
    return c.text("Banner not found", 404);
  }
});

// Search profiles by username or displayName
app.get("/api/profiles/search", async (c) => {
  try {
    const q = (c.req.query("q") || "").trim().toLowerCase();
    if (!q) {
      return c.json({ success: true, results: [] });
    }

    const p = getPool();
    const res = await p.query(
      `SELECT id, username, display_name, bio, avatar_url, COALESCE(banner_url, header_url) as banner_url, is_private, is_verified
       FROM public.profiles
       WHERE lower(username) LIKE $1 OR lower(display_name) LIKE $1
       ORDER BY
         CASE
           WHEN lower(username) = $2 THEN 0
           WHEN lower(username) LIKE $3 THEN 1
           ELSE 2
         END,
         display_name ASC
       LIMIT 30`,
      [`%${q}%`, q, `${q}%`]
    );

    const results = res.rows.map((row) => ({
      id: row.id,
      username: row.username,
      displayName: row.display_name,
      bio: row.bio,
      avatarUrl: row.avatar_url,
      bannerUrl: row.banner_url,
      isPrivate: Boolean(row.is_private),
      isVerified: Boolean(row.is_verified),
    }));

    return c.json({ success: true, results });
  } catch (err: any) {
    return c.json({ success: false, error: err.message || "Error al buscar perfiles" }, 500);
  }
});

// Suggested / recent profiles for discovery
app.get("/api/profiles/suggested", async (c) => {
  try {
    const p = getPool();
    const res = await p.query(
      `SELECT id, username, display_name, bio, avatar_url, COALESCE(banner_url, header_url) as banner_url, is_private, is_verified
       FROM public.profiles
       ORDER BY updated_at DESC NULLS LAST, created_at DESC
       LIMIT 10`
    );

    const results = res.rows.map((row) => ({
      id: row.id,
      username: row.username,
      displayName: row.display_name,
      bio: row.bio,
      avatarUrl: row.avatar_url,
      bannerUrl: row.banner_url,
      isPrivate: Boolean(row.is_private),
      isVerified: Boolean(row.is_verified),
    }));

    return c.json({ success: true, results });
  } catch (err: any) {
    return c.json({ success: false, error: err.message || "Error al obtener sugerencias" }, 500);
  }
});

// Read any user profile by username
app.get("/api/profile/:username", async (c) => {
  try {
    const username = c.req.param("username").toLowerCase();
    const auth = await getAuthenticatedUser(c);
    const p = getPool();
    const res = await p.query(
      "SELECT id, username, display_name, bio, avatar_url, COALESCE(banner_url, header_url) as banner_url, is_private, is_verified, role, is_suspended FROM public.profiles WHERE lower(username) = $1",
      [username]
    );
    if (res.rows.length === 0) {
      return c.json({ success: false, error: "Usuario no encontrado" }, 404);
    }
    const profile = await buildProfilePayload(p, res.rows[0], auth?.userId);
    return c.json({
      success: true,
      profile,
    });
  } catch (err: any) {
    return c.json({ success: false, error: err.message || "Error al buscar perfil" }, 500);
  }
});

// Follow a user (either public => accepted, or private => pending)
app.post("/api/profile/:target/follow", async (c) => {
  try {
    const auth = await getAuthenticatedUser(c);
    if (!auth) {
      return c.json({ success: false, error: "No autorizado o sesión expirada" }, 401);
    }

    const targetParam = c.req.param("target");
    const p = getPool();

    const targetRes = await p.query(
      `SELECT id, username, display_name, bio, avatar_url, COALESCE(banner_url, header_url) as banner_url, is_private, is_verified
       FROM public.profiles
       WHERE id::text = $1 OR lower(username) = lower($1)
       LIMIT 1`,
      [targetParam]
    );

    if (targetRes.rows.length === 0) {
      return c.json({ success: false, error: "Usuario a seguir no encontrado" }, 404);
    }

    const target = targetRes.rows[0];
    if (target.id === auth.userId) {
      return c.json({ success: false, error: "No puedes seguirte a ti mismo" }, 400);
    }

    const targetStatus = target.is_private ? "pending" : "accepted";

    await p.query(
      `INSERT INTO public.follows (follower_id, following_id, status, created_at)
       VALUES ($1, $2, $3, now())
       ON CONFLICT (follower_id, following_id) DO UPDATE
       SET status = EXCLUDED.status, created_at = now()`,
      [auth.userId, target.id, targetStatus]
    );

    await notify(p, {
      recipientId: target.id,
      actorId: auth.userId,
      type: targetStatus === "pending" ? "follow_request" : "follow",
    });

    const profilePayload = await buildProfilePayload(p, target, auth.userId);
    return c.json({
      success: true,
      status: targetStatus,
      isFollowing: targetStatus === "accepted",
      isPending: targetStatus === "pending",
      profile: profilePayload,
    });
  } catch (err: any) {
    return c.json({ success: false, error: err.message || "Error al seguir al usuario" }, 500);
  }
});

// Unfollow a user or cancel follow request
app.post("/api/profile/:target/unfollow", async (c) => {
  try {
    const auth = await getAuthenticatedUser(c);
    if (!auth) {
      return c.json({ success: false, error: "No autorizado o sesión expirada" }, 401);
    }

    const targetParam = c.req.param("target");
    const p = getPool();

    const targetRes = await p.query(
      `SELECT id, username, display_name, bio, avatar_url, COALESCE(banner_url, header_url) as banner_url, is_private, is_verified
       FROM public.profiles
       WHERE id::text = $1 OR lower(username) = lower($1)
       LIMIT 1`,
      [targetParam]
    );

    if (targetRes.rows.length === 0) {
      return c.json({ success: false, error: "Usuario no encontrado" }, 404);
    }

    const target = targetRes.rows[0];

    await p.query(
      `DELETE FROM public.follows
       WHERE follower_id = $1 AND following_id = $2`,
      [auth.userId, target.id]
    );

    await clearNotification(p, { recipientId: target.id, actorId: auth.userId, type: "follow" });
    await clearNotification(p, { recipientId: target.id, actorId: auth.userId, type: "follow_request" });

    const profilePayload = await buildProfilePayload(p, target, auth.userId);
    return c.json({
      success: true,
      status: "none",
      isFollowing: false,
      isPending: false,
      profile: profilePayload,
    });
  } catch (err: any) {
    return c.json({ success: false, error: err.message || "Error al dejar de seguir" }, 500);
  }
});

// View pending follow requests for the authenticated user
app.get("/api/profile/me/follow-requests", async (c) => {
  try {
    const auth = await getAuthenticatedUser(c);
    if (!auth) {
      return c.json({ success: false, error: "No autorizado o sesión expirada" }, 401);
    }

    const p = getPool();
    const res = await p.query(
      `SELECT f.follower_id as id, p.username, p.display_name, p.bio, p.avatar_url, f.created_at
       FROM public.follows f
       INNER JOIN public.profiles p ON f.follower_id = p.id
       WHERE f.following_id = $1 AND f.status = 'pending'
       ORDER BY f.created_at DESC`,
      [auth.userId]
    );

    return c.json({
      success: true,
      requests: res.rows.map((row) => ({
        id: row.id,
        username: row.username,
        displayName: row.display_name,
        bio: row.bio,
        avatarUrl: row.avatar_url,
        createdAt: row.created_at,
      })),
    });
  } catch (err: any) {
    return c.json({ success: false, error: err.message || "Error al obtener solicitudes" }, 500);
  }
});

// Accept a follow request
app.post("/api/profile/follow-requests/:followerId/accept", async (c) => {
  try {
    const auth = await getAuthenticatedUser(c);
    if (!auth) {
      return c.json({ success: false, error: "No autorizado o sesión expirada" }, 401);
    }

    const followerId = c.req.param("followerId");
    const p = getPool();

    const res = await p.query(
      `UPDATE public.follows
       SET status = 'accepted'
       WHERE follower_id = $1 AND following_id = $2 AND status = 'pending'
       RETURNING follower_id`,
      [followerId, auth.userId]
    );

    if (res.rows.length === 0) {
      return c.json({ success: false, error: "Solicitud no encontrada" }, 404);
    }

    await clearNotification(p, { recipientId: auth.userId, actorId: followerId, type: "follow_request" });
    await notify(p, { recipientId: followerId, actorId: auth.userId, type: "follow_accepted" });

    const profileRes = await p.query(
      "SELECT id, username, display_name, bio, avatar_url, COALESCE(banner_url, header_url) as banner_url, is_private, is_verified, role, is_suspended FROM public.profiles WHERE id = $1",
      [auth.userId]
    );
    const updatedProfile = await buildProfilePayload(p, profileRes.rows[0], auth.userId);

    return c.json({
      success: true,
      message: "Solicitud de seguimiento aceptada",
      profile: updatedProfile,
    });
  } catch (err: any) {
    return c.json({ success: false, error: err.message || "Error al aceptar solicitud" }, 500);
  }
});

// Reject a follow request
app.post("/api/profile/follow-requests/:followerId/reject", async (c) => {
  try {
    const auth = await getAuthenticatedUser(c);
    if (!auth) {
      return c.json({ success: false, error: "No autorizado o sesión expirada" }, 401);
    }

    const followerId = c.req.param("followerId");
    const p = getPool();

    const res = await p.query(
      `DELETE FROM public.follows
       WHERE follower_id = $1 AND following_id = $2 AND status = 'pending'
       RETURNING follower_id`,
      [followerId, auth.userId]
    );

    if (res.rows.length === 0) {
      return c.json({ success: false, error: "Solicitud no encontrada" }, 404);
    }

    await clearNotification(p, { recipientId: auth.userId, actorId: followerId, type: "follow_request" });

    const profileRes = await p.query(
      "SELECT id, username, display_name, bio, avatar_url, COALESCE(banner_url, header_url) as banner_url, is_private, is_verified, role, is_suspended FROM public.profiles WHERE id = $1",
      [auth.userId]
    );
    const updatedProfile = await buildProfilePayload(p, profileRes.rows[0], auth.userId);

    return c.json({
      success: true,
      message: "Solicitud de seguimiento rechazada",
      profile: updatedProfile,
    });
  } catch (err: any) {
    return c.json({ success: false, error: err.message || "Error al rechazar solicitud" }, 500);
  }
});

// ==========================================
// PUBLICATIONS / POSTS ENDPOINTS
// ==========================================

// Upload post image to Neon Object Storage
app.post("/api/posts/upload-image", async (c) => {
  try {
    const auth = await getAuthenticatedUser(c);
    if (!auth) {
      return c.json({ success: false, error: "No autorizado o sesión expirada" }, 401);
    }

    let fileBuffer: Buffer | null = null;
    let contentType = "image/jpeg";
    let fileExt = "jpg";
    const reqContentType = c.req.header("content-type") || "";

    if (reqContentType.includes("multipart/form-data")) {
      const body = await c.req.parseBody();
      const file = body["file"] || body["image"];
      if (file && typeof file === "object" && "arrayBuffer" in file) {
        const ab = await (file as any).arrayBuffer();
        fileBuffer = Buffer.from(ab);
        contentType = (file as any).type || "image/jpeg";
      }
    } else if (reqContentType.includes("application/json")) {
      const body = await c.req.json();
      if (body.image) {
        const raw = body.image.replace(/^data:image\/\w+;base64,/, "");
        fileBuffer = Buffer.from(raw, "base64");
        contentType = body.mimeType || "image/jpeg";
      }
    } else if (reqContentType.startsWith("image/")) {
      const ab = await c.req.arrayBuffer();
      fileBuffer = Buffer.from(ab);
      contentType = reqContentType;
    }

    if (!fileBuffer || fileBuffer.length === 0) {
      return c.json({ success: false, error: "No se recibió ninguna imagen válida." }, 400);
    }

    if (contentType.includes("png")) fileExt = "png";
    else if (contentType.includes("webp")) fileExt = "webp";
    else if (contentType.includes("gif")) fileExt = "gif";
    else fileExt = "jpg";

    const objectKey = `post-${auth.userId}-${Date.now()}.${fileExt}`;
    const s3 = getS3();

    await s3.send(
      new PutObjectCommand({
        Bucket: "posts",
        Key: objectKey,
        Body: fileBuffer,
        ContentType: contentType,
      })
    );

    const host = c.req.header("host") || "br-spring-base-betng0ba-api.compute.c-9.us-east-2.aws.neon.tech";
    const proto = host.includes("localhost") ? "http" : "https";
    const imageUrl = `${proto}://${host}/api/posts/media/${objectKey}`;

    return c.json({
      success: true,
      imageUrl,
    });
  } catch (err: any) {
    console.error("Post image upload error:", err);
    return c.json({ success: false, error: err.message || "Error al subir imagen" }, 500);
  }
});

// Serve post media from Neon Object Storage
app.get("/api/posts/media/:key", async (c) => {
  try {
    const key = c.req.param("key");
    const s3 = getS3();
    const res = await s3.send(
      new GetObjectCommand({
        Bucket: "posts",
        Key: key,
      })
    );

    let contentType = res.ContentType || "image/jpeg";
    if (key.endsWith(".png")) contentType = "image/png";
    else if (key.endsWith(".webp")) contentType = "image/webp";
    else if (key.endsWith(".gif")) contentType = "image/gif";

    const stream = res.Body as any;
    return new Response(stream, {
      headers: {
        "Content-Type": contentType,
        "Cache-Control": "public, max-age=31536000, immutable",
      },
    });
  } catch (err: any) {
    return c.text("Imagen no encontrada", 404);
  }
});

// Create a publication (text, markdown, image or text with image)
app.post("/api/posts", async (c) => {
  try {
    const auth = await getAuthenticatedUser(c);
    if (!auth) {
      return c.json({ success: false, error: "No autorizado o sesión expirada" }, 401);
    }

    const p = getPool();

    // Check suspension & rate limit
    const perm = await verifyUserPostPermission(p, auth.userId, "post");
    if (!perm.allowed) {
      return c.json({ success: false, error: perm.error }, 403);
    }

    const body = await c.req.json().catch(() => ({}));
    const content = typeof body.content === "string" ? body.content.trim() : "";
    const rawImages: unknown[] = Array.isArray(body.imageUrls)
      ? body.imageUrls
      : (typeof body.imageUrl === "string" && body.imageUrl.trim().length > 0 ? [body.imageUrl] : []);
    const imageUrls = rawImages
      .filter((u): u is string => typeof u === "string" && u.trim().length > 0)
      .map((u) => u.trim());
    const primaryImageUrl = imageUrls.length > 0 ? imageUrls[0] : null;

    if (!content && imageUrls.length === 0) {
      return c.json({ success: false, error: "La publicación debe tener texto o una imagen." }, 400);
    }

    // Heuristic content moderation check
    const modCheck = checkContentModeration(content);
    if (!modCheck.allowed) {
      return c.json({ success: false, error: modCheck.reason }, 400);
    }

    const isSensitive = Boolean(body.isSensitive);

    const insertRes = await p.query(
      `INSERT INTO public.posts (author_id, content, image_url, visibility, is_sensitive, created_at, updated_at)
       VALUES ($1, $2, $3, 'public', $4, now(), now())
       RETURNING id, author_id, content, image_url, is_sensitive, is_hidden, reports_count, likes_count, comments_count, created_at`,
      [auth.userId, content || null, primaryImageUrl, isSensitive]
    );

    const postRow = insertRes.rows[0];

    // Populate post_media for each image
    for (let i = 0; i < imageUrls.length; i++) {
      await p.query(
        `INSERT INTO public.post_media (post_id, media_type, media_url, order_index, created_at)
         VALUES ($1, 'image', $2, $3, now())`,
        [postRow.id, imageUrls[i], i]
      );
    }

    // Fetch author profile
    const authorRes = await p.query(
      "SELECT id, username, display_name, avatar_url, is_private, is_verified FROM public.profiles WHERE id = $1",
      [auth.userId]
    );
    const author = authorRes.rows[0];

    return c.json({
      success: true,
      post: {
        id: postRow.id,
        authorId: postRow.author_id,
        authorName: author?.display_name || author?.username || "Usuario",
        authorUsername: author?.username || "usuario",
        authorAvatarUrl: author?.avatar_url,
        isVerified: Boolean(author?.is_verified),
        content: postRow.content || "",
        imageUrl: postRow.image_url,
        imageUrls: imageUrls.length > 0 ? imageUrls : (postRow.image_url ? [postRow.image_url] : []),
        isSensitive: Boolean(postRow.is_sensitive),
        isHidden: Boolean(postRow.is_hidden),
        reportsCount: Number(postRow.reports_count || 0),
        likesCount: postRow.likes_count || 0,
        commentsCount: postRow.comments_count || 0,
        repostsCount: 0,
        isLiked: false,
        createdAt: postRow.created_at,
      },
    });
  } catch (err: any) {
    console.error("Create post error:", err);
    return c.json({ success: false, error: err.message || "Error al crear publicación" }, 500);
  }
});

// Posts can be marked to last 24 hours: the app adds a last line "⏳ 24 h" (see its PostContent).
// Expired ones are hidden from every listing and deleted at most once an hour.
// COALESCE: image-only posts have no content, and NULL would hide them from every listing
const EXPIRED_POST = `(COALESCE(p.content, '') ~ '(^|\\n)⏳ 24 h$' AND p.created_at < now() - interval '24 hours')`;
const NOT_EXPIRED_POST = `NOT ${EXPIRED_POST}`;
let lastExpiredPurge = 0;
function purgeExpiredPosts(p: Pool): void {
  if (Date.now() - lastExpiredPurge < 60 * 60 * 1000) return;
  lastExpiredPurge = Date.now();
  p.query(`DELETE FROM public.posts p WHERE ${EXPIRED_POST}`).catch((err) => {
    console.error("Expired posts purge error:", err.message);
  });
}

// Helper for formatting post rows
function mapPostRow(row: any) {
  const mediaUrls: string[] = Array.isArray(row.media_urls)
    ? row.media_urls.filter((u: any): u is string => typeof u === "string" && u.trim().length > 0)
    : [];
  const imageUrls = mediaUrls.length > 0 ? mediaUrls : (row.image_url ? [row.image_url] : []);
  const primaryImageUrl = row.image_url || (imageUrls.length > 0 ? imageUrls[0] : null);

  return {
    id: row.id,
    authorId: row.author_id,
    authorName: row.author_name || row.author_username || "Usuario",
    authorUsername: row.author_username || "usuario",
    authorAvatarUrl: row.author_avatar_url,
    isVerified: Boolean(row.author_is_verified),
    content: row.content || "",
    imageUrl: primaryImageUrl,
    imageUrls: imageUrls,
    isSensitive: Boolean(row.is_sensitive),
    isHidden: Boolean(row.is_hidden),
    reportsCount: Number(row.reports_count || 0),
    likesCount: Number(row.likes_count || 0),
    commentsCount: Number(row.comments_count || 0),
    repostsCount: 0,
    isLiked: Boolean(row.is_liked),
    isFollowingAuthor: Boolean(row.is_following_author),
    createdAt: row.created_at,
  };
}

// Get feed posts (public accounts + followed private accounts, or exclusively followed accounts)
app.get("/api/posts/feed", async (c) => {
  try {
    const auth = await getAuthenticatedUser(c);
    const viewerId = auth?.userId || null;
    const filter = c.req.query("filter"); // "following", "reviews" or undefined
    const p = getPool();
    purgeExpiredPosts(p);

    if (filter === "following") {
      if (!viewerId) {
        return c.json({ success: true, posts: [] });
      }

      const sql = `
        SELECT
          p.id,
          p.author_id,
          p.content,
          COALESCE(p.image_url, (SELECT media_url FROM public.post_media pm WHERE pm.post_id = p.id ORDER BY order_index ASC LIMIT 1)) as image_url,
          COALESCE((SELECT array_agg(pm.media_url ORDER BY pm.order_index ASC) FROM public.post_media pm WHERE pm.post_id = p.id), ARRAY[]::text[]) as media_urls,
          p.is_sensitive,
          p.is_hidden,
          p.reports_count,
          p.likes_count,
          p.comments_count,
          p.created_at,
          pr.username as author_username,
          pr.display_name as author_name,
          pr.avatar_url as author_avatar_url,
          pr.is_private as author_is_private,
          pr.is_verified as author_is_verified,
          EXISTS(SELECT 1 FROM public.post_likes pl WHERE pl.post_id = p.id AND pl.user_id = $1::uuid) as is_liked,
          true as is_following_author
        FROM public.posts p
        INNER JOIN public.profiles pr ON p.author_id = pr.id
        INNER JOIN public.follows f ON f.following_id = p.author_id AND f.follower_id = $1::uuid AND f.status = 'accepted'
        WHERE ${NOT_EXPIRED_POST}
          AND (p.is_hidden = false OR p.author_id = $1::uuid)
          AND (pr.is_suspended = false OR p.author_id = $1::uuid)
          AND NOT EXISTS (
            SELECT 1 FROM public.blocks b
            WHERE (b.blocker_id = $1::uuid AND b.blocked_id = p.author_id)
               OR (b.blocker_id = p.author_id AND b.blocked_id = $1::uuid)
          )
        ORDER BY p.created_at DESC
        LIMIT 50;
      `;

      const res = await p.query(sql, [viewerId]);
      return c.json({
        success: true,
        posts: res.rows.map(mapPostRow),
      });
    }

    const sql = `
      SELECT
        p.id,
        p.author_id,
        p.content,
        COALESCE(p.image_url, (SELECT media_url FROM public.post_media pm WHERE pm.post_id = p.id ORDER BY order_index ASC LIMIT 1)) as image_url,
        COALESCE((SELECT array_agg(pm.media_url ORDER BY pm.order_index ASC) FROM public.post_media pm WHERE pm.post_id = p.id), ARRAY[]::text[]) as media_urls,
        p.is_sensitive,
        p.is_hidden,
        p.reports_count,
        p.likes_count,
        p.comments_count,
        p.created_at,
        pr.username as author_username,
        pr.display_name as author_name,
        pr.avatar_url as author_avatar_url,
        pr.is_private as author_is_private,
        pr.is_verified as author_is_verified,
        ($1::uuid IS NOT NULL AND EXISTS(SELECT 1 FROM public.post_likes pl WHERE pl.post_id = p.id AND pl.user_id = $1::uuid)) as is_liked,
        ($1::uuid IS NOT NULL AND EXISTS(SELECT 1 FROM public.follows f WHERE f.follower_id = $1::uuid AND f.following_id = p.author_id AND f.status = 'accepted')) as is_following_author
      FROM public.posts p
      INNER JOIN public.profiles pr ON p.author_id = pr.id
      WHERE
        (pr.is_private = false
          OR ($1::uuid IS NOT NULL AND (
               p.author_id = $1::uuid
               OR EXISTS(SELECT 1 FROM public.follows f WHERE f.follower_id = $1::uuid AND f.following_id = p.author_id AND f.status = 'accepted')
             )))
        -- "reviews": posts whose first line is a movie or music review (see the app's PostContent)
        AND ($2::boolean = false OR p.content ~ '^(🎬|🎵) ')
        AND ${NOT_EXPIRED_POST}
        AND (p.is_hidden = false OR p.author_id = $1::uuid)
        AND (pr.is_suspended = false OR p.author_id = $1::uuid)
        AND ($1::uuid IS NULL OR NOT EXISTS (
          SELECT 1 FROM public.blocks b
          WHERE (b.blocker_id = $1::uuid AND b.blocked_id = p.author_id)
             OR (b.blocker_id = p.author_id AND b.blocked_id = $1::uuid)
        ))
      ORDER BY p.created_at DESC
      LIMIT 50;
    `;

    const res = await p.query(sql, [viewerId, filter === "reviews"]);
    return c.json({
      success: true,
      posts: res.rows.map(mapPostRow),
    });
  } catch (err: any) {
    console.error("Feed error:", err);
    return c.json({ success: false, error: err.message || "Error al obtener el feed" }, 500);
  }
});

// Alias for following feed
app.get("/api/posts/following", async (c) => {
  try {
    const auth = await getAuthenticatedUser(c);
    const viewerId = auth?.userId || null;
    const p = getPool();

    if (!viewerId) {
      return c.json({ success: true, posts: [] });
    }

    const sql = `
      SELECT
        p.id,
        p.author_id,
        p.content,
        COALESCE(p.image_url, (SELECT media_url FROM public.post_media pm WHERE pm.post_id = p.id ORDER BY order_index ASC LIMIT 1)) as image_url,
        COALESCE((SELECT array_agg(pm.media_url ORDER BY pm.order_index ASC) FROM public.post_media pm WHERE pm.post_id = p.id), ARRAY[]::text[]) as media_urls,
        p.is_sensitive,
        p.is_hidden,
        p.reports_count,
        p.likes_count,
        p.comments_count,
        p.created_at,
        pr.username as author_username,
        pr.display_name as author_name,
        pr.avatar_url as author_avatar_url,
        pr.is_private as author_is_private,
        pr.is_verified as author_is_verified,
        EXISTS(SELECT 1 FROM public.post_likes pl WHERE pl.post_id = p.id AND pl.user_id = $1::uuid) as is_liked,
        true as is_following_author
      FROM public.posts p
      INNER JOIN public.profiles pr ON p.author_id = pr.id
      INNER JOIN public.follows f ON f.following_id = p.author_id AND f.follower_id = $1::uuid AND f.status = 'accepted'
      WHERE ${NOT_EXPIRED_POST}
        AND (p.is_hidden = false OR p.author_id = $1::uuid)
        AND (pr.is_suspended = false OR p.author_id = $1::uuid)
        AND NOT EXISTS (
          SELECT 1 FROM public.blocks b
          WHERE (b.blocker_id = $1::uuid AND b.blocked_id = p.author_id)
             OR (b.blocker_id = p.author_id AND b.blocked_id = $1::uuid)
        )
      ORDER BY p.created_at DESC
      LIMIT 50;
    `;

    const res = await p.query(sql, [viewerId]);
    return c.json({
      success: true,
      posts: res.rows.map(mapPostRow),
    });
  } catch (err: any) {
    console.error("Following feed error:", err);
    return c.json({ success: false, error: err.message || "Error al obtener el feed de siguiendo" }, 500);
  }
});

// Get posts for a specific user profile
app.get("/api/posts/user/:target", async (c) => {
  try {
    const auth = await getAuthenticatedUser(c);
    const viewerId = auth?.userId || null;
    const target = c.req.param("target");
    const p = getPool();

    const profileRes = await p.query(
      `SELECT id, username, display_name, avatar_url, is_private
       FROM public.profiles
       WHERE id::text = $1 OR lower(username) = lower($1)
       LIMIT 1`,
      [target]
    );

    if (profileRes.rows.length === 0) {
      return c.json({ success: false, error: "Perfil no encontrado" }, 404);
    }

    const profile = profileRes.rows[0];
    const isOwner = viewerId && viewerId === profile.id;

    if (viewerId && !isOwner) {
      const blockRes = await p.query(
        `SELECT 1 FROM public.blocks
         WHERE (blocker_id = $1 AND blocked_id = $2)
            OR (blocker_id = $2 AND blocked_id = $1)
         LIMIT 1`,
        [viewerId, profile.id]
      );
      if (blockRes.rows.length > 0) {
        return c.json({
          success: true,
          locked: true,
          isBlocked: true,
          posts: [],
        });
      }
    }

    if (profile.is_private && !isOwner) {
      let isFollower = false;
      if (viewerId) {
        const followRes = await p.query(
          `SELECT 1 FROM public.follows WHERE follower_id = $1 AND following_id = $2 AND status = 'accepted'`,
          [viewerId, profile.id]
        );
        isFollower = followRes.rows.length > 0;
      }
      if (!isFollower) {
        return c.json({
          success: true,
          locked: true,
          posts: [],
        });
      }
    }

    const sql = `
      SELECT
        p.id,
        p.author_id,
        p.content,
        COALESCE(p.image_url, (SELECT media_url FROM public.post_media pm WHERE pm.post_id = p.id ORDER BY order_index ASC LIMIT 1)) as image_url,
        COALESCE((SELECT array_agg(pm.media_url ORDER BY pm.order_index ASC) FROM public.post_media pm WHERE pm.post_id = p.id), ARRAY[]::text[]) as media_urls,
        p.is_sensitive,
        p.is_hidden,
        p.reports_count,
        p.likes_count,
        p.comments_count,
        p.created_at,
        pr.username as author_username,
        pr.display_name as author_name,
        pr.avatar_url as author_avatar_url,
        pr.is_private as author_is_private,
        pr.is_verified as author_is_verified,
        ($2::uuid IS NOT NULL AND EXISTS(SELECT 1 FROM public.post_likes pl WHERE pl.post_id = p.id AND pl.user_id = $2::uuid)) as is_liked
      FROM public.posts p
      INNER JOIN public.profiles pr ON p.author_id = pr.id
      WHERE p.author_id = $1
        AND ${NOT_EXPIRED_POST}
        AND (p.is_hidden = false OR $2::uuid = $1::uuid)
      ORDER BY p.created_at DESC
      LIMIT 50;
    `;

    const postsRes = await p.query(sql, [profile.id, viewerId]);
    return c.json({
      success: true,
      locked: false,
      posts: postsRes.rows.map(mapPostRow),
    });
  } catch (err: any) {
    console.error("User posts error:", err);
    return c.json({ success: false, error: err.message || "Error al obtener publicaciones" }, 500);
  }
});

// Toggle like on a post
app.post("/api/posts/:id/like", async (c) => {
  try {
    const auth = await getAuthenticatedUser(c);
    if (!auth) {
      return c.json({ success: false, error: "No autorizado o sesión expirada" }, 401);
    }

    const postId = c.req.param("id");
    const p = getPool();

    const likeCheck = await p.query(
      "SELECT 1 FROM public.post_likes WHERE post_id = $1 AND user_id = $2",
      [postId, auth.userId]
    );

    let isLiked = false;
    if (likeCheck.rows.length > 0) {
      await p.query(
        "DELETE FROM public.post_likes WHERE post_id = $1 AND user_id = $2",
        [postId, auth.userId]
      );
      await p.query(
        "UPDATE public.posts SET likes_count = GREATEST(0, likes_count - 1), updated_at = now() WHERE id = $1",
        [postId]
      );
      isLiked = false;
    } else {
      await p.query(
        "INSERT INTO public.post_likes (post_id, user_id, created_at) VALUES ($1, $2, now())",
        [postId, auth.userId]
      );
      await p.query(
        "UPDATE public.posts SET likes_count = likes_count + 1, updated_at = now() WHERE id = $1",
        [postId]
      );
      isLiked = true;
    }

    const countRes = await p.query("SELECT likes_count, author_id FROM public.posts WHERE id = $1", [postId]);
    const likesCount = countRes.rows[0]?.likes_count ?? 0;

    const authorId = countRes.rows[0]?.author_id;
    if (authorId) {
      const event = { recipientId: authorId, actorId: auth.userId, type: "like" as const, postId };
      await (isLiked ? notify(p, event) : clearNotification(p, event));
    }

    return c.json({
      success: true,
      isLiked,
      likesCount,
    });
  } catch (err: any) {
    console.error("Like toggle error:", err);
    return c.json({ success: false, error: err.message || "Error al dar me gusta" }, 500);
  }
});

// ==========================================
// CHAT & MESSAGING ENDPOINTS (WITH PRIVACY)
// ==========================================

// List conversations for authenticated user
app.get("/api/chats", async (c) => {
  try {
    const auth = await getAuthenticatedUser(c);
    if (!auth) {
      return c.json({ success: false, error: "No autorizado o sesión expirada" }, 401);
    }

    const p = getPool();

    // Query all conversations where auth.userId is a participant
    const convsRes = await p.query(
      `SELECT 
        c.id,
        c.is_group,
        c.title,
        c.last_message_at,
        c.created_at,
        cp.last_read_at,
        -- Other participant info for 1-on-1 chats
        other_p.id as other_id,
        other_p.username as other_username,
        other_p.display_name as other_display_name,
        other_p.avatar_url as other_avatar_url,
        other_p.is_verified as other_is_verified,
        other_p.is_private as other_is_private,
        -- Last message info
        last_m.content as last_message_content,
        last_m.media_url as last_message_media_url,
        last_m.sender_id as last_message_sender_id,
        last_m.created_at as last_message_created_at,
        -- Unread count
        COALESCE((
          SELECT count(*)::int 
          FROM public.messages m 
          WHERE m.conversation_id = c.id 
            AND m.sender_id != $1 
            AND (cp.last_read_at IS NULL OR m.created_at > cp.last_read_at)
        ), 0) as unread_count
      FROM public.conversations c
      JOIN public.conversation_participants cp ON c.id = cp.conversation_id AND cp.user_id = $1
      LEFT JOIN LATERAL (
        SELECT p.*
        FROM public.conversation_participants other_cp
        JOIN public.profiles p ON other_cp.user_id = p.id
        WHERE other_cp.conversation_id = c.id AND other_cp.user_id != $1
        LIMIT 1
      ) other_p ON true
      LEFT JOIN LATERAL (
        SELECT content, media_url, sender_id, created_at
        FROM public.messages
        WHERE conversation_id = c.id
        ORDER BY created_at DESC
        LIMIT 1
      ) last_m ON true
      ORDER BY c.last_message_at DESC`,
      [auth.userId]
    );

    const chats = convsRes.rows.map((row) => ({
      id: row.id,
      isGroup: row.is_group,
      title: row.title,
      lastMessageAt: row.last_message_at,
      unreadCount: row.unread_count,
      lastMessage: row.last_message_content || (row.last_message_media_url ? "📷 Foto" : ""),
      lastMessageTime: row.last_message_created_at,
      isRead: row.unread_count === 0,
      otherParticipant: row.other_id ? {
        id: row.other_id,
        username: row.other_username,
        displayName: row.other_display_name,
        avatarUrl: row.other_avatar_url,
        isVerified: row.other_is_verified,
        isPrivate: row.other_is_private,
      } : null,
    }));

    return c.json({ success: true, chats });
  } catch (err: any) {
    console.error("List chats error:", err);
    return c.json({ success: false, error: err.message || "Error al obtener conversaciones" }, 500);
  }
});

// Start or get existing conversation with a user (with strict privacy check)
app.post("/api/chats/with/:targetUserId", async (c) => {
  try {
    const auth = await getAuthenticatedUser(c);
    if (!auth) {
      return c.json({ success: false, error: "No autorizado o sesión expirada" }, 401);
    }

    const targetUserId = c.req.param("targetUserId");
    if (targetUserId === auth.userId) {
      return c.json({ success: false, error: "No podés iniciar un chat con vos mismo" }, 400);
    }

    const p = getPool();

    // Check target profile
    const targetRes = await p.query(
      "SELECT id, username, display_name, avatar_url, is_verified, is_private FROM public.profiles WHERE id = $1 LIMIT 1",
      [targetUserId]
    );
    if (targetRes.rows.length === 0) {
      return c.json({ success: false, error: "Usuario no encontrado" }, 404);
    }
    const target = targetRes.rows[0];

    // PRIVACY CHECK:
    // If target profile is private, verify current user is an accepted follower OR target follows current user
    if (target.is_private) {
      const followRes = await p.query(
        `SELECT status FROM public.follows
         WHERE (follower_id = $1 AND following_id = $2 AND status = 'accepted')
            OR (follower_id = $2 AND following_id = $1 AND status = 'accepted')
         LIMIT 1`,
        [auth.userId, targetUserId]
      );
      if (followRes.rows.length === 0) {
        return c.json({
          success: false,
          isPrivateRestricted: true,
          error: "Esta cuenta es privada. Solo podés enviarle mensajes si es tu seguidor o te aceptó la solicitud.",
        }, 403);
      }
    }

    // Check if 1-to-1 conversation already exists
    const existingConv = await p.query(
      `SELECT c.id 
       FROM public.conversations c
       JOIN public.conversation_participants cp1 ON c.id = cp1.conversation_id AND cp1.user_id = $1
       JOIN public.conversation_participants cp2 ON c.id = cp2.conversation_id AND cp2.user_id = $2
       WHERE c.is_group = false
       LIMIT 1`,
      [auth.userId, targetUserId]
    );

    let conversationId: string;
    if (existingConv.rows.length > 0) {
      conversationId = existingConv.rows[0].id;
    } else {
      // Create new conversation
      const insertConv = await p.query(
        "INSERT INTO public.conversations (is_group, last_message_at, created_at) VALUES (false, now(), now()) RETURNING id"
      );
      conversationId = insertConv.rows[0].id;

      // Add participants
      await p.query(
        `INSERT INTO public.conversation_participants (conversation_id, user_id, joined_at)
         VALUES ($1, $2, now()), ($1, $3, now())`,
        [conversationId, auth.userId, targetUserId]
      );
    }

    // Optional initial message
    const body = await c.req.json().catch(() => ({}));
    if (body.initialMessage && typeof body.initialMessage === "string" && body.initialMessage.trim().length > 0) {
      await p.query(
        `INSERT INTO public.messages (conversation_id, sender_id, content, created_at)
         VALUES ($1, $2, $3, now())`,
        [conversationId, auth.userId, body.initialMessage.trim()]
      );
      await p.query(
        "UPDATE public.conversations SET last_message_at = now() WHERE id = $1",
        [conversationId]
      );
      await p.query(
        "UPDATE public.conversation_participants SET last_read_at = now() WHERE conversation_id = $1 AND user_id = $2",
        [conversationId, auth.userId]
      );
    }

    return c.json({
      success: true,
      conversationId,
      otherParticipant: {
        id: target.id,
        username: target.username,
        displayName: target.display_name,
        avatarUrl: target.avatar_url,
        isVerified: target.is_verified,
        isPrivate: target.is_private,
      },
    });
  } catch (err: any) {
    console.error("Start chat error:", err);
    return c.json({ success: false, error: err.message || "Error al iniciar conversación" }, 500);
  }
});

// Get messages for a conversation
app.get("/api/chats/:conversationId/messages", async (c) => {
  try {
    const auth = await getAuthenticatedUser(c);
    if (!auth) {
      return c.json({ success: false, error: "No autorizado o sesión expirada" }, 401);
    }

    const conversationId = c.req.param("conversationId");
    const p = getPool();

    // Verify user is a participant
    const partCheck = await p.query(
      "SELECT 1 FROM public.conversation_participants WHERE conversation_id = $1 AND user_id = $2",
      [conversationId, auth.userId]
    );
    if (partCheck.rows.length === 0) {
      return c.json({ success: false, error: "No tenés permiso para ver esta conversación" }, 403);
    }

    // Mark as read for this user
    await p.query(
      "UPDATE public.conversation_participants SET last_read_at = now() WHERE conversation_id = $1 AND user_id = $2",
      [conversationId, auth.userId]
    );

    // Get messages
    const msgsRes = await p.query(
      `SELECT 
        m.id,
        m.conversation_id,
        m.sender_id,
        m.content,
        m.media_url,
        m.created_at,
        p.display_name as sender_name,
        p.username as sender_username,
        p.avatar_url as sender_avatar_url
      FROM public.messages m
      JOIN public.profiles p ON m.sender_id = p.id
      WHERE m.conversation_id = $1
      ORDER BY m.created_at ASC`,
      [conversationId]
    );

    // Get other participant info
    const otherRes = await p.query(
      `SELECT p.id, p.username, p.display_name, p.avatar_url, p.is_verified, p.is_private
       FROM public.conversation_participants cp
       JOIN public.profiles p ON cp.user_id = p.id
       WHERE cp.conversation_id = $1 AND cp.user_id != $2
       LIMIT 1`,
      [conversationId, auth.userId]
    );

    return c.json({
      success: true,
      messages: msgsRes.rows.map((row) => ({
        id: row.id,
        conversationId: row.conversation_id,
        senderId: row.sender_id,
        senderName: row.sender_name,
        senderUsername: row.sender_username,
        senderAvatarUrl: row.sender_avatar_url,
        content: row.content || "",
        mediaUrl: row.media_url,
        createdAt: row.created_at,
        isMe: row.sender_id === auth.userId,
      })),
      otherParticipant: otherRes.rows[0] ? {
        id: otherRes.rows[0].id,
        username: otherRes.rows[0].username,
        displayName: otherRes.rows[0].display_name,
        avatarUrl: otherRes.rows[0].avatar_url,
        isVerified: otherRes.rows[0].is_verified,
        isPrivate: otherRes.rows[0].is_private,
      } : null,
    });
  } catch (err: any) {
    console.error("Get messages error:", err);
    return c.json({ success: false, error: err.message || "Error al obtener mensajes" }, 500);
  }
});

// Send a message in a conversation (with strict privacy check)
app.post("/api/chats/:conversationId/messages", async (c) => {
  try {
    const auth = await getAuthenticatedUser(c);
    if (!auth) {
      return c.json({ success: false, error: "No autorizado o sesión expirada" }, 401);
    }

    const conversationId = c.req.param("conversationId");
    const p = getPool();

    // Verify user is a participant
    const partCheck = await p.query(
      "SELECT 1 FROM public.conversation_participants WHERE conversation_id = $1 AND user_id = $2",
      [conversationId, auth.userId]
    );
    if (partCheck.rows.length === 0) {
      return c.json({ success: false, error: "No tenés permiso para enviar mensajes en esta conversación" }, 403);
    }

    // PRIVACY CHECK:
    // If 1-to-1 conversation, check other participant's privacy
    const otherCheck = await p.query(
      `SELECT p.id, p.is_private 
       FROM public.conversation_participants cp
       JOIN public.profiles p ON cp.user_id = p.id
       WHERE cp.conversation_id = $1 AND cp.user_id != $2
       LIMIT 1`,
      [conversationId, auth.userId]
    );

    if (otherCheck.rows.length > 0 && otherCheck.rows[0].is_private) {
      const otherId = otherCheck.rows[0].id;
      const followCheck = await p.query(
        `SELECT status FROM public.follows
         WHERE (follower_id = $1 AND following_id = $2 AND status = 'accepted')
            OR (follower_id = $2 AND following_id = $1 AND status = 'accepted')
         LIMIT 1`,
        [auth.userId, otherId]
      );
      if (followCheck.rows.length === 0) {
        return c.json({
          success: false,
          isPrivateRestricted: true,
          error: "Esta cuenta es privada. Solo podés enviarle mensajes si es tu seguidor o te aceptó la solicitud.",
        }, 403);
      }
    }

    const body = await c.req.json();
    const content = (body.content || "").trim();
    const mediaUrl = body.mediaUrl || null;

    if (!content && !mediaUrl) {
      return c.json({ success: false, error: "El mensaje no puede estar vacío" }, 400);
    }

    // Insert message
    const insertRes = await p.query(
      `INSERT INTO public.messages (conversation_id, sender_id, content, media_url, created_at)
       VALUES ($1, $2, $3, $4, now())
       RETURNING id, conversation_id, sender_id, content, media_url, created_at`,
      [conversationId, auth.userId, content || null, mediaUrl]
    );

    const msg = insertRes.rows[0];

    // Update conversation timestamp
    await p.query(
      "UPDATE public.conversations SET last_message_at = now() WHERE id = $1",
      [conversationId]
    );

    // Update sender last_read_at
    await p.query(
      "UPDATE public.conversation_participants SET last_read_at = now() WHERE conversation_id = $1 AND user_id = $2",
      [conversationId, auth.userId]
    );

    const recipientsRes = await p.query(
      "SELECT user_id FROM public.conversation_participants WHERE conversation_id = $1 AND user_id != $2",
      [conversationId, auth.userId]
    );
    for (const row of recipientsRes.rows) {
      await notify(p, { recipientId: row.user_id, actorId: auth.userId, type: "message", conversationId });
    }

    // Get sender info
    const senderRes = await p.query(
      "SELECT username, display_name, avatar_url FROM public.profiles WHERE id = $1",
      [auth.userId]
    );
    const sender = senderRes.rows[0];

    return c.json({
      success: true,
      message: {
        id: msg.id,
        conversationId: msg.conversation_id,
        senderId: msg.sender_id,
        senderName: sender?.display_name || "Yo",
        senderUsername: sender?.username || "yo",
        senderAvatarUrl: sender?.avatar_url,
        content: msg.content || "",
        mediaUrl: msg.media_url,
        createdAt: msg.created_at,
        isMe: true,
      },
    });
  } catch (err: any) {
    console.error("Send message error:", err);
    return c.json({ success: false, error: err.message || "Error al enviar mensaje" }, 500);
  }
});

// Search or list candidate users for new chat respecting privacy rules
app.get("/api/chats/candidates", async (c) => {
  try {
    const auth = await getAuthenticatedUser(c);
    if (!auth) {
      return c.json({ success: false, error: "No autorizado o sesión expirada" }, 401);
    }

    const query = (c.req.query("q") || "").trim().toLowerCase();
    const p = getPool();

    let sqlQuery: string;
    let params: any[];

    if (query.length > 0) {
      sqlQuery = `
        SELECT 
          p.id,
          p.username,
          p.display_name,
          p.avatar_url,
          p.is_verified,
          p.is_private,
          EXISTS(
            SELECT 1 FROM public.follows f 
            WHERE f.follower_id = $1 AND f.following_id = p.id AND f.status = 'accepted'
          ) as is_following,
          EXISTS(
            SELECT 1 FROM public.follows f 
            WHERE f.follower_id = p.id AND f.following_id = $1 AND f.status = 'accepted'
          ) as is_follower,
          EXISTS(
            SELECT 1 FROM public.follows f 
            WHERE f.follower_id = $1 AND f.following_id = p.id AND f.status = 'pending'
          ) as is_pending
        FROM public.profiles p
        WHERE p.id != $1
          AND (lower(p.username) LIKE $2 OR lower(p.display_name) LIKE $2)
        ORDER BY p.display_name ASC
        LIMIT 20
      `;
      params = [auth.userId, `%${query}%`];
    } else {
      sqlQuery = `
        SELECT DISTINCT
          p.id,
          p.username,
          p.display_name,
          p.avatar_url,
          p.is_verified,
          p.is_private,
          EXISTS(
            SELECT 1 FROM public.follows f 
            WHERE f.follower_id = $1 AND f.following_id = p.id AND f.status = 'accepted'
          ) as is_following,
          EXISTS(
            SELECT 1 FROM public.follows f 
            WHERE f.follower_id = p.id AND f.following_id = $1 AND f.status = 'accepted'
          ) as is_follower,
          EXISTS(
            SELECT 1 FROM public.follows f 
            WHERE f.follower_id = $1 AND f.following_id = p.id AND f.status = 'pending'
          ) as is_pending
        FROM public.profiles p
        LEFT JOIN public.follows f ON (f.follower_id = $1 AND f.following_id = p.id) OR (f.follower_id = p.id AND f.following_id = $1)
        WHERE p.id != $1
        ORDER BY p.display_name ASC
        LIMIT 20
      `;
      params = [auth.userId];
    }

    const res = await p.query(sqlQuery, params);

    const candidates = res.rows.map((row) => {
      // User can be messaged if they are public OR if current user is an accepted follower OR if target follows current user
      const canMessage = !row.is_private || row.is_following || row.is_follower;
      return {
        id: row.id,
        username: row.username,
        displayName: row.display_name,
        avatarUrl: row.avatar_url,
        isVerified: row.is_verified,
        isPrivate: row.is_private,
        isFollowing: row.is_following,
        isFollower: row.is_follower,
        isPending: row.is_pending,
        canMessage,
      };
    });

    return c.json({ success: true, candidates });
  } catch (err: any) {
    console.error("Candidates error:", err);
    return c.json({ success: false, error: err.message || "Error al buscar usuarios" }, 500);
  }
});

// Upload chat attachment image
app.post("/api/chats/upload-image", async (c) => {
  try {
    const auth = await getAuthenticatedUser(c);
    if (!auth) {
      return c.json({ success: false, error: "No autorizado o sesión expirada" }, 401);
    }

    const body = await c.req.parseBody();
    const file = body["file"];
    if (!file || typeof file === "string") {
      return c.json({ success: false, error: "No se proporcionó ningún archivo" }, 400);
    }

    const buffer = Buffer.from(await (file as File).arrayBuffer());
    const ext = (file as File).name?.split(".").pop() || "jpg";
    const key = `chats/${auth.userId}/${Date.now()}-${Math.random().toString(36).substring(7)}.${ext}`;

    const s3 = getS3();
    const bucketName = process.env.AWS_BUCKET_POSTS || "posts";

    await s3.send(
      new PutObjectCommand({
        Bucket: bucketName,
        Key: key,
        Body: buffer,
        ContentType: (file as File).type || "image/jpeg",
      })
    );

    const publicUrl = `/api/posts/media/${encodeURIComponent(key)}`;
    return c.json({ success: true, imageUrl: publicUrl, key });
  } catch (err: any) {
    console.error("Upload chat image error:", err);
    return c.json({ success: false, error: err.message || "Error al subir la imagen" }, 500);
  }
});

// List followers / following of a user (private accounts: only owner and accepted followers)
const followListHandler = (direction: "followers" | "following") => async (c: any) => {
  try {
    const auth = await getAuthenticatedUser(c);
    const viewerId = auth?.userId || null;
    const targetParam = c.req.param("target");
    const p = getPool();

    if (targetParam === "me" && !viewerId) {
      return c.json({ success: false, error: "No autorizado o sesión expirada" }, 401);
    }

    const targetRes = await p.query(
      `SELECT id, is_private FROM public.profiles
       WHERE id::text = $1 OR lower(username) = lower($1)
       LIMIT 1`,
      [targetParam === "me" ? viewerId : targetParam]
    );
    if (targetRes.rows.length === 0) {
      return c.json({ success: false, error: "Usuario no encontrado" }, 404);
    }
    const target = targetRes.rows[0];
    const isOwner = viewerId === target.id;

    if (target.is_private && !isOwner) {
      const followRes = viewerId
        ? await p.query(
            `SELECT 1 FROM public.follows WHERE follower_id = $1 AND following_id = $2 AND status = 'accepted'`,
            [viewerId, target.id]
          )
        : { rows: [] };
      if (followRes.rows.length === 0) {
        return c.json({ success: false, locked: true, error: "Esta cuenta es privada" }, 403);
      }
    }

    // followers: people whose follow points at target; following: people target points at
    const [matchCol, listCol] =
      direction === "followers" ? ["following_id", "follower_id"] : ["follower_id", "following_id"];

    const res = await p.query(
      `SELECT
        pr.id, pr.username, pr.display_name, pr.avatar_url, pr.is_verified, pr.is_private,
        (SELECT status FROM public.follows WHERE follower_id = $2 AND following_id = pr.id) as viewer_status,
        EXISTS(SELECT 1 FROM public.follows WHERE follower_id = pr.id AND following_id = $2 AND status = 'accepted') as follows_viewer
      FROM public.follows f
      INNER JOIN public.profiles pr ON pr.id = f.${listCol}
      WHERE f.${matchCol} = $1 AND f.status = 'accepted'
      ORDER BY f.created_at DESC
      LIMIT 500`,
      [target.id, viewerId]
    );

    return c.json({
      success: true,
      users: res.rows.map((row) => ({
        id: row.id,
        username: row.username,
        displayName: row.display_name,
        avatarUrl: row.avatar_url,
        isVerified: Boolean(row.is_verified),
        isPrivate: Boolean(row.is_private),
        followStatus: row.viewer_status || "none",
        isFollowedBy: Boolean(row.follows_viewer),
      })),
    });
  } catch (err: any) {
    console.error(`${direction} list error:`, err);
    return c.json({ success: false, error: err.message || "Error al obtener la lista" }, 500);
  }
};

app.get("/api/profile/:target/followers", followListHandler("followers"));
app.get("/api/profile/:target/following", followListHandler("following"));

// End-to-end encrypted chats: the server keeps each user's public key and their
// private key encrypted with a chat password only they know. Messages and photos
// are encrypted on the device, so the server never sees their plaintext.
let chatKeysTable: Promise<void> | null = null;
function ensureChatKeysTable(p: Pool): Promise<void> {
  if (!chatKeysTable) {
    chatKeysTable = p
      .query(
        `CREATE TABLE IF NOT EXISTS public.chat_keys (
           user_id UUID PRIMARY KEY REFERENCES public.profiles(id) ON DELETE CASCADE,
           public_key TEXT NOT NULL,
           encrypted_private_key TEXT NOT NULL,
           key_nonce TEXT NOT NULL,
           kdf_salt TEXT NOT NULL,
           kdf_iterations INTEGER NOT NULL,
           created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
           updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
         )`
      )
      .then(() => undefined)
      .catch((err) => {
        chatKeysTable = null;
        throw err;
      });
  }
  return chatKeysTable;
}

// Canonical base64 that decodes to exactly `bytes` bytes
function isBase64OfLength(value: unknown, bytes: number): value is string {
  if (typeof value !== "string") return false;
  const decoded = Buffer.from(value, "base64");
  return decoded.length === bytes && decoded.toString("base64") === value;
}

async function getOrProvisionUserKeys(
  p: Pool,
  userId: string
): Promise<{ publicKey: string; keyBundle: any }> {
  await ensureChatKeysTable(p);
  const res = await p.query(
    `SELECT public_key, encrypted_private_key, key_nonce, kdf_salt, kdf_iterations
     FROM public.chat_keys WHERE user_id = $1`,
    [userId]
  );
  if (res.rows.length > 0) {
    const row = res.rows[0];
    return {
      publicKey: row.public_key,
      keyBundle: {
        publicKey: row.public_key,
        encryptedPrivateKey: row.encrypted_private_key,
        nonce: row.key_nonce,
        salt: row.kdf_salt,
        iterations: row.kdf_iterations,
      },
    };
  }

  // Auto-provision X25519 keypair for this user so encryption is always guaranteed
  const { publicKey: pubKeyObj, privateKey: privKeyObj } = crypto.generateKeyPairSync("x25519");
  const rawPublic = pubKeyObj.export({ type: "spki", format: "der" }).subarray(-32);
  const rawPrivate = privKeyObj.export({ type: "pkcs8", format: "der" }).subarray(-32);

  const salt = crypto.randomBytes(16);
  const nonce = crypto.randomBytes(12);
  const iterations = 310000;
  const vaultPass = `brote_e2e_vault_${userId}`;
  const derivedKey = crypto.pbkdf2Sync(vaultPass, salt, iterations, 32, "sha256");

  const cipher = crypto.createCipheriv("aes-256-gcm", derivedKey, nonce);
  const encrypted = Buffer.concat([cipher.update(rawPrivate), cipher.final()]);
  const tag = cipher.getAuthTag();
  const encryptedPrivateKey = Buffer.concat([encrypted, tag]);

  const publicKeyB64 = rawPublic.toString("base64");
  const encryptedPrivB64 = encryptedPrivateKey.toString("base64");
  const nonceB64 = nonce.toString("base64");
  const saltB64 = salt.toString("base64");

  await p.query(
    `INSERT INTO public.chat_keys (user_id, public_key, encrypted_private_key, key_nonce, kdf_salt, kdf_iterations)
     VALUES ($1, $2, $3, $4, $5, $6)
     ON CONFLICT (user_id) DO NOTHING`,
    [userId, publicKeyB64, encryptedPrivB64, nonceB64, saltB64, iterations]
  );

  return {
    publicKey: publicKeyB64,
    keyBundle: {
      publicKey: publicKeyB64,
      encryptedPrivateKey: encryptedPrivB64,
      nonce: nonceB64,
      salt: saltB64,
      iterations,
    },
  };
}

// Own key bundle (only the owner gets the encrypted private key)
app.get("/api/keys/me", async (c) => {
  try {
    const auth = await getAuthenticatedUser(c);
    if (!auth) {
      return c.json({ success: false, error: "No autorizado o sesión expirada" }, 401);
    }

    const p = getPool();
    const { keyBundle } = await getOrProvisionUserKeys(p, auth.userId);
    return c.json({
      success: true,
      keyBundle,
    });
  } catch (err: any) {
    console.error("Get chat keys error:", err);
    return c.json({ success: false, error: err.message || "Error al obtener las claves" }, 500);
  }
});

// Create or replace own key bundle
app.put("/api/keys/me", async (c) => {
  try {
    const auth = await getAuthenticatedUser(c);
    if (!auth) {
      return c.json({ success: false, error: "No autorizado o sesión expirada" }, 401);
    }

    const body = await c.req.json().catch(() => ({}));
    const { publicKey, encryptedPrivateKey, nonce, salt, iterations } = body as Record<string, unknown>;
    const validIterations =
      typeof iterations === "number" && Number.isInteger(iterations) && iterations >= 100000 && iterations <= 5000000;
    if (
      !isBase64OfLength(publicKey, 32) ||
      !isBase64OfLength(encryptedPrivateKey, 48) ||
      !isBase64OfLength(nonce, 12) ||
      !isBase64OfLength(salt, 16) ||
      !validIterations
    ) {
      return c.json({ success: false, error: "Claves inválidas." }, 400);
    }

    const p = getPool();
    await ensureChatKeysTable(p);
    await p.query(
      `INSERT INTO public.chat_keys (user_id, public_key, encrypted_private_key, key_nonce, kdf_salt, kdf_iterations)
       VALUES ($1, $2, $3, $4, $5, $6)
       ON CONFLICT (user_id) DO UPDATE SET
         public_key = EXCLUDED.public_key,
         encrypted_private_key = EXCLUDED.encrypted_private_key,
         key_nonce = EXCLUDED.key_nonce,
         kdf_salt = EXCLUDED.kdf_salt,
         kdf_iterations = EXCLUDED.kdf_iterations,
         updated_at = now()`,
      [auth.userId, publicKey, encryptedPrivateKey, nonce, salt, iterations]
    );
    return c.json({ success: true });
  } catch (err: any) {
    console.error("Save chat keys error:", err);
    return c.json({ success: false, error: err.message || "Error al guardar las claves" }, 500);
  }
});

// Another user's public key (automatically provisions if not present)
app.get("/api/keys/:userId", async (c) => {
  try {
    const auth = await getAuthenticatedUser(c);
    if (!auth) {
      return c.json({ success: false, error: "No autorizado o sesión expirada" }, 401);
    }

    const p = getPool();
    const targetUserId = c.req.param("userId");
    const { publicKey } = await getOrProvisionUserKeys(p, targetUserId);
    return c.json({ success: true, publicKey });
  } catch (err: any) {
    console.error("Get public chat key error:", err);
    return c.json({ success: false, error: err.message || "Error al obtener la clave" }, 500);
  }
});

// Comments on posts (public.post_comments and thread replies + likes)
let postCommentsTable: Promise<void> | null = null;
function ensurePostCommentsTable(p: Pool): Promise<void> {
  if (!postCommentsTable) {
    postCommentsTable = p
      .query(
        `CREATE TABLE IF NOT EXISTS public.post_comments (
           id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
           post_id UUID NOT NULL REFERENCES public.posts(id) ON DELETE CASCADE,
           author_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
           content TEXT NOT NULL,
           created_at TIMESTAMPTZ NOT NULL DEFAULT now()
         );
         ALTER TABLE public.post_comments ADD COLUMN IF NOT EXISTS parent_id UUID REFERENCES public.post_comments(id) ON DELETE CASCADE;
         ALTER TABLE public.post_comments ADD COLUMN IF NOT EXISTS likes_count INTEGER NOT NULL DEFAULT 0;
         CREATE INDEX IF NOT EXISTS idx_post_comments_post_id ON public.post_comments (post_id, created_at ASC);
         CREATE INDEX IF NOT EXISTS idx_post_comments_parent_id ON public.post_comments (parent_id);

         CREATE TABLE IF NOT EXISTS public.post_comment_likes (
           comment_id UUID NOT NULL REFERENCES public.post_comments(id) ON DELETE CASCADE,
           user_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
           created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
           PRIMARY KEY (comment_id, user_id)
         );
         CREATE INDEX IF NOT EXISTS idx_comment_likes_comment_id ON public.post_comment_likes (comment_id);
         CREATE INDEX IF NOT EXISTS idx_comment_likes_user_id ON public.post_comment_likes (user_id);`
      )
      .then(() => undefined)
      .catch((err) => {
        postCommentsTable = null;
        throw err;
      });
  }
  return postCommentsTable;
}

// The post's author when the viewer can see it (public author, the author, or an accepted follower)
async function visiblePostAuthor(p: Pool, postId: string, viewerId: string): Promise<string | null> {
  const res = await p.query(
    `SELECT p.author_id, p.is_hidden, pr.is_private, pr.is_suspended,
            EXISTS(SELECT 1 FROM public.follows f
                   WHERE f.follower_id = $2::uuid AND f.following_id = p.author_id AND f.status = 'accepted') AS follows,
            EXISTS(SELECT 1 FROM public.blocks b
                   WHERE (b.blocker_id = $2::uuid AND b.blocked_id = p.author_id)
                      OR (b.blocker_id = p.author_id AND b.blocked_id = $2::uuid)) AS is_blocked
     FROM public.posts p
     INNER JOIN public.profiles pr ON pr.id = p.author_id
     WHERE p.id::text = $1 AND ${NOT_EXPIRED_POST}`,
    [postId, viewerId]
  );
  const row = res.rows[0];
  if (!row) return null;
  if (row.is_blocked) return null;
  if (row.is_suspended && row.author_id !== viewerId) return null;
  if (row.is_hidden && row.author_id !== viewerId) return null;
  if (row.is_private && row.author_id !== viewerId && !row.follows) return null;
  return row.author_id;
}

function mapCommentRow(row: any) {
  return {
    id: row.id,
    postId: row.post_id,
    parentId: row.parent_id || null,
    content: row.content,
    createdAt: row.created_at,
    likesCount: Number(row.likes_count || 0),
    isLiked: Boolean(row.is_liked),
    isHidden: Boolean(row.is_hidden),
    reportsCount: Number(row.reports_count || 0),
    replyToUsername: row.reply_to_username || null,
    author: {
      id: row.author_id,
      username: row.username,
      displayName: row.display_name,
      avatarUrl: row.avatar_url,
    },
  };
}

app.get("/api/posts/:id/comments", async (c) => {
  try {
    const auth = await getAuthenticatedUser(c);
    if (!auth) {
      return c.json({ success: false, error: "No autorizado o sesión expirada" }, 401);
    }

    const postId = c.req.param("id");
    const p = getPool();
    await ensurePostCommentsTable(p);
    if (!(await visiblePostAuthor(p, postId, auth.userId))) {
      return c.json({ success: false, error: "Publicación no encontrada" }, 404);
    }

    const res = await p.query(
      `SELECT cm.id, cm.post_id, cm.parent_id, cm.content, cm.created_at, cm.author_id,
              cm.is_hidden, cm.reports_count,
              COALESCE(cm.likes_count, 0) AS likes_count,
              pr.username, pr.display_name, pr.avatar_url,
              parent_pr.username AS reply_to_username,
              EXISTS(
                SELECT 1 FROM public.post_comment_likes cl
                WHERE cl.comment_id = cm.id AND cl.user_id = $2::uuid
              ) AS is_liked
       FROM public.post_comments cm
       INNER JOIN public.profiles pr ON pr.id = cm.author_id
       LEFT JOIN public.post_comments parent_cm ON parent_cm.id = cm.parent_id
       LEFT JOIN public.profiles parent_pr ON parent_pr.id = parent_cm.author_id
       WHERE cm.post_id = $1
         AND (cm.is_hidden = false OR cm.author_id = $2::uuid)
         AND (pr.is_suspended = false OR cm.author_id = $2::uuid)
         AND NOT EXISTS (
           SELECT 1 FROM public.blocks b
           WHERE (b.blocker_id = $2::uuid AND b.blocked_id = cm.author_id)
              OR (b.blocker_id = cm.author_id AND b.blocked_id = $2::uuid)
         )
       ORDER BY cm.created_at ASC
       LIMIT 300`,
      [postId, auth.userId]
    );
    return c.json({ success: true, comments: res.rows.map(mapCommentRow) });
  } catch (err: any) {
    console.error("Get comments error:", err);
    return c.json({ success: false, error: err.message || "Error al obtener los comentarios" }, 500);
  }
});

app.post("/api/posts/:id/comments", async (c) => {
  try {
    const auth = await getAuthenticatedUser(c);
    if (!auth) {
      return c.json({ success: false, error: "No autorizado o sesión expirada" }, 401);
    }

    const p = getPool();

    // Check suspension & rate limit
    const perm = await verifyUserPostPermission(p, auth.userId, "comment");
    if (!perm.allowed) {
      return c.json({ success: false, error: perm.error }, 403);
    }

    const body = await c.req.json().catch(() => ({}));
    const content = typeof body.content === "string" ? body.content.trim() : "";
    const parentId =
      typeof body.parentId === "string" && body.parentId.trim().length > 0 ? body.parentId.trim() : null;

    if (!content) {
      return c.json({ success: false, error: "El comentario no puede estar vacío." }, 400);
    }
    if (content.length > 500) {
      return c.json({ success: false, error: "El comentario no puede superar los 500 caracteres." }, 400);
    }

    // Heuristic content moderation check
    const modCheck = checkContentModeration(content);
    if (!modCheck.allowed) {
      return c.json({ success: false, error: modCheck.reason }, 400);
    }

    const postId = c.req.param("id");
    await ensurePostCommentsTable(p);
    const postAuthorId = await visiblePostAuthor(p, postId, auth.userId);
    if (!postAuthorId) {
      return c.json({ success: false, error: "Publicación no encontrada" }, 404);
    }

    // Block check
    const blockCheck = await p.query(
      `SELECT 1 FROM public.blocks
       WHERE (blocker_id = $1 AND blocked_id = $2)
          OR (blocker_id = $2 AND blocked_id = $1)
       LIMIT 1`,
      [auth.userId, postAuthorId]
    );
    if (blockCheck.rows.length > 0) {
      return c.json({ success: false, error: "No puedes comentar en esta publicación." }, 403);
    }

    let parentAuthorId: string | null = null;
    if (parentId) {
      const parentRes = await p.query(
        "SELECT id, author_id FROM public.post_comments WHERE id = $1 AND post_id = $2",
        [parentId, postId]
      );
      if (parentRes.rows.length === 0) {
        return c.json({ success: false, error: "Comentario original no encontrado" }, 400);
      }
      parentAuthorId = parentRes.rows[0].author_id;
    }

    const inserted = await p.query(
      `INSERT INTO public.post_comments (post_id, author_id, content, parent_id)
       VALUES ($1, $2, $3, $4)
       RETURNING id`,
      [postId, auth.userId, content, parentId]
    );
    const countRes = await p.query(
      "UPDATE public.posts SET comments_count = comments_count + 1 WHERE id = $1 RETURNING comments_count",
      [postId]
    );

    if (parentAuthorId && parentAuthorId !== auth.userId) {
      await notify(p, { recipientId: parentAuthorId, actorId: auth.userId, type: "comment", postId });
    }
    if (postAuthorId !== auth.userId && postAuthorId !== parentAuthorId) {
      await notify(p, { recipientId: postAuthorId, actorId: auth.userId, type: "comment", postId });
    }

    const commentRes = await p.query(
      `SELECT cm.id, cm.post_id, cm.parent_id, cm.content, cm.created_at, cm.author_id,
              cm.is_hidden, cm.reports_count,
              COALESCE(cm.likes_count, 0) AS likes_count,
              pr.username, pr.display_name, pr.avatar_url,
              parent_pr.username AS reply_to_username,
              FALSE AS is_liked
       FROM public.post_comments cm
       INNER JOIN public.profiles pr ON pr.id = cm.author_id
       LEFT JOIN public.post_comments parent_cm ON parent_cm.id = cm.parent_id
       LEFT JOIN public.profiles parent_pr ON parent_pr.id = parent_cm.author_id
       WHERE cm.id = $1`,
      [inserted.rows[0].id]
    );
    return c.json({
      success: true,
      comment: mapCommentRow(commentRes.rows[0]),
      commentsCount: countRes.rows[0]?.comments_count ?? 0,
    });
  } catch (err: any) {
    console.error("Create comment error:", err);
    return c.json({ success: false, error: err.message || "Error al comentar" }, 500);
  }
});

// Like / unlike a comment
app.post("/api/posts/:id/comments/:commentId/like", async (c) => {
  try {
    const auth = await getAuthenticatedUser(c);
    if (!auth) {
      return c.json({ success: false, error: "No autorizado o sesión expirada" }, 401);
    }

    const postId = c.req.param("id");
    const commentId = c.req.param("commentId");
    const p = getPool();
    await ensurePostCommentsTable(p);

    if (!(await visiblePostAuthor(p, postId, auth.userId))) {
      return c.json({ success: false, error: "Publicación no encontrada" }, 404);
    }

    const commentRes = await p.query(
      "SELECT id, author_id, likes_count FROM public.post_comments WHERE id = $1 AND post_id = $2",
      [commentId, postId]
    );
    if (commentRes.rows.length === 0) {
      return c.json({ success: false, error: "Comentario no encontrado" }, 404);
    }
    const commentRow = commentRes.rows[0];

    const existingLike = await p.query(
      "SELECT 1 FROM public.post_comment_likes WHERE comment_id = $1 AND user_id = $2",
      [commentId, auth.userId]
    );

    let isLiked = false;
    let newLikesCount = Number(commentRow.likes_count || 0);

    if (existingLike.rows.length > 0) {
      await p.query(
        "DELETE FROM public.post_comment_likes WHERE comment_id = $1 AND user_id = $2",
        [commentId, auth.userId]
      );
      const updateRes = await p.query(
        "UPDATE public.post_comments SET likes_count = GREATEST(0, likes_count - 1) WHERE id = $1 RETURNING likes_count",
        [commentId]
      );
      isLiked = false;
      newLikesCount = updateRes.rows[0]?.likes_count ?? Math.max(0, newLikesCount - 1);
    } else {
      await p.query(
        "INSERT INTO public.post_comment_likes (comment_id, user_id) VALUES ($1, $2) ON CONFLICT DO NOTHING",
        [commentId, auth.userId]
      );
      const updateRes = await p.query(
        "UPDATE public.post_comments SET likes_count = likes_count + 1 WHERE id = $1 RETURNING likes_count",
        [commentId]
      );
      isLiked = true;
      newLikesCount = updateRes.rows[0]?.likes_count ?? (newLikesCount + 1);

      if (commentRow.author_id !== auth.userId) {
        await notify(p, { recipientId: commentRow.author_id, actorId: auth.userId, type: "like", postId });
      }
    }

    return c.json({
      success: true,
      isLiked,
      likesCount: newLikesCount,
    });
  } catch (err: any) {
    console.error("Comment like error:", err);
    return c.json({ success: false, error: err.message || "Error al dar me gusta al comentario" }, 500);
  }
});

// The comment's author or the post's author can delete a comment (and its child replies)
app.delete("/api/posts/:id/comments/:commentId", async (c) => {
  try {
    const auth = await getAuthenticatedUser(c);
    if (!auth) {
      return c.json({ success: false, error: "No autorizado o sesión expirada" }, 401);
    }

    const postId = c.req.param("id");
    const commentId = c.req.param("commentId");
    const p = getPool();
    await ensurePostCommentsTable(p);

    const checkRes = await p.query(
      `SELECT cm.id, cm.author_id, po.author_id AS post_author_id
       FROM public.post_comments cm
       INNER JOIN public.posts po ON po.id = cm.post_id
       WHERE cm.id::text = $1 AND cm.post_id::text = $2`,
      [commentId, postId]
    );
    if (checkRes.rows.length === 0) {
      return c.json({ success: false, error: "Comentario no encontrado" }, 404);
    }
    const row = checkRes.rows[0];
    if (row.author_id !== auth.userId && row.post_author_id !== auth.userId) {
      return c.json({ success: false, error: "No tenés permiso para borrar este comentario" }, 403);
    }

    // Count how many comments in this subtree will be removed
    const countSubtree = await p.query(
      `WITH RECURSIVE tree AS (
         SELECT id FROM public.post_comments WHERE id::text = $1
         UNION ALL
         SELECT c.id FROM public.post_comments c INNER JOIN tree t ON c.parent_id = t.id
       )
       SELECT count(*)::int AS count FROM tree`,
      [commentId]
    );
    const toDeleteCount = countSubtree.rows[0]?.count ?? 1;

    await p.query("DELETE FROM public.post_comments WHERE id::text = $1", [commentId]);

    const countRes = await p.query(
      "UPDATE public.posts SET comments_count = GREATEST(0, comments_count - $1) WHERE id = $2 RETURNING comments_count",
      [toDeleteCount, postId]
    );
    return c.json({ success: true, commentsCount: countRes.rows[0]?.comments_count ?? 0 });
  } catch (err: any) {
    console.error("Delete comment error:", err);
    return c.json({ success: false, error: err.message || "Error al borrar el comentario" }, 500);
  }
});

// Delete own post (likes, comments, media rows and notifications go with it)
app.delete("/api/posts/:id", async (c) => {
  try {
    const auth = await getAuthenticatedUser(c);
    if (!auth) {
      return c.json({ success: false, error: "No autorizado o sesión expirada" }, 401);
    }

    const p = getPool();
    const res = await p.query(
      "DELETE FROM public.posts WHERE id::text = $1 AND author_id = $2 RETURNING id",
      [c.req.param("id"), auth.userId]
    );
    if (res.rows.length === 0) {
      return c.json({ success: false, error: "Publicación no encontrada" }, 404);
    }
    return c.json({ success: true });
  } catch (err: any) {
    console.error("Delete post error:", err);
    return c.json({ success: false, error: err.message || "Error al borrar la publicación" }, 500);
  }
});

// In-app notifications: likes, comments, follows, follow requests (and their acceptance) and messages.
// Message notifications never include the content, which can be end-to-end encrypted.
type NotificationType = "like" | "comment" | "follow" | "follow_request" | "follow_accepted" | "message";

interface NotificationEvent {
  recipientId: string;
  actorId: string;
  type: NotificationType;
  postId?: string | null;
  conversationId?: string | null;
}

let notificationsTable: Promise<void> | null = null;
function ensureNotificationsTable(p: Pool): Promise<void> {
  if (!notificationsTable) {
    notificationsTable = p
      .query(
        `CREATE TABLE IF NOT EXISTS public.notifications (
           id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
           recipient_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
           actor_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
           type VARCHAR(20) NOT NULL,
           post_id UUID REFERENCES public.posts(id) ON DELETE CASCADE,
           conversation_id UUID REFERENCES public.conversations(id) ON DELETE CASCADE,
           created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
           read_at TIMESTAMPTZ
         );
         CREATE INDEX IF NOT EXISTS idx_notifications_recipient_created
           ON public.notifications (recipient_id, created_at DESC);`
      )
      .then(() => undefined)
      .catch((err) => {
        notificationsTable = null;
        throw err;
      });
  }
  return notificationsTable;
}

// Removes unread notifications for an event that was undone or handled. Never throws.
async function clearNotification(p: Pool, event: NotificationEvent): Promise<void> {
  try {
    await ensureNotificationsTable(p);
    await p.query(
      `DELETE FROM public.notifications
       WHERE recipient_id = $1 AND actor_id = $2 AND type = $3 AND read_at IS NULL
         AND post_id IS NOT DISTINCT FROM $4::uuid
         AND conversation_id IS NOT DISTINCT FROM $5::uuid`,
      [event.recipientId, event.actorId, event.type, event.postId ?? null, event.conversationId ?? null]
    );
  } catch (err: any) {
    console.error("Clear notification error:", err.message);
  }
}

// Records a notification, replacing an unread one for the same event so repeats
// (like/unlike/like, several messages) don't pile up. Never throws.
async function notify(p: Pool, event: NotificationEvent): Promise<void> {
  if (event.recipientId === event.actorId) return;
  try {
    await clearNotification(p, event);
    await p.query(
      `INSERT INTO public.notifications (recipient_id, actor_id, type, post_id, conversation_id)
       VALUES ($1, $2, $3, $4, $5)`,
      [event.recipientId, event.actorId, event.type, event.postId ?? null, event.conversationId ?? null]
    );
  } catch (err: any) {
    console.error("Notification error:", err.message);
  }
}

async function unreadNotificationsCount(p: Pool, userId: string): Promise<number> {
  const res = await p.query(
    "SELECT COUNT(*)::int AS count FROM public.notifications WHERE recipient_id = $1 AND read_at IS NULL",
    [userId]
  );
  return res.rows[0]?.count ?? 0;
}

// Latest notifications with who triggered them
app.get("/api/notifications", async (c) => {
  try {
    const auth = await getAuthenticatedUser(c);
    if (!auth) {
      return c.json({ success: false, error: "No autorizado o sesión expirada" }, 401);
    }

    const p = getPool();
    await ensureNotificationsTable(p);
    const res = await p.query(
      `SELECT n.id, n.type, n.post_id, n.conversation_id, n.created_at, n.read_at,
              a.id AS actor_id, a.username, a.display_name, a.avatar_url,
              LEFT(po.content, 200) AS post_content
       FROM public.notifications n
       INNER JOIN public.profiles a ON a.id = n.actor_id
       LEFT JOIN public.posts po ON po.id = n.post_id
       WHERE n.recipient_id = $1
       ORDER BY n.created_at DESC
       LIMIT 50`,
      [auth.userId]
    );

    return c.json({
      success: true,
      unreadCount: await unreadNotificationsCount(p, auth.userId),
      notifications: res.rows.map((row) => ({
        id: row.id,
        type: row.type,
        createdAt: row.created_at,
        isRead: row.read_at !== null,
        postId: row.post_id,
        postContent: row.post_content,
        conversationId: row.conversation_id,
        actor: {
          id: row.actor_id,
          username: row.username,
          displayName: row.display_name,
          avatarUrl: row.avatar_url,
        },
      })),
    });
  } catch (err: any) {
    console.error("Notifications error:", err);
    return c.json({ success: false, error: err.message || "Error al obtener las notificaciones" }, 500);
  }
});

// Unread count for the badge (cheap enough to poll)
app.get("/api/notifications/unread-count", async (c) => {
  try {
    const auth = await getAuthenticatedUser(c);
    if (!auth) {
      return c.json({ success: false, error: "No autorizado o sesión expirada" }, 401);
    }

    const p = getPool();
    await ensureNotificationsTable(p);
    return c.json({ success: true, unreadCount: await unreadNotificationsCount(p, auth.userId) });
  } catch (err: any) {
    console.error("Unread notifications error:", err);
    return c.json({ success: false, error: err.message || "Error al contar las notificaciones" }, 500);
  }
});

// Mark every notification as read
app.post("/api/notifications/read", async (c) => {
  try {
    const auth = await getAuthenticatedUser(c);
    if (!auth) {
      return c.json({ success: false, error: "No autorizado o sesión expirada" }, 401);
    }

    const p = getPool();
    await ensureNotificationsTable(p);
    await p.query(
      "UPDATE public.notifications SET read_at = now() WHERE recipient_id = $1 AND read_at IS NULL",
      [auth.userId]
    );
    return c.json({ success: true });
  } catch (err: any) {
    console.error("Read notifications error:", err);
    return c.json({ success: false, error: err.message || "Error al marcar las notificaciones" }, 500);
  }
});

// ==========================================
// REPORTS & COMMUNITY SAFETY (Pillars 3 & 4)
// ==========================================

// Create a report (against post, comment or user)
app.post("/api/reports", async (c) => {
  try {
    const auth = await getAuthenticatedUser(c);
    if (!auth) {
      return c.json({ success: false, error: "No autorizado o sesión expirada" }, 401);
    }

    const body = await c.req.json().catch(() => ({}));
    const postId = typeof body.postId === "string" && body.postId.trim().length > 0 ? body.postId.trim() : null;
    const commentId = typeof body.commentId === "string" && body.commentId.trim().length > 0 ? body.commentId.trim() : null;
    const reportedUserId = typeof body.userId === "string" && body.userId.trim().length > 0 ? body.userId.trim() : null;
    const reason = typeof body.reason === "string" ? body.reason.trim() : "other";
    const details = typeof body.details === "string" ? body.details.trim() : null;

    if (!postId && !commentId && !reportedUserId) {
      return c.json({ success: false, error: "Debes especificar qué deseas reportar." }, 400);
    }

    const p = getPool();

    // Prevent duplicate reports from the same user on the same entity
    const existing = await p.query(
      `SELECT id FROM public.reports
       WHERE reporter_id = $1
         AND (
           ($2::uuid IS NOT NULL AND reported_post_id = $2::uuid)
           OR ($3::uuid IS NOT NULL AND reported_comment_id = $3::uuid)
           OR ($4::uuid IS NOT NULL AND reported_user_id = $4::uuid)
         )
       LIMIT 1`,
      [auth.userId, postId, commentId, reportedUserId]
    );

    if (existing.rows.length > 0) {
      return c.json({
        success: true,
        message: "Ya has reportado este contenido. Nuestro equipo lo está revisando.",
      });
    }

    await p.query(
      `INSERT INTO public.reports (reporter_id, reported_post_id, reported_comment_id, reported_user_id, reason, details)
       VALUES ($1, $2, $3, $4, $5, $6)`,
      [auth.userId, postId, commentId, reportedUserId, reason, details]
    );

    // Auto-hide threshold: if >= 3 reports, hide content automatically
    if (postId) {
      await p.query(
        `UPDATE public.posts
         SET reports_count = reports_count + 1,
             is_hidden = CASE WHEN reports_count + 1 >= 3 THEN true ELSE is_hidden END
         WHERE id = $1`,
        [postId]
      );
    } else if (commentId) {
      await p.query(
        `UPDATE public.post_comments
         SET reports_count = reports_count + 1,
             is_hidden = CASE WHEN reports_count + 1 >= 3 THEN true ELSE is_hidden END
         WHERE id = $1`,
        [commentId]
      );
    }

    return c.json({
      success: true,
      message: "Reporte recibido. Gracias por ayudar a mantener segura la comunidad.",
    });
  } catch (err: any) {
    console.error("Report error:", err);
    return c.json({ success: false, error: err.message || "Error al enviar reporte" }, 500);
  }
});

// Block a user
app.post("/api/users/:id/block", async (c) => {
  try {
    const auth = await getAuthenticatedUser(c);
    if (!auth) {
      return c.json({ success: false, error: "No autorizado o sesión expirada" }, 401);
    }

    const targetId = c.req.param("id");
    if (targetId === auth.userId) {
      return c.json({ success: false, error: "No puedes bloquearte a ti mismo" }, 400);
    }

    const p = getPool();
    await p.query(
      `INSERT INTO public.blocks (blocker_id, blocked_id)
       VALUES ($1, $2)
       ON CONFLICT (blocker_id, blocked_id) DO NOTHING`,
      [auth.userId, targetId]
    );

    // Break any follower/following relationship
    await p.query(
      `DELETE FROM public.follows
       WHERE (follower_id = $1 AND following_id = $2)
          OR (follower_id = $2 AND following_id = $1)`,
      [auth.userId, targetId]
    );

    return c.json({ success: true, isBlocked: true });
  } catch (err: any) {
    console.error("Block user error:", err);
    return c.json({ success: false, error: err.message || "Error al bloquear usuario" }, 500);
  }
});

// Unblock a user
app.delete("/api/users/:id/block", async (c) => {
  try {
    const auth = await getAuthenticatedUser(c);
    if (!auth) {
      return c.json({ success: false, error: "No autorizado o sesión expirada" }, 401);
    }

    const targetId = c.req.param("id");
    const p = getPool();
    await p.query(
      "DELETE FROM public.blocks WHERE blocker_id = $1 AND blocked_id = $2",
      [auth.userId, targetId]
    );

    return c.json({ success: true, isBlocked: false });
  } catch (err: any) {
    console.error("Unblock user error:", err);
    return c.json({ success: false, error: err.message || "Error al desbloquear usuario" }, 500);
  }
});

// Check block status with a user
app.get("/api/users/:id/block", async (c) => {
  try {
    const auth = await getAuthenticatedUser(c);
    if (!auth) {
      return c.json({ success: false, error: "No autorizado o sesión expirada" }, 401);
    }

    const targetId = c.req.param("id");
    const p = getPool();
    const res = await p.query(
      "SELECT 1 FROM public.blocks WHERE blocker_id = $1 AND blocked_id = $2",
      [auth.userId, targetId]
    );

    return c.json({ success: true, isBlocked: res.rows.length > 0 });
  } catch (err: any) {
    console.error("Get block status error:", err);
    return c.json({ success: false, error: err.message || "Error al consultar estado de bloqueo" }, 500);
  }
});

// List reports (Admin & Moderator Dashboard)
app.get("/api/admin/reports", async (c) => {
  try {
    const admin = await requireAdminUser(c);
    if (!admin) {
      return c.json({ success: false, error: "Acceso denegado. Se requieren permisos de moderación." }, 403);
    }

    const status = c.req.query("status") || "pending";
    const { p } = admin;

    const sql = `
      SELECT
        r.id,
        r.reason,
        r.details,
        r.status,
        r.action_taken,
        r.created_at,
        r.resolved_at,
        -- Reporter
        rep.id as reporter_id,
        rep.username as reporter_username,
        rep.display_name as reporter_name,
        rep.avatar_url as reporter_avatar_url,
        -- Reported post
        po.id as post_id,
        po.content as post_content,
        po.image_url as post_image_url,
        po.is_sensitive as post_is_sensitive,
        po.is_hidden as post_is_hidden,
        po.reports_count as post_reports_count,
        po_author.id as post_author_id,
        po_author.username as post_author_username,
        po_author.display_name as post_author_name,
        -- Reported comment
        cm.id as comment_id,
        cm.content as comment_content,
        cm.is_hidden as comment_is_hidden,
        cm.reports_count as comment_reports_count,
        cm_author.id as comment_author_id,
        cm_author.username as comment_author_username,
        cm_author.display_name as comment_author_name,
        -- Reported user
        ru.id as user_id,
        ru.username as user_username,
        ru.display_name as user_name,
        ru.avatar_url as user_avatar_url,
        ru.is_suspended as user_is_suspended
      FROM public.reports r
      LEFT JOIN public.profiles rep ON rep.id = r.reporter_id
      LEFT JOIN public.posts po ON po.id = r.reported_post_id
      LEFT JOIN public.profiles po_author ON po_author.id = po.author_id
      LEFT JOIN public.post_comments cm ON cm.id = r.reported_comment_id
      LEFT JOIN public.profiles cm_author ON cm_author.id = cm.author_id
      LEFT JOIN public.profiles ru ON ru.id = r.reported_user_id
      WHERE ($1 = 'all' OR r.status = $1)
      ORDER BY r.created_at DESC
      LIMIT 100
    `;

    const res = await p.query(sql, [status]);
    return c.json({
      success: true,
      reports: res.rows.map((row) => ({
        id: row.id,
        reason: row.reason,
        details: row.details,
        status: row.status,
        actionTaken: row.action_taken,
        createdAt: row.created_at,
        resolvedAt: row.resolved_at,
        reporter: row.reporter_id ? {
          id: row.reporter_id,
          username: row.reporter_username,
          displayName: row.reporter_name,
          avatarUrl: row.reporter_avatar_url,
        } : null,
        post: row.post_id ? {
          id: row.post_id,
          content: row.post_content,
          imageUrl: row.post_image_url,
          isSensitive: Boolean(row.post_is_sensitive),
          isHidden: Boolean(row.post_is_hidden),
          reportsCount: Number(row.post_reports_count || 0),
          authorId: row.post_author_id,
          authorUsername: row.post_author_username,
          authorName: row.post_author_name,
        } : null,
        comment: row.comment_id ? {
          id: row.comment_id,
          content: row.comment_content,
          isHidden: Boolean(row.comment_is_hidden),
          reportsCount: Number(row.comment_reports_count || 0),
          authorId: row.comment_author_id,
          authorUsername: row.comment_author_username,
          authorName: row.comment_author_name,
        } : null,
        user: row.user_id ? {
          id: row.user_id,
          username: row.user_username,
          displayName: row.user_name,
          avatarUrl: row.user_avatar_url,
          isSuspended: Boolean(row.user_is_suspended),
        } : null,
      })),
    });
  } catch (err: any) {
    console.error("Admin reports error:", err);
    return c.json({ success: false, error: err.message || "Error al obtener reportes" }, 500);
  }
});

// Take moderator action on a report
app.post("/api/admin/reports/:id/action", async (c) => {
  try {
    const admin = await requireAdminUser(c);
    if (!admin) {
      return c.json({ success: false, error: "Acceso denegado. Se requieren permisos de moderación." }, 403);
    }

    const reportId = c.req.param("id");
    const body = await c.req.json().catch(() => ({}));
    const action = body.action; // 'dismiss' | 'hide' | 'delete' | 'suspend'
    const { p, userId } = admin;

    const repRes = await p.query(
      "SELECT * FROM public.reports WHERE id = $1",
      [reportId]
    );
    if (repRes.rows.length === 0) {
      return c.json({ success: false, error: "Reporte no encontrado" }, 404);
    }
    const report = repRes.rows[0];

    if (action === "dismiss") {
      await p.query(
        `UPDATE public.reports
         SET status = 'dismissed', action_taken = 'dismiss', resolved_at = now(), resolved_by = $1
         WHERE id = $2`,
        [userId, reportId]
      );
      if (report.reported_post_id) {
        await p.query("UPDATE public.posts SET is_hidden = false, reports_count = 0 WHERE id = $1", [report.reported_post_id]);
      } else if (report.reported_comment_id) {
        await p.query("UPDATE public.post_comments SET is_hidden = false, reports_count = 0 WHERE id = $1", [report.reported_comment_id]);
      }
    } else if (action === "hide") {
      await p.query(
        `UPDATE public.reports
         SET status = 'resolved', action_taken = 'hide', resolved_at = now(), resolved_by = $1
         WHERE id = $2`,
        [userId, reportId]
      );
      if (report.reported_post_id) {
        await p.query("UPDATE public.posts SET is_hidden = true WHERE id = $1", [report.reported_post_id]);
      } else if (report.reported_comment_id) {
        await p.query("UPDATE public.post_comments SET is_hidden = true WHERE id = $1", [report.reported_comment_id]);
      }
    } else if (action === "delete") {
      await p.query(
        `UPDATE public.reports
         SET status = 'resolved', action_taken = 'delete', resolved_at = now(), resolved_by = $1
         WHERE id = $2`,
        [userId, reportId]
      );
      if (report.reported_post_id) {
        await p.query("DELETE FROM public.posts WHERE id = $1", [report.reported_post_id]);
      } else if (report.reported_comment_id) {
        await p.query("DELETE FROM public.post_comments WHERE id = $1", [report.reported_comment_id]);
      }
    } else if (action === "suspend") {
      await p.query(
        `UPDATE public.reports
         SET status = 'resolved', action_taken = 'suspend', resolved_at = now(), resolved_by = $1
         WHERE id = $2`,
        [userId, reportId]
      );

      let targetUserId = report.reported_user_id;
      if (!targetUserId && report.reported_post_id) {
        const poRes = await p.query("SELECT author_id FROM public.posts WHERE id = $1", [report.reported_post_id]);
        targetUserId = poRes.rows[0]?.author_id;
      } else if (!targetUserId && report.reported_comment_id) {
        const cmRes = await p.query("SELECT author_id FROM public.post_comments WHERE id = $1", [report.reported_comment_id]);
        targetUserId = cmRes.rows[0]?.author_id;
      }

      if (targetUserId) {
        await p.query("UPDATE public.profiles SET is_suspended = true WHERE id = $1", [targetUserId]);
        await p.query("UPDATE public.posts SET is_hidden = true WHERE author_id = $1", [targetUserId]);
        await p.query("UPDATE public.post_comments SET is_hidden = true WHERE author_id = $1", [targetUserId]);
      }
    } else {
      return c.json({ success: false, error: "Acción no válida." }, 400);
    }

    return c.json({ success: true, message: `Acción '${action}' aplicada correctamente.` });
  } catch (err: any) {
    console.error("Report action error:", err);
    return c.json({ success: false, error: err.message || "Error al procesar acción sobre reporte" }, 500);
  }
});

export default app;
