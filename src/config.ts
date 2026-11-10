import dotenv from "dotenv";

// Load .env.local first, fallback to .env
dotenv.config({ path: ".env.local" });
dotenv.config({ path: ".env" });

export const config = {
  port: parseInt(process.env.PORT || "3333", 10),
  // Postgres
  databaseUrl: (process.env.DATABASE_URL || "").replace("sslmode=require", "sslmode=verify-full"),
  databaseUrlUnpooled: process.env.DATABASE_URL_UNPOOLED,
  // Branch & Functions
  neonBranch: process.env.NEON_BRANCH,
  neonBranchId: process.env.NEON_BRANCH_ID,
  neonFunctionHostSuffix: process.env.NEON_FUNCTION_HOST_SUFFIX,
  // Auth
  neonAuthBaseUrl: process.env.NEON_AUTH_BASE_URL,
  neonAuthJwksUrl: process.env.NEON_AUTH_JWKS_URL,
  // Realtime
  neonRealtimeUrl: process.env.NEON_REALTIME_URL,
  neonRealtimeSecret: process.env.NEON_REALTIME_SECRET,
  // Object Storage (S3)
  awsAccessKeyId: process.env.AWS_ACCESS_KEY_ID,
  awsSecretAccessKey: process.env.AWS_SECRET_ACCESS_KEY,
  awsEndpointUrlS3: process.env.AWS_ENDPOINT_URL_S3,
  awsRegion: process.env.AWS_REGION || "us-east-2",
  storageBucket: "assets",
};
