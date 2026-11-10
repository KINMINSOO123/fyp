import assert from "node:assert/strict";
import { test } from "node:test";
import { NotificationService } from "./notification.service.js";
import { derivePending } from "./pending-action.service.js";
import { detectInventoryAlerts } from "./inventory-alert.service.js";
import { NotificationEventService } from "./notification-event.service.js";

const userA = "12345678-1234-4123-8123-123456789abc";
const noteId = "12345678-1234-4123-8123-123456789abd";

test("T-ALT-AUTO-01 [FR-ALT-02, FR-ALT-03]: own list, mark-read and preferences use authenticated identity", async () => {
  const calls: string[] = [];
  const service = new NotificationService({
    async preferences(user) {
      calls.push(`prefs:${user}`);
      return [
        { notificationType: "LOW_STOCK", inAppEnabled: true,
          pushEnabled: false },
        { notificationType: "LOST_SALES", inAppEnabled: false,
          pushEnabled: true },
      ];
    },
    async savePreference(user) {
      calls.push(`save:${user}`);
      return { notificationType: "LOW_STOCK", inAppEnabled: true,
        pushEnabled: false };
    },
    async list(user, page, unread, types) {
      calls.push(`list:${user}:${page}:${unread}:${types.join(",")}`);
      return { page, pageSize: 50, total: 0, items: [] };
    },
    async markRead(user, id) {
      calls.push(`read:${user}:${id}`);
      return { id, notificationType: "LOW_STOCK", severity: "INFO",
        title: "Stock", message: "Low", relatedEntityType: null,
        relatedEntityId: null, isRead: true, readAt: "now", createdAt: "now" };
    },
    async registerToken() { return { id: "token-id" }; },
    async deactivateToken() {}, async deliveries() { return []; },
  });
  await service.list(userA, { page: "2", unreadOnly: "true" });
  await service.markRead(userA, noteId, {});
  await service.savePreference(userA, { notificationType: "LOW_STOCK",
    inAppEnabled: true, pushEnabled: false });
  assert.deepEqual(calls, [
    `prefs:${userA}`, `list:${userA}:2:true:LOW_STOCK`,
    `read:${userA}:${noteId}`, `save:${userA}`,
  ]);
  await assert.rejects(service.list(userA, { recipientUserId: "other" }));
  await assert.rejects(service.markRead(userA, "bad-id", {}));
  await assert.rejects(service.savePreference(userA, {
    notificationType: "LOW_STOCK", inAppEnabled: true, pushEnabled: true,
    role: "SYSTEM_ADMINISTRATOR" }));
});

test("T-MAN-AUTO-01 [FR-ALT-01, scope 1.4]: derives manager prerequisites without business mutation", () => {
  const snapshot = { activeCategoryIds: ["a", "b"],
    todayPredictionIds: ["a", "b"], nextPredictionIds: ["a"],
    confirmedCategoryIds: ["a", "b"], completedCategoryIds: [],
    remainingLeftovers: 0 };
  const manager = derivePending("2026-11-09", "2026-11-10", snapshot,
    "BAKERY_MANAGER");
  assert.deepEqual(manager.items.map((item) => item.status),
    ["READY", "COMPLETE", "READY", "BLOCKED"]);
  const administrator = derivePending("2026-11-09", "2026-11-10", snapshot,
    "SYSTEM_ADMINISTRATOR");
  assert.deepEqual(administrator.items, []);
  assert.ok(administrator.administrationLinks.includes("OPEN_MODEL_MANAGEMENT"));
  const completed = derivePending("2026-11-09", "2026-11-10", {
    ...snapshot, completedCategoryIds: ["a", "b"],
    remainingLeftovers: 4 }, "BAKERY_MANAGER");
  assert.equal(completed.items[2]?.status, "COMPLETE");
  assert.equal(completed.items[3]?.status, "READY");
});

test("T-ALT-AUTO-02 [FR-ALT-01]: manual inventory scan distinguishes low stock and expiry", () => {
  const events = detectInventoryAlerts({ timezone: "Asia/Kuala_Lumpur",
    ingredients: [{ id: "ingredient-1", name: "Flour", stock: 50,
      threshold: 100 }], batches: [
      { id: "batch-old", ingredientId: "ingredient-1",
        expiryDate: "2026-11-08" },
      { id: "batch-soon", ingredientId: "ingredient-1",
        expiryDate: "2026-11-11" },
      { id: "batch-later", ingredientId: "ingredient-1",
        expiryDate: "2026-11-20" },
    ] }, new Date("2026-11-09T02:00:00Z"));
  assert.deepEqual(events.map((event) => event.type),
    ["LOW_STOCK", "EXPIRED_BATCH", "EXPIRING_BATCH"]);
});

test("T-ALT-AUTO-03 [BR-ALT-01, FR-ALT-04]: per-recipient push gates and delivery evidence", async () => {
  const history: string[] = [];
  const events = new NotificationEventService({
    async recipients(_type, roles) {
      assert.deepEqual(roles, ["BAKERY_MANAGER", "SYSTEM_ADMINISTRATOR"]);
      return [
        { userId: "a", inAppEnabled: true, pushEnabled: false },
        { userId: "b", inAppEnabled: true, pushEnabled: true },
        { userId: "c", inAppEnabled: false, pushEnabled: true },
      ];
    },
    async insert(user) { history.push(`insert:${user}`);
      return { id: `note-${user}`, created: true }; },
    async tokens(user) { return [{ id: `token-${user}`, token: user }]; },
    async skip(id, reason) { history.push(`skip:${id}:${reason}`); },
    async pending(id, token) { history.push(`pending:${id}:${token}`);
      return `delivery-${token}`; },
    async submitted(id, provider) { history.push(`submitted:${id}:${provider}`); },
    async failed(id, reason) { history.push(`failed:${id}:${reason}`); },
    async deactivateToken(id, user) { history.push(`deactivate:${id}:${user}`); },
  }, { async send(token) {
    if (token === "c") throw new Error("FCM_UNREGISTERED");
    return { providerMessageId: `provider-${token}` };
  } });
  await events.publish({ type: "LOW_STOCK", severity: "WARNING",
    title: "Stock low", message: "Review flour", eventKey: "flour:50" });
  assert.ok(history.includes("skip:note-a:PUSH_NOT_OPTED_IN"));
  assert.ok(history.includes("submitted:delivery-token-b:provider-b"));
  assert.ok(history.includes("failed:delivery-token-c:FCM_UNREGISTERED"));
  assert.ok(history.includes("deactivate:token-c:c"));
  assert.equal(history.filter((item) => item.startsWith("insert:")).length, 3);
});
