import { AppError } from "../../shared/AppError.js";
import type { AuthAdminAdapter } from "./auth-admin.adapter.js";
import type {
  AdminUserListPage, AdminUserListItem
} from "./user-administration.model.js";
import type { UserAdministrationRepo } from "./user-administration.repo.js";
import type {
  AccountStatus,
  UserProfile,
  UserRole,
} from "../profile/profile.model.js";

export class UserAdministrationService {
  constructor(
    private readonly providedAuthAdminAdapter?: Pick<
      AuthAdminAdapter, "listAccounts" | "createAccount" | "deleteAccount"
    >,
    private readonly providedUserRepo?: Pick<
      UserAdministrationRepo,
      "findProfilesByUserIds" | "createProfileWithAudit" | "updateProfileWithAudit"
    >,
  ) {}

  private async authAdminAdapter() {
    return this.providedAuthAdminAdapter ?? new (
      await import("./auth-admin.adapter.js")
    ).AuthAdminAdapter();
  }

  private async userRepo() {
    return this.providedUserRepo ?? new (
      await import("./user-administration.repo.js")
    ).UserAdministrationRepo();
  }

  async listUsers(query: {
    page?: unknown;
    pageSize?: unknown;
  }): Promise<AdminUserListPage> {
    const page = this.parsePositiveInteger(
      query.page,
      1,
      "page",
      Number.MAX_SAFE_INTEGER,
    );

    const pageSize = this.parsePositiveInteger(
      query.pageSize,
      20,
      "pageSize",
      50,
    );

    const authAdminAdapter = await this.authAdminAdapter();
    const userRepo = await this.userRepo();
    const { accounts, total } =
      await authAdminAdapter.listAccounts(page, pageSize);

    const profiles = await userRepo.findProfilesByUserIds(
      accounts.map((account) => account.userId),
    );

    const users = accounts.map((account) => {
      const profile = profiles.get(account.userId);

      return {
        ...account,
        fullName: profile?.fullName ?? null,
        role: profile?.role ?? null,
        accountStatus: profile?.accountStatus ?? null,
        profileStatus: profile ? "COMPLETE" as const : "MISSING" as const,
      };
    });

    return {
      users,
      page,
      pageSize,
      total,
    };
  }

  private parsePositiveInteger(
    value: unknown,
    defaultValue: number,
    fieldName: string,
    maximum: number,
  ): number {
    if (value === undefined) {
      return defaultValue;
    }

    if (
      typeof value !== "string" ||
      !/^[1-9]\d*$/.test(value)
    ) {
      throw new AppError(
        400,
        "VALIDATION_ERROR",
        `${fieldName} must be a positive whole number.`,
      );
    }

    const parsedValue = Number(value);

    if (
      !Number.isSafeInteger(parsedValue) ||
      parsedValue > maximum
    ) {
      throw new AppError(
        400,
        "VALIDATION_ERROR",
        `${fieldName} exceeds the allowed limit.`,
      );
    }

    return parsedValue;
  }

  async createUser(
    actorUserId: string,
    input: unknown,
  ): Promise<AdminUserListItem> {
    if (
      typeof input !== "object" ||
      input === null ||
      Array.isArray(input)
    ) {
      throw new AppError(
        400,
        "VALIDATION_ERROR",
        "A valid user-account object is required.",
      );
    }

    const body = input as Record<string, unknown>;
    const allowedFields = new Set([
      "email",
      "password",
      "fullName",
      "role",
      "accountStatus",
    ]);

    const unsupportedField = Object.keys(body).find(
      (field) => !allowedFields.has(field),
    );

    if (unsupportedField) {
      throw new AppError(
        400,
        "VALIDATION_ERROR",
        `The field '${unsupportedField}' is not supported.`,
      );
    }

    const email = this.requireText(body.email, "email")
      .toLowerCase();

    const password = this.requireText(
      body.password,
      "password",
      false,
    );

    const fullName = this.requireText(
      body.fullName,
      "fullName",
    );

    if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) {
      throw new AppError(
        400,
        "VALIDATION_ERROR",
        "A valid email address is required.",
      );
    }

    if (password.length < 8) {
      throw new AppError(
        400,
        "VALIDATION_ERROR",
        "The password must contain at least 8 characters.",
      );
    }

    const role = body.role;

    if (
      role !== "BAKERY_MANAGER" &&
      role !== "SYSTEM_ADMINISTRATOR"
    ) {
      throw new AppError(
        400,
        "VALIDATION_ERROR",
        "A valid user role is required.",
      );
    }

    const requestedStatus = body.accountStatus ?? "ACTIVE";

