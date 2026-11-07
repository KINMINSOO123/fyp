import { AppError } from "../../shared/AppError.js";

export function mapAdminUpdateError(error: {
  code: string;
  message: string;
}): Error {
  if (error.code === "P0002") {
    return new AppError(404, "USER_NOT_FOUND", "The user profile does not exist.");
  }
  if (
    error.code === "P0001" &&
    error.message.includes("final active System Administrator")
  ) {
    return new AppError(
      409,
      "FINAL_ACTIVE_ADMIN_REQUIRED",
      "The final active System Administrator cannot be deactivated or assigned another role.",
    );
  }
  if (error.code === "42501") {
    return new AppError(403, "FORBIDDEN", "Administrator permission is required.");
  }
  if (error.code === "22023") {
    return new AppError(400, "VALIDATION_ERROR", error.message);
  }
  return new Error("Unable to update the user profile and audit record.");
}
