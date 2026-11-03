import type { RequestHandler } from "express";
import { AppError } from "../../shared/AppError.js";
import { ProfileService } from "./profile.service.js";

export class ProfileController {
  private readonly profileService = new ProfileService();
  
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

  updateMe: RequestHandler = async (req, res): Promise<void> => {
    const profile = req.auth;

    if (!profile) {
      throw new AppError(
        401,
        "UNAUTHENTICATED",
        "Please sign in to continue.",
      );
    }

    const updatedProfile = await this.profileService.updateOwnProfile(
      profile.userId,
      req.body,
    );

    res.json({
      data: updatedProfile,
    });
  }
}