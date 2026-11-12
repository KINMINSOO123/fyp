import { AppError } from "../../shared/AppError.js";
import { isCalendarDate } from "./history-selection.service.js";
import { MalaysiaHolidayClient, type MalaysiaHolidayCheck } from
  "./malaysia-holiday.client.js";
import type { KlHolidayRepo } from "./kl-holiday.repo.js";

type Repo = Pick<KlHolidayRepo, "coverage" | "events" | "save">;
export class KlHolidayService {
  constructor(private readonly providedRepo?: Repo,
    private readonly client: Pick<MalaysiaHolidayClient, "year"> =
      new MalaysiaHolidayClient(),
    private readonly now: () => Date = () => new Date()) {}

  private async repo(): Promise<Repo> {
    return this.providedRepo ?? new (await import("./kl-holiday.repo.js"))
      .KlHolidayRepo();
  }

  async ensure(actor: string, date: string): Promise<MalaysiaHolidayCheck | null> {
    if (!isCalendarDate(date)) throw new AppError(400, "VALIDATION_ERROR",
      "A valid holiday date is required.");
    const year = Number(date.slice(0, 4));
    const repo = await this.repo();
    let coverage = await repo.coverage(year);
    if (!coverage || Date.parse(coverage.refreshAfter) <= this.now().getTime()) {
      let published;
      try {
        published = await this.client.year(year);
      } catch (error) {
        if (error instanceof AppError && error.code ===
            "HOLIDAY_PROVIDER_UNAVAILABLE") return null;
        throw error;
      }
      await repo.save(actor, published);
      coverage = await repo.coverage(year);
    }
    if (!coverage || !Number.isFinite(Date.parse(coverage.refreshAfter)) ||
        Date.parse(coverage.refreshAfter) <= this.now().getTime()) {
      return null;
    }
    const yearEvents = await repo.events(year);
    if (yearEvents.length !== coverage.eventCount) {
      throw new AppError(503, "CALENDAR_CONTEXT_UNAVAILABLE",
        "KL holiday cache is incomplete; refresh the year.");
    }
    const events = yearEvents.filter((item) =>
      item.eventDate === date);
    return { date, stateCode: "KUL", isHoliday: events.length > 0,
      sourceUrl: coverage.sourceUrl,
      holidays: events.map((item) => ({ name: item.eventName,
        sourceUrl: item.sourceReference,
        subjectToChange: item.subjectToChange })) };
  }

  async list(year: number) {
    this.validYear(year);
    const repo = await this.repo();
    return { year, stateCode: "KUL", coverage: await repo.coverage(year),
      events: await repo.events(year) };
  }
  async refresh(actor: string, year: number) {
    this.validYear(year);
    const repo = await this.repo();
    await repo.save(actor, await this.client.year(year));
    return this.list(year);
  }
  private validYear(year: number) {
    if (!Number.isInteger(year) || year < 2000 || year > 2100) {
      throw new AppError(400, "VALIDATION_ERROR", "A valid year is required.");
    }
  }
}
