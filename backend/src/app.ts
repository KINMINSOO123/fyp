import express from "express";
import {authenticate} from "./middleware/authenticate.js";
import { AppError } from "./shared/AppError.js";
import { errorHandler } from "./middleware/errorHandler.js";
import profileRouter from "./modules/profile/profile.routes.js";
import {requireRole} from "./middleware/requireRole.js";
import userAdministrationRouter from "./modules/user-administration/user-administration.routes.js";

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

//register the authentication middleware for all routes under /api/profile
app.use("/api/profile", authenticate, profileRouter);

//register the authentication middleware for all routes under /api/user-administration
app.use("/api/admin/users", authenticate, requireRole("SYSTEM_ADMINISTRATOR"), userAdministrationRouter);

// Profile routes will go here next.

app.use((_req, _res, next) => {
  next(new AppError(404, "NOT_FOUND", "This endpoint does not exist."));
});

app.use(errorHandler);

export default app;