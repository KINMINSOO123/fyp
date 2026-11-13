import assert from "node:assert/strict";
import { test } from "node:test";
import { AppError } from "../../shared/AppError.js";
import { CurrentWeatherClient, parseCurrentWeather } from "./current-weather.client.js";

const requested = { latitude: 3.203, longitude: 101.723 };
const now = new Date("2026-11-13T04:00:00Z");
const raw = (code = 500, dt = Date.parse("2026-11-13T03:55:00Z") / 1000) =>
  ({ coord: { lat: 3.203, lon: 101.723 }, weather: [{ id: code }], dt });

test("T-POS-WEATHER-02 [FR-POS-02]: current codes, location and timestamps are validated", () => {
  const conditions = new Map([
    [800, "CLEAR"], [802, "CLOUDY"], [500, "RAIN"],
    [300, "RAIN"], [200, "STORM"], [600, "OTHER"],
  ]);
  for (const [code, condition] of conditions) {
    const result = parseCurrentWeather(raw(code), requested, now);
    assert.equal(result.condition, condition);
    assert.equal(result.providerTimestamp, "2026-11-13T03:55:00.000Z");
    assert.equal(result.fetchedAt, now.toISOString());
  }
  for (const bad of [raw(500, Date.parse("2026-11-13T03:00:00Z") / 1000),
    { ...raw(), coord: { lat: 4, lon: 101.723 } },
    { ...raw(), weather: [] }, { ...raw(), dt: "yesterday" }]) {
    assert.throws(() => parseCurrentWeather(bad, requested, now),
      (error: unknown) => error instanceof AppError &&
        error.code === "CURRENT_WEATHER_UNAVAILABLE");
  }
});

test("T-POS-WEATHER-03 [FR-POS-02]: cache is short and provider failures are retryable", async () => {
  const old = [process.env.OPENWEATHER_API_KEY, process.env.BAKERY_LATITUDE,
    process.env.BAKERY_LONGITUDE];
  process.env.OPENWEATHER_API_KEY = "test-key";
  process.env.BAKERY_LATITUDE = String(requested.latitude);
  process.env.BAKERY_LONGITUDE = String(requested.longitude);
  let clock = now;
  let calls = 0;
  let fail = false;
  const client = new CurrentWeatherClient(async (input) => {
    calls++;
    const url = new URL(String(input));
    assert.equal(url.pathname, "/data/2.5/weather");
    assert.equal(url.searchParams.get("lat"), String(requested.latitude));
    return new Response(JSON.stringify(raw(500,
      Math.floor(clock.getTime() / 1000) - 60)),
    { status: fail ? 503 : 200 });
  }, () => clock);
  try {
    assert.equal((await client.get()).condition, "RAIN");
    assert.equal((await client.get()).condition, "RAIN");
    assert.equal(calls, 1);
    clock = new Date(now.getTime() + 5 * 60_000 + 1);
    fail = true;
    await assert.rejects(client.get(), (error: unknown) =>
      error instanceof AppError && error.code === "CURRENT_WEATHER_UNAVAILABLE");
    assert.equal(calls, 2);
  } finally {
    for (const [index, name] of ["OPENWEATHER_API_KEY", "BAKERY_LATITUDE",
      "BAKERY_LONGITUDE"].entries()) {
      if (old[index] === undefined) delete process.env[name];
      else process.env[name] = old[index];
    }
  }
});
