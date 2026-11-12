import assert from "node:assert/strict";
import { test } from "node:test";
import { AppError } from "../../shared/AppError.js";
import { KlHolidayService } from "./kl-holiday.service.js";
import type { KlHolidayRepo } from "./kl-holiday.repo.js";
import type { MalaysiaHolidayYear } from "./malaysia-holiday.client.js";

const year = 2026;
const now = new Date("2026-11-12T00:00:00Z");
const yearData: MalaysiaHolidayYear = { year, stateCode: "KUL",
  sourceUrl: "https://example.org/2026", holidays: [
    { date: "2026-11-13", name: "KL holiday",
      sourceUrl: "https://example.org/source", subjectToChange: false },
    { date: "2026-11-20", name: "Another KL holiday",
      sourceUrl: "https://example.org/source", subjectToChange: false },
  ] };

function fixture() {
  let coverage: Awaited<ReturnType<KlHolidayRepo["coverage"]>> = null;
  const events = new Map<string, { id: string; eventDate: string;
    eventName: string; sourceReference: string; subjectToChange: boolean }>();
  let fetched = 0;
  let saved = 0;
  const repo: Pick<KlHolidayRepo, "coverage" | "events" | "save"> = {
    async coverage() { return coverage; },
    async events() { return [...events.values()]; },
    async save(actor, data) {
      assert.equal(actor, "manager-1");
      saved += 1;
      events.clear();
      for (const item of data.holidays) {
        events.set(`${item.date}:${item.name}`, { id: `event-${events.size}`,
          eventDate: item.date, eventName: item.name,
          sourceReference: item.sourceUrl,
          subjectToChange: item.subjectToChange });
      }
      coverage = { year, sourceUrl: data.sourceUrl,
        lastSuccessfulAt: now.toISOString(),
        refreshAfter: "2026-11-19T00:00:00Z", eventCount: data.holidays.length };
      return {};
    },
  };
  const client = { async year(requested: number) {
    assert.equal(requested, year);
    fetched += 1;
    return yearData;
  } };
  return { service: new KlHolidayService(repo, client, () => now),
    counts: () => ({ fetched, saved, events: events.size }),
    expire: () => { coverage = { ...coverage!,
      refreshAfter: "2026-11-11T00:00:00Z" }; },
    failProvider: () => { client.year = async () => {
      throw new AppError(503, "HOLIDAY_PROVIDER_UNAVAILABLE", "Unavailable");
    }; },
    corruptCoverage: () => { coverage = { ...coverage!, eventCount: 99 }; },
  };
}

test("T-DP-KL-01 [FR-DP-04]: year sync is shared across date checks and repeated safely", async () => {
  const state = fixture();
  assert.equal((await state.service.ensure("manager-1", "2026-11-13"))
    ?.isHoliday, true);
  assert.equal((await state.service.ensure("manager-1", "2026-11-14"))
    ?.isHoliday, false);
  assert.deepEqual(state.counts(), { fetched: 1, saved: 1, events: 2 });
  state.expire();
  await state.service.ensure("manager-1", "2026-11-13");
  assert.deepEqual(state.counts(), { fetched: 2, saved: 2, events: 2 });
});

test("T-DP-KL-02 [FR-DP-04]: no coverage and provider failure is not non-holiday", async () => {
  const state = fixture();
  state.failProvider();
  assert.equal(await state.service.ensure("manager-1", "2026-11-14"), null);
  assert.equal(state.counts().saved, 0);
});

test("T-DP-KL-03 [FR-DP-04]: stored result must match exact KL date", async () => {
  const state = fixture();
  const nonHoliday = await state.service.ensure("manager-1", "2026-11-14");
  assert.equal(nonHoliday?.stateCode, "KUL");
  assert.equal(nonHoliday?.isHoliday, false);
  assert.deepEqual(nonHoliday?.holidays, []);
});

test("T-DP-KL-04 [FR-DP-04]: incomplete cached year is not ordinary coverage", async () => {
  const state = fixture();
  await state.service.ensure("manager-1", "2026-11-13");
  state.corruptCoverage();
  await assert.rejects(state.service.ensure("manager-1", "2026-11-14"),
    (error: unknown) => error instanceof AppError &&
      error.code === "CALENDAR_CONTEXT_UNAVAILABLE");
});
