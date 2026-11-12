import assert from "node:assert/strict";
import { test } from "node:test";
import { AppError } from "../../shared/AppError.js";
import { MalaysiaHolidayClient, parseMalaysiaHolidays } from
  "./malaysia-holiday.client.js";

const date = "2026-11-09";
const holiday = { date, name: "Deepavali Holiday", is_subject_to_change: false,
  source: { source_url: "https://www.kabinet.gov.my/holiday.pdf" } };
const response = (rows: unknown[]) => ({ data: rows,
  meta: { year: 2026, state: "KUL", count: rows.length } });

test("T-DP-HOL-01 [FR-DP-04]: KUL holiday uses published source metadata", () => {
  const result = parseMalaysiaHolidays(response([holiday]), date, "KUL");
  assert.equal(result.isHoliday, true);
  assert.equal(result.holidays[0]?.name, "Deepavali Holiday");
  assert.match(result.sourceUrl, /state=KUL/);
});

test("T-DP-HOL-02 [FR-DP-04]: covered non-holiday differs from empty year", () => {
  const result = parseMalaysiaHolidays(response([{ ...holiday,
    date: "2026-11-08" }]), date, "KUL");
  assert.equal(result.isHoliday, false);
  assert.throws(() => parseMalaysiaHolidays(response([]), date, "KUL"),
    (error: unknown) => error instanceof AppError &&
      error.code === "HOLIDAY_PROVIDER_UNAVAILABLE");
  assert.throws(() => parseMalaysiaHolidays({ ...response([holiday]),
    meta: { year: 2026, state: "SGR", count: 1 } }, date, "KUL"));
  assert.throws(() => parseMalaysiaHolidays(response([holiday, holiday]),
    date, "KUL"));
});

test("T-DP-HOL-03 [FR-DP-04]: provider client requests state and source", async () => {
  let called = false;
  const client = new MalaysiaHolidayClient(async (url) => {
    const parsed = new URL(String(url));
    assert.equal(parsed.searchParams.get("state"), "KUL");
    assert.equal(parsed.searchParams.get("include_source"), "1");
    called = true;
    return new Response(JSON.stringify(response([holiday])), { status: 200 });
  });
  assert.equal((await client.check(date, "KUL")).isHoliday, true);
  assert.equal(called, true);
});
