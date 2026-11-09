import { isCalendarDate, HistorySelectionService, type DailySalesObservationRow } from
  "../prediction/history-selection.service.js";
import { DATASET_CSV_SHA256 } from "./adapted-demo-package.js";

export const SOURCE_REFERENCE_PREFIX = "adapted-demo-timeline-v2:";
export const DATA_USAGE = "ADAPTED_DEMO";
export const TIMELINE_TYPE = "DUMMY_CONSECUTIVE_DATES";
export const FIRST_DATE = "2026-10-10";
export const LAST_DATE = "2026-11-08";

export const SOURCE_PRODUCTS: Readonly<Record<string, string>> = {
  "Butter Sugar Bun": "CROISSANT",
  "Coconut Bun": "PAIN AUX RAISINS",
  "Chicken Sausage Bun": "FORMULE SANDWICH",
  "Red Bean Bun": "PAIN AU CHOCOLAT",
  "Cheese Bun": "BANETTE",
  "Custard Bun": "ECLAIR",
  "Mexican Coffee Bun": "BRIOCHE",
  "Chicken Floss Bun": "SANDWICH COMPLET",
};

const columns = ["sales_date", "bread_category", "units_sold", "data_origin",
  "external_source_reference", "is_validated", "data_usage",
  "original_sales_date", "source_product", "source_daily_net_quantity",
  "source_transaction_rows", "source_negative_quantity_rows",
  "quantity_scale_factor", "previous_demo_sales_date", "timeline_type"] as const;
type Column = typeof columns[number];
type CsvRecord = Record<Column, string>;

export interface ImportCategory {
  id: string;
  name: string;
  isActive: boolean;
}
export interface ExistingSale {
  id: string;
  breadCategoryId: string;
  salesDate: string;
  unitsSold: number;
  dataOrigin: string;
  isValidated: boolean;
  sourceDailyResultId: string | null;
  externalSourceReference: string | null;
}
export interface SaleToInsert {
  sales_date: string;
  bread_category_id: string;
  units_sold: number;
  data_origin: "IMPORTED_HISTORICAL";
  source_daily_result_id: null;
  external_source_reference: string;
  is_validated: true;
  validation_notes: string;
}
export interface ImportFinding {
  row: number;
  category: string;
  salesDate: string;
  reason: string;
  existingId?: string;
}
export interface CategorySummary {
  name: string;
  id: string | null;
  isActive: boolean | null;
  packageRows: number;
  accepted: number;
  identicalExisting: number;
  rejected: number;
  conflicts: number;
  firstDate: string | null;
  lastDate: string | null;
  eligibleDatesNow: number;
  eligibleDatesAfter: number;
}
export interface ImportPlan {
  dataset: { csvSha256: string; dataUsage: string; timelineType: string };
  categories: CategorySummary[];
  accepted: SaleToInsert[];
  identicalExisting: ImportFinding[];
  rejected: ImportFinding[];
  conflicts: ImportFinding[];
  previousDemoRows: ExistingSale[];
  issues: string[];
  canApply: boolean;
}

function parseCsv(text: string): string[][] {
  const input = text.replace(/^\uFEFF/, "");
  const rows: string[][] = [];
  let row: string[] = [];
  let cell = "";
  let quoted = false;
  for (let index = 0; index < input.length; index++) {
    const char = input[index];
    if (quoted) {
      if (char === '"' && input[index + 1] === '"') { cell += '"'; index++; }
      else if (char === '"') quoted = false;
      else cell += char;
    } else if (char === '"') {
      if (cell) throw new Error("Malformed CSV quoting.");
      quoted = true;
    } else if (char === ",") {
      row.push(cell); cell = "";
    } else if (char === "\n" || char === "\r") {
      if (char === "\r" && input[index + 1] === "\n") index++;
      row.push(cell); cell = "";
      rows.push(row); row = [];
    } else cell += char;
  }
  if (quoted) throw new Error("Unclosed CSV quote.");
  if (cell || row.length) { row.push(cell); rows.push(row); }
  return rows;
}

