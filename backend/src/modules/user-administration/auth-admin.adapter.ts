import { supabaseAdmin } from "../../config/supabase.js";
import type { AuthAccount } from "./user-administration.model.js";
import { AppError } from "../../shared/AppError.js";

export class AuthAdminAdapter {
  async listAccounts(page: number, pageSize: number): Promise<{ accounts: AuthAccount[]; total: number }> {
    const { data, error } = await supabaseAdmin.auth.admin.listUsers({
      page,
      perPage: pageSize,
    });

    if (error) {
      throw new Error("Unable to load authentication accounts.");
    }

    return {
      accounts: data.users.map((user) => ({
        userId: user.id,
        email: user.email ?? null,
        createdAt: user.created_at,
      })),
      total: data.total,
    }
  }

  async createAccount(email: string, password: string): Promise<AuthAccount> {
    const { data, error } = await supabaseAdmin.auth.admin.createUser({
      email,
      password,
      email_confirm: true,
    });

    if (error) {
      if (error.code === "email_exists" || error.status === 422) {
        throw new AppError(409, "EMAIL_ALREADY_EXISTS", "An account with this email already exists.");
      }

      throw new AppError(
        502,
        "AUTH_ACCOUNT_CREATION_FAILED",
        "The authentication account could not be created.",
      );
    }

    return {
      userId: data.user.id,
      email: data.user.email ?? null,
      createdAt: data.user.created_at,
    };
  }

  async deleteAccount(userId: string): Promise<void> {
    const { error } = await supabaseAdmin.auth.admin.deleteUser(userId);

    if (error) {
      throw new Error(
        "Unable to remove the incomplete authentication account.",
      )
    }
  }
}