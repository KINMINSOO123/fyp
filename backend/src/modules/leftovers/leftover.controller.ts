import type { RequestHandler } from "express";
import { AppError } from "../../shared/AppError.js";
import { CharityPartnerService, LeftoverManagementService } from "./leftover.service.js";
import { NotificationEventService } from "../notifications/notification-event.service.js";
import { publishBestEffort } from "../notifications/event-hooks.js";
import type { EventPublisher } from "../notifications/event-hooks.js";

export class LeftoverManagementController {
  constructor(private readonly service: Pick<LeftoverManagementService,
    "list" | "recommendation" | "donate" | "recordWaste" |
    "advanceDonation" | "listDonations" | "listCharities"> =
      new LeftoverManagementService(),
    private readonly notifications: EventPublisher = new NotificationEventService()) {}

  list: RequestHandler = async (req, res): Promise<void> => {
    res.json({ data: await this.service.list(req.query) });
  };
  recommendation: RequestHandler = async (req, res): Promise<void> => {
    const resultId = req.params.resultId;
    if (typeof resultId !== "string") throw new AppError(400,
      "VALIDATION_ERROR", "A result ID is required.");
    res.json({ data: await this.service.recommendation(resultId) });
  };
  activeCharities: RequestHandler = async (_req, res): Promise<void> => {
    res.json({ data: await this.service.listCharities(true) });
  };
  donate: RequestHandler = async (req, res): Promise<void> => {
    if (!req.auth) throw new AppError(401, "UNAUTHENTICATED", "Please sign in.");
    const result = await this.service.donate(req.auth.userId, req.body);
    const donationId = (result as { allocationId?: unknown })?.allocationId;
    if (typeof donationId === "string") await publishBestEffort(this.notifications, [{
      type: "DONATION_STATUS", severity: "INFO", title: "Donation pending",
      message: "A manager confirmed a donation allocation.",
      eventKey: `donation-status:${donationId}:PENDING`,
      relatedEntityType: "donations", relatedEntityId: donationId,
    }]);
    res.status(201).json({ data: result });
  };
  recordWaste: RequestHandler = async (req, res): Promise<void> => {
    if (!req.auth) throw new AppError(401, "UNAUTHENTICATED", "Please sign in.");
    res.status(201).json({ data: await this.service.recordWaste(req.auth.userId, req.body) });
  };
  listDonations: RequestHandler = async (req, res): Promise<void> => {
    res.json({ data: await this.service.listDonations(req.query) });
  };
  advanceDonation: RequestHandler = async (req, res): Promise<void> => {
    if (!req.auth) throw new AppError(401, "UNAUTHENTICATED", "Please sign in.");
    const donationId = req.params.donationId;
    if (typeof donationId !== "string") throw new AppError(400,
      "VALIDATION_ERROR", "A donation ID is required.");
    const result = await this.service.advanceDonation(
      req.auth.userId, donationId, req.body);
    const status = (result as { status?: unknown })?.status;
    if (status === "COLLECTED" || status === "COMPLETED") {
      await publishBestEffort(this.notifications, [{
        type: "DONATION_STATUS", severity: "INFO",
        title: `Donation ${status.toLowerCase()}`,
        message: `Donation status changed to ${status.toLowerCase()}.`,
        eventKey: `donation-status:${donationId}:${status}`,
        relatedEntityType: "donations", relatedEntityId: donationId,
      }]);
    }
    res.json({ data: result });
  };
}

export class CharityPartnerController {
  constructor(private readonly service: Pick<CharityPartnerService,
    "list" | "save"> = new CharityPartnerService()) {}
  list: RequestHandler = async (_req, res): Promise<void> => {
    res.json({ data: await this.service.list() });
  };
  create: RequestHandler = async (req, res): Promise<void> => {
    if (!req.auth) throw new AppError(401, "UNAUTHENTICATED", "Please sign in.");
    res.status(201).json({ data: await this.service.save(req.auth.userId, req.body) });
  };
  update: RequestHandler = async (req, res): Promise<void> => {
    if (!req.auth) throw new AppError(401, "UNAUTHENTICATED", "Please sign in.");
    const partnerId = req.params.partnerId;
    if (typeof partnerId !== "string") throw new AppError(400,
      "VALIDATION_ERROR", "A partner ID is required.");
    res.json({ data: await this.service.save(req.auth.userId, req.body, partnerId) });
  };
}
