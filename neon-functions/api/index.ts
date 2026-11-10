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

  let pendingRequestsCount = 0;
  if (isOwner) {
    const reqRes = await p.query(
      `SELECT COUNT(*)::int as count FROM public.follows WHERE following_id = $1 AND status = 'pending'`,
      [profileId]
    );
    pendingRequestsCount = reqRes.rows[0]?.count ?? 0;
  }

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
    pendingRequestsCount,
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

    const profileRes = await p.query(
      "SELECT id, username, display_name, bio, avatar_url, COALESCE(banner_url, header_url) as banner_url, is_private FROM public.profiles WHERE id = $1",
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

    const profileRes = await p.query(
      "SELECT id, username, display_name, bio, avatar_url, COALESCE(banner_url, header_url) as banner_url, is_private FROM public.profiles WHERE id = $1",
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

    const body = await c.req.json().catch(() => ({}));
    const content = typeof body.content === "string" ? body.content.trim() : "";
    const imageUrl = typeof body.imageUrl === "string" && body.imageUrl.trim().length > 0 ? body.imageUrl.trim() : null;

    if (!content && !imageUrl) {
      return c.json({ success: false, error: "La publicación debe tener texto o una imagen." }, 400);
    }

    const p = getPool();
    const insertRes = await p.query(
      `INSERT INTO public.posts (author_id, content, image_url, visibility, created_at, updated_at)
       VALUES ($1, $2, $3, 'public', now(), now())
       RETURNING id, author_id, content, image_url, likes_count, comments_count, created_at`,
      [auth.userId, content || null, imageUrl]
    );

    const postRow = insertRes.rows[0];

    // If imageUrl exists, also populate post_media for relational consistency
    if (imageUrl) {
      await p.query(
        `INSERT INTO public.post_media (post_id, media_type, media_url, order_index, created_at)
         VALUES ($1, 'image', $2, 0, now())`,
        [postRow.id, imageUrl]
      );
    }

    // Fetch author profile
    const authorRes = await p.query(
      "SELECT id, username, display_name, avatar_url, is_private FROM public.profiles WHERE id = $1",
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
        isVerified: true,
        content: postRow.content || "",
        imageUrl: postRow.image_url,
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

// Helper for formatting post rows
function mapPostRow(row: any) {
  return {
    id: row.id,
    authorId: row.author_id,
    authorName: row.author_name || row.author_username || "Usuario",
    authorUsername: row.author_username || "usuario",
    authorAvatarUrl: row.author_avatar_url,
    isVerified: true,
    content: row.content || "",
    imageUrl: row.image_url || null,
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
    const filter = c.req.query("filter"); // "following" or undefined
    const p = getPool();

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
          p.likes_count,
          p.comments_count,
          p.created_at,
          pr.username as author_username,
          pr.display_name as author_name,
          pr.avatar_url as author_avatar_url,
          pr.is_private as author_is_private,
          EXISTS(SELECT 1 FROM public.post_likes pl WHERE pl.post_id = p.id AND pl.user_id = $1::uuid) as is_liked,
          true as is_following_author
        FROM public.posts p
        INNER JOIN public.profiles pr ON p.author_id = pr.id
        INNER JOIN public.follows f ON f.following_id = p.author_id AND f.follower_id = $1::uuid AND f.status = 'accepted'
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
        p.likes_count,
        p.comments_count,
        p.created_at,
        pr.username as author_username,
        pr.display_name as author_name,
        pr.avatar_url as author_avatar_url,
        pr.is_private as author_is_private,
        ($1::uuid IS NOT NULL AND EXISTS(SELECT 1 FROM public.post_likes pl WHERE pl.post_id = p.id AND pl.user_id = $1::uuid)) as is_liked,
        ($1::uuid IS NOT NULL AND EXISTS(SELECT 1 FROM public.follows f WHERE f.follower_id = $1::uuid AND f.following_id = p.author_id AND f.status = 'accepted')) as is_following_author
      FROM public.posts p
      INNER JOIN public.profiles pr ON p.author_id = pr.id
      WHERE
        pr.is_private = false
        OR ($1::uuid IS NOT NULL AND (
             p.author_id = $1::uuid
             OR EXISTS(SELECT 1 FROM public.follows f WHERE f.follower_id = $1::uuid AND f.following_id = p.author_id AND f.status = 'accepted')
           ))
      ORDER BY p.created_at DESC
      LIMIT 50;
    `;

    const res = await p.query(sql, [viewerId]);
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
        p.likes_count,
        p.comments_count,
        p.created_at,
        pr.username as author_username,
        pr.display_name as author_name,
        pr.avatar_url as author_avatar_url,
        pr.is_private as author_is_private,
        EXISTS(SELECT 1 FROM public.post_likes pl WHERE pl.post_id = p.id AND pl.user_id = $1::uuid) as is_liked,
        true as is_following_author
      FROM public.posts p
      INNER JOIN public.profiles pr ON p.author_id = pr.id
      INNER JOIN public.follows f ON f.following_id = p.author_id AND f.follower_id = $1::uuid AND f.status = 'accepted'
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
        p.likes_count,
        p.comments_count,
        p.created_at,
        pr.username as author_username,
        pr.display_name as author_name,
        pr.avatar_url as author_avatar_url,
        pr.is_private as author_is_private,
        ($2::uuid IS NOT NULL AND EXISTS(SELECT 1 FROM public.post_likes pl WHERE pl.post_id = p.id AND pl.user_id = $2::uuid)) as is_liked
      FROM public.posts p
      INNER JOIN public.profiles pr ON p.author_id = pr.id
      WHERE p.author_id = $1
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

    const countRes = await p.query("SELECT likes_count FROM public.posts WHERE id = $1", [postId]);
    const likesCount = countRes.rows[0]?.likes_count ?? 0;

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

export default app;
