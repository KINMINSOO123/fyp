import { Router } from "express";
import { requireRole } from "../../middleware/requireRole.js";
import { RestockController } from "./restock.controller.js";

export const managerRestockRouter = Router();
export const adminRestockRouter = Router();
const controller = new RestockController();
managerRestockRouter.get("/preview/:date",
  requireRole("BAKERY_MANAGER"), controller.preview);
managerRestockRouter.get("/", controller.list);
managerRestockRouter.post("/", requireRole("BAKERY_MANAGER"),
  controller.submit);
adminRestockRouter.get("/", controller.list);
adminRestockRouter.post("/:requestId/cancel", controller.cancel);
