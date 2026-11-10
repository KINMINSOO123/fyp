import express from "express";
import { authenticate } from "./middleware/authenticate.js";
import { AppError } from "./shared/AppError.js";
import { errorHandler } from "./middleware/errorHandler.js";
import profileRouter from "./modules/profile/profile.routes.js";
import { requireRole } from "./middleware/requireRole.js";
import userAdministrationRouter from "./modules/user-administration/user-administration.routes.js";
import modelManagementRouter from "./modules/prediction/model-management.routes.js";
import predictionRouter from "./modules/prediction/prediction.routes.js";
import calendarRouter from "./modules/prediction/calendar.routes.js";
import recommendationRouter from "./modules/inventory/recommendation.routes.js";
import inventoryAdminRouter from "./modules/inventory/inventory-admin.routes.js";
import posSimulationRouter from "./modules/pos-simulation/pos-simulation.routes.js";
import { leftoverRouter, donationRouter, wasteRouter,
  charityAdminRouter } from "./modules/leftovers/leftover.routes.js";
import { reportRouter, dashboardRouter } from "./modules/reports/report.routes.js";
import { notificationRouter, preferenceRouter, tokenRouter,
  pendingRouter, inventoryAlertRouter } from "./modules/notifications/notification.routes.js";
import { settingsRouter, auditRouter, serviceStatusRouter } from
  "./modules/administration/administration.routes.js";

const app = express();

// Parse incoming JSON request bodies.
app.use(express.json());

// Public endpoint: no authentication required.
app.get("/api/health", (_req, res) => {
  res.json({
    status: "ok",
    service: "smart-bakery-api",
  });
});

// Protect every profile route with the authenticated, active user profile.
app.use("/api/profile", authenticate, profileRouter);

// Administrator account operations require the stored administrator role.
app.use("/api/admin/users", authenticate, requireRole("SYSTEM_ADMINISTRATOR"), userAdministrationRouter);

app.use("/api/admin/models", authenticate, requireRole("SYSTEM_ADMINISTRATOR"), modelManagementRouter);
app.use("/api/admin/calendar-events", authenticate,
  requireRole("SYSTEM_ADMINISTRATOR"), calendarRouter);
app.use("/api/admin/inventory", authenticate, requireRole("SYSTEM_ADMINISTRATOR"), inventoryAdminRouter);
app.use("/api/predictions", authenticate, predictionRouter);
app.use("/api/simulations", authenticate, posSimulationRouter);
app.use("/api/leftovers", authenticate, leftoverRouter);
app.use("/api/donations", authenticate, donationRouter);
app.use("/api/waste-records", authenticate, wasteRouter);
app.use("/api/reports", authenticate, reportRouter);
app.use("/api/dashboard", authenticate, dashboardRouter);
app.use("/api/notifications", authenticate, notificationRouter);
app.use("/api/notification-preferences", authenticate, preferenceRouter);
app.use("/api/fcm-tokens", authenticate, tokenRouter);
app.use("/api/pending-actions", authenticate, pendingRouter);
app.use("/api/admin/inventory", authenticate, inventoryAlertRouter);
app.use("/api/admin/settings", authenticate,
  requireRole("SYSTEM_ADMINISTRATOR"), settingsRouter);
app.use("/api/admin/audit", authenticate,
  requireRole("SYSTEM_ADMINISTRATOR"), auditRouter);
app.use("/api/admin/service-status", authenticate,
  requireRole("SYSTEM_ADMINISTRATOR"), serviceStatusRouter);
app.use("/api/admin/charity-partners", authenticate,
  requireRole("SYSTEM_ADMINISTRATOR"), charityAdminRouter);
app.use("/api", authenticate, requireRole("BAKERY_MANAGER"), recommendationRouter);

app.use((_req, _res, next) => {
  next(new AppError(404, "NOT_FOUND", "This endpoint does not exist."));
});

app.use(errorHandler);

export default app;
