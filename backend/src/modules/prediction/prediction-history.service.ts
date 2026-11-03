import type { DailySalesRecordRepo } from "./daily-sales-record.repo.js";
import {
  HistorySelectionService,
  type HistorySelectionResult,
} from "./history-selection.service.js";

type SalesHistoryReader = Pick<DailySalesRecordRepo, "listBeforeDate">;

export class PredictionHistoryService {
  constructor(
    private readonly repo?: SalesHistoryReader,
    private readonly selector = new HistorySelectionService(),
  ) {}

  async loadSelected(
    breadCategoryId: string,
    targetDate: string,
  ): Promise<HistorySelectionResult> {
    const repo = this.repo ?? new (
      await import("./daily-sales-record.repo.js")
    ).DailySalesRecordRepo();
    const rows = await repo.listBeforeDate(breadCategoryId, targetDate);
    return this.selector.selectForCategory(rows, breadCategoryId, targetDate);
  }
}
