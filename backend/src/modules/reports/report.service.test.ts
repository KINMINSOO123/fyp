import assert from "node:assert/strict";
import { test } from "node:test";
import { ReportExportAdapter } from "./report-export.adapter.js";
import type { StoredReportRow } from "./report.repo.js";
import { ReportService, buildReport } from "./report.service.js";

const first: StoredReportRow = {
  dailyResultId: "result-1", date: "2026-11-09",
  breadCategoryId: "category-1", breadCategoryName: "Bread, butter",
  displayOrder: 1, predictedUnitsSold: 100, produced: 120,
  unitsSold: 80, lostSales: 10, estimatedDemand: 90, leftover: 40,
  donated: 10, wasted: 5, remainingUnallocated: 25,
  salesPredictionError: -20,
  revenue: 8, ingredientCost: 11, grossProfit: -3,
  evaluationUnitsSold: 75, evaluationDataOrigin: "IMPORTED_HISTORICAL",
};
const second: StoredReportRow = {
  ...first, dailyResultId: "result-2", breadCategoryId: "category-2",
  breadCategoryName: "Roti", displayOrder: 2,
  predictedUnitsSold: 0, produced: 0, unitsSold: 0,
  lostSales: 0, estimatedDemand: 0, leftover: 0,
  donated: 0, wasted: 0, remainingUnallocated: 0,
  salesPredictionError: 0, revenue: 0, ingredientCost: 0, grossProfit: 0,
  evaluationUnitsSold: 0, evaluationDataOrigin: "SIMULATION_GENERATED",
};
const filters = { period: "DAY" as const, fromDate: "2026-11-09",
  toDate: "2026-11-09", breadCategoryId: null };

test("T-RPT-AUTO-01 [FR-RPT-01, FR-RPT-04, FR-RPT-05]: aggregates at result grain and keeps signed/error/null semantics", () => {
  const report = buildReport(filters, "Asia/Kuala_Lumpur",
    "2026-11-09T00:00:00.000Z", [first, second]);
  assert.equal(report.totals.resultCount, 2);
  assert.equal(report.totals.salesPredictionError, -20);
  assert.equal(report.totals.leftover, 40);
  assert.equal(report.totals.wasted, 5);
  assert.equal(report.totals.grossProfit, -3);
  assert.equal(report.totals.grossProfitMarginPct, -37.5);
  assert.equal(report.totals.leftoverRatePct, 40 / 120 * 100);
  assert.equal(report.totals.discardedWasteRatePct, 5 / 120 * 100);
  assert.equal(report.totals.salesFulfilmentPct, 80 / 90 * 100);
  assert.equal(report.rows[0]?.evaluationPredictionError, -25);
  assert.equal(report.rows[0]?.evaluationDataOrigin, "IMPORTED_HISTORICAL");
  assert.equal(report.rows[1]?.leftoverRatePct, null);
  assert.equal(report.rows[1]?.salesFulfilmentPct, null);
  assert.equal(report.rows[1]?.grossProfitMarginPct, null);
  const empty = buildReport(filters, "Asia/Kuala_Lumpur", "now", []);
  assert.equal(empty.totals.grossProfitMarginPct, null);
});

test("T-RPT-AUTO-02 [FR-RPT-02, FR-RPT-03]: date, week and category filters reach one read model", async () => {
  const calls: Array<[string, string, string | null]> = [];
  const service = new ReportService({
    async getBakeryTimezone() { return "Asia/Kuala_Lumpur"; },
    async categories() { return []; },
    async list(from, to, category) {
      calls.push([from, to, category]);
      return [first];
    },
  }, () => new Date("2026-11-08T17:00:00Z"));
  const category = "12345678-1234-4123-8123-123456789abc";
  const report = await service.get({ period: "WEEK", date: "2026-11-08",
    breadCategoryId: category });
  assert.deepEqual(report.filters, { period: "WEEK", fromDate: "2026-11-02",
    toDate: "2026-11-08", breadCategoryId: category });
  assert.deepEqual(calls, [["2026-11-02", "2026-11-08", category]]);
  await service.get({ period: "CUSTOM", fromDate: "2026-11-01",
    toDate: "2026-11-09" });
  assert.deepEqual(calls[1], ["2026-11-01", "2026-11-09", null]);
  for (const invalid of [
    { period: "MONTH" }, { period: "CUSTOM", fromDate: "2026-02-30",
      toDate: "2026-11-09" }, { date: "2026-11-10" },
    { role: "SYSTEM_ADMINISTRATOR" },
    { period: "CUSTOM", fromDate: "2026-11-09", toDate: "2026-11-01" },
  ]) {
    await assert.rejects(service.get(invalid),
      (error: unknown) => typeof error === "object" && error !== null &&
        "code" in error && error.code === "VALIDATION_ERROR");
  }
  assert.equal(calls.length, 2);
});

test("T-RPT-AUTO-03 [FR-RPT-06, NFR-ACC-07]: CSV/PDF use same values and label simulated records", () => {
  const report = buildReport(filters, "Asia/Kuala_Lumpur",
    "2026-11-09T00:00:00.000Z", [first, second]);
  const exporter = new ReportExportAdapter();
  const csv = exporter.render(report, "CSV");
  const pdf = exporter.render(report, "PDF");
  assert.equal(csv.contentType, "text/csv; charset=utf-8");
  assert.match(csv.bytes.toString("utf8"), /"Bread, butter"/);
  assert.match(csv.bytes.toString("utf8"), /SIMULATION_GENERATED/);
  assert.match(csv.bytes.toString("utf8"), /IMPORTED_HISTORICAL/);
  assert.match(csv.bytes.toString("utf8"), /Not Applicable/);
  assert.match(csv.bytes.toString("utf8"), /"-3"/);
  assert.match(pdf.bytes.toString("latin1"), /^%PDF-1\.4/);
  assert.match(pdf.bytes.toString("latin1"), /SIMULATED DATA/);
  assert.match(pdf.bytes.toString("latin1"), /Gross profit RM -3\.00/);
  assert.match(pdf.bytes.toString("latin1"), /%%EOF/);
  const body = pdf.bytes.toString("latin1");
  const xrefOffset = Number(/startxref\n(\d+)\n%%EOF/.exec(body)?.[1]);
  assert.equal(body.slice(xrefOffset, xrefOffset + 4), "xref");
  const many = new Array(140).fill(first).map((row, index) => ({
    ...row, dailyResultId: `result-${index}`,
  }));
  const paged = exporter.render(buildReport(filters, "Asia/Kuala_Lumpur",
    "2026-11-09T00:00:00.000Z", many), "PDF");
  assert.ok((paged.bytes.toString("latin1").match(/\/Type \/Page \/Parent/g) ??
    []).length > 1);
});
