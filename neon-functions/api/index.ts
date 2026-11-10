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
      "SELECT id, username, display_name, bio, avatar_url, COALESCE(banner_url, header_url) as banner_url FROM public.profiles WHERE id = $1",
      [userId]
    );
    const profile = profileRes.rows[0] || {
      id: userId,
      username: queryParam,
      display_name: authData.user.name,
      bio: null,
      avatarUrl: null,
      bannerUrl: null,
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
      `SELECT s.token, u.id, u.email, u.name, p.username, p.display_name, p.bio, p.avatar_url, COALESCE(p.banner_url, p.header_url) as banner_url
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

  if (viewerId && !isOwner) {
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
    isPrivate,
    followersCount,
    followingCount,
    followStatus,
    isFollowedBy,
    canViewContent,
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
      "SELECT id, username, display_name, bio, avatar_url, COALESCE(banner_url, header_url) as banner_url, is_private FROM public.profiles WHERE id = $1",
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
    const sql = `UPDATE public.profiles SET ${updates.join(", ")} WHERE id = $${paramIndex} RETURNING id, username, display_name, bio, avatar_url, COALESCE(banner_url, header_url) as banner_url, is_private`;
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
      `SELECT id, username, display_name, bio, avatar_url, COALESCE(banner_url, header_url) as banner_url, is_private
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
      `SELECT id, username, display_name, bio, avatar_url, COALESCE(banner_url, header_url) as banner_url, is_private
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
      "SELECT id, username, display_name, bio, avatar_url, COALESCE(banner_url, header_url) as banner_url, is_private FROM public.profiles WHERE lower(username) = $1",
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
      `SELECT id, username, display_name, bio, avatar_url, COALESCE(banner_url, header_url) as banner_url, is_private
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
      `SELECT id, username, display_name, bio, avatar_url, COALESCE(banner_url, header_url) as banner_url, is_private
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

    return c.json({ success: true, message: "Solicitud de seguimiento aceptada" });
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

    return c.json({ success: true, message: "Solicitud de seguimiento rechazada" });
  } catch (err: any) {
    return c.json({ success: false, error: err.message || "Error al rechazar solicitud" }, 500);
  }
});

export default app;
