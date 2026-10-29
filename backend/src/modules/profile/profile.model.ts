export type UserRole =
  | "BAKERY_MANAGER"
  | "SYSTEM_ADMINISTRATOR";

export type AccountStatus = "ACTIVE" | "INACTIVE";

export interface UserProfile {
  userId: string;
  fullName: string;
  role: UserRole;
  accountStatus: AccountStatus;
}