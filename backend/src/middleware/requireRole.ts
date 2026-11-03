import type { RequestHandler } from "express";
import type { UserRole } from "../modules/profile/profile.model.js";
import { AppError } from "../shared/AppError.js";

export function requireRole( ...allowedRoles: UserRole[]): RequestHandler {
  return (req, _res, next) => {
    if (!req.auth) {
      throw new AppError(
        401,
        "UNAUTHENTICATED",
        "Please sign in to continue.",
      );
    }

    if(!allowedRoles.includes(req.auth.role)) {
      throw new AppError(
        403,
        "FORBIDDEN",
        "Your role cannot perform this action.",
      );
    }

    next();

  };
}