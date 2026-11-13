import assert from "node:assert/strict";
import type { Server } from "node:http";
import { test } from "node:test";
import express from "express";
import { createAuthenticate } from "../../middleware/authenticate.js";
import { errorHandler } from "../../middleware/errorHandler.js";
import { AppError } from "../../shared/AppError.js";
import { InventoryAdminController } from "./inventory-admin.controller.js";
import { createInventoryRouter } from "./inventory-admin.routes.js";

test("inventory reads allow both roles; definitions are admin-only and batches manager-only", async () => {
  let reads = 0;
  let definitionActor = "";
  let batchActor = "";
  const controller = new InventoryAdminController({
    async listCategories() { reads++; return []; },
    async listIngredients() { return []; },
    async listRecipes() { return []; },
    async listBatches() { return { items: [], page: 1, pageSize: 50, total: 0 }; },
    async saveCategory(actorId) { definitionActor = actorId; return { id: "category" }; },
    async saveIngredient() { return {}; },
    async replaceRecipe() { return {}; },
    async receiveBatch(actorId) { batchActor = actorId; return {}; },
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
  } }));
  app.use(createInventoryRouter(controller));
  app.use(errorHandler);
  const server = await new Promise<Server>((resolve) => {
    const listening = app.listen(0, "127.0.0.1", () => resolve(listening));
  });
  try {
    const address = server.address();
    if (!address || typeof address === "string") throw new Error("No test port.");
    const base = `http://127.0.0.1:${address.port}`;
    for (const token of [null, "inactive"] as const) {
      const headers: Record<string, string> = token ?
        { Authorization: `Bearer ${token}` } : {};
      const read = await fetch(`${base}/categories`, { headers });
      assert.equal(read.status, 401);
      const write = await fetch(`${base}/categories`, { method: "POST", headers });
      assert.equal(write.status, 401);
    }
    assert.equal(reads, 0);
    for (const token of ["admin", "manager"]) {
      const read = await fetch(`${base}/categories`, {
        headers: { Authorization: `Bearer ${token}` },
      });
      assert.equal(read.status, 200);
      const stock = await fetch(`${base}/batches`, {
        headers: { Authorization: `Bearer ${token}` },
      });
      assert.equal(stock.status, 200);
    }
    assert.equal(reads, 2);
    const deniedDefinition = await fetch(`${base}/ingredients`, {
      method: "POST", headers: { Authorization: "Bearer manager" },
    });
    assert.equal(deniedDefinition.status, 403);
    const deniedBatch = await fetch(`${base}/batches`, {
      method: "POST", headers: { Authorization: "Bearer admin" },
    });
    assert.equal(deniedBatch.status, 403);
    const deniedAdjustment = await fetch(`${base}/batches/id/stock`, {
      method: "PATCH", headers: { Authorization: "Bearer admin" },
    });
    assert.equal(deniedAdjustment.status, 403);
    const write = await fetch(`${base}/categories`, {
      method: "POST", headers: { Authorization: "Bearer admin",
        "Content-Type": "application/json" }, body: "{}",
    });
    assert.equal(write.status, 201);
    assert.equal(definitionActor, "admin");
    const receipt = await fetch(`${base}/batches`, { method: "POST",
      headers: { Authorization: "Bearer manager" } });
    assert.equal(receipt.status, 201);
    assert.equal(batchActor, "manager");
  } finally {
    await new Promise<void>((resolve, reject) => server.close((error) =>
      error ? reject(error) : resolve()));
  }
});
