import type { RequestHandler } from "express";
import { AppError } from "../../shared/AppError.js";
import { NotificationEventService } from "../notifications/notification-event.service.js";
import type { EventPublisher } from "../notifications/event-hooks.js";
import { publishBestEffort } from "../notifications/event-hooks.js";
import { RestockService } from "./restock.service.js";

export class RestockController {
  constructor(private readonly service: Pick<RestockService,
    "preview" | "submit" | "list" | "cancel"> = new RestockService(),
    private readonly notifications: EventPublisher =
      new NotificationEventService()) {}
  private actor(req: Parameters<RequestHandler>[0]) {
    if (!req.auth) throw new AppError(401, "UNAUTHENTICATED", "Please sign in.");
    return req.auth;
  }
  preview: RequestHandler = async (req, res) => {
    res.json({ data: await this.service.preview(req.params.date as string) });
  };
  submit: RequestHandler = async (req, res) => {
    const saved = await this.service.submit(this.actor(req).userId, req.body);
    await publishBestEffort(this.notifications, [{
      type: "ADMINISTRATIVE_EVENT", severity: "WARNING",
      title: "Restock requested",
      message: `A manager requested ingredients for ${saved.productionDate}.`,
      eventKey: `restock:${saved.id}`, relatedEntityType: "restock_requests",
      relatedEntityId: saved.id,
    }]);
    res.status(201).json({ data: saved });
  };
  list: RequestHandler = async (req, res) => {
    const actor = this.actor(req);
    res.json({ data: await this.service.list(actor.userId, actor.role) });
  };
  cancel: RequestHandler = async (req, res) => {
    res.json({ data: await this.service.cancel(this.actor(req).userId,
      req.params.requestId as string, req.body) });
  };
}