function validInteger(value: string, positive = false): number | null {
  if (!/^(0|[1-9]\d*)$/.test(value)) return null;
  const number = Number(value);
  return Number.isSafeInteger(number) && number <= 2_147_483_647 &&
    (!positive || number > 0) ? number : null;
}

function daysInclusive(start: string, end: string): string[] {
  const days: string[] = [];
  const cursor = new Date(`${start}T00:00:00.000Z`);
  while (cursor.toISOString().slice(0, 10) <= end) {
    days.push(cursor.toISOString().slice(0, 10));
    cursor.setUTCDate(cursor.getUTCDate() + 1);
  }
  return days;
}

function sourceIsValid(row: CsvRecord): boolean {
  return row.external_source_reference ===
    `${SOURCE_REFERENCE_PREFIX}af5eede55b6eb2ef:${row.original_sales_date}:${row.source_product}`;
}

function validationReason(row: CsvRecord): string | null {
  if (Object.values(row).some((value) => value === "")) return "MISSING_REQUIRED_FIELD";
  if (!isCalendarDate(row.sales_date) || row.sales_date < FIRST_DATE ||
      row.sales_date > LAST_DATE || !isCalendarDate(row.original_sales_date) ||
      !isCalendarDate(row.previous_demo_sales_date)) return "INVALID_DATE";
  if (validInteger(row.units_sold) === null) return "INVALID_UNITS_SOLD";
  if (!Object.hasOwn(SOURCE_PRODUCTS, row.bread_category) ||
      SOURCE_PRODUCTS[row.bread_category] !== row.source_product) {
    return "UNEXPECTED_CATEGORY_OR_SOURCE_PRODUCT";
  }
  if (row.data_origin !== "IMPORTED_HISTORICAL" || row.is_validated !== "false" ||
      row.data_usage !== DATA_USAGE || row.timeline_type !== TIMELINE_TYPE ||
      !sourceIsValid(row)) return "INVALID_PROVENANCE";
  const net = Number(row.source_daily_net_quantity);
  const scale = Number(row.quantity_scale_factor);
  const transactions = validInteger(row.source_transaction_rows, true);
  const negatives = validInteger(row.source_negative_quantity_rows);
  if (!Number.isFinite(net) || net <= 0 || !Number.isFinite(scale) ||
      scale <= 0 || transactions === null || negatives === null ||
      negatives > transactions) return "INVALID_SOURCE_METADATA";
  return null;
}

function asHistory(row: ExistingSale): DailySalesObservationRow {
  return { id: row.id, breadCategoryId: row.breadCategoryId,
    salesDate: row.salesDate, unitsSold: row.unitsSold,
    dataOrigin: row.dataOrigin, isValidated: row.isValidated,
    sourceDailyResultId: row.sourceDailyResultId,
    externalSourceReference: row.externalSourceReference };
}

