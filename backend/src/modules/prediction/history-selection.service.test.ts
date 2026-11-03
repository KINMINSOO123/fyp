import assert from "node:assert/strict";
import { test } from "node:test";
import {
  HistorySelectionService,
  type DailySalesObservationRow,
} from "./history-selection.service.js";

const selector = new HistorySelectionService();
const categoryId = "bread-a";
const targetDate = "2026-11-04";

function row(
  id: string,
  salesDate: string,
  dataOrigin: DailySalesObservationRow["dataOrigin"],
  unitsSold: number,
  changes: Partial<DailySalesObservationRow> = {},
): DailySalesObservationRow {
  return {
    id,
    breadCategoryId: categoryId,
    salesDate,
    dataOrigin,
    unitsSold,
    isValidated: true,
    sourceDailyResultId: dataOrigin === "SIMULATION_GENERATED" ? `result-${id}` : null,
    externalSourceReference: dataOrigin === "SIMULATION_GENERATED" ? null : `source-${id}`,
    ...changes,
  };
}

test("T-DP-HIST-01 [FR-DP-01, BR-DP-03]: selects origin priority regardless of input order", () => {
  const result = selector.selectForCategory([
    row("simulation", "2026-11-01", "SIMULATION_GENERATED", 8),
    row("imported", "2026-11-01", "IMPORTED_HISTORICAL", 9),
    row("actual", "2026-11-01", "ACTUAL_TRANSACTION", 0),
    row("later", "2026-11-02", "SIMULATION_GENERATED", 12),
  ], categoryId, targetDate);

  assert.equal(result.distinctDayCount, 2);
  assert.deepEqual(result.observations.map((item) => item.id), ["actual", "later"]);
  assert.deepEqual(result.observations.map((item) => item.unitsSold), [0, 12]);
  assert.equal(result.observations[0]?.dataOrigin, "ACTUAL_TRANSACTION");
});

test("T-DP-HIST-02 [FR-DP-01]: invalid actual does not suppress valid imported history", () => {
  const result = selector.selectForCategory([
    row("invalid-actual", "2026-11-01", "ACTUAL_TRANSACTION", -1),
    row("imported", "2026-11-01", "IMPORTED_HISTORICAL", 7),
    row("unvalidated", "2026-11-02", "ACTUAL_TRANSACTION", 4, {
      isValidated: false,
    }),
  ], categoryId, targetDate);

  assert.equal(result.distinctDayCount, 1);
  assert.equal(result.observations[0]?.id, "imported");
  assert.deepEqual(result.rejected.map((item) => item.reason), [
    "INVALID_OBSERVATION", "UNVALIDATED",
  ]);
});

test("T-DP-HIST-03 [BR-DP-02, FR-DP-01]: excludes future and malformed history", () => {
  const result = selector.selectForCategory([
    row("good", "2026-11-03", "ACTUAL_TRANSACTION", 3),
    row("today", targetDate, "ACTUAL_TRANSACTION", 100),
    row("future", "2026-11-05", "ACTUAL_TRANSACTION", 100),
    row("bad-source", "2026-11-02", "SIMULATION_GENERATED", 5, {
      sourceDailyResultId: null,
    }),
  ], categoryId, targetDate);

  assert.equal(result.distinctDayCount, 1);
  assert.equal(result.observations[0]?.id, "good");
  assert.deepEqual(result.rejected.map((item) => item.reason), [
    "NOT_HISTORICAL", "NOT_HISTORICAL", "INVALID_OBSERVATION",
  ]);
});

test("T-DP-HIST-04 [FR-DP-01]: rejects same-origin duplicate", () => {
  assert.throws(() => selector.selectForCategory([
    row("one", "2026-11-01", "ACTUAL_TRANSACTION", 3),
    row("two", "2026-11-01", "ACTUAL_TRANSACTION", 4),
  ], categoryId, targetDate), /Duplicate validated/);
});

test("T-DP-HIST-05 [BR-DP-03, BR-DP-04]: counts distinct days including zero sales", () => {
  const rows = Array.from({ length: 30 }, (_, index) => {
    const day = String(index + 1).padStart(2, "0");
    return row(`actual-${day}`, `2026-10-${day}`, "ACTUAL_TRANSACTION", 0);
  });
  rows.push(row("extra-origin", "2026-10-01", "SIMULATION_GENERATED", 40));

  const result = selector.selectForCategory(rows, categoryId, targetDate);
  assert.equal(result.distinctDayCount, 30);
  assert.equal(result.observations.every((item) => item.unitsSold === 0), true);
});

test("T-DP-HIST-06 [FR-DP-01]: rejects category and date mismatch", () => {
  assert.throws(() => selector.selectForCategory([
    row("foreign", "2026-11-01", "ACTUAL_TRANSACTION", 1, {
      breadCategoryId: "bread-b",
    }),
  ], categoryId, targetDate), /another bread category/);
  assert.throws(() => selector.selectForCategory([], categoryId, "2026-02-30"),
    /valid target date/);
});
