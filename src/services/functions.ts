import { config } from "../config.js";

export function getFunctionUrl(functionSlug: string = "hello"): string {
  if (!config.neonBranchId || !config.neonFunctionHostSuffix) {
    throw new Error("NEON_BRANCH_ID or NEON_FUNCTION_HOST_SUFFIX is not set in environment.");
  }
  return `https://${config.neonBranchId}-${functionSlug}${config.neonFunctionHostSuffix}/`;
}

export async function testFunctions(): Promise<{
  success: boolean;
  functionUrl: string;
  statusCode: number;
  responseBody: string;
}> {
  const url = getFunctionUrl("hello");
  const response = await fetch(url);

  if (!response.ok) {
    throw new Error(
      `Failed to call Neon Function at ${url}: ${response.status} ${response.statusText}`
    );
  }

  const responseBody = await response.text();

  return {
    success: true,
    functionUrl: url,
    statusCode: response.status,
    responseBody: responseBody.trim(),
  };
}
