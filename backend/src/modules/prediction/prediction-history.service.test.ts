import assert from "node:assert/strict";
import { test } from "node:test";
import { PredictionHistoryService } from "./prediction-history.service.js";

test("T-DP-HIST-07 [FR-DP-01, BR-DP-03]: repository history is selected before use", async () => {
  let requestedCategory: string | undefined;
  let requestedDate: string | undefined;
  const service = new PredictionHistoryService({
    async listBeforeDate(categoryId, targetDate) {
      requestedCategory = categoryId;
      requestedDate = targetDate;
      return [
        {
          id: "simulated",
          breadCategoryId: categoryId,
          salesDate: "2026-11-01",
          unitsSold: 15,
          dataOrigin: "SIMULATION_GENERATED",
          isValidated: true,
          sourceDailyResultId: "result-1",
          externalSourceReference: null,
        },
        {
          id: "actual",
          breadCategoryId: categoryId,
          salesDate: "2026-11-01",
          unitsSold: 10,
          dataOrigin: "ACTUAL_TRANSACTION",
          isValidated: true,
          sourceDailyResultId: null,
          externalSourceReference: "receipt-1",
        },
      ];
    },
  });

  const result = await service.loadSelected("bread-a", "2026-11-04");
  assert.equal(requestedCategory, "bread-a");
  assert.equal(requestedDate, "2026-11-04");
  assert.equal(result.distinctDayCount, 1);
  assert.equal(result.observations[0]?.id, "actual");
});
