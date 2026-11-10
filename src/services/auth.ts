import { createAuthClient } from "@neon/auth";
import { config } from "../config.js";
import { getPostgresPool } from "./postgres.js";

export function getAuthClient() {
  if (!config.neonAuthBaseUrl) {
    throw new Error("NEON_AUTH_BASE_URL is not set in environment.");
  }
  return createAuthClient(config.neonAuthBaseUrl);
}

export async function testAuth(): Promise<{
  success: boolean;
  baseUrl: string;
  jwksUrl: string;
  keysFound: number;
  keyIds: string[];
}> {
  if (!config.neonAuthJwksUrl) {
    throw new Error("NEON_AUTH_JWKS_URL is not set in environment.");
  }

  // Fetch JWKS endpoint
  const response = await fetch(config.neonAuthJwksUrl);
  if (!response.ok) {
    throw new Error(
      `Failed to fetch JWKS from ${config.neonAuthJwksUrl}: ${response.status} ${response.statusText}`
    );
  }

  const jwks = (await response.json()) as { keys?: Array<{ kid?: string; kty?: string; alg?: string }> };
  const keys = jwks.keys || [];

  if (keys.length === 0) {
    throw new Error("No public keys found in Neon Auth JWKS endpoint.");
  }

  return {
    success: true,
    baseUrl: config.neonAuthBaseUrl || "",
    jwksUrl: config.neonAuthJwksUrl,
    keysFound: keys.length,
    keyIds: keys.map((k) => k.kid || "unknown"),
  };
}

export interface RegisterParams {
  username: string;
  password: string;
  displayName: string;
  email?: string;
}

export interface AuthResult {
  user: {
    id: string;
    email: string;
    name: string;
  };
  profile: {
    id: string;
    username: string;
    displayName: string;
    bio?: string | null;
    avatarUrl?: string | null;
  };
  token: string;
}

export async function registerUser(params: RegisterParams): Promise<AuthResult> {
  const username = params.username.trim().toLowerCase();
  const displayName = params.displayName.trim();
  const password = params.password;

  if (!username || username.length < 3) {
    throw new Error("El nombre de usuario debe tener al menos 3 caracteres.");
  }
  if (!/^[a-z0-9_]+$/.test(username)) {
    throw new Error("El nombre de usuario solo puede contener letras, números y guiones bajos.");
  }
  if (!displayName) {
    throw new Error("El nombre a mostrar es obligatorio.");
  }
  if (!password || password.length < 6) {
    throw new Error("La contraseña debe tener al menos 6 caracteres.");
  }

  const pool = getPostgresPool();

  // 1. Check if username is already taken in profiles
  const existingCheck = await pool.query(
    "SELECT id FROM public.profiles WHERE lower(username) = $1 LIMIT 1",
    [username]
  );
  if (existingCheck.rows.length > 0) {
    throw new Error("El nombre de usuario ya está registrado.");
  }

  // 2. Compute email
  const email = (params.email?.trim() || `${username}@brote.app`).toLowerCase();

  // 3. Register in Neon Auth (Better Auth)
  const authResponse = await fetch(`${config.neonAuthBaseUrl}/sign-up/email`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Origin: `http://localhost:${config.port}`,
    },
    body: JSON.stringify({
      email,
      password,
      name: displayName,
    }),
  });

  const authData = (await authResponse.json()) as any;
  if (!authResponse.ok) {
    throw new Error(authData.message || "No se pudo registrar el usuario en el servicio de autenticación.");
  }

  const userId = authData.user?.id;
  const token = authData.token;

  // 4. Update the profile created by trigger to use the exact requested username and display name
  await pool.query(
    `INSERT INTO public.profiles (id, username, display_name)
     VALUES ($1, $2, $3)
     ON CONFLICT (id) DO UPDATE
     SET username = EXCLUDED.username, display_name = EXCLUDED.display_name, updated_at = now()`,
    [userId, username, displayName]
  );

  const profileRes = await pool.query(
    "SELECT id, username, display_name, bio, avatar_url FROM public.profiles WHERE id = $1",
    [userId]
  );
  const profile = profileRes.rows[0];

  return {
    user: {
      id: userId,
      email: authData.user.email,
      name: authData.user.name,
    },
    profile: {
      id: profile.id,
      username: profile.username,
      displayName: profile.display_name,
      bio: profile.bio,
      avatarUrl: profile.avatar_url,
    },
    token,
  };
}

export async function loginUser(usernameOrEmail: string, password: string): Promise<AuthResult> {
  const queryParam = usernameOrEmail.trim();
  if (!queryParam) {
    throw new Error("Debes ingresar un nombre de usuario o email.");
  }
  if (!password) {
    throw new Error("Debes ingresar la contraseña.");
  }

  const pool = getPostgresPool();
  let email = queryParam.toLowerCase();

  // If queryParam is not an email, lookup from profiles -> neon_auth.user
  if (!queryParam.includes("@")) {
    const userRes = await pool.query(
      `SELECT u.email, p.id, p.username, p.display_name, p.bio, p.avatar_url
       FROM public.profiles p
       INNER JOIN neon_auth.user u ON p.id = u.id
       WHERE lower(p.username) = lower($1)
       LIMIT 1`,
      [queryParam]
    );

    if (userRes.rows.length === 0) {
      throw new Error("Usuario o contraseña incorrectos.");
    }
    email = userRes.rows[0].email;
  }

  // Call Neon Auth sign-in
  const authResponse = await fetch(`${config.neonAuthBaseUrl}/sign-in/email`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Origin: `http://localhost:${config.port}`,
    },
    body: JSON.stringify({
      email,
      password,
    }),
  });

  const authData = (await authResponse.json()) as any;
  if (!authResponse.ok) {
    throw new Error("Usuario o contraseña incorrectos.");
  }

  const userId = authData.user?.id;
  const token = authData.token;

  const profileRes = await pool.query(
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

  return {
    user: {
      id: userId,
      email: authData.user.email,
      name: authData.user.name,
    },
    profile: {
      id: profile.id,
      username: profile.username,
      displayName: profile.display_name,
      bio: profile.bio,
      avatarUrl: profile.avatar_url,
    },
    token,
  };
}
