import { AppError } from "../../shared/AppError.js";
import type { WeatherCondition } from "./prediction-context.js";

export type WeatherForecast = { condition: WeatherCondition;
  tempHighC: number; tempLowC: number; humidityPct: number };

function bakeryDate(epochSeconds: number, timezone: string): string {
  const parts = new Intl.DateTimeFormat("en-US", { timeZone: timezone,
    year: "numeric", month: "2-digit", day: "2-digit" })
    .formatToParts(new Date(epochSeconds * 1000));
  const part = (type: string) => parts.find((item) => item.type === type)?.value;
  return `${part("year")}-${part("month")}-${part("day")}`;
}

function condition(id: number): WeatherCondition {
  if (id >= 200 && id < 300) return "STORM";
  if (id >= 300 && id < 600) return "RAIN";
  if (id === 800) return "CLEAR";
  if (id >= 801 && id <= 804) return "CLOUDY";
  return "OTHER";
}

export function parseOpenWeatherForecast(raw: unknown, targetDate: string,
  timezone: string): WeatherForecast {
  const value = raw as { list?: unknown };
  if (!value || !Array.isArray(value.list)) throw new AppError(503,
    "WEATHER_PROVIDER_UNAVAILABLE", "Weather forecast response is invalid.");
  const points: Array<{ temp: number; humidity: number;
    condition: WeatherCondition }> = [];
  for (const rawPoint of value.list) {
    const point = rawPoint as { dt?: unknown; main?: { temp?: unknown;
      humidity?: unknown }; weather?: Array<{ id?: unknown }> };
    if (typeof point?.dt !== "number" || !Number.isSafeInteger(point.dt))
      continue;
    if (bakeryDate(point.dt, timezone) !== targetDate) continue;
    const temp = point.main?.temp;
    const humidity = point.main?.humidity;
    const id = point.weather?.[0]?.id;
    if (typeof temp !== "number" || !Number.isFinite(temp) ||
        temp < -100 || temp > 100 || typeof humidity !== "number" ||
        !Number.isFinite(humidity) || humidity < 0 || humidity > 100 ||
        typeof id !== "number" || !Number.isSafeInteger(id)) {
      throw new AppError(503, "WEATHER_PROVIDER_UNAVAILABLE",
        "Weather forecast point is invalid.");
    }
    points.push({ temp, humidity, condition: condition(id) });
  }
  if (points.length < 4) throw new AppError(503,
    "WEATHER_PROVIDER_UNAVAILABLE", "Next-day weather coverage is incomplete.");
  const severity: Record<WeatherCondition, number> = {
    CLEAR: 1, CLOUDY: 2, OTHER: 3, RAIN: 4, STORM: 5,
  };
  return { condition: points.reduce((worst, point) =>
    severity[point.condition] > severity[worst] ? point.condition : worst,
  points[0]!.condition),
  tempHighC: Math.max(...points.map((point) => point.temp)),
  tempLowC: Math.min(...points.map((point) => point.temp)),
  humidityPct: Math.round(points.reduce((sum, point) =>
    sum + point.humidity, 0) / points.length * 100) / 100 };
}

export class OpenWeatherMapClient {
  constructor(private readonly transport: typeof fetch = fetch) {}

  async nextDay(targetDate: string, timezone: string): Promise<WeatherForecast> {
    const key = process.env.OPENWEATHER_API_KEY?.trim();
    const latitude = Number(process.env.BAKERY_LATITUDE);
    const longitude = Number(process.env.BAKERY_LONGITUDE);
    if (!key || !process.env.BAKERY_LATITUDE || !process.env.BAKERY_LONGITUDE ||
        !Number.isFinite(latitude) || latitude < -90 || latitude > 90 ||
        !Number.isFinite(longitude) || longitude < -180 || longitude > 180) {
      throw new AppError(503, "WEATHER_PROVIDER_NOT_CONFIGURED",
        "Weather provider coordinates or server key are not configured.");
    }
    const url = new URL("https://api.openweathermap.org/data/2.5/forecast");
    url.searchParams.set("lat", String(latitude));
    url.searchParams.set("lon", String(longitude));
    url.searchParams.set("units", "metric");
    url.searchParams.set("appid", key);
    try {
      const response = await this.transport(url, {
        signal: AbortSignal.timeout(5000),
      });
      if (!response.ok) throw new Error("Provider returned an error.");
      return parseOpenWeatherForecast(await response.json(), targetDate, timezone);
    } catch (error) {
      if (error instanceof AppError) throw error;
      throw new AppError(503, "WEATHER_PROVIDER_UNAVAILABLE",
        "Weather forecast is temporarily unavailable.");
    }
  }
}
