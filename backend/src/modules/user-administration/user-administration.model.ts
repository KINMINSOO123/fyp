import type { AccountStatus, UserRole } from "../profile/profile.model.js";

export interface AuthAccount {
  userId: string;
  email: string | null;
  createdAt: string;
}

export interface AdminUserListItem extends AuthAccount {
  fullName: string | null;
  role: UserRole | null;
  accountStatus: AccountStatus | null;
  profileStatus: "COMPLETE" | "MISSING";
}

export interface AdminUserListPage {
  users: AdminUserListItem[];
  page: number;
  pageSize: number;
  total: number;
}