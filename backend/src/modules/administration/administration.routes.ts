import { Router } from "express";
import { AdministrationController } from "./administration.controller.js";

export const settingsRouter = Router();
export const auditRouter = Router();
const controller = new AdministrationController();
settingsRouter.get("/", controller.settings);
settingsRouter.patch("/bakery", controller.saveBakery);
settingsRouter.patch("/:key", controller.saveSystem);
auditRouter.get("/", controller.audit);
export const serviceStatusRouter = Router();
serviceStatusRouter.get("/", controller.serviceStatus);
