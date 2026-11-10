import type { RequestHandler } from "express";
import { AppError } from "../../shared/AppError.js";
import { PredictionOrchestrationService } from "./prediction-orchestration.service.js";
import { NotificationEventService } from "../notifications/notification-event.service.js";
import { publishBestEffort, publishFailureBestEffort } from "../notifications/event-hooks.js";
import type { EventPublisher } from "../notifications/event-hooks.js";

export class PredictionController {
  constructor(
    private readonly service: Pick<PredictionOrchestrationService,
      "generate" | "listByDate" | "getNextDayState"> =
        new PredictionOrchestrationService(),
    private readonly notifications: EventPublisher = new NotificationEventService(),
  ) {}

  generate: RequestHandler = async (req, res): Promise<void> => {
    if (!req.auth) {
      throw new AppError(401, "UNAUTHENTICATED", "Please sign in to continue.");
    }
    let result;
    try {
      result = await this.service.generate(req.auth.userId, req.body);
    } catch (error) {
      await publishFailureBestEffort(this.notifications, error, "PREDICTION");
      throw error;
    }
    await publishBestEffort(this.notifications, result.predictions
      .filter((item) => item.lowConfidence)
      .map((item) => ({ type: "LOW_CONFIDENCE" as const,
        severity: "WARNING" as const,
        title: "Low-confidence prediction",
        message: `${item.breadCategoryName} for ${result.targetDate} needs manager review.`,
        eventKey: `prediction:${result.targetDate}:${item.id ?? item.breadCategoryName}`,
        ...(typeof item.id === "string" ? {
          relatedEntityType: "daily_predictions", relatedEntityId: item.id,
        } : {}),
      })));
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
