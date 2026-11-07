import assert from "node:assert/strict";
import { test } from "node:test";
import { AppError } from "../../shared/AppError.js";
import {
  parsePredictionRules, resolvePredictionContext,
} from "./prediction-context.js";

const neutral = {
  baseQuantities: {},
  weekdayFactors: { SUNDAY: 1, MONDAY: 1, TUESDAY: 1,
    WEDNESDAY: 1, THURSDAY: 1, FRIDAY: 1, SATURDAY: 1 },
  monsoonMonths: [], monsoonFactor: 1, otherSeasonFactor: 1,
  weatherFactors: { CLEAR: 1, CLOUDY: 1, RAIN: 1, STORM: 1,
    OTHER: 1 },
  weatherFallbackFactor: 1,
  holidayFactor: 1, nonHolidayFactor: 1,
  calendarVerifiedThrough: null, allowCalendarFallback: true,
};

test("T-DP-GEN-07 [FR-DP-04, NFR-REL-03]: configured context fallback is explicitly labelled", () => {
  const rules = parsePredictionRules(neutral);
  const result = resolvePredictionContext("2026-11-05", rules, null, []);
  assert.deepEqual(result.factors, { weekdayFactor: 1,
    monsoonFactor: 1, weatherFactor: 1, holidayFactor: 1 });
  assert.equal(result.weatherSource, "CONFIGURED_FALLBACK");
  assert.equal(result.calendarSource, "CONFIGURED_FALLBACK");
  assert.equal(result.weatherRecordId, null);
  assert.deepEqual(result.calendarEventIds, []);
  assert.throws(() => parsePredictionRules({ ...neutral,
    weekdayFactors: { ...neutral.weekdayFactors, THURSDAY: -1 } }),
  (error: unknown) => error instanceof AppError &&
    error.code === "PREDICTION_CONFIG_INCOMPLETE");
});
