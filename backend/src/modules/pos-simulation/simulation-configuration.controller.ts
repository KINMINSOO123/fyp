import type { RequestHandler } from "express";
import { AppError } from "../../shared/AppError.js";
import { SimulationConfigurationService } from
  "./simulation-configuration.service.js";

export class SimulationConfigurationController {
  constructor(private readonly service: Pick<SimulationConfigurationService,
    "get" | "saveBaseline" | "saveScenario"> =
      new SimulationConfigurationService()) {}
  get: RequestHandler = async (_req, res) => {
    res.json({ data: await this.service.get() });
  };
  baseline: RequestHandler = async (req, res) => {
    if (!req.auth) throw new AppError(401, "UNAUTHENTICATED", "Please sign in.");
    const categoryId = req.params.categoryId;
    if (typeof categoryId !== "string") throw new AppError(400,
      "VALIDATION_ERROR", "A category is required.");
    res.json({ data: await this.service.saveBaseline(req.auth.userId,
      categoryId, req.body) });
  };
  scenario: RequestHandler = async (req, res) => {
    if (!req.auth) throw new AppError(401, "UNAUTHENTICATED", "Please sign in.");
    res.json({ data: await this.service.saveScenario(req.auth.userId,
      req.body) });
  };
}
