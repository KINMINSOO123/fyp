import assert from "node:assert/strict";
import { test } from "node:test";
import { AppError } from "../../shared/AppError.js";
import { parseOpenWeatherForecast } from "./open-weather-map.client.js";

test("T-DP-WEA-01 [FR-DP-04]: forecast points use bakery date and validated sampled values", () => {
  const at = (hour: number, id: number, temp: number) => ({
    dt: Date.parse(`2026-11-11T${String(hour).padStart(2, "0")}:00:00Z`) / 1000,
    main: { temp, humidity: 80 }, weather: [{ id }],
  });
  const result = parseOpenWeatherForecast({ list: [
    at(0, 800, 27), at(3, 801, 29), at(6, 500, 31),
    at(9, 200, 28), at(12, 800, 25), at(15, 800, 24),
    at(18, 800, 23), at(21, 800, 22),
  ] }, "2026-11-11", "Asia/Kuala_Lumpur");
  assert.deepEqual(result, { condition: "STORM", tempHighC: 31,
    tempLowC: 24, humidityPct: 80 });
  assert.throws(() => parseOpenWeatherForecast({ list: [at(0, 800, 27)] },
    "2026-11-11", "Asia/Kuala_Lumpur"),
  (error: unknown) => error instanceof AppError &&
    error.code === "WEATHER_PROVIDER_UNAVAILABLE");
});
