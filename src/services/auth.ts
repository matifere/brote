import { createAuthClient } from "@neon/auth";
import { config } from "../config.js";

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
