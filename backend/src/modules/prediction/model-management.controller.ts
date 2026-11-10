import type { RequestHandler } from "express";
import { AppError } from "../../shared/AppError.js";
import { ModelManagementService } from "./model-management.service.js";
import { NotificationEventService } from "../notifications/notification-event.service.js";
import { publishFailureBestEffort } from "../notifications/event-hooks.js";
import type { EventPublisher } from "../notifications/event-hooks.js";

export class ModelManagementController {
  constructor(
    private readonly service: Pick<ModelManagementService,
      "listTrainingCategories" | "listModels" | "getModelDetails" | "trainCandidates" |
      "evaluateCandidate" | "activateCandidate" |
      "restorePreviousModel"> = new ModelManagementService(),
    private readonly notifications: EventPublisher = new NotificationEventService(),
  ) {}

  private async guarded<T>(operation: () => Promise<T>): Promise<T> {
    try { return await operation(); }
    catch (error) {
      await publishFailureBestEffort(this.notifications, error, "MODEL");
      throw error;
    }
  }

  categories: RequestHandler = async (req, res): Promise<void> => {
    if (!req.auth) {
      throw new AppError(401, "UNAUTHENTICATED", "Please sign in to continue.");
    }
    res.json({ data: await this.service.listTrainingCategories() });
  };

  list: RequestHandler = async (req, res): Promise<void> => {
    if (!req.auth) {
      throw new AppError(401, "UNAUTHENTICATED", "Please sign in to continue.");
    }
    res.json({ data: await this.service.listModels(req.query) });
  };

  detail: RequestHandler = async (req, res): Promise<void> => {
    if (!req.auth) {
      throw new AppError(401, "UNAUTHENTICATED", "Please sign in to continue.");
    }
    const modelVersionId = req.params.modelVersionId;
    if (typeof modelVersionId !== "string") {
      throw new AppError(400, "VALIDATION_ERROR",
        "A model version ID is required.");
    }
    res.json({ data: await this.service.getModelDetails(modelVersionId) });
  };

  train: RequestHandler = async (req, res): Promise<void> => {
    if (!req.auth) {
      throw new AppError(401, "UNAUTHENTICATED", "Please sign in to continue.");
    }
    const result = await this.guarded(() =>
      this.service.trainCandidates(req.auth!.userId, req.body));
    res.status(201).json({ data: result });
  };

  evaluate: RequestHandler = async (req, res): Promise<void> => {
    if (!req.auth) {
      throw new AppError(401, "UNAUTHENTICATED", "Please sign in to continue.");
    }
    if (req.body !== undefined && (
      typeof req.body !== "object" || req.body === null ||
      Array.isArray(req.body) || Object.keys(req.body).length !== 0
    )) {
      throw new AppError(400, "VALIDATION_ERROR",
        "Evaluation accepts no client-supplied dataset or role fields.");
    }
    const modelVersionId = req.params.modelVersionId;
    if (typeof modelVersionId !== "string") {
      throw new AppError(400, "VALIDATION_ERROR",
        "A model version ID is required.");
    }
    const result = await this.guarded(() =>
      this.service.evaluateCandidate(req.auth!.userId, modelVersionId));
    res.status(201).json({ data: result });
  };

  activate: RequestHandler = async (req, res): Promise<void> => {
    if (!req.auth) {
      throw new AppError(401, "UNAUTHENTICATED", "Please sign in to continue.");
    }
    const modelVersionId = req.params.modelVersionId;
    if (typeof modelVersionId !== "string") {
      throw new AppError(400, "VALIDATION_ERROR",
        "A model version ID is required.");
    }
    const result = await this.guarded(() =>
      this.service.activateCandidate(req.auth!.userId, modelVersionId,
        req.body));
    res.json({ data: result });
  };

  restore: RequestHandler = async (req, res): Promise<void> => {
    if (!req.auth) {
      throw new AppError(401, "UNAUTHENTICATED", "Please sign in to continue.");
    }
    const modelVersionId = req.params.modelVersionId;
    if (typeof modelVersionId !== "string") {
      throw new AppError(400, "VALIDATION_ERROR",
        "A model version ID is required.");
    }
    const result = await this.guarded(() =>
      this.service.restorePreviousModel(req.auth!.userId, modelVersionId,
        req.body));
    res.json({ data: result });
  };
}
