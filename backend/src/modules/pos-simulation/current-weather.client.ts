import { AppError } from "../../shared/AppError.js";
import { mapOpenWeatherCondition } from "../prediction/open-weather-map.client.js";
import type { WeatherCondition } from "../prediction/prediction-context.js";

// Five minutes avoids a provider call for rapid retries. Provider observations
// older than 30 minutes are rejected even when the HTTP response is fresh.
export const CURRENT_WEATHER_CACHE_MS = 5 * 60_000;
export const CURRENT_WEATHER_MAX_AGE_MS = 30 * 60_000;
const FUTURE_SKEW_MS = 5 * 60_000;
const MAX_LOCATION_OFFSET_DEGREES = 0.25;

export interface CurrentWeather {
  provider: "OPENWEATHER_CURRENT";
  condition: WeatherCondition;
  providerTimestamp: string;
  fetchedAt: string;
  location: { latitude: number; longitude: number };
  requestedLocation: { latitude: number; longitude: number };
}

export function parseCurrentWeather(raw: unknown, requestedLocation: {
  latitude: number; longitude: number;
}, fetchedAt: Date): CurrentWeather {
  const value = raw as { coord?: { lat?: unknown; lon?: unknown };
    weather?: Array<{ id?: unknown }>; dt?: unknown };
  const latitude = value?.coord?.lat;
  const longitude = value?.coord?.lon;
  const code = value?.weather?.[0]?.id;
  const timestamp = value?.dt;
  const invalid = typeof latitude !== "number" || !Number.isFinite(latitude) ||
    latitude < -90 || latitude > 90 ||
    typeof longitude !== "number" || !Number.isFinite(longitude) ||
    longitude < -180 || longitude > 180 ||
    typeof code !== "number" || !Number.isSafeInteger(code) ||
    code < 200 || code > 999 ||
    typeof timestamp !== "number" || !Number.isSafeInteger(timestamp) ||
    timestamp <= 0;
  if (invalid) throw new AppError(503, "CURRENT_WEATHER_UNAVAILABLE",
    "Current weather response is invalid. Please retry.");
  const location = { latitude: latitude as number, longitude: longitude as number };
  const observedAt = new Date((timestamp as number) * 1000);
  if (Math.abs(location.latitude - requestedLocation.latitude) > MAX_LOCATION_OFFSET_DEGREES ||
      Math.abs(location.longitude - requestedLocation.longitude) > MAX_LOCATION_OFFSET_DEGREES ||
      fetchedAt.getTime() - observedAt.getTime() > CURRENT_WEATHER_MAX_AGE_MS ||
      observedAt.getTime() - fetchedAt.getTime() > FUTURE_SKEW_MS) {
    throw new AppError(503, "CURRENT_WEATHER_UNAVAILABLE",
      "Current weather is stale or for another location. Please retry.");
  }
  return { provider: "OPENWEATHER_CURRENT", condition: mapOpenWeatherCondition(code as number),
    providerTimestamp: observedAt.toISOString(), fetchedAt: fetchedAt.toISOString(),
    location, requestedLocation };
}

export class CurrentWeatherClient {
  private cached?: { key: string; value: CurrentWeather; expiresAt: number };
  constructor(private readonly transport: typeof fetch = fetch,
    private readonly now: () => Date = () => new Date()) {}

  async get(): Promise<CurrentWeather> {
    const key = process.env.OPENWEATHER_API_KEY?.trim();
    const latitude = Number(process.env.BAKERY_LATITUDE);
    const longitude = Number(process.env.BAKERY_LONGITUDE);
    if (!key || !process.env.BAKERY_LATITUDE || !process.env.BAKERY_LONGITUDE ||
        !Number.isFinite(latitude) || latitude < -90 || latitude > 90 ||
        !Number.isFinite(longitude) || longitude < -180 || longitude > 180) {
      throw new AppError(503, "WEATHER_PROVIDER_NOT_CONFIGURED",
        "Configure the backend OpenWeather key and bakery coordinates.");
    }
    const cacheKey = `${latitude}:${longitude}:${key}`;
    const now = this.now();
    if (this.cached?.key === cacheKey && this.cached.expiresAt > now.getTime() &&
        now.getTime() - Date.parse(this.cached.value.providerTimestamp) <=
          CURRENT_WEATHER_MAX_AGE_MS) return this.cached.value;
    const url = new URL("https://api.openweathermap.org/data/2.5/weather");
    url.searchParams.set("lat", String(latitude));
    url.searchParams.set("lon", String(longitude));
    url.searchParams.set("appid", key);
    try {
      const response = await this.transport(url, { signal: AbortSignal.timeout(5000) });
      if (!response.ok) throw new Error("Current weather provider failed.");
      const value = parseCurrentWeather(await response.json(),
        { latitude, longitude }, this.now());
      this.cached = { key: cacheKey, value,
        expiresAt: this.now().getTime() + CURRENT_WEATHER_CACHE_MS };
      return value;
    } catch (error) {
      if (error instanceof AppError) throw error;
      throw new AppError(503, "CURRENT_WEATHER_UNAVAILABLE",
        "Current weather is unavailable. Please retry.");
    }
  }
}
