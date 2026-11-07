import { AppError } from "../../shared/AppError.js";
import { isCalendarDate } from "./history-selection.service.js";
import type { ColdStartFactorsDto } from "./prediction-category.dto.js";

export type WeatherCondition = "CLEAR" | "CLOUDY" | "RAIN" | "STORM" | "OTHER";
export type CalendarEventType =
  "PUBLIC_HOLIDAY" | "SCHOOL_HOLIDAY" | "LOCAL_EVENT" | "RELIGIOUS_HOLIDAY";

export interface PredictionRules {
  baseQuantities: Record<string, number>;
  weekdayFactors: Record<string, number>;
  monsoonMonths: number[];
  monsoonFactor: number;
  otherSeasonFactor: number;
  weatherFactors: Record<WeatherCondition, number>;
  weatherFallbackFactor: number | null;
  holidayFactor: number;
  nonHolidayFactor: number;
  calendarVerifiedThrough: string | null;
  allowCalendarFallback: boolean;
}

const weekdays = ["SUNDAY", "MONDAY", "TUESDAY", "WEDNESDAY",
  "THURSDAY", "FRIDAY", "SATURDAY"] as const;
const weatherConditions = ["CLEAR", "CLOUDY", "RAIN", "STORM", "OTHER"] as const;

function object(value: unknown): Record<string, unknown> | null {
  return typeof value === "object" && value !== null && !Array.isArray(value)
    ? value as Record<string, unknown> : null;
}

function factor(value: unknown): number | null {
  return typeof value === "number" && Number.isFinite(value) && value >= 0
    ? value : null;
}

function configurationError(): never {
  throw new AppError(409, "PREDICTION_CONFIG_INCOMPLETE",
    "Prediction rules are incomplete; ask the System Administrator to review them.");
}

export function parsePredictionRules(value: unknown): PredictionRules {
  const data = object(value);
  const baseQuantities = object(data?.baseQuantities);
  const weekdayFactors = object(data?.weekdayFactors);
  const weatherFactors = object(data?.weatherFactors);
  if (!data || !baseQuantities || !weekdayFactors || !weatherFactors ||
      !Array.isArray(data.monsoonMonths) ||
      data.monsoonMonths.some((month) => !Number.isInteger(month) ||
        month < 1 || month > 12) ||
      new Set(data.monsoonMonths).size !== data.monsoonMonths.length ||
      factor(data.monsoonFactor) === null ||
      factor(data.otherSeasonFactor) === null ||
      factor(data.holidayFactor) === null ||
      factor(data.nonHolidayFactor) === null ||
      !(data.weatherFallbackFactor === null ||
        factor(data.weatherFallbackFactor) !== null) ||
      !(data.calendarVerifiedThrough === null ||
        (typeof data.calendarVerifiedThrough === "string" &&
          isCalendarDate(data.calendarVerifiedThrough))) ||
      typeof data.allowCalendarFallback !== "boolean" ||
      weekdays.some((day) => factor(weekdayFactors[day]) === null) ||
      weatherConditions.some((condition) =>
        factor(weatherFactors[condition]) === null) ||
      Object.values(baseQuantities).some((quantity) =>
        !Number.isSafeInteger(quantity) || (quantity as number) < 0)) {
    configurationError();
  }
  return data as unknown as PredictionRules;
}

export function resolvePredictionContext(
  targetDate: string,
  rules: PredictionRules,
  weather: { id: string; condition: WeatherCondition } | null,
  calendarEvents: Array<{ id: string; eventType: CalendarEventType }>,
): {
  factors: ColdStartFactorsDto;
  weatherRecordId: string | null;
  calendarEventIds: string[];
  weatherSource: "STORED_RECORD" | "CONFIGURED_FALLBACK";
  calendarSource: "STORED_EVENTS" | "STORED_COVERAGE" | "CONFIGURED_FALLBACK";
} {
  if (!isCalendarDate(targetDate)) configurationError();
  const date = new Date(`${targetDate}T00:00:00Z`);
  const weekday = weekdays[date.getUTCDay()]!;
  const month = date.getUTCMonth() + 1;
  if (!weather && rules.weatherFallbackFactor === null) {
    throw new AppError(503, "WEATHER_CONTEXT_UNAVAILABLE",
      "Weather context is unavailable; retry after it is updated.");
  }
  const weatherSource = weather ? "STORED_RECORD" : "CONFIGURED_FALLBACK";
  let calendarSource: "STORED_EVENTS" | "STORED_COVERAGE" |
    "CONFIGURED_FALLBACK";
  if (calendarEvents.length > 0) {
    calendarSource = "STORED_EVENTS";
  } else if (rules.calendarVerifiedThrough &&
             rules.calendarVerifiedThrough >= targetDate) {
    calendarSource = "STORED_COVERAGE";
  } else if (rules.allowCalendarFallback) {
    calendarSource = "CONFIGURED_FALLBACK";
  } else {
    throw new AppError(503, "CALENDAR_CONTEXT_UNAVAILABLE",
      "Calendar context is unverified; retry after it is updated.");
  }
  return {
    factors: {
      weekdayFactor: rules.weekdayFactors[weekday]!,
      monsoonFactor: rules.monsoonMonths.includes(month)
        ? rules.monsoonFactor : rules.otherSeasonFactor,
      weatherFactor: weather
        ? rules.weatherFactors[weather.condition]
        : rules.weatherFallbackFactor!,
      holidayFactor: calendarEvents.length > 0
        ? rules.holidayFactor : rules.nonHolidayFactor,
    },
    weatherRecordId: weather?.id ?? null,
    calendarEventIds: calendarEvents.map((event) => event.id),
    weatherSource,
    calendarSource,
  };
}
