import assert from "node:assert/strict";
import type { Server } from "node:http";
import { test } from "node:test";
import express from "express";
import type { UserProfile } from "../modules/profile/profile.model.js";
import { AppError } from "../shared/AppError.js";
import { createAuthenticate } from "./authenticate.js";
import { errorHandler } from "./errorHandler.js";
import { requireRole } from "./requireRole.js";

const manager: UserProfile = {
  userId: "00000000-0000-4000-8000-000000000001",
  fullName: "Manager",
  role: "BAKERY_MANAGER",
  accountStatus: "ACTIVE",
};
const administrator: UserProfile = {
  ...manager,
  userId: "00000000-0000-4000-8000-000000000002",
  role: "SYSTEM_ADMINISTRATOR",
};

async function withAccessServer(
  run: (baseUrl: string) => Promise<void>,
): Promise<void> {
  const app = express();
  app.use(express.json());
  const authenticate = createAuthenticate({
    async authenticate(token: string) {
      if (token === "manager") return manager;
      if (token === "administrator") return administrator;
      throw new AppError(401, "INVALID_TOKEN", "Invalid token.");
    },
  });
  app.get("/manager", authenticate, requireRole("BAKERY_MANAGER"), (_req, res) => {
    res.json({ allowed: true });
  });
  app.get("/administrator", authenticate, requireRole("SYSTEM_ADMINISTRATOR"),
    (_req, res) => { res.json({ allowed: true }); });
  app.patch("/profile", authenticate, (_req, res) => {
    res.json({ allowed: true });
  });
  app.use(errorHandler);

  const server = await new Promise<Server>((resolve) => {
    const listening = app.listen(0, "127.0.0.1", () => resolve(listening));
  });
  try {
    const address = server.address();
    if (!address || typeof address === "string") {
      throw new Error("Test server did not receive a TCP port.");
    }
    await run(`http://127.0.0.1:${address.port}`);
  } finally {
    await new Promise<void>((resolve, reject) => {
      server.close((error) => error ? reject(error) : resolve());
    });
  }
}

test("T-UAM-AUTO-08 [BR-UAM-01, NFR-SEC-01]: protected route rejects missing and invalid token", async () => {
  await withAccessServer(async (baseUrl) => {
    const missing = await fetch(`${baseUrl}/administrator`);
    assert.equal(missing.status, 401);
    assert.equal((await missing.json()).error.code, "UNAUTHENTICATED");

    const invalid = await fetch(`${baseUrl}/administrator`, {
      headers: { Authorization: "Bearer invalid" },
    });
    assert.equal(invalid.status, 401);
    assert.equal((await invalid.json()).error.code, "INVALID_TOKEN");
  });
});

test("T-UAM-AUTO-09 [BR-UAM-02, FR-UAM-04, NFR-SEC-02]: roles do not inherit each other's actions", async () => {
  await withAccessServer(async (baseUrl) => {
    for (const [path, token] of [
      ["/administrator", "manager"],
      ["/manager", "administrator"],
    ]) {
      const denied = await fetch(`${baseUrl}${path}`, {
        headers: { Authorization: `Bearer ${token}` },
      });
      assert.equal(denied.status, 403);
      assert.equal((await denied.json()).error.code, "FORBIDDEN");
    }

    const allowed = await fetch(`${baseUrl}/administrator`, {
      headers: { Authorization: "Bearer administrator" },
    });
    assert.equal(allowed.status, 200);
  });
});

test("T-UAM-AUTO-16 [FR-UAM-03, NFR-DAT-01]: malformed JSON is a request error", async () => {
  await withAccessServer(async (baseUrl) => {
    const response = await fetch(`${baseUrl}/profile`, {
      method: "PATCH",
      headers: {
        Authorization: "Bearer manager",
        "Content-Type": "application/json",
      },
      body: '{"fullName":"Broken",',
    });
    assert.equal(response.status, 400);
    assert.equal((await response.json()).error.code, "INVALID_JSON");
  });
});
