import { Router } from "express";
import { NotificationController, PendingActionController,
  InventoryAlertController } from
  "./notification.controller.js";
import { requireRole } from "../../middleware/requireRole.js";

export const notificationRouter = Router();
export const preferenceRouter = Router();
export const tokenRouter = Router();
export const pendingRouter = Router();
export const inventoryAlertRouter = Router();
const notification = new NotificationController();
const pending = new PendingActionController();
const inventoryAlert = new InventoryAlertController();

notificationRouter.get("/", notification.list);
notificationRouter.patch("/:notificationId/read", notification.markRead);
notificationRouter.get("/:notificationId/deliveries", notification.deliveries);
preferenceRouter.get("/", notification.preferences);
preferenceRouter.patch("/", notification.savePreference);
tokenRouter.post("/", notification.registerToken);
tokenRouter.delete("/:tokenId", notification.deactivateToken);
pendingRouter.get("/", pending.get);
inventoryAlertRouter.post("/scan-alerts", requireRole("SYSTEM_ADMINISTRATOR"),
  inventoryAlert.scan);
