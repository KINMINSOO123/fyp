import type { RequestHandler } from "express";
import { AppError } from "../../shared/AppError.js";
import { CalendarService } from "./calendar.service.js";

export class CalendarController {
  constructor(private readonly service = new CalendarService()) {}
  list: RequestHandler = async (req, res) => {
    res.json({ data: await this.service.list(String(req.query.date ?? "")) });
  };
  add: RequestHandler = async (req, res) => {
    if (!req.auth) throw new AppError(401, "UNAUTHENTICATED", "Please sign in.");
    res.status(201).json({ data: await this.service.add(
      req.auth.userId, req.body) });
  };
}
