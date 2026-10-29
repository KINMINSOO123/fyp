import type { RequestHandler } from "express";
import { AppError } from "../../shared/AppError.js";

export class ProfileController {
  getMe: RequestHandler = (req, res): void => {
    const profile = req.auth;

    if (!profile) {
      throw new AppError(
        401,
        "UNAUTHENTICATED",
        "Please sign in to continue.",
      );
    }

    res.json({
      data: {
        userId: profile.userId,
        fullName: profile.fullName,
        role: profile.role,
        accountStatus: profile.accountStatus,
      },
    });
  };
}