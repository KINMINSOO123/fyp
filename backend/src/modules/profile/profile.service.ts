import { AppError } from "../../shared/AppError.js";
import type { ProfileRepo } from "./profile.repo.js";
import type { UserProfile } from "./profile.model.js";

export class ProfileService {
  constructor(
    private readonly profileRepo?: Pick<ProfileRepo, "updateFullName">,
  ) {}

  async updateOwnProfile(
    userId: string,
    input: unknown,
  ): Promise<UserProfile> {
    if (
      typeof input !== "object" ||
      input === null ||
      Array.isArray(input)
    ) {
      throw new AppError(
        400,
        "VALIDATION_ERROR",
        "A valid profile object is required.",
      );
    }

    const body = input as Record<string, unknown>;
    const allowedFields = new Set(["fullName"]);

    const unsupportedField = Object.keys(body).find(
      (field) => !allowedFields.has(field),
    );

    if (unsupportedField) {
      throw new AppError(
        400,
        "PROFILE_FIELD_NOT_EDITABLE",
        `The field '${unsupportedField}' cannot be changed here.`,
      );
    }

    if (typeof body.fullName !== "string") {
      throw new AppError(
        400,
        "VALIDATION_ERROR",
        "Full name is required.",
      );
    }

    const fullName = body.fullName.trim();

    if (!fullName) {
      throw new AppError(
        400,
        "VALIDATION_ERROR",
        "Full name cannot be empty.",
      );
    }

    const profileRepo = this.profileRepo ?? new (
      await import("./profile.repo.js")
    ).ProfileRepo();
    const updatedProfile = await profileRepo.updateFullName(userId, fullName);

    if (!updatedProfile) {
      throw new AppError(
        404,
        "PROFILE_NOT_FOUND",
        "The user profile no longer exists.",
      );
    }

    return updatedProfile;
  }
}
