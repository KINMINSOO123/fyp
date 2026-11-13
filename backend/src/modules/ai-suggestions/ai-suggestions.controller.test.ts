import assert from "node:assert/strict";
import type { Server } from "node:http";
import { test } from "node:test";
import express from "express";
import { createAuthenticate } from "../../middleware/authenticate.js";
import { errorHandler } from "../../middleware/errorHandler.js";
import { requireRole } from "../../middleware/requireRole.js";
import { AppError } from "../../shared/AppError.js";
import { AiSuggestionsController } from "./ai-suggestions.controller.js";

test("AI suggestions require an active administrator", async () => {
  let calls = 0;
  const controller = new AiSuggestionsController({ async generate() {
    calls++;
    return { suggestions: [] };
  } }, { async catalogue() { return { ingredients: [], categories: [] }; },
    async create() { calls++; return { categoryId: "new" }; } });
  const app = express();
  app.use(express.json());
  app.use(createAuthenticate({ async authenticate(token) {
    if (token === "inactive") throw new AppError(401,
      "INACTIVE_ACCOUNT", "Account inactive.");
    if (token !== "manager" && token !== "admin") throw new AppError(401,
      "INVALID_TOKEN", "Invalid token.");
    return { userId: token, fullName: "Test",
      role: token === "admin" ? "SYSTEM_ADMINISTRATOR" as const :
        "BAKERY_MANAGER" as const, accountStatus: "ACTIVE" as const };
  } }), requireRole("SYSTEM_ADMINISTRATOR"));
  app.post("/api/admin/ai-suggestions", controller.generate);
  app.post("/api/admin/ai-suggestions/reviewed", controller.createReviewed);
  app.use(errorHandler);
  const server = await new Promise<Server>((resolve) => {
    const listening = app.listen(0, "127.0.0.1", () => resolve(listening));
  });
  try {
    const address = server.address();
    if (!address || typeof address === "string") throw new Error("No test port.");
    const url = `http://127.0.0.1:${address.port}/api/admin/ai-suggestions`;
    for (const token of [null, "manager", "inactive"] as const) {
      const response = await fetch(url, { method: "POST", headers: token ?
        { Authorization: `Bearer ${token}` } : {} });
      assert.equal(response.status, token === "manager" ? 403 : 401);
      const reviewed = await fetch(`${url}/reviewed`, { method: "POST",
        headers: token ? { Authorization: `Bearer ${token}` } : {} });
      assert.equal(reviewed.status, token === "manager" ? 403 : 401);
    }
    assert.equal(calls, 0);
    const allowed = await fetch(url, { method: "POST",
      headers: { Authorization: "Bearer admin" } });
    assert.equal(allowed.status, 200);
    assert.equal(calls, 1);
    const reviewed = await fetch(`${url}/reviewed`, { method: "POST",
      headers: { Authorization: "Bearer admin" } });
    assert.equal(reviewed.status, 201);
    assert.equal(calls, 2);
  } finally {
    await new Promise<void>((resolve, reject) => server.close((error) =>
      error ? reject(error) : resolve()));
  }
});
