import assert from "node:assert/strict";
import { test } from "node:test";
import { AppError } from "../../shared/AppError.js";
import type { UserProfile } from "./profile.model.js";
import { ProfileService } from "./profile.service.js";

const profile: UserProfile = {
  userId: "00000000-0000-4000-8000-000000000001",
  fullName: "Original Name",
  role: "BAKERY_MANAGER",
  accountStatus: "ACTIVE",
};

test("T-UAM-AUTO-05 [FR-UAM-03]: own name update uses authenticated user id", async () => {
  let updatedId: string | undefined;
  let updatedName: string | undefined;
  const service = new ProfileService({
    async updateFullName(userId, fullName) {
      updatedId = userId;
      updatedName = fullName;
      return { ...profile, fullName };
    },
  });

  const result = await service.updateOwnProfile(profile.userId, { fullName: " New Name " });
  assert.equal(updatedId, profile.userId);
  assert.equal(updatedName, "New Name");
  assert.equal(result.fullName, "New Name");
  assert.equal(result.role, "BAKERY_MANAGER");
});

test("T-UAM-AUTO-06 [FR-UAM-04, NFR-SEC-02]: own role and status injection never reaches repo", async () => {
  let repoCalls = 0;
  const service = new ProfileService({
    async updateFullName() {
      repoCalls += 1;
      return profile;
    },
  });

  for (const input of [
    { fullName: "New", role: "SYSTEM_ADMINISTRATOR" },
    { fullName: "New", accountStatus: "ACTIVE" },
    { fullName: "New", userId: "another-user" },
  ]) {
    await assert.rejects(
      service.updateOwnProfile(profile.userId, input),
      (error: unknown) => {
        assert.ok(error instanceof AppError);
        assert.equal(error.statusCode, 400);
        assert.equal(error.code, "PROFILE_FIELD_NOT_EDITABLE");
        return true;
      },
    );
  }
  assert.equal(repoCalls, 0);
});

test("T-UAM-AUTO-07 [FR-UAM-03, NFR-DAT-01]: missing and blank names are rejected", async () => {
  const service = new ProfileService({
    async updateFullName() {
      throw new Error("Repository must not be called.");
    },
  });
  for (const input of [{}, { fullName: "   " }]) {
    await assert.rejects(
      service.updateOwnProfile(profile.userId, input),
      (error: unknown) => {
        assert.ok(error instanceof AppError);
        assert.equal(error.code, "VALIDATION_ERROR");
        return true;
      },
    );
  }
});
