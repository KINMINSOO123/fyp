import type { RequestHandler } from "express";
import { AppError } from "../../shared/AppError.js";
import { KlHolidayService } from "./kl-holiday.service.js";

export class KlHolidayController {
  constructor(private readonly service: Pick<KlHolidayService,
    "list" | "refresh"> = new KlHolidayService()) {}
  list: RequestHandler = async (req, res) => {
    const year = Number(req.query.year);
    res.json({ data: await this.service.list(year) });
  };
  refresh: RequestHandler = async (req, res) => {
    if (!req.auth) throw new AppError(401, "UNAUTHENTICATED", "Please sign in.");
    const body = req.body;
    if (!body || typeof body !== "object" || Array.isArray(body) ||
        Object.keys(body).length !== 1 || !Number.isInteger(body.year)) {
      throw new AppError(400, "VALIDATION_ERROR", "A year is required.");
    }
    res.json({ data: await this.service.refresh(req.auth.userId, body.year) });
  };
}
