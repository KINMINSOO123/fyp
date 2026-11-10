import { AppError } from "../../shared/AppError.js";
import { isCalendarDate } from "../prediction/history-selection.service.js";
import type { LeftoverRepo } from "./leftover.repo.js";

const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
type DataRepo = Pick<LeftoverRepo,
  "getBakeryTimezone" | "list" | "find" | "listCharities" |
  "allocate" | "advanceStatus" | "saveCharity" | "listDonations">;

function id(value: unknown): string {
  if (typeof value !== "string" || !uuid.test(value)) {
    throw new AppError(400, "VALIDATION_ERROR", "A valid ID is required.");
  }
  return value;
}
function text(value: unknown, name: string, max: number): string {
  if (typeof value !== "string" || !value.trim() ||
      value.trim().length > max) {
    throw new AppError(400, "VALIDATION_ERROR", `${name} is required.`);
  }
  return value.trim();
}
function object(value: unknown, keys: string[]): Record<string, unknown> {
  if (typeof value !== "object" || value === null || Array.isArray(value) ||
      Object.keys(value).some((key) => !keys.includes(key))) {
    throw new AppError(400, "VALIDATION_ERROR", "Invalid request fields.");
  }
  return value as Record<string, unknown>;
}
function bakeryDate(now: Date, timezone: string): string {
  const parts = new Intl.DateTimeFormat("en-US", {
    timeZone: timezone, year: "numeric", month: "2-digit", day: "2-digit",
  }).formatToParts(now);
  const get = (type: string) => parts.find((part) => part.type === type)?.value;
  return `${get("year")}-${get("month")}-${get("day")}`;
}

export class LeftoverManagementService {
  constructor(private readonly providedRepo?: DataRepo,
    private readonly now: () => Date = () => new Date()) {}
  private async repo(): Promise<DataRepo> {
    return this.providedRepo ?? new (
      await import("./leftover.repo.js")
    ).LeftoverRepo();
  }

  async list(rawQuery: unknown) {
    const query = object(rawQuery, ["date", "breadCategoryId"]);
    const repo = await this.repo();
    const today = bakeryDate(this.now(), await repo.getBakeryTimezone());
    const date = query.date === undefined ? today : query.date;
    if (typeof date !== "string" || !isCalendarDate(date)) {
      throw new AppError(400, "VALIDATION_ERROR", "A valid date is required.");
    }
    const categoryId = query.breadCategoryId === undefined ? null : id(query.breadCategoryId);
    return { date, items: await repo.list(date, categoryId) };
  }

  async recommendation(resultId: string) {
    const repo = await this.repo();
    const [result, charities] = await Promise.all([
      repo.find(id(resultId)), repo.listCharities(true),
    ]);
    return { dailyResultId: result.dailyResultId,
      remainingUnallocated: result.remainingUnallocated,
      activeCharities: charities,
      recommendation: result.remainingUnallocated === 0 ? "NO_LEFTOVER" :
        charities.length ? "MANAGER_REVIEW_DONATION_OR_WASTE" :
          "MANAGER_REVIEW_WASTE_OR_WAIT_FOR_CHARITY",
      automaticAllocation: false };
  }

  async donate(actorId: string, raw: unknown) {
    const input = object(raw, ["dailyResultId", "quantity", "charityPartnerId",
      "notes", "confirm"]);
    if (Object.keys(input).some((key) =>
      !["dailyResultId", "quantity", "charityPartnerId", "notes", "confirm"].includes(key)) ||
        input.confirm !== true || !Number.isSafeInteger(input.quantity) ||
        (input.quantity as number) <= 0 ||
        (input.notes !== undefined && input.notes !== null &&
         (typeof input.notes !== "string" || input.notes.trim().length > 500))) {
      throw new AppError(400, "VALIDATION_ERROR",
        "Confirm a positive donation quantity and valid details.");
    }
    return (await this.repo()).allocate(actorId, {
      action: "DONATE", dailyResultId: id(input.dailyResultId),
      quantity: input.quantity as number,
      charityPartnerId: id(input.charityPartnerId),
      disposalReason: null,
      notes: typeof input.notes === "string" ? input.notes.trim() || null : null,
    });
  }

  async recordWaste(actorId: string, raw: unknown) {
    const input = object(raw, ["dailyResultId", "quantity", "disposalReason", "confirm"]);
    if (input.confirm !== true || !Number.isSafeInteger(input.quantity) ||
        (input.quantity as number) <= 0) {
      throw new AppError(400, "VALIDATION_ERROR",
        "Confirm a positive waste quantity.");
    }
    return (await this.repo()).allocate(actorId, {
      action: "WASTE", dailyResultId: id(input.dailyResultId),
      quantity: input.quantity as number,
      charityPartnerId: null,
      disposalReason: text(input.disposalReason, "Disposal reason", 500),
      notes: null,
    });
  }

  async advanceDonation(actorId: string, donationId: string, raw: unknown) {
    const input = object(raw, ["status", "confirm"]);
    if (Object.keys(input).length !== 2 || input.confirm !== true ||
        (input.status !== "COLLECTED" && input.status !== "COMPLETED")) {
      throw new AppError(400, "VALIDATION_ERROR",
        "Only confirmed collected or completed progress is supported.");
    }
    return (await this.repo()).advanceStatus(actorId, id(donationId), input.status);
  }

  async listDonations(rawQuery: unknown) {
    const query = object(rawQuery, ["date", "page"]);
    const repo = await this.repo();
    const today = bakeryDate(this.now(), await repo.getBakeryTimezone());
    const date = query.date === undefined ? today : query.date;
    const page = query.page === undefined ? 1 : Number(query.page);
    if (typeof date !== "string" || !isCalendarDate(date) ||
        !Number.isSafeInteger(page) || page < 1 || page > 42_949_672) {
      throw new AppError(400, "VALIDATION_ERROR", "Invalid donation filters.");
    }
    return repo.listDonations(date, page);
  }

  async listCharities(activeOnly = true) {
    return (await this.repo()).listCharities(activeOnly);
  }
}

export class CharityPartnerService {
  constructor(private readonly providedRepo?: DataRepo) {}
  private async repo(): Promise<DataRepo> {
    return this.providedRepo ?? new (
      await import("./leftover.repo.js")
    ).LeftoverRepo();
  }
  async list() { return (await this.repo()).listCharities(false); }
  async save(actorId: string, raw: unknown, partnerId?: string) {
    const input = object(raw, ["name", "contactInfo", "isActive"]);
    if (Object.keys(input).length !== 3 ||
        typeof input.isActive !== "boolean" ||
        !(input.contactInfo === null || typeof input.contactInfo === "string") ||
        (typeof input.contactInfo === "string" &&
         input.contactInfo.trim().length > 500)) {
      throw new AppError(400, "VALIDATION_ERROR", "Invalid charity partner fields.");
    }
    return (await this.repo()).saveCharity(actorId, {
      id: partnerId === undefined ? null : id(partnerId),
      name: text(input.name, "Charity name", 120),
      contactInfo: typeof input.contactInfo === "string" ?
        input.contactInfo.trim() || null : null,
      isActive: input.isActive,
    });
  }
}
