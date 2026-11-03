export type DataOrigin =
  | "ACTUAL_TRANSACTION"
  | "IMPORTED_HISTORICAL"
  | "SIMULATION_GENERATED";

// Node maps database columns to this shape before constructing an ML DTO.
// The runtime checks below still reject malformed or unvalidated rows.
export interface DailySalesObservationRow {
  id: string;
  breadCategoryId: string;
  salesDate: string;
  unitsSold: number;
  dataOrigin: string;
  isValidated: boolean;
  sourceDailyResultId: string | null;
  externalSourceReference: string | null;
}

export interface SelectedSalesObservation {
  id: string;
  breadCategoryId: string;
  salesDate: string;
  unitsSold: number;
  dataOrigin: DataOrigin;
  sourceDailyResultId: string | null;
  externalSourceReference: string | null;
}

export interface RejectedSalesObservation {
  id: string;
  reason: "UNVALIDATED" | "INVALID_OBSERVATION" | "NOT_HISTORICAL";
}

export interface HistorySelectionResult {
  observations: SelectedSalesObservation[];
  distinctDayCount: number;
  rejected: RejectedSalesObservation[];
}

const originPriority: Record<DataOrigin, number> = {
  ACTUAL_TRANSACTION: 0,
  IMPORTED_HISTORICAL: 1,
  SIMULATION_GENERATED: 2,
};

export function isCalendarDate(value: string): boolean {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(value)) {
    return false;
  }

  const parsed = new Date(`${value}T00:00:00.000Z`);
  return !Number.isNaN(parsed.getTime()) &&
    parsed.toISOString().slice(0, 10) === value;
}

function isOrigin(value: string): value is DataOrigin {
  return Object.hasOwn(originPriority, value);
}

function hasValidSource(row: DailySalesObservationRow): boolean {
  if (row.dataOrigin === "SIMULATION_GENERATED") {
    return typeof row.sourceDailyResultId === "string" &&
      row.sourceDailyResultId.trim().length > 0 &&
      row.externalSourceReference === null;
  }

  return row.sourceDailyResultId === null &&
    typeof row.externalSourceReference === "string" &&
    row.externalSourceReference.trim().length > 0;
}

export class HistorySelectionService {
  selectForCategory(
    rows: readonly DailySalesObservationRow[],
    breadCategoryId: string,
    targetDate: string,
  ): HistorySelectionResult {
    if (!breadCategoryId.trim() || !isCalendarDate(targetDate)) {
      throw new Error("A category and valid target date are required.");
    }

    const selectedByDate = new Map<string, SelectedSalesObservation>();
    const seenDateOrigins = new Set<string>();
    const rejected: RejectedSalesObservation[] = [];

    for (const row of rows) {
      if (row.breadCategoryId !== breadCategoryId) {
        throw new Error("History contains another bread category.");
      }

      if (!row.isValidated) {
        rejected.push({ id: row.id, reason: "UNVALIDATED" });
        continue;
      }

      if (
        typeof row.id !== "string" || !row.id.trim() ||
        !isCalendarDate(row.salesDate) ||
        !Number.isSafeInteger(row.unitsSold) || row.unitsSold < 0 ||
        !isOrigin(row.dataOrigin) || !hasValidSource(row)
      ) {
        rejected.push({ id: row.id, reason: "INVALID_OBSERVATION" });
        continue;
      }

      // The target day and later days cannot be training or baseline history.
      if (row.salesDate >= targetDate) {
        rejected.push({ id: row.id, reason: "NOT_HISTORICAL" });
        continue;
      }

      const dateOrigin = `${row.salesDate}:${row.dataOrigin}`;
      if (seenDateOrigins.has(dateOrigin)) {
        throw new Error(
          `Duplicate validated ${row.dataOrigin} observation for ${row.salesDate}.`,
        );
      }
      seenDateOrigins.add(dateOrigin);

      const candidate: SelectedSalesObservation = {
        id: row.id,
        breadCategoryId: row.breadCategoryId,
        salesDate: row.salesDate,
        unitsSold: row.unitsSold,
        dataOrigin: row.dataOrigin,
        sourceDailyResultId: row.sourceDailyResultId,
        externalSourceReference: row.externalSourceReference,
      };
      const current = selectedByDate.get(row.salesDate);
      if (
        current === undefined ||
        originPriority[candidate.dataOrigin] < originPriority[current.dataOrigin]
      ) {
        selectedByDate.set(row.salesDate, candidate);
      }
    }

    const observations = [...selectedByDate.values()].sort(
      (a, b) => a.salesDate.localeCompare(b.salesDate),
    );

    return {
      observations,
      distinctDayCount: observations.length,
      rejected,
    };
  }
}
