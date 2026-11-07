import type { RequestHandler } from "express";
import { AppError } from "../../shared/AppError.js";
import { RecommendationService } from "./recommendation.service.js";

export class RecommendationController {
  constructor(private readonly service: Pick<RecommendationService,
    "getPlan" | "confirm"> = new RecommendationService()) {}

  getPlan: RequestHandler = async (req, res): Promise<void> => {
    if (!req.auth) throw new AppError(401, "UNAUTHENTICATED", "Please sign in to continue.");
    const date = req.params.date;
    if (typeof date !== "string") throw new AppError(400, "VALIDATION_ERROR", "A date is required.");
    res.json({ data: await this.service.getPlan(date, req.query) });
  };

  confirm: RequestHandler = async (req, res): Promise<void> => {
    if (!req.auth) throw new AppError(401, "UNAUTHENTICATED", "Please sign in to continue.");
    res.json({ data: await this.service.confirm(req.auth.userId, req.body) });
  };
}
