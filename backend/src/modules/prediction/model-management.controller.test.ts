import assert from "node:assert/strict";
import type { Server } from "node:http";
import { test } from "node:test";
import express from "express";
import { createAuthenticate } from "../../middleware/authenticate.js";
import { errorHandler } from "../../middleware/errorHandler.js";
import { requireRole } from "../../middleware/requireRole.js";
import { AppError } from "../../shared/AppError.js";
import { ModelManagementController } from "./model-management.controller.js";

test("T-DP-ADMIN-05 [BR-UAM-02, FR-DP-06, FR-DP-12]: only an authenticated administrator reaches model actions", async () => {
  let trainActor = "";
  let evaluateActor = "";
  let activationActor = "";
  let restorationActor = "";
  let listed = false;
  let categoriesRead = false;
  const controller = new ModelManagementController({
    async listTrainingCategories() {
      categoriesRead = true;
      return [{ id: "category-id", name: "Wholemeal Bread", displayOrder: 1 }];
    },
    async listModels() {
      listed = true;
      return { items: [], page: 1, pageSize: 20, total: 0 };
    },
    async getModelDetails() {
      return { id: "model-id" } as never;
    },
    async trainCandidates(actorId) {
      trainActor = actorId;
      return { candidates: [] } as never;
    },
    async evaluateCandidate(actorId) {
      evaluateActor = actorId;
      return { results: [] } as never;
    },
    async activateCandidate(actorId) {
      activationActor = actorId;
      return { lifecycleStatus: "ACTIVE" } as never;
    },
    async restorePreviousModel(actorId) {
      restorationActor = actorId;
      return { lifecycleStatus: "ACTIVE" } as never;
    },
  });
  const app = express();
  app.use(express.json());
  const authenticate = createAuthenticate({
    async authenticate(token) {
      if (token !== "manager" && token !== "administrator") {
        throw new AppError(401, "INVALID_TOKEN", "Invalid token.");
      }
      return {
        userId: token === "administrator" ? "admin-id" : "manager-id",
        fullName: "Test user",
        role: token === "administrator" ? "SYSTEM_ADMINISTRATOR" : "BAKERY_MANAGER",
        accountStatus: "ACTIVE",
      };
    },
  });
  app.post("/api/admin/models/train", authenticate,
    requireRole("SYSTEM_ADMINISTRATOR"), controller.train);
  app.post("/api/admin/models/:modelVersionId/evaluate", authenticate,
    requireRole("SYSTEM_ADMINISTRATOR"), controller.evaluate);
  app.post("/api/admin/models/:modelVersionId/activate", authenticate,
    requireRole("SYSTEM_ADMINISTRATOR"), controller.activate);
  app.post("/api/admin/models/:modelVersionId/restore", authenticate,
    requireRole("SYSTEM_ADMINISTRATOR"), controller.restore);
  app.get("/api/admin/models", authenticate,
    requireRole("SYSTEM_ADMINISTRATOR"), controller.list);
  app.get("/api/admin/models/categories", authenticate,
    requireRole("SYSTEM_ADMINISTRATOR"), controller.categories);
  app.get("/api/admin/models/:modelVersionId", authenticate,
    requireRole("SYSTEM_ADMINISTRATOR"), controller.detail);
  app.use(errorHandler);
  const server = await new Promise<Server>((resolve) => {
    const listening = app.listen(0, "127.0.0.1", () => resolve(listening));
  });
  try {
    const address = server.address();
    if (!address || typeof address === "string") throw new Error("No test port.");
    const base = `http://127.0.0.1:${address.port}/api/admin/models`;
    const deniedList = await fetch(base, {
      headers: { Authorization: "Bearer manager" },
    });
    assert.equal(deniedList.status, 403);
    assert.equal(listed, false);
    const allowedList = await fetch(base, {
      headers: { Authorization: "Bearer administrator" },
    });
    assert.equal(allowedList.status, 200);
    assert.equal(listed, true);
    const deniedCategories = await fetch(`${base}/categories`, {
      headers: { Authorization: "Bearer manager" },
    });
    assert.equal(deniedCategories.status, 403);
    assert.equal(categoriesRead, false);
    const allowedCategories = await fetch(`${base}/categories`, {
      headers: { Authorization: "Bearer administrator" },
    });
    assert.equal(allowedCategories.status, 200);
    assert.equal((await allowedCategories.json()).data[0].name, "Wholemeal Bread");
    const allowedDetail = await fetch(`${base}/model-id`, {
      headers: { Authorization: "Bearer administrator" },
    });
    assert.equal(allowedDetail.status, 200);
    for (const [token, expected] of [[null, 401], ["manager", 403]] as const) {
      const denied = await fetch(`${base}/train`, {
        method: "POST",
        headers: token ? { Authorization: `Bearer ${token}` } : {},
      });
      assert.equal(denied.status, expected);
    }
    assert.equal(trainActor, "");
    const trained = await fetch(`${base}/train`, {
      method: "POST",
      headers: { Authorization: "Bearer administrator", "Content-Type": "application/json" },
      body: JSON.stringify({ breadCategoryId: "category-id" }),
    });
    assert.equal(trained.status, 201);
    assert.equal(trainActor, "admin-id");

    const rejectedBody = await fetch(`${base}/candidate-id/evaluate`, {
      method: "POST",
      headers: { Authorization: "Bearer administrator", "Content-Type": "application/json" },
      body: JSON.stringify({ role: "SYSTEM_ADMINISTRATOR" }),
    });
    assert.equal(rejectedBody.status, 400);
    assert.equal((await rejectedBody.json()).error.code, "VALIDATION_ERROR");
    assert.equal(evaluateActor, "");
    const evaluated = await fetch(`${base}/candidate-id/evaluate`, {
      method: "POST", headers: { Authorization: "Bearer administrator" },
    });
    assert.equal(evaluated.status, 201);
    assert.equal(evaluateActor, "admin-id");

    const managerActivation = await fetch(`${base}/candidate-id/activate`, {
      method: "POST", headers: { Authorization: "Bearer manager" },
    });
    assert.equal(managerActivation.status, 403);
    assert.equal(activationActor, "");
    const adminActivation = await fetch(`${base}/candidate-id/activate`, {
      method: "POST", headers: { Authorization: "Bearer administrator",
        "Content-Type": "application/json" },
      body: JSON.stringify({ confirm: true, evaluationId: "evaluation-id" }),
    });
    assert.equal(adminActivation.status, 200);
    assert.equal(activationActor, "admin-id");

    const managerRestoration = await fetch(`${base}/previous-id/restore`, {
      method: "POST", headers: { Authorization: "Bearer manager" },
    });
    assert.equal(managerRestoration.status, 403);
    assert.equal(restorationActor, "");
    const adminRestoration = await fetch(`${base}/previous-id/restore`, {
      method: "POST", headers: { Authorization: "Bearer administrator",
        "Content-Type": "application/json" },
      body: JSON.stringify({ confirm: true }),
    });
    assert.equal(adminRestoration.status, 200);
    assert.equal(restorationActor, "admin-id");
  } finally {
    await new Promise<void>((resolve, reject) =>
      server.close((error) => error ? reject(error) : resolve()));
  }
});
