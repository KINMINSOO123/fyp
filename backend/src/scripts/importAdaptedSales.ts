import { resolve } from "node:path";
import { buildImportPlan } from "../modules/sales-import/adapted-demo-import.js";
import { AdaptedDemoImportRepo } from
  "../modules/sales-import/adapted-demo-import.repo.js";
import { readReviewedPackage } from
  "../modules/sales-import/adapted-demo-package.js";

function options(): { zipPath: string; apply: boolean } {
  const args = process.argv.slice(2);
  const zipIndex = args.indexOf("--zip");
  const mode = args.filter((arg) => arg === "--dry-run" || arg === "--apply");
  if (args.length !== 3 || (zipIndex !== 0 && zipIndex !== 1) ||
      !args[zipIndex + 1] || args[zipIndex + 1]!.startsWith("--") ||
      mode.length !== 1 || args.some((arg, index) =>
        index !== zipIndex && index !== zipIndex + 1 && arg !== mode[0])) {
    throw new Error("Usage: --zip <reviewed-package.zip> --dry-run | --apply");
  }
  return { zipPath: resolve(args[zipIndex + 1]!), apply: mode[0] === "--apply" };
}

function printFindings<T extends object>(label: string, rows: T[]): void {
  console.log(`${label}: ${rows.length}`);
  if (rows.length) console.table(rows.slice(0, 20));
  if (rows.length > 20) console.log(`... ${rows.length - 20} more ${label.toLowerCase()}.`);
}

async function main(): Promise<void> {
  const { zipPath, apply } = options();
  const csv = readReviewedPackage(zipPath);
  const repo = new AdaptedDemoImportRepo();
  const [categories, existing, targetDate] = await Promise.all([
    repo.loadCategories(), repo.loadExistingSales(), repo.getBakeryDate(),
  ]);
  const plan = buildImportPlan(csv, categories, existing, targetDate);
  console.log(`Mode: ${apply ? "APPLY" : "DRY RUN"}`);
  console.log(`Bakery date: ${targetDate}`);
  console.log(`Reviewed CSV SHA-256: ${plan.dataset.csvSha256}`);
  console.log(`Provenance: ${plan.dataset.dataUsage}; ${plan.dataset.timelineType}`);
  console.table(plan.categories.map((item) => ({ category: item.name,
    categoryId: item.id ?? "MISSING", active: item.isActive,
    rows: item.packageRows, accepted: item.accepted,
    alreadyImported: item.identicalExisting, rejected: item.rejected,
    conflicts: item.conflicts, from: item.firstDate, through: item.lastDate,
    eligibleNow: item.eligibleDatesNow,
    eligibleAfter: item.eligibleDatesAfter })));
  printFindings("Rejected CSV rows", plan.rejected);
  printFindings("Existing-record conflicts", plan.conflicts);
  printFindings("Possible earlier demo rows", plan.previousDemoRows);
  console.log(`Accepted for insert: ${plan.accepted.length}`);
  console.log(`Identical already imported: ${plan.identicalExisting.length}`);
  if (plan.issues.length) console.log("Issues:\n" + plan.issues.join("\n"));
  console.log(`Import permitted: ${plan.canApply ? "YES" : "NO"}`);
  if (!apply) return;
  if (!plan.canApply) throw new Error("Import blocked; reconcile the findings first.");
  const inserted = await repo.insertAccepted(plan.accepted);
  console.log(`Inserted ${inserted} validated imported-historical rows. No models were trained or activated.`);
}

main().catch((error: unknown) => {
  console.error(error instanceof Error ? error.message : "Import failed.");
  process.exitCode = 1;
});
