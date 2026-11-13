import { createHash } from "node:crypto";
import { cp, mkdir, readdir, readFile, writeFile } from "node:fs/promises";
import path from "node:path";
import { supabaseAdmin } from "../config/supabase.js";

const tables = [
  "daily_sales_records", "daily_predictions", "prediction_calendar_events",
  "production_decisions", "daily_production", "daily_results",
  "sales_transactions", "sales_by_timeslot", "donations", "waste_records",
  "inventory_log", "inventory_batches", "inventory", "weather_records",
  "calendar_events", "kl_holiday_syncs", "ml_model_versions",
  "model_evaluations", "feature_importance", "restock_requests",
  "restock_request_items", "notifications", "notification_deliveries",
  "system_logs", "simulation_baselines", "simulation_scenarios",
  "bread_categories", "recipes", "ingredients", "system_settings",
  "bakery_settings", "charity_partners", "reviewed_ai_bread_requests",
] as const;

async function run() {
  const label = new Date().toISOString().replace(/[:.]/g, "-");
  const root = path.resolve(process.cwd(), "../backups", `experiment-inspection-${label}`);
  await mkdir(root, { recursive: true, mode: 0o700 });
  const manifest: Record<string, unknown> = { createdAt: new Date().toISOString(),
    purpose: "Read-only pre-reset snapshot. No database rows were changed.", tables: {} };
  const summary = manifest.tables as Record<string, unknown>;
  for (const table of tables) {
    const rows: Record<string, unknown>[] = [];
    let unavailable: string | null = null;
    for (let offset = 0; ; offset += 500) {
      const { data, error } = await supabaseAdmin.from(table).select("*")
        .range(offset, offset + 499);
      if (error || !data) {
        unavailable = error?.code ?? "READ_FAILED";
        break;
      }
      rows.push(...data);
      if (data.length < 500) break;
    }
    if (unavailable) {
      summary[table] = { status: "UNAVAILABLE", code: unavailable };
      continue;
    }
    const bytes = Buffer.from(JSON.stringify(rows, null, 2));
    await writeFile(path.join(root, `${table}.json`), bytes, { mode: 0o600 });
    summary[table] = { status: "BACKED_UP", rows: rows.length,
      sha256: createHash("sha256").update(bytes).digest("hex") };
  }
  const source = path.resolve(process.cwd(), "../ml_service/artifacts");
  const names = await readdir(source).catch(() => [] as string[]);
  const artifactFiles = await readdir(source, { recursive: true })
    .catch(() => [] as string[]);
  const artifactSummary: Record<string, unknown> = {};
  if (names.length) {
    const destination = path.join(root, "model-artifacts");
    await cp(source, destination, { recursive: true, errorOnExist: true, force: false });
    for (const name of artifactFiles) {
      if (!name.endsWith(".joblib")) continue;
      const bytes = await readFile(path.join(source, name));
      artifactSummary[name] = { bytes: bytes.length,
        sha256: createHash("sha256").update(bytes).digest("hex") };
    }
  }
  manifest.modelArtifacts = artifactSummary;
  await writeFile(path.join(root, "manifest.json"),
    JSON.stringify(manifest, null, 2), { mode: 0o600 });
  console.log(JSON.stringify({ backupPath: root, tables: summary,
    modelArtifactCount: Object.keys(artifactSummary).length }, null, 2));
}

run().catch((error: unknown) => {
  console.error("Read-only backup failed:", error instanceof Error ? error.message : error);
  process.exitCode = 1;
});
