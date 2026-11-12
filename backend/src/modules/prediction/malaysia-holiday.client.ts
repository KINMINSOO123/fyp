import { AppError } from "../../shared/AppError.js";
import { isCalendarDate } from "./history-selection.service.js";

const baseUrl = "https://malaysia-holiday.dydxsoft.my/api/v1/holidays";

export type MalaysiaHolidayCheck = {
  date: string; stateCode: string; isHoliday: boolean;
  holidays: Array<{ name: string; sourceUrl: string;
    subjectToChange: boolean }>;
  sourceUrl: string;
};
export type MalaysiaHolidayYear = { year: number; stateCode: "KUL";
  sourceUrl: string; holidays: Array<{ date: string; name: string;
    sourceUrl: string; subjectToChange: boolean }> };

function unavailable(): never {
  throw new AppError(503, "HOLIDAY_PROVIDER_UNAVAILABLE",
    "Malaysia holiday data is unavailable or incomplete.");
}

export function parseMalaysiaHolidays(raw: unknown, date: string,
  stateCode: string): MalaysiaHolidayCheck {
  const year = parseMalaysiaHolidayYear(raw, Number(date.slice(0, 4)),
    stateCode);
  const holidays = year.holidays.filter((item) => item.date === date);
  return { date, stateCode, isHoliday: holidays.length > 0,
    holidays, sourceUrl: year.sourceUrl };
}

export function parseMalaysiaHolidayYear(raw: unknown, year: number,
  stateCode: string): MalaysiaHolidayYear {
  if (!Number.isInteger(year) || year < 2000 || year > 2100 ||
      stateCode !== "KUL" ||
      !raw || typeof raw !== "object" || Array.isArray(raw)) unavailable();
  const response = raw as Record<string, unknown>;
  const meta = response.meta as Record<string, unknown> | null;
  const data = response.data;
  if (!meta || typeof meta !== "object" || Array.isArray(meta) ||
      meta.year !== year || meta.state !== stateCode ||
      !Array.isArray(data) || !Number.isSafeInteger(meta.count) ||
      meta.count !== data.length || data.length === 0) unavailable();
  const holidays: MalaysiaHolidayYear["holidays"] = [];
  const seen = new Set<string>();
  for (const item of data) {
    if (!item || typeof item !== "object" || Array.isArray(item)) unavailable();
    const row = item as Record<string, unknown>;
    if (typeof row.date !== "string" || !isCalendarDate(row.date) ||
        !row.date.startsWith(String(year)) ||
        typeof row.name !== "string" || !row.name.trim() ||
        row.name.trim().length > 120 ||
        typeof row.is_subject_to_change !== "boolean") unavailable();
    const source = row.source as Record<string, unknown> | null;
    if (!source || typeof source !== "object" || Array.isArray(source) ||
        typeof source.source_url !== "string" ||
        !source.source_url.startsWith("https://") ||
        source.source_url.length > 500) unavailable();
    const identity = `${row.date}\u0000${row.name.trim()}`;
    if (seen.has(identity)) unavailable();
    seen.add(identity);
    holidays.push({ date: row.date, name: row.name.trim(),
      sourceUrl: source.source_url,
      subjectToChange: row.is_subject_to_change });
  }
  return { year, stateCode: "KUL", holidays,
    sourceUrl: `${baseUrl}?year=${year}` +
      `&state=${stateCode}&include_source=1` };
}

export class MalaysiaHolidayClient {
  constructor(private readonly transport: typeof fetch = fetch) {}
  async year(year: number): Promise<MalaysiaHolidayYear> {
    if (!Number.isInteger(year) || year < 2000 || year > 2100) unavailable();
    const url = new URL(baseUrl);
    url.searchParams.set("year", String(year));
    url.searchParams.set("state", "KUL");
    url.searchParams.set("include_source", "1");
    try {
      const response = await this.transport(url, {
        signal: AbortSignal.timeout(5000),
        headers: { Accept: "application/json" },
      });
      if (!response.ok) unavailable();
      return parseMalaysiaHolidayYear(await response.json(), year, "KUL");
    } catch (error) {
      if (error instanceof AppError) throw error;
      unavailable();
    }
  }
  async check(date: string, stateCode: string): Promise<MalaysiaHolidayCheck> {
    if (!isCalendarDate(date) || stateCode !== "KUL") {
      throw new AppError(409, "HOLIDAY_STATE_INVALID",
        "Configure a valid Malaysian bakery state code.");
    }
    const result = await this.year(Number(date.slice(0, 4)));
    const holidays = result.holidays.filter((item) => item.date === date);
    return { date, stateCode, isHoliday: holidays.length > 0,
      holidays, sourceUrl: result.sourceUrl };
  }
}
