import { NotificationEventService } from "./notification-event.service.js";
import { publishBestEffort } from "./event-hooks.js";
import type { EventPublisher } from "./event-hooks.js";
import type { BusinessEvent } from "./notification-event.service.js";

type InventoryAlertSnapshot = { timezone: string;
  ingredients: Array<{ id: string; name: string; stock: number;
    threshold: number }>;
  batches: Array<{ id: string; ingredientId: string; expiryDate: string }> };

export class InventoryAlertRepo {
  async snapshot(): Promise<InventoryAlertSnapshot> {
    const { supabaseAdmin } = await import("../../config/supabase.js");
    const [bakery, ingredients, stock] = await Promise.all([
      supabaseAdmin.from("bakery_settings").select("timezone")
        .eq("singleton_guard", true).single(),
      supabaseAdmin.from("ingredients")
        .select("id,name,reorder_threshold").eq("is_active", true),
      supabaseAdmin.from("inventory").select("ingredient_id,quantity_grams"),
    ]);
    if (bakery.error || !bakery.data || ingredients.error ||
        !ingredients.data || stock.error || !stock.data) {
      throw new Error("Unable to load inventory alert state.");
    }
    const byId = new Map(stock.data.map((row) =>
      [row.ingredient_id, Number(row.quantity_grams)]));
    const allBatches: InventoryAlertSnapshot["batches"] = [];
    for (let offset = 0; ; offset += 500) {
      const { data, error } = await supabaseAdmin.from("inventory_batches")
        .select("id,ingredient_id,expiry_date")
        .eq("status", "ACTIVE").gt("remaining_quantity_grams", 0)
        .order("expiry_date", { ascending: true })
        .order("id", { ascending: true }).range(offset, offset + 499);
      if (error || !data) throw new Error("Unable to load inventory batches.");
      allBatches.push(...data.map((row) => ({ id: row.id,
        ingredientId: row.ingredient_id, expiryDate: row.expiry_date })));
      if (data.length < 500) break;
    }
    return { timezone: bakery.data.timezone,
      ingredients: ingredients.data.map((row) => ({ id: row.id,
        name: row.name, stock: byId.get(row.id) ?? 0,
        threshold: Number(row.reorder_threshold) })),
      batches: allBatches };
  }
}

function bakeryDate(now: Date, timezone: string): string {
  const parts = new Intl.DateTimeFormat("en-US", {
    timeZone: timezone, year: "numeric", month: "2-digit", day: "2-digit",
  }).formatToParts(now);
  const get = (type: string) => parts.find((part) => part.type === type)?.value;
  return `${get("year")}-${get("month")}-${get("day")}`;
}

export function detectInventoryAlerts(snapshot: InventoryAlertSnapshot,
  now: Date): BusinessEvent[] {
  const today = bakeryDate(now, snapshot.timezone);
  const soon = new Date(Date.parse(`${today}T00:00:00Z`) + 3 * 86_400_000)
    .toISOString().slice(0, 10);
  const names = new Map(snapshot.ingredients.map((item) =>
    [item.id, item.name]));
  const events: BusinessEvent[] = [];
  for (const ingredient of snapshot.ingredients) {
    if (!Number.isFinite(ingredient.stock) || ingredient.stock < 0 ||
        !Number.isFinite(ingredient.threshold) || ingredient.threshold < 0) {
      throw new Error("Invalid inventory alert quantity.");
    }
    if (ingredient.stock <= ingredient.threshold) {
      events.push({ type: "LOW_STOCK", severity: "WARNING",
        title: "Ingredient stock is low",
        message: `${ingredient.name} is at or below its reorder threshold.`,
        eventKey: `low-stock:${ingredient.id}:${today}:${ingredient.stock}`,
        relatedEntityType: "ingredients", relatedEntityId: ingredient.id });
    }
  }
  for (const batch of snapshot.batches) {
    if (!names.has(batch.ingredientId)) continue;
    const expired = batch.expiryDate < today;
    if (batch.expiryDate > soon) continue;
    events.push({ type: expired ? "EXPIRED_BATCH" : "EXPIRING_BATCH",
      severity: expired ? "CRITICAL" : "WARNING",
      title: expired ? "Inventory batch expired" : "Inventory batch expiring",
      message: `${names.get(batch.ingredientId)} batch ${expired ?
        "expired" : "expires"} on ${batch.expiryDate}.`,
      eventKey: `${expired ? "expired" : "expiring"}:${batch.id}:${today}:${batch.expiryDate}`,
      relatedEntityType: "inventory_batches", relatedEntityId: batch.id });
  }
  return events;
}

export class InventoryAlertService {
  constructor(private readonly repo = new InventoryAlertRepo(),
    private readonly notifications: EventPublisher = new NotificationEventService(),
    private readonly now: () => Date = () => new Date()) {}
  async scan() {
    const events = detectInventoryAlerts(await this.repo.snapshot(), this.now());
    await publishBestEffort(this.notifications, events);
    return { detected: events.length };
  }
}
