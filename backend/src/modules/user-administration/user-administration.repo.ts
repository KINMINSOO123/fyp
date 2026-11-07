import { supabaseAdmin } from "../../config/supabase.js";
import type { AccountStatus, UserProfile, UserRole } from "../profile/profile.model.js";
import { mapAdminUpdateError } from "./admin-update-error.js";

export class UserAdministrationRepo {
  async findProfilesByUserIds(
    userIds: string[],
  ): Promise<Map<string, UserProfile>> {
    if (userIds.length === 0) {
      return new Map();
    }

    const { data, error } = await supabaseAdmin
      .from("user_profiles")
      .select("user_id, full_name, role, account_status")
      .in("user_id", userIds);

    if (error) {
      throw new Error("Unable to load user profiles.");
    }

    const profiles = new Map<string, UserProfile>();

    for (const row of data) {
      if (
        row.role !== "BAKERY_MANAGER" &&
        row.role !== "SYSTEM_ADMINISTRATOR"
      ) {
        throw new Error("Invalid stored user role.");
      }

      if (
        row.account_status !== "ACTIVE" &&
        row.account_status !== "INACTIVE"
      ) {
        throw new Error("Invalid stored account status.");
      }

      profiles.set(row.user_id, {
        userId: row.user_id,
        fullName: row.full_name,
        role: row.role,
        accountStatus: row.account_status,
      });
    }

    return profiles;
  }

  async createProfileWithAudit(
    actorUserId: string,
    userId: string,
    fullName: string,
    role: UserRole,
    accountStatus: AccountStatus,
  ): Promise<UserProfile> {
    const { data, error } = await supabaseAdmin
      .rpc("create_user_profile_with_audit", {
        p_actor_user_id: actorUserId,
        p_user_id: userId,
        p_full_name: fullName,
        p_role: role,
        p_account_status: accountStatus,
      })
      .single();

    if (error || !data) {
      throw new Error(
        "Unable to create the user profile and audit record.",
      );
    }

    const row = data as {
      user_id: string;
      full_name: string;
      role: unknown;
      account_status: unknown;
    }

    if (
      row.role !== "BAKERY_MANAGER" &&
      row.role !== "SYSTEM_ADMINISTRATOR"
    ) {
      throw new Error("Invalid stored user role.");
    }

    if (
      row.account_status !== "ACTIVE" &&
      row.account_status !== "INACTIVE"
    ) {
      throw new Error("Invalid stored account status.");
    }

    return {
      userId: row.user_id,
      fullName: row.full_name,
      role: row.role as UserRole,
      accountStatus: row.account_status as AccountStatus, 
    };
  }

  async updateProfileWithAudit(
    actorUserId: string,
    targetUserId: string,
    fullName: string | null,
    role: UserRole | null,
    accountStatus: AccountStatus | null,
  ): Promise<UserProfile> {
    const { data, error } = await supabaseAdmin
      .rpc("update_user_profile_admin_with_audit", {
        p_actor_user_id: actorUserId,
        p_target_user_id: targetUserId,
        p_full_name: fullName,
        p_role: role,
        p_account_status: accountStatus,
      })
      .single();

    if (error) {
      throw mapAdminUpdateError(error);
    }

    if (!data) {
      throw new Error("The updated user profile was not returned.");
    }

    const row = data as {
      user_id: string;
      full_name: string;
      role: unknown;
      account_status: unknown;
    };

    if (
      row.role !== "BAKERY_MANAGER" &&
      row.role !== "SYSTEM_ADMINISTRATOR"
    ) {
      throw new Error("Invalid stored user role.");
    }

    if (
      row.account_status !== "ACTIVE" &&
      row.account_status !== "INACTIVE"
    ) {
      throw new Error("Invalid stored account status.");
    }

    return {
      userId: row.user_id,
      fullName: row.full_name,
      role: row.role,
      accountStatus: row.account_status,
    };
  }
}
