import express from "express";
import {authenticate} from "./middleware/authenticate.js";
import { AppError } from "./shared/AppError.js";
import { errorHandler } from "./middleware/errorHandler.js";
import profileRouter from "./modules/profile/profile.routes.js";

const app = express();

// Parse incoming JSON request bodies.
app.use(express.json());

//register the authentication middleware for all routes under /api/profile
app.use("/api/profile", authenticate, profileRouter);

// Profile routes will go here next.

app.use((_req, _res, next) => {
  next(new AppError(404, "NOT_FOUND", "This endpoint does not exist."));
});

app.use(errorHandler);

// A simple endpoint to check whether the server is running.
app.get("/api/health", (_req, res) => {
  res.json({
    status: "ok",
    service: "smart-bakery-api",
  });
});

export default app;