import type { OpenWeatherMapClient } from "./open-weather-map.client.js";
import type { WeatherRepo } from "./weather.repo.js";

export class WeatherService {
  constructor(private readonly providedClient?: Pick<OpenWeatherMapClient,
    "nextDay">, private readonly providedRepo?: Pick<WeatherRepo, "cache">) {}

  async cacheNextDay(actorUserId: string, targetDate: string,
    timezone: string): Promise<void> {
    const client = this.providedClient ?? new (await import(
      "./open-weather-map.client.js")).OpenWeatherMapClient();
    const repo = this.providedRepo ?? new (await import(
      "./weather.repo.js")).WeatherRepo();
    await repo.cache(actorUserId, targetDate,
      await client.nextDay(targetDate, timezone));
  }
}
