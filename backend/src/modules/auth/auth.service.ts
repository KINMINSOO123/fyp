import { AppError } from "../../shared/AppError.js";
import type { ProfileRepo } from "../profile/profile.repo.js";
import type { UserProfile } from "../profile/profile.model.js";

interface TokenVerifier {
  getUser(accessToken: string): Promise<{
    data: { user: { id: string } | null };
    error: { status?: number } | null;
  }>;
}

type ProfileReader = Pick<ProfileRepo, "findByUserId">;

export class AuthService {
  constructor(
    private readonly tokenVerifier?: TokenVerifier,
    private readonly profileRepo?: ProfileReader,
  ) {}

  async authenticate(accessToken: string): Promise<UserProfile> {
    if (!accessToken.trim()) {
      throw new AppError(
        401,
        "UNAUTHENTICATED",
        "Please sign in to continue.",
      );
    }

    const verifier = this.tokenVerifier ??
      (await import("../../config/supabase.js")).supabaseAdmin.auth;
    const { data, error } = await verifier.getUser(accessToken);

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

    const profileRepo = this.profileRepo ?? new (
      await import("../profile/profile.repo.js")
    ).ProfileRepo();
    const profile = await profileRepo.findByUserId(data.user.id);

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
