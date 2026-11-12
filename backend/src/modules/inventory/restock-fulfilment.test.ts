import assert from "node:assert/strict";
import { test } from "node:test";
import { AppError } from "../../shared/AppError.js";
import { restockFulfilment } from "./restock-fulfilment.js";

test("T-RST-06 [EXT-RST-04, EXT-RST-05]: partial receipt and cancelled outstanding remain distinct", () => {
  assert.deepEqual(restockFulfilment(1000, 0, [400]), {
    requestedGrams: 1000, receivedGrams: 400,
    cancelledGrams: 0, outstandingGrams: 600 });
  assert.deepEqual(restockFulfilment(1000, 0, [400, 600]), {
    requestedGrams: 1000, receivedGrams: 1000,
    cancelledGrams: 0, outstandingGrams: 0 });
  assert.deepEqual(restockFulfilment(1000, 600, [400]), {
    requestedGrams: 1000, receivedGrams: 400,
    cancelledGrams: 600, outstandingGrams: 0 });
  assert.throws(() => restockFulfilment(1000, 0, [600, 600]),
    (error: unknown) => error instanceof AppError &&
      error.code === "RESTOCK_DATA_INVALID");
});
