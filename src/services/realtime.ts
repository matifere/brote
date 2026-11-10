import { createRealtime, rawSql, type RealtimeDirectServer } from "@neon/realtime/server";
import { config } from "../config.js";

export function getRealtimeServer() {
  if (!config.neonRealtimeSecret || !config.neonRealtimeUrl) {
    throw new Error("NEON_REALTIME_SECRET or NEON_REALTIME_URL is not set in environment.");
  }
  return createRealtime({
    url: config.neonRealtimeUrl,
    secret: config.neonRealtimeSecret,
    db: "neondb",
  });
}

export async function testRealtime(): Promise<{
  success: boolean;
  realtimeUrl: string;
  queryFingerprint: string;
  subscriptionEstablished: boolean;
}> {
  if (!config.neonRealtimeUrl || !config.neonRealtimeSecret) {
    throw new Error("NEON_REALTIME_URL or NEON_REALTIME_SECRET is not set in environment.");
  }

  const realtime = getRealtimeServer();
  const query = rawSql("SELECT 1 AS num");

  // 1. Test sealing query
  const sealed = (await realtime.seal({ query })) as { queryFingerprint?: string; capability?: string };

  // 2. Test live subscription
  const sub = await realtime.subscribe(query);
  const subscriptionEstablished = !!sub;

  // Wait brief moment then close
  await new Promise((resolve) => setTimeout(resolve, 500));
  await realtime.close();

  return {
    success: true,
    realtimeUrl: config.neonRealtimeUrl,
    queryFingerprint: sealed.queryFingerprint || "generated",
    subscriptionEstablished,
  };
}