    if (
      requestedStatus !== "ACTIVE" &&
      requestedStatus !== "INACTIVE"
    ) {
      throw new AppError(
        400,
        "VALIDATION_ERROR",
        "A valid account status is required.",
      );
    }

    const authAdminAdapter = await this.authAdminAdapter();
    const userRepo = await this.userRepo();
    const account = await authAdminAdapter.createAccount(
      email,
      password,
    );

    try {
      const profile =
        await userRepo.createProfileWithAudit(
          actorUserId,
          account.userId,
          fullName,
          role as UserRole,
          requestedStatus as AccountStatus,
        );

      return {
        ...account,
        fullName: profile.fullName,
        role: profile.role,
        accountStatus: profile.accountStatus,
        profileStatus: "COMPLETE",
      };
    } catch {
      let existingProfile;

      try {
        const profiles =
          await userRepo.findProfilesByUserIds([
            account.userId,
          ]);

        existingProfile = profiles.get(account.userId);
      } catch {
        throw new AppError(
          500,
          "ACCOUNT_CREATION_REQUIRES_CLEANUP",
          "Account creation status could not be confirmed and requires administrator review.",
        );
      }

      // The RPC committed successfully, but response mapping failed.
      if (existingProfile) {
        return {
          ...account,
          fullName: existingProfile.fullName,
          role: existingProfile.role,
          accountStatus: existingProfile.accountStatus,
          profileStatus: "COMPLETE",
        };
      }

      // No profile exists, so removing the incomplete Auth account is safe.
      try {
        await authAdminAdapter.deleteAccount(
          account.userId,
        );
      } catch {
        throw new AppError(
          500,
          "ACCOUNT_CREATION_REQUIRES_CLEANUP",
          "Account creation was incomplete and requires administrator review.",
        );
      }

      throw new AppError(
        500,
        "ACCOUNT_CREATION_FAILED",
        "The account could not be created.",
      );
    }
  }

  private requireText(
    value: unknown,
    fieldName: string,
    trimValue = true,
  ): string {
    if (typeof value !== "string") {
      throw new AppError(
        400,
        "VALIDATION_ERROR",
        `${fieldName} is required.`,
      );
    }

    const result = trimValue ? value.trim() : value;

    if (!result) {
      throw new AppError(
        400,
        "VALIDATION_ERROR",
        `${fieldName} cannot be empty.`,
      );
    }

    return result;
  }

  async updateUser(
    actorUserId: string,
    targetUserId: string,
    input: unknown,
  ): Promise<UserProfile> {
    if (
      !/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i
        .test(targetUserId)
    ) {
      throw new AppError(
        400,
        "VALIDATION_ERROR",
        "A valid user ID is required.",
      );
    }

    if (
      typeof input !== "object" ||
      input === null ||
      Array.isArray(input)
    ) {
      throw new AppError(
        400,
        "VALIDATION_ERROR",
        "A valid user update object is required.",
      );
    }

    const body = input as Record<string, unknown>;
    const allowedFields = new Set([
      "fullName",
      "role",
      "accountStatus",
    ]);

    const fields = Object.keys(body);

    if (fields.length === 0) {
      throw new AppError(
        400,
        "VALIDATION_ERROR",
        "At least one update field is required.",
      );
    }

    const unsupportedField = fields.find(
      (field) => !allowedFields.has(field),
    );

    if (unsupportedField) {
      throw new AppError(
        400,
        "VALIDATION_ERROR",
        `The field '${unsupportedField}' cannot be changed here.`,
      );
    }

    let fullName: string | null = null;

    if ("fullName" in body) {
      fullName = this.requireText(
        body.fullName,
        "fullName",
      );
    }

    let role: UserRole | null = null;

    if ("role" in body) {
      if (
        body.role !== "BAKERY_MANAGER" &&
        body.role !== "SYSTEM_ADMINISTRATOR"
      ) {
        throw new AppError(
          400,
          "VALIDATION_ERROR",
          "A valid user role is required.",
        );
      }

      role = body.role;
    }

    let accountStatus: AccountStatus | null = null;

    if ("accountStatus" in body) {
      if (
        body.accountStatus !== "ACTIVE" &&
        body.accountStatus !== "INACTIVE"
      ) {
        throw new AppError(
          400,
          "VALIDATION_ERROR",
          "A valid account status is required.",
        );
      }

      accountStatus = body.accountStatus;
    }

    const userRepo = await this.userRepo();
    return userRepo.updateProfileWithAudit(
      actorUserId,
      targetUserId,
      fullName,
      role,
      accountStatus,
    );
  }
}
