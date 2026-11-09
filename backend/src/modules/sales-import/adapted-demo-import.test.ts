import assert from "node:assert/strict";
import { test } from "node:test";
import { buildImportPlan, SOURCE_PRODUCTS, type ExistingSale } from
  "./adapted-demo-import.js";

const names = Object.keys(SOURCE_PRODUCTS);
const categories = names.map((name, index) => ({
  id: `category-${index}`, name, isActive: true,
}));
const header = "sales_date,bread_category,units_sold,data_origin,external_source_reference,is_validated,data_usage,original_sales_date,source_product,source_daily_net_quantity,source_transaction_rows,source_negative_quantity_rows,quantity_scale_factor,previous_demo_sales_date,timeline_type";

function fixture(): string {
  const lines = [header];
  for (const name of names) {
    for (let index = 0; index < 30; index++) {
      const date = new Date(Date.UTC(2026, 9, 10 + index))
        .toISOString().slice(0, 10);
      const product = SOURCE_PRODUCTS[name]!;
      lines.push([
        date, name, String(index), "IMPORTED_HISTORICAL",
        `adapted-demo-timeline-v2:af5eede55b6eb2ef:${date}:${product}`,
        "false", "ADAPTED_DEMO", date, product, "10", "2", "0", "1",
        date, "DUMMY_CONSECUTIVE_DATES",
      ].join(","));
    }
  }
  return lines.join("\n") + "\n";
}

function existingFromFirst(csv: string, changes: Partial<ExistingSale> = {}): ExistingSale {
  const columns = csv.split("\n")[1]!.split(",");
  return {
    id: "existing-1", breadCategoryId: categories[0]!.id,
    salesDate: columns[0]!, unitsSold: Number(columns[2]),
    dataOrigin: "IMPORTED_HISTORICAL", isValidated: true,
    sourceDailyResultId: null, externalSourceReference: columns[4]!,
    ...changes,
  };
}

test("T-DP-IMPORT-01 [FR-DP-01, BR-DP-03]: validates 240 adapted rows and 30 eligible days per mapped category", () => {
  const plan = buildImportPlan(fixture(), categories, [], "2026-11-09");
  assert.equal(plan.canApply, true);
  assert.equal(plan.accepted.length, 240);
  assert.equal(plan.rejected.length, 0);
  assert.equal(plan.conflicts.length, 0);
  assert.equal(plan.categories.length, 8);
  assert.ok(plan.categories.every((item) => item.eligibleDatesAfter === 30));
  assert.ok(plan.accepted.every((item) =>
    item.data_origin === "IMPORTED_HISTORICAL" && item.is_validated &&
    item.source_daily_result_id === null && item.validation_notes.includes("ADAPTED_DEMO")));
});

test("T-DP-IMPORT-02 [FR-DP-01, NFR-DAT-01]: rerun skips an identical validated row", () => {
  const csv = fixture();
  const plan = buildImportPlan(csv, categories, [existingFromFirst(csv)], "2026-11-09");
  assert.equal(plan.canApply, true);
  assert.equal(plan.accepted.length, 239);
  assert.equal(plan.identicalExisting.length, 1);
  assert.equal(plan.categories[0]!.eligibleDatesAfter, 30);
});

test("T-DP-IMPORT-03 [FR-DP-01, NFR-DAT-01]: actual overlap and changed import block writes", () => {
  const csv = fixture();
  const actual = existingFromFirst(csv, {
    dataOrigin: "ACTUAL_TRANSACTION", externalSourceReference: "real-transaction-1",
  });
  const actualPlan = buildImportPlan(csv, categories, [actual], "2026-11-09");
  assert.equal(actualPlan.canApply, false);
  assert.equal(actualPlan.conflicts[0]?.reason, "ACTUAL_SALES_OVERLAP");
  const changed = existingFromFirst(csv, { unitsSold: 100 });
  const changedPlan = buildImportPlan(csv, categories, [changed], "2026-11-09");
  assert.equal(changedPlan.canApply, false);
  assert.equal(changedPlan.conflicts.length, 1);
});

test("T-DP-IMPORT-04 [FR-DP-01, NFR-DAT-01]: older demo data requires reconciliation", () => {
  const csv = fixture();
  const older = existingFromFirst(csv, {
    salesDate: "2026-09-01", externalSourceReference: "adapted-demo-timeline-v1:old",
  });
  const plan = buildImportPlan(csv, categories, [older], "2026-11-09");
  assert.equal(plan.canApply, false);
  assert.equal(plan.previousDemoRows.length, 1);
});

test("T-DP-IMPORT-05 [FR-DP-01, NFR-DAT-01]: invalid quantity or missing category blocks the import", () => {
  const csv = fixture();
  const invalid = csv.replace(",0,IMPORTED_HISTORICAL,", ",-1,IMPORTED_HISTORICAL,");
  const invalidPlan = buildImportPlan(invalid, categories, [], "2026-11-09");
  assert.equal(invalidPlan.canApply, false);
  assert.equal(invalidPlan.rejected[0]?.reason, "INVALID_UNITS_SOLD");
  const missingPlan = buildImportPlan(csv, categories.slice(1), [], "2026-11-09");
  assert.equal(missingPlan.canApply, false);
  assert.ok(missingPlan.issues.some((issue) => issue.includes("Butter Sugar Bun")));
});
