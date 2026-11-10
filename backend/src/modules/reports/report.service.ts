import { AppError } from "../../shared/AppError.js";
import { isCalendarDate } from "../prediction/history-selection.service.js";
import type { ReportRepo, StoredReportRow } from "./report.repo.js";

const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
export type ReportPeriod = "DAY" | "WEEK" | "CUSTOM";
export type ReportFilters = {
  period: ReportPeriod; fromDate: string; toDate: string;
  breadCategoryId: string | null;
};
export type ReportRow = StoredReportRow & {
  dataOrigin: "SIMULATION_GENERATED";
  evaluationPredictionError: number | null;
  leftoverRatePct: number | null;
  discardedWasteRatePct: number | null;
  salesFulfilmentPct: number | null;
  grossProfitMarginPct: number | null;
};
export type ReportTotals = {
  resultCount: number; predictedUnitsSold: number; produced: number;
  unitsSold: number; lostSales: number; estimatedDemand: number;
  leftover: number; donated: number; wasted: number;
  remainingUnallocated: number; salesPredictionError: number;
  revenue: number; ingredientCost: number; grossProfit: number;
  leftoverRatePct: number | null; discardedWasteRatePct: number | null;
  salesFulfilmentPct: number | null; grossProfitMarginPct: number | null;
};
export type Report = {
  filters: ReportFilters; timezone: string;
  generatedAt: string; sourceLabel: "SIMULATED_OPERATIONAL_RESULTS";
  totals: ReportTotals; rows: ReportRow[];
};
type DataRepo = Pick<ReportRepo, "getBakeryTimezone" | "list" | "categories">;

function bakeryDate(now: Date, timezone: string): string {
  const parts = new Intl.DateTimeFormat("en-US", {
    timeZone: timezone, year: "numeric", month: "2-digit", day: "2-digit",
  }).formatToParts(now);
  const get = (type: string) => parts.find((part) => part.type === type)?.value;
  return `${get("year")}-${get("month")}-${get("day")}`;
}

function ratio(numerator: number, denominator: number): number | null {
  return denominator === 0 ? null : numerator / denominator * 100;
}

function dateMs(date: string): number {
  return Date.parse(`${date}T00:00:00Z`);
}

function isoDate(milliseconds: number): string {
  return new Date(milliseconds).toISOString().slice(0, 10);
}

function weekFor(date: string): [string, string] {
  const weekday = new Date(dateMs(date)).getUTCDay();
  const monday = dateMs(date) - ((weekday + 6) % 7) * 86_400_000;
  return [isoDate(monday), isoDate(monday + 6 * 86_400_000)];
}

function parseFilters(raw: unknown, today: string): ReportFilters {
  if (typeof raw !== "object" || raw === null || Array.isArray(raw)) {
    throw new AppError(400, "VALIDATION_ERROR", "Invalid report filters.");
  }
  const query = raw as Record<string, unknown>;
  if (Object.keys(query).some((key) =>
    !["period", "date", "fromDate", "toDate", "breadCategoryId"].includes(key))) {
    throw new AppError(400, "VALIDATION_ERROR", "Invalid report filters.");
  }
  const period = query.period === undefined ? "DAY" : query.period;
  const category = query.breadCategoryId === undefined ? null : query.breadCategoryId;
  if ((period !== "DAY" && period !== "WEEK" && period !== "CUSTOM") ||
      (category !== null && (typeof category !== "string" || !uuid.test(category)))) {
    throw new AppError(400, "VALIDATION_ERROR", "Invalid report period or category.");
  }
  let fromDate: string;
  let toDate: string;
  if (period === "CUSTOM") {
    if (query.date !== undefined || typeof query.fromDate !== "string" ||
        typeof query.toDate !== "string" ||
        !isCalendarDate(query.fromDate) || !isCalendarDate(query.toDate)) {
      throw new AppError(400, "VALIDATION_ERROR",
        "A custom report needs valid fromDate and toDate.");
    }
    fromDate = query.fromDate;
    toDate = query.toDate;
  } else {
    if (query.fromDate !== undefined || query.toDate !== undefined ||
        (query.date !== undefined &&
         (typeof query.date !== "string" || !isCalendarDate(query.date)))) {
      throw new AppError(400, "VALIDATION_ERROR", "Invalid report date.");
    }
    const date = typeof query.date === "string" ? query.date : today;
    [fromDate, toDate] = period === "WEEK" ? weekFor(date) : [date, date];
  }
  if (fromDate > toDate || (dateMs(toDate) - dateMs(fromDate)) / 86_400_000 > 365 ||
      fromDate > today) {
    throw new AppError(400, "VALIDATION_ERROR",
      "Report range must be valid, at most 366 days, and not start in the future.");
  }
  return { period, fromDate, toDate, breadCategoryId: category as string | null };
}

