import { AppError } from "../../shared/AppError.js";
import { isCalendarDate } from "../prediction/history-selection.service.js";
import { buildRestockPreview } from "./restock-planning.js";
import type { RestockRepo, RestockSnapshot } from "./restock.repo.js";

const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
type Repo = Pick<RestockRepo, "loadPlanning" | "submit" | "list" | "cancel">;

function snapshot(preview: ReturnType<typeof buildRestockPreview>): RestockSnapshot {
  return { desiredQuantities: preview.desiredQuantities.map((row) => ({
    breadCategoryId: row.breadCategoryId, desiredQty: row.desiredQty,
  })), shortages: preview.shortages.map((row) => ({
    ingredientId: row.ingredientId, additionalGrams: row.additionalGrams,
  })) };
}

function normalizedExpected(value: unknown): RestockSnapshot | null {
  if (!value || typeof value !== "object" || Array.isArray(value)) return null;
  const raw = value as Record<string, unknown>;
  if (Object.keys(raw).length !== 2 ||
      !Array.isArray(raw.desiredQuantities) || !Array.isArray(raw.shortages)) return null;
  const desiredQuantities = raw.desiredQuantities.map((item: unknown) => {
    if (!item || typeof item !== "object" || Array.isArray(item)) return null;
    const row = item as Record<string, unknown>;
    if (Object.keys(row).length !== 2 ||
        typeof row.breadCategoryId !== "string" ||
        !Number.isSafeInteger(row.desiredQty) || (row.desiredQty as number) < 0) return null;
    return { breadCategoryId: row.breadCategoryId,
      desiredQty: row.desiredQty as number };
  });
  const shortages = raw.shortages.map((item: unknown) => {
    if (!item || typeof item !== "object" || Array.isArray(item)) return null;
    const row = item as Record<string, unknown>;
    const grams = row.additionalGrams;
    if (Object.keys(row).length !== 2 ||
        typeof row.ingredientId !== "string" ||
        typeof grams !== "number" || !Number.isFinite(grams) || grams <= 0 ||
        Math.abs(grams * 1000 - Math.round(grams * 1000)) > 1e-6) return null;
    return { ingredientId: row.ingredientId, additionalGrams: grams };
  });
  if (desiredQuantities.some((item) => item === null) ||
      shortages.some((item) => item === null)) return null;
  return { desiredQuantities: desiredQuantities as RestockSnapshot["desiredQuantities"],
    shortages: shortages as RestockSnapshot["shortages"] };
}

export class RestockService {
  constructor(private readonly providedRepo?: Repo) {}
  private async repo(): Promise<Repo> {
    return this.providedRepo ?? new (await import(
      "./restock.repo.js")).RestockRepo();
  }
  async preview(date: string) {
    if (!isCalendarDate(date)) throw new AppError(400, "VALIDATION_ERROR",
      "A valid production date is required.");
    return buildRestockPreview(await (await this.repo()).loadPlanning(date));
  }
  async submit(actorUserId: string, raw: unknown) {
    const body = raw as Record<string, unknown> | null;
    if (!body || typeof body !== "object" || Array.isArray(body) ||
        Object.keys(body).length !== 3 ||
        Object.keys(body).some((key) => ![
          "targetDate", "expectedPlan", "confirmed",
        ].includes(key)) || typeof body.targetDate !== "string" ||
        !isCalendarDate(body.targetDate) || body.confirmed !== true ||
        typeof body.expectedPlan !== "object" ||
        body.expectedPlan === null || Array.isArray(body.expectedPlan)) {
      throw new AppError(400, "VALIDATION_ERROR",
        "Confirm the current restock preview before submitting.");
    }
    const current = await this.preview(body.targetDate);
    if (!current.shortages.length) throw new AppError(409, "NO_RESTOCK_NEEDED",
      "Valid stock supports the desired production quantities.");
    const expected = normalizedExpected(body.expectedPlan);
    if (!expected) throw new AppError(400, "VALIDATION_ERROR",
      "Invalid restock preview snapshot.");
    const authoritative = snapshot(current);
    if (JSON.stringify(expected) !== JSON.stringify(authoritative)) {
      throw new AppError(409, "RESTOCK_PLAN_CHANGED",
        "Production or stock changed. Refresh the restock preview.");
    }
    return (await this.repo()).submit(actorUserId, body.targetDate,
      authoritative);
  }
  async list(actorUserId: string, role: string) {
    return (await this.repo()).list(role === "SYSTEM_ADMINISTRATOR" ?
      null : actorUserId);
  }
  async cancel(actorUserId: string, requestId: string, raw: unknown) {
    const body = raw as Record<string, unknown> | null;
    if (!uuid.test(requestId) || !body || typeof body !== "object" ||
        Array.isArray(body) || Object.keys(body).length !== 1 ||
        typeof body.reason !== "string" || !body.reason.trim() ||
        body.reason.trim().length > 500) {
      throw new AppError(400, "VALIDATION_ERROR",
        "A request ID and cancellation reason are required.");
    }
    return (await this.repo()).cancel(actorUserId, requestId,
      body.reason.trim());
  }
}
