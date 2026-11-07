import assert from "node:assert/strict";
import { test } from "node:test";
import { AppError } from "../../shared/AppError.js";
import type { UserProfile } from "../profile/profile.model.js";
import type { AuthAdminAdapter } from "./auth-admin.adapter.js";
import { mapAdminUpdateError } from "./admin-update-error.js";
import type { UserAdministrationRepo } from "./user-administration.repo.js";
import { UserAdministrationService } from "./user-administration.service.js";

const actorId = "00000000-0000-4000-8000-000000000001";
const targetId = "00000000-0000-4000-8000-000000000002";
const account = {
  userId: targetId,
  email: "new.manager@example.com",
  createdAt: "2026-11-04T00:00:00Z",
};
const profile: UserProfile = {
  userId: targetId,
  fullName: "New Manager",
  role: "BAKERY_MANAGER",
  accountStatus: "ACTIVE",
};

function testDependencies(): {
  adapter: Pick<AuthAdminAdapter, "listAccounts" | "createAccount" | "deleteAccount">;
  repo: Pick<UserAdministrationRepo,
    "findProfilesByUserIds" | "createProfileWithAudit" | "updateProfileWithAudit">;
} {
  return {
    adapter: {
      async listAccounts() { return { accounts: [account], total: 1 }; },
      async createAccount(_email: string, _password: string) { return account; },
      async deleteAccount(_userId: string) {},
    },
    repo: {
      async findProfilesByUserIds() { return new Map([[targetId, profile]]); },
      async createProfileWithAudit() { return profile; },
      async updateProfileWithAudit() { return profile; },
    },
  };
}

test("T-UAM-AUTO-10 [FR-UAM-05]: account listing joins the stored profile", async () => {
  const { adapter, repo } = testDependencies();
  const service = new UserAdministrationService(adapter, repo);
  const page = await service.listUsers({ page: "1", pageSize: "20" });
  assert.equal(page.total, 1);
  assert.equal(page.users[0]?.profileStatus, "COMPLETE");
  assert.equal(page.users[0]?.role, "BAKERY_MANAGER");
});

test("T-UAM-AUTO-11 [FR-UAM-05, NFR-DAT-03]: create passes actor to audited profile RPC and omits password", async () => {
  const { adapter, repo } = testDependencies();
  let observedActor: string | undefined;
  let observedRole: string | undefined;
  repo.createProfileWithAudit = async (actor, _id, _name, role) => {
    observedActor = actor;
    observedRole = role;
    return profile;
  };
  const service = new UserAdministrationService(adapter, repo);
  const created = await service.createUser(actorId, {
    email: "new.manager@example.com",
    password: "Temporary123!",
    fullName: "New Manager",
    role: "BAKERY_MANAGER",
  });
  assert.equal(observedActor, actorId);
  assert.equal(observedRole, "BAKERY_MANAGER");
  assert.equal(created.profileStatus, "COMPLETE");
  assert.equal("password" in created, false);
});

test("T-UAM-AUTO-12 [FR-UAM-05, NFR-REL-01]: failed profile creation removes incomplete Auth account", async () => {
  const { adapter, repo } = testDependencies();
  let deletedId: string | undefined;
  repo.createProfileWithAudit = async () => { throw new Error("RPC failure"); };
  repo.findProfilesByUserIds = async () => new Map();
  adapter.deleteAccount = async (id) => { deletedId = id; };
  const service = new UserAdministrationService(adapter, repo);

  await assert.rejects(
    service.createUser(actorId, {
      email: account.email,
      password: "Temporary123!",
      fullName: profile.fullName,
      role: profile.role,
    }),
    (error: unknown) => {
      assert.ok(error instanceof AppError);
      assert.equal(error.code, "ACCOUNT_CREATION_FAILED");
      return true;
    },
  );
  assert.equal(deletedId, targetId);
});

test("T-UAM-AUTO-13 [FR-UAM-05, NFR-REL-01]: committed profile is retained after response failure", async () => {
  const { adapter, repo } = testDependencies();
  let deletionAttempted = false;
  repo.createProfileWithAudit = async () => { throw new Error("response mapping failure"); };
  adapter.deleteAccount = async () => { deletionAttempted = true; };
  const service = new UserAdministrationService(adapter, repo);
  const created = await service.createUser(actorId, {
    email: account.email,
    password: "Temporary123!",
    fullName: profile.fullName,
    role: profile.role,
  });
  assert.equal(created.profileStatus, "COMPLETE");
  assert.equal(deletionAttempted, false);
});

test("T-UAM-AUTO-14 [FR-UAM-05]: administrator update delegates only validated fields and actor", async () => {
  const { adapter, repo } = testDependencies();
  let args: unknown[] = [];
  repo.updateProfileWithAudit = async (...values) => {
    args = values;
    return { ...profile, accountStatus: "INACTIVE" };
  };
  const service = new UserAdministrationService(adapter, repo);
  const updated = await service.updateUser(actorId, targetId, {
    accountStatus: "INACTIVE",
  });
  assert.deepEqual(args, [actorId, targetId, null, null, "INACTIVE"]);
  assert.equal(updated.accountStatus, "INACTIVE");

  await assert.rejects(
    service.updateUser(actorId, targetId, { actorUserId: targetId }),
    (error: unknown) => {
      assert.ok(error instanceof AppError);
      assert.equal(error.code, "VALIDATION_ERROR");
      return true;
    },
  );
});

test("T-UAM-AUTO-15 [BR-UAM-03, FR-UAM-05]: final-admin SQL rejection maps to HTTP 409", () => {
  const error = mapAdminUpdateError({
    code: "P0001",
    message: "The final active System Administrator must be preserved.",
  });
  assert.ok(error instanceof AppError);
  assert.equal(error.statusCode, 409);
  assert.equal(error.code, "FINAL_ACTIVE_ADMIN_REQUIRED");
});