export function buildImportPlan(csvText: string, categories: ImportCategory[],
  existing: ExistingSale[], targetDate: string): ImportPlan {
  if (!isCalendarDate(targetDate) || targetDate <= LAST_DATE) {
    throw new Error("The bakery date must be after 2026-11-08.");
  }
  const parsed = parseCsv(csvText);
  if (parsed.length === 0 || parsed[0]?.join("\u0000") !== columns.join("\u0000")) {
    throw new Error("The CSV header does not match the reviewed package.");
  }
  const issues: string[] = [];
  const expectedDays = new Set(daysInclusive(FIRST_DATE, LAST_DATE));
  if (parsed.length - 1 !== 240) issues.push(`Expected 240 CSV rows; found ${parsed.length - 1}.`);
  const names = Object.keys(SOURCE_PRODUCTS);
  const byName = new Map<string, ImportCategory[]>();
  for (const category of categories) {
    const key = category.name.trim().toLowerCase();
    byName.set(key, [...(byName.get(key) ?? []), category]);
  }
  const summaries = new Map(names.map((name): [string, CategorySummary] => [name,
    { name, id: null, isActive: null, packageRows: 0, accepted: 0,
      identicalExisting: 0, rejected: 0, conflicts: 0,
      firstDate: null, lastDate: null, eligibleDatesNow: 0,
      eligibleDatesAfter: 0 }]));
  for (const name of names) {
    const matches = byName.get(name.toLowerCase()) ?? [];
    const summary = summaries.get(name)!;
    if (matches.length !== 1) {
      issues.push(`${name}: expected one existing category mapping; found ${matches.length}.`);
    } else {
      summary.id = matches[0]!.id;
      summary.isActive = matches[0]!.isActive;
      if (!matches[0]!.isActive) issues.push(`${name}: category is inactive.`);
    }
  }
  const byDate = new Map<string, ExistingSale[]>();
  const byReference = new Map<string, ExistingSale[]>();
  for (const row of existing) {
    const key = `${row.breadCategoryId}:${row.salesDate}`;
    byDate.set(key, [...(byDate.get(key) ?? []), row]);
    if (row.externalSourceReference) {
      byReference.set(row.externalSourceReference,
        [...(byReference.get(row.externalSourceReference) ?? []), row]);
    }
  }
  const accepted: SaleToInsert[] = [];
  const identicalExisting: ImportFinding[] = [];
  const rejected: ImportFinding[] = [];
  const conflicts: ImportFinding[] = [];
  const seenDate = new Set<string>();
  const seenReference = new Set<string>();
  const previousKeys = new Set<string>();
  for (let index = 1; index < parsed.length; index++) {
    const cells = parsed[index]!;
    const line = index + 1;
    if (cells.length !== columns.length) {
      rejected.push({ row: line, category: cells[1] ?? "", salesDate: cells[0] ?? "",
        reason: "WRONG_COLUMN_COUNT" });
      continue;
    }
    const row = Object.fromEntries(columns.map((name, position) =>
      [name, cells[position]!])) as CsvRecord;
    const summary = summaries.get(row.bread_category);
    if (summary) {
      summary.packageRows++;
      summary.firstDate = summary.firstDate === null || row.sales_date < summary.firstDate
        ? row.sales_date : summary.firstDate;
      summary.lastDate = summary.lastDate === null || row.sales_date > summary.lastDate
        ? row.sales_date : summary.lastDate;
    }
    const reason = validationReason(row);
    const category = summary?.id ? categories.find((item) => item.id === summary.id) : null;
    const dateKey = `${row.bread_category}:${row.sales_date}`;
    if (reason || !category || !category.isActive || seenDate.has(dateKey) ||
        seenReference.has(row.external_source_reference)) {
      rejected.push({ row: line, category: row.bread_category,
        salesDate: row.sales_date,
        reason: reason ?? (!category ? "CATEGORY_NOT_MAPPED" :
          !category.isActive ? "CATEGORY_INACTIVE" : "DUPLICATE_IN_PACKAGE") });
      continue;
    }
    seenDate.add(dateKey);
    seenReference.add(row.external_source_reference);
    previousKeys.add(`${category.id}:${row.previous_demo_sales_date}`);
    const sameDate = byDate.get(`${category.id}:${row.sales_date}`) ?? [];
    const sameReference = byReference.get(row.external_source_reference) ?? [];
    const exact = sameDate.find((item) => item.dataOrigin === "IMPORTED_HISTORICAL" &&
      item.externalSourceReference === row.external_source_reference &&
      item.unitsSold === Number(row.units_sold) && item.sourceDailyResultId === null &&
      item.isValidated);
    const other = sameDate.find((item) => item.id !== exact?.id);
    const referenceElsewhere = sameReference.find((item) => item.id !== exact?.id);
    if (other || referenceElsewhere || (sameDate.length > 0 && !exact)) {
      const found = other ?? referenceElsewhere ?? sameDate[0]!;
      conflicts.push({ row: line, category: row.bread_category,
        salesDate: row.sales_date,
        reason: found.dataOrigin === "ACTUAL_TRANSACTION" ? "ACTUAL_SALES_OVERLAP" :
          found.dataOrigin === "SIMULATION_GENERATED" ? "SIMULATION_OVERLAP" :
          found.externalSourceReference === row.external_source_reference ?
            "SOURCE_REFERENCE_REUSED" : "IMPORTED_DATE_CONFLICT",
        existingId: found.id });
    } else if (exact) {
      identicalExisting.push({ row: line, category: row.bread_category,
        salesDate: row.sales_date, reason: "ALREADY_IMPORTED", existingId: exact.id });
    } else {
      accepted.push({ sales_date: row.sales_date, bread_category_id: category.id,
        units_sold: Number(row.units_sold), data_origin: "IMPORTED_HISTORICAL",
        source_daily_result_id: null,
        external_source_reference: row.external_source_reference,
        is_validated: true,
        validation_notes: `${DATA_USAGE}; ${TIMELINE_TYPE}; original_sales_date=${row.original_sales_date}; source_product=${row.source_product}; csv_sha256=${DATASET_CSV_SHA256}` });
    }
  }
  const previousDemoRows = existing.filter((row) =>
    row.dataOrigin === "IMPORTED_HISTORICAL" &&
    row.externalSourceReference !== null &&
    !row.externalSourceReference.startsWith(SOURCE_REFERENCE_PREFIX) &&
    (/(adapted|dummy|demo)/i.test(row.externalSourceReference) ||
      previousKeys.has(`${row.breadCategoryId}:${row.salesDate}`)));
  if (previousDemoRows.length) {
    issues.push(`${previousDemoRows.length} possible earlier demo import row(s) need explicit reconciliation.`);
  }
  const selector = new HistorySelectionService();
  for (const summary of summaries.values()) {
    const name = summary.name;
    const categoryRows = summary.id ? existing.filter((row) =>
      row.breadCategoryId === summary.id).map(asHistory) : [];
    if (summary.id) {
      summary.eligibleDatesNow = selector.selectForCategory(
        categoryRows, summary.id, targetDate).distinctDayCount;
      const projected = [...categoryRows, ...accepted.filter((row) =>
        row.bread_category_id === summary.id).map((row, index): DailySalesObservationRow => ({
          id: `preview-${name}-${index}`, breadCategoryId: row.bread_category_id,
          salesDate: row.sales_date, unitsSold: row.units_sold,
          dataOrigin: row.data_origin, isValidated: true, sourceDailyResultId: null,
          externalSourceReference: row.external_source_reference,
        }))];
      summary.eligibleDatesAfter = selector.selectForCategory(
        projected, summary.id, targetDate).distinctDayCount;
    }
    summary.accepted = accepted.filter((row) => row.bread_category_id === summary.id).length;
    summary.identicalExisting = identicalExisting.filter((row) => row.category === name).length;
    summary.rejected = rejected.filter((row) => row.category === name).length;
    summary.conflicts = conflicts.filter((row) => row.category === name).length;
    if (summary.packageRows !== 30 || summary.firstDate !== FIRST_DATE ||
        summary.lastDate !== LAST_DATE) {
      issues.push(`${name}: expected 30 rows from ${FIRST_DATE} through ${LAST_DATE}.`);
    }
    const selectedDays = new Set(parsed.slice(1).filter((cells) =>
      cells.length === columns.length && cells[1] === name).map((cells) => cells[0]));
    if ([...expectedDays].some((day) => !selectedDays.has(day))) {
      issues.push(`${name}: one or more dates are missing from the 30-day sequence.`);
    }
  }
  return {
    dataset: { csvSha256: DATASET_CSV_SHA256, dataUsage: DATA_USAGE,
      timelineType: TIMELINE_TYPE },
    categories: [...summaries.values()], accepted, identicalExisting,
    rejected, conflicts, previousDemoRows, issues,
    canApply: issues.length === 0 && rejected.length === 0 && conflicts.length === 0,
  };
}
