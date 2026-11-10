import type { RequestHandler } from "express";
import { AppError } from "../../shared/AppError.js";
import { AdministrationService } from "./administration.service.js";

export class AdministrationController {
  constructor(private readonly service = new AdministrationService()) {}
  private actor(req: Parameters<RequestHandler>[0]): string {
    if (!req.auth) throw new AppError(401, "UNAUTHENTICATED", "Please sign in.");
    return req.auth.userId;
  }
  settings: RequestHandler = async (_req, res) => {
    res.json({ data: await this.service.settings() });
  };
  serviceStatus: RequestHandler = async (_req, res) => {
    res.json({ data: await this.service.serviceStatus() });
  };
  saveBakery: RequestHandler = async (req, res) => {
    res.json({ data: await this.service.saveBakery(this.actor(req), req.body) });
  };
  saveSystem: RequestHandler = async (req, res) => {
    res.json({ data: await this.service.saveSystem(this.actor(req),
      req.params.key as string, req.body) });
  };
  audit: RequestHandler = async (req, res) => {
    res.json({ data: await this.service.audit(req.query) });
  };
}
