import type { RequestHandler } from "express";
import { AppError } from "../../shared/AppError.js";
import { NotificationService } from "./notification.service.js";
import { PendingActionService } from "./pending-action.service.js";
import { InventoryAlertService } from "./inventory-alert.service.js";

export class NotificationController {
  constructor(private readonly service = new NotificationService()) {}
  private user(req: Parameters<RequestHandler>[0]): string {
    if (!req.auth) throw new AppError(401, "UNAUTHENTICATED", "Please sign in.");
    return req.auth.userId;
  }
  list: RequestHandler = async (req, res) => {
    res.json({ data: await this.service.list(this.user(req), req.query) });
  };
  preferences: RequestHandler = async (req, res) => {
    res.json({ data: await this.service.preferences(this.user(req)) });
  };
  savePreference: RequestHandler = async (req, res) => {
    res.json({ data: await this.service.savePreference(this.user(req), req.body) });
  };
  markRead: RequestHandler = async (req, res) => {
    res.json({ data: await this.service.markRead(this.user(req),
      req.params.notificationId as string, req.body ?? {}) });
  };
  deliveries: RequestHandler = async (req, res) => {
    res.json({ data: await this.service.deliveries(this.user(req),
      req.params.notificationId as string) });
  };
  registerToken: RequestHandler = async (req, res) => {
    res.status(201).json({ data: await this.service.registerToken(
      this.user(req), req.body) });
  };
  deactivateToken: RequestHandler = async (req, res) => {
    await this.service.deactivateToken(this.user(req),
      req.params.tokenId as string);
    res.json({ data: { deactivated: true } });
  };
}

export class PendingActionController {
  constructor(private readonly service = new PendingActionService()) {}
  get: RequestHandler = async (req, res) => {
    if (!req.auth) throw new AppError(401, "UNAUTHENTICATED", "Please sign in.");
    res.json({ data: await this.service.get(req.auth.role, req.query) });
  };
}

export class InventoryAlertController {
  constructor(private readonly service = new InventoryAlertService()) {}
  scan: RequestHandler = async (_req, res) => {
    res.json({ data: await this.service.scan() });
  };
}
