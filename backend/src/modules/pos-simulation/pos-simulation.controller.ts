import type { RequestHandler } from "express";
import { AppError } from "../../shared/AppError.js";
import { PosSimulationService } from "./pos-simulation.service.js";
import { NotificationEventService } from "../notifications/notification-event.service.js";
import { publishBestEffort, publishFailureBestEffort } from "../notifications/event-hooks.js";
import type { EventPublisher } from "../notifications/event-hooks.js";

export class PosSimulationController {
  constructor(private readonly service: Pick<PosSimulationService,
    "run" | "getToday" | "getResult" | "getTransactions"> = new PosSimulationService(),
    private readonly notifications: EventPublisher = new NotificationEventService()) {}

  getToday: RequestHandler = async (req, res): Promise<void> => {
    if (!req.auth) throw new AppError(401, "UNAUTHENTICATED", "Please sign in to continue.");
    res.json({ data: await this.service.getToday() });
  };

  run: RequestHandler = async (req, res): Promise<void> => {
    if (!req.auth) throw new AppError(401, "UNAUTHENTICATED", "Please sign in to continue.");
    let result;
    try {
      result = await this.service.run(req.auth.userId, req.body);
    } catch (error) {
      await publishFailureBestEffort(this.notifications, error, "SIMULATION");
      throw error;
    }
    const surplusThreshold = Number(process.env.SURPLUS_ALERT_THRESHOLD_PCT ?? "20");
    const threshold = Number.isFinite(surplusThreshold) && surplusThreshold >= 0 &&
      surplusThreshold <= 100 ? surplusThreshold : 20;
    await publishBestEffort(this.notifications, result.items.flatMap((item) => {
      const events = [] as Array<{ type: "LOST_SALES" | "EXCESSIVE_LEFTOVER";
        severity: "WARNING"; title: string; message: string;
        eventKey: string; relatedEntityType: string; relatedEntityId: string }>;
      if (item.lostSales > 0) events.push({ type: "LOST_SALES",
        severity: "WARNING", title: "Simulated lost sales",
        message: `${item.breadCategoryName}: ${item.lostSales} simulated lost sales on ${result.date}.`,
        eventKey: `lost-sales:${item.dailyResultId}`,
        relatedEntityType: "daily_results", relatedEntityId: item.dailyResultId });
      if (item.leftover > 0 && item.leftoverRatePct !== null &&
          item.leftoverRatePct >= threshold) events.push({
        type: "EXCESSIVE_LEFTOVER", severity: "WARNING",
        title: "Simulated surplus needs review",
        message: `${item.breadCategoryName}: ${item.leftover} leftover units on ${result.date}.`,
        eventKey: `surplus:${item.dailyResultId}`,
        relatedEntityType: "daily_results", relatedEntityId: item.dailyResultId });
      return events;
    }));
    res.status(201).json({ data: result });
  };

  getResult: RequestHandler = async (req, res): Promise<void> => {
    if (!req.auth) throw new AppError(401, "UNAUTHENTICATED", "Please sign in to continue.");
    const date = req.params.date;
    if (typeof date !== "string") throw new AppError(400, "VALIDATION_ERROR", "A date is required.");
    res.json({ data: await this.service.getResult(date) });
  };

  getTransactions: RequestHandler = async (req, res): Promise<void> => {
    if (!req.auth) throw new AppError(401, "UNAUTHENTICATED", "Please sign in to continue.");
    const date = req.params.date;
    if (typeof date !== "string") throw new AppError(400, "VALIDATION_ERROR", "A date is required.");
    res.json({ data: await this.service.getTransactions(date, req.query) });
  };
}
