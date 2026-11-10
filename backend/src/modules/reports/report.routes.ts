import { Router } from "express";
import { ReportController } from "./report.controller.js";

export const reportRouter = Router();
export const dashboardRouter = Router();
const controller = new ReportController();

reportRouter.get("/", controller.get);
reportRouter.get("/categories", controller.categories);
reportRouter.get("/export", controller.export);
dashboardRouter.get("/", controller.get);
