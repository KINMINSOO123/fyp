import { supabaseAdmin } from "../../config/supabase.js";
import { AppError } from "../../shared/AppError.js";
import { ProfileRepo } from "../profile/profile.repo.js";
import type { UserProfile } from "../profile/profile.model.js";

export class AuthService {
  private readonly profileRepo = new ProfileRepo();

  async authenticate(accessToken: string): Promise<UserProfile> {
    if (!accessToken.trim()) {
      throw new AppError(
        401,
        "UNAUTHENTICATED",
        "Please sign in to continue.",
      );
    }

    const { data, error } =
      await supabaseAdmin.auth.getUser(accessToken);

    if (error) {
      const status = error.status;

      if (!status || status >= 500 || status === 429) {
        throw new AppError(
          503,
          "AUTH_UNAVAILABLE",
          "Authentication is temporarily unavailable. Please try again.",
        );
      }

      throw new AppError(
        401,
        "INVALID_TOKEN",
        "Your session is invalid or expired. Please sign in again.",
      );
    }

    if (!data.user) {
      throw new AppError(
        401,
        "UNAUTHENTICATED",
        "Please sign in to continue.",
      );
    }

    const profile = await this.profileRepo.findByUserId(data.user.id);

    if (!profile) {
      throw new AppError(
        403,
        "PROFILE_REQUIRED",
        "Your account has no application profile.",
      );
    }

    if (profile.accountStatus !== "ACTIVE") {
      throw new AppError(
        403,
        "ACCOUNT_INACTIVE",
        "Your account is inactive. Please contact the administrator.",
      );
    }

    return profile;
  }
}