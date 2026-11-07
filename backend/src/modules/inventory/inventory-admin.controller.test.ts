import assert from "node:assert/strict";
import type { Server } from "node:http";
import { test } from "node:test";
import express from "express";
import { createAuthenticate } from "../../middleware/authenticate.js";
import { errorHandler } from "../../middleware/errorHandler.js";
import { requireRole } from "../../middleware/requireRole.js";
import { AppError } from "../../shared/AppError.js";
import { InventoryAdminController } from "./inventory-admin.controller.js";

test("T-INV-AUTO-12 [FR-INV-01, BR-UAM-02]: only active administrators can read and change inventory", async () => {
  let reads = 0;
  let actor = "";
  const controller = new InventoryAdminController({
    async listCategories() { reads++; return []; },
    async listIngredients() { return []; },
    async listRecipes() { return []; },
    async listBatches() { return { items: [], page: 1, pageSize: 50, total: 0 }; },
    async saveCategory(actorId) { actor = actorId; return { id: "category" }; },
    async saveIngredient() { return {}; },
    async replaceRecipe() { return {}; },
    async receiveBatch() { return {}; },
    async adjustBatch() { return {}; },
  });
  const app = express();
  app.use(express.json());
  app.use(createAuthenticate({ async authenticate(token) {
    if (!["admin", "manager", "inactive"].includes(token)) {
      throw new AppError(401, "INVALID_TOKEN", "Invalid token.");
    }
    if (token === "inactive") {
      throw new AppError(401, "INACTIVE_ACCOUNT", "This account is inactive.");
    }
    return { userId: token, fullName: "Test",
      role: token === "manager" ? "BAKERY_MANAGER" as const : "SYSTEM_ADMINISTRATOR" as const,
      accountStatus: "ACTIVE" as const };
  } }), requireRole("SYSTEM_ADMINISTRATOR"));
  app.get("/categories", controller.listCategories);
  app.post("/categories", controller.createCategory);
  app.use(errorHandler);
  const server = await new Promise<Server>((resolve) => {
    const listening = app.listen(0, "127.0.0.1", () => resolve(listening));
  });
  try {
    const address = server.address();
    if (!address || typeof address === "string") throw new Error("No test port.");
    const base = `http://127.0.0.1:${address.port}`;
    for (const token of [null, "manager", "inactive"] as const) {
      const headers: Record<string, string> = token ?
        { Authorization: `Bearer ${token}` } : {};
      const read = await fetch(`${base}/categories`, { headers });
      assert.equal(read.status, token === "manager" ? 403 : 401);
      const write = await fetch(`${base}/categories`, { method: "POST", headers });
      assert.equal(write.status, token === "manager" ? 403 : 401);
    }
    assert.equal(reads, 0);
    const success = await fetch(`${base}/categories`, {
      headers: { Authorization: "Bearer admin" },
    });
    assert.equal(success.status, 200);
    assert.equal(reads, 1);
    const write = await fetch(`${base}/categories`, {
      method: "POST", headers: { Authorization: "Bearer admin",
        "Content-Type": "application/json" }, body: "{}",
    });
    assert.equal(write.status, 201);
    assert.equal(actor, "admin");
  } finally {
    await new Promise<void>((resolve, reject) => server.close((error) =>
      error ? reject(error) : resolve()));
  }
});
