import assert from "node:assert/strict";
import { test } from "node:test";
import { AppError } from "../../shared/AppError.js";
import type { UserProfile } from "../profile/profile.model.js";
import { AuthService } from "./auth.service.js";

const userId = "00000000-0000-4000-8000-000000000001";
const activeProfile: UserProfile = {
  userId,
  fullName: "Test Manager",
  role: "BAKERY_MANAGER",
  accountStatus: "ACTIVE",
};

function verifier(status?: number, user: { id: string } | null = { id: userId }) {
  return {
    async getUser(_token: string) {
      return {
        data: { user: status === undefined ? user : null },
        error: status === undefined ? null : { status },
      };
    },
  };
}

function reader(profile: UserProfile | null) {
  return { async findByUserId(_id: string) { return profile; } };
}

function hasCode(statusCode: number, code: string) {
  return (error: unknown) => {
    assert.ok(error instanceof AppError);
    assert.equal(error.statusCode, statusCode);
    assert.equal(error.code, code);
    return true;
  };
}

test("T-UAM-AUTO-01 [FR-UAM-01, NFR-SEC-01]: verified token and active profile authenticate", async () => {
  const service = new AuthService(verifier(), reader(activeProfile));
  assert.deepEqual(await service.authenticate("valid-token"), activeProfile);
});

test("T-UAM-AUTO-02 [BR-UAM-01, NFR-SEC-01]: empty and invalid tokens are rejected", async () => {
  const service = new AuthService(verifier(401), reader(activeProfile));
  await assert.rejects(service.authenticate("  "), hasCode(401, "UNAUTHENTICATED"));
  await assert.rejects(service.authenticate("expired-token"), hasCode(401, "INVALID_TOKEN"));
});

test("T-UAM-AUTO-03 [BR-UAM-01, NFR-SEC-01]: missing or inactive profile is rejected", async () => {
  await assert.rejects(
    new AuthService(verifier(), reader(null)).authenticate("token"),
    hasCode(403, "PROFILE_REQUIRED"),
  );
  await assert.rejects(
    new AuthService(verifier(), reader({
      ...activeProfile,
      accountStatus: "INACTIVE",
    })).authenticate("token"),
    hasCode(403, "ACCOUNT_INACTIVE"),
  );
});

test("T-UAM-AUTO-04 [FR-UAM-01]: unavailable auth provider reports retryable failure", async () => {
  const service = new AuthService(verifier(503), reader(activeProfile));
  await assert.rejects(service.authenticate("token"), hasCode(503, "AUTH_UNAVAILABLE"));
});
