import { supabaseAdmin } from "../../config/supabase.js";
import type { UserProfile } from "./profile.model.js";

export class ProfileRepo {

  validateRoleAndAccountStatus(role: string, accountStatus: string): void {
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
  }

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

    this.validateRoleAndAccountStatus(role, accountStatus);

    return {
      userId: data.user_id,
      fullName: data.full_name,
      role,
      accountStatus,
    };
  }
  
  async updateFullName(userId: string, fullName: string): Promise<UserProfile | null> {
    const { data, error } = await supabaseAdmin
    .from("user_profiles")
    .update({
      full_name: fullName,
    })
    .eq("user_id", userId)
    .select("user_id, full_name, role, account_status")
    .maybeSingle();

    if (error) {
      throw new Error("Unable to update user profile.");
    }

    if (!data) {
      return null;
    }

    const role = data.role;
    const accountStatus = data.account_status;

    this.validateRoleAndAccountStatus(role, accountStatus);

    return {
      userId: data.user_id,
      fullName: data.full_name,
      role: data.role,
      accountStatus: data.account_status,
    };
  }
}