function cents(value: number): number { return Math.round(value * 100); }

export function buildReport(filters: ReportFilters, timezone: string,
  generatedAt: string, stored: StoredReportRow[]): Report {
  const rows: ReportRow[] = stored.map((item) => ({
    ...item,
    dataOrigin: "SIMULATION_GENERATED",
    evaluationPredictionError: item.evaluationUnitsSold === null ? null :
      item.evaluationUnitsSold - item.predictedUnitsSold,
    leftoverRatePct: ratio(item.leftover, item.produced),
    discardedWasteRatePct: ratio(item.wasted, item.produced),
    salesFulfilmentPct: ratio(item.unitsSold, item.estimatedDemand),
    grossProfitMarginPct: ratio(item.grossProfit, item.revenue),
  }));
  const sum = (field: keyof StoredReportRow): number =>
    rows.reduce((total, row) => total + Number(row[field]), 0);
  const revenue = rows.reduce((total, row) => total + cents(row.revenue), 0) / 100;
  const ingredientCost = rows.reduce((total, row) =>
    total + cents(row.ingredientCost), 0) / 100;
  const grossProfit = revenue - ingredientCost;
  const produced = sum("produced");
  const estimatedDemand = sum("estimatedDemand");
  const totals: ReportTotals = {
    resultCount: rows.length,
    predictedUnitsSold: sum("predictedUnitsSold"),
    produced, unitsSold: sum("unitsSold"), lostSales: sum("lostSales"),
    estimatedDemand, leftover: sum("leftover"), donated: sum("donated"),
    wasted: sum("wasted"), remainingUnallocated: sum("remainingUnallocated"),
    salesPredictionError: sum("salesPredictionError"),
    revenue, ingredientCost, grossProfit,
    leftoverRatePct: ratio(sum("leftover"), produced),
    discardedWasteRatePct: ratio(sum("wasted"), produced),
    salesFulfilmentPct: ratio(sum("unitsSold"), estimatedDemand),
    grossProfitMarginPct: ratio(grossProfit, revenue),
  };
  return { filters, timezone, generatedAt,
    sourceLabel: "SIMULATED_OPERATIONAL_RESULTS", totals, rows };
}

export class ReportService {
  constructor(private readonly providedRepo?: DataRepo,
    private readonly now: () => Date = () => new Date()) {}
  private async repo(): Promise<DataRepo> {
    return this.providedRepo ?? new (
      await import("./report.repo.js")
    ).ReportRepo();
  }

  async get(rawQuery: unknown): Promise<Report> {
    const repo = await this.repo();
    const timezone = await repo.getBakeryTimezone();
    const generatedAt = this.now().toISOString();
    const filters = parseFilters(rawQuery, bakeryDate(this.now(), timezone));
    return buildReport(filters, timezone, generatedAt,
      await repo.list(filters.fromDate, filters.toDate, filters.breadCategoryId));
  }

  async categories() { return (await this.repo()).categories(); }
}
