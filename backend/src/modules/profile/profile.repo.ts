import { supabaseAdmin } from "../../config/supabase.js";
import type { UserProfile } from "./profile.model.js";

export class ProfileRepo {
  async findByUserId(userId: string): Promise<UserProfile | null> {
    const { data, error } = await supabaseAdmin
      .from("user_profiles")
      .select("user_id, full_name, role, account_status")
      .eq("user_id", userId)
      .maybeSingle();

    if (error) {
      throw new Error("Unable to load user profile.");
    }

    if (!data) {
      return null;
    }

    const role = data.role;
    const accountStatus = data.account_status;

    if (
      role !== "BAKERY_MANAGER" &&
      role !== "SYSTEM_ADMINISTRATOR"
    ) {
      throw new Error("Invalid stored user role.");
    }

    if (
      accountStatus !== "ACTIVE" &&
      accountStatus !== "INACTIVE"
    ) {
      throw new Error("Invalid stored account status.");
    }

    return {
      userId: data.user_id,
      fullName: data.full_name,
      role,
      accountStatus,
    };
  }
}