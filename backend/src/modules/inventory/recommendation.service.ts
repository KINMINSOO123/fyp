import { AppError } from "../../shared/AppError.js";
import { isCalendarDate } from "../prediction/history-selection.service.js";
import { RecommendationEngine } from "./recommendation-engine.js";
import type { RecommendationRepo } from "./recommendation.repo.js";

const uuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
type DataRepo = Pick<RecommendationRepo, "load" | "loadByPredictionId" | "confirm">;

export class RecommendationService {
  constructor(private readonly providedRepo?: DataRepo,
    private readonly engine = new RecommendationEngine()) {}

  private async repo(): Promise<DataRepo> {
    return this.providedRepo ?? new (await import("./recommendation.repo.js")).RecommendationRepo();
  }

  async getPlan(date: string, query: unknown = {}) {
    if (!isCalendarDate(date)) throw new AppError(400, "VALIDATION_ERROR", "A valid production date is required.");
    if (typeof query !== "object" || query === null || Array.isArray(query)) {
      throw new AppError(400, "VALIDATION_ERROR", "Invalid planning preview request.");
    }
    const params = query as Record<string, unknown>;
    if (Object.keys(params).some((key) => key !== "revisingPredictionId") ||
        (params.revisingPredictionId !== undefined &&
         (typeof params.revisingPredictionId !== "string" ||
          !uuidPattern.test(params.revisingPredictionId)))) {
      throw new AppError(400, "VALIDATION_ERROR", "Invalid revision preview.");
    }
    const input = await (await this.repo()).load(date);
    const revisionId = params.revisingPredictionId as string | undefined;
    if (revisionId) {
      const existing = input.decisions.find((row) => row.predictionId === revisionId);
      if (!existing || existing.processed) {
        throw new AppError(409, "DECISION_NOT_REVISABLE", "Only an outstanding decision can be previewed for revision.");
      }
    }
    return this.engine.build(input, revisionId);
  }

  async confirm(actorUserId: string, body: unknown) {
    if (typeof body !== "object" || body === null || Array.isArray(body)) {
      throw new AppError(400, "VALIDATION_ERROR", "A production decision is required.");
    }
    const input = body as Record<string, unknown>;
    if (Object.keys(input).some((key) => ![
      "predictionId", "finalSelectedQty", "selectedOption", "decisionReason",
    ].includes(key)) || Object.keys(input).length !== 4 ||
        typeof input.predictionId !== "string" || !uuidPattern.test(input.predictionId) ||
        !Number.isSafeInteger(input.finalSelectedQty) || (input.finalSelectedQty as number) < 0 ||
        !["ACCEPT_RECOMMENDATION", "REDUCE", "MANUAL_OVERRIDE"].includes(String(input.selectedOption)) ||
        !(input.decisionReason === null || typeof input.decisionReason === "string")) {
      throw new AppError(400, "VALIDATION_ERROR", "Invalid production decision fields.");
    }
    const predictionId = input.predictionId;
    const selected = input.finalSelectedQty as number;
    const option = input.selectedOption as string;
    const reason = typeof input.decisionReason === "string" ? input.decisionReason.trim() : null;
    if ((option === "ACCEPT_RECOMMENDATION" && reason !== null) ||
        (option !== "ACCEPT_RECOMMENDATION" && !reason)) {
      throw new AppError(400, "VALIDATION_ERROR", "The selected option requires a valid reason.");
    }
    const repo = await this.repo();
    const inputData = await repo.loadByPredictionId(predictionId);
    if (!inputData.predictions.some((row) => row.id === predictionId)) {
      throw new AppError(404, "PREDICTION_NOT_FOUND", "The stored prediction was not found.");
    }
    const existing = inputData.decisions.find((row) => row.predictionId === predictionId);
    if (existing?.processed) {
      throw new AppError(409, "DECISION_ALREADY_PROCESSED", "Processed production cannot be revised.");
    }
    const plan = this.engine.build(inputData, predictionId);
    if (plan.status !== "READY") {
      throw new AppError(409, "PLAN_SHORTAGE", "Existing commitments exceed valid stock.");
    }
    const entry = plan.entries.find((row) => row.predictionId === predictionId);
    if (!entry || entry.recommendedProduction === null) {
      throw new AppError(409, "PREDICTION_INCOMPLETE", "A current recommendation is required.");
    }
    const maxAfterCommitments = this.engine.maxAfterCommitments(
      inputData, entry.breadCategoryId, predictionId);
    if (selected > maxAfterCommitments) {
      throw new AppError(409, "PLAN_SHORTAGE", "The selected quantity exceeds jointly available ingredients.");
    }
    if ((option === "ACCEPT_RECOMMENDATION" && selected !== entry.recommendedProduction) ||
        (option === "REDUCE" && selected >= entry.recommendedProduction)) {
      throw new AppError(400, "VALIDATION_ERROR", "The selected quantity does not match the option.");
    }
    // The RPC repeats all checks under the production-date lock. This preview is never authoritative.
    await repo.confirm(actorUserId, { predictionId, finalSelectedQty: selected,
      selectedOption: option, decisionReason: reason });
    return this.engine.build(await repo.load(inputData.targetDate));
  }
}
