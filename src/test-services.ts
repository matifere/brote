import { runAllTests } from "./index.js";
import { closePostgres } from "./services/postgres.js";

async function main() {
  console.log("==================================================");
  console.log("   BROTE APP - NEON SERVICES END-TO-END TEST");
  console.log("==================================================");

  const report = await runAllTests();

  console.log("\n--- TEST RESULTS PER SERVICE ---");
  for (const [service, res] of Object.entries(report.services) as [string, any][]) {
    const statusIcon = res.success ? "✓ PASS" : "✗ FAIL";
    console.log(`\n[${statusIcon}] Service: ${service.toUpperCase()}`);
    console.log(JSON.stringify(res, null, 2));
  }

  console.log("\n==================================================");
  if (report.allPassed) {
    console.log("✓ ALL NEON SERVICES VERIFIED END-TO-END SUCCESSFULLY!");
  } else {
    console.error("✗ SOME SERVICES FAILED END-TO-END VERIFICATION!");
  }
  console.log("==================================================");

  await closePostgres();
  if (!report.allPassed) {
    process.exit(1);
  }
}

main().catch(async (err) => {
  console.error("Unexpected error during test execution:", err);
  await closePostgres();
  process.exit(1);
});
