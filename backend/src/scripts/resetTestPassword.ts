import { supabaseAdmin } from "../config/supabase.js";

async function resetPassword(): Promise<void> {
  const userId = process.env.RESET_USER_ID;
  const password = process.env.RESET_PASSWORD;

  if (!userId || !password) {
    throw new Error("User ID and new password are required.");
  }

  const { error } = await supabaseAdmin.auth.admin.updateUserById(
    userId,
    { password },
  );

  if (error) {
    throw new Error(error.message);
  }

  console.log("Password changed successfully.");
}

resetPassword().catch((error: unknown) => {
  console.error(
    error instanceof Error ? error.message : "Password reset failed.",
  );
  process.exitCode = 1;
});