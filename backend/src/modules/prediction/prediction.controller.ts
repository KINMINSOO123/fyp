import type { RequestHandler } from "express";
import { AppError } from "../../shared/AppError.js";
import { PredictionOrchestrationService } from "./prediction-orchestration.service.js";

export class PredictionController {
  constructor(
    private readonly service: Pick<PredictionOrchestrationService,
      "generate" | "listByDate" | "getNextDayState"> =
        new PredictionOrchestrationService(),
  ) {}

  generate: RequestHandler = async (req, res): Promise<void> => {
    if (!req.auth) {
      throw new AppError(401, "UNAUTHENTICATED", "Please sign in to continue.");
    }
    const result = await this.service.generate(req.auth.userId, req.body);
    res.status(201).json({ data: result });
  };

  listByDate: RequestHandler = async (req, res): Promise<void> => {
    if (!req.auth) {
      throw new AppError(401, "UNAUTHENTICATED", "Please sign in to continue.");
    }
    const date = req.params.date;
    if (typeof date !== "string") {
      throw new AppError(400, "VALIDATION_ERROR", "A prediction date is required.");
    }
    res.json({ data: await this.service.listByDate(date) });
  };

  nextDay: RequestHandler = async (req, res): Promise<void> => {
    if (!req.auth) {
      throw new AppError(401, "UNAUTHENTICATED", "Please sign in to continue.");
    }
    res.json({ data: await this.service.getNextDayState() });
  };
}
