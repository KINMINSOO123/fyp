import type { RequestHandler } from "express";
import { AppError } from "../../shared/AppError.js";
import { ReportExportAdapter } from "./report-export.adapter.js";
import { ReportService } from "./report.service.js";

export class ReportController {
  constructor(private readonly service = new ReportService(),
    private readonly exporter = new ReportExportAdapter()) {}

  get: RequestHandler = async (req, res): Promise<void> => {
    res.json({ data: await this.service.get(req.query) });
  };

  categories: RequestHandler = async (_req, res): Promise<void> => {
    res.json({ data: await this.service.categories() });
  };

  export: RequestHandler = async (req, res): Promise<void> => {
    const { format, ...filters } = req.query;
    if (format !== "CSV" && format !== "PDF") {
      throw new AppError(400, "VALIDATION_ERROR", "Choose CSV or PDF format.");
    }
    const file = this.exporter.render(await this.service.get(filters), format);
    res.setHeader("Content-Type", file.contentType);
    res.setHeader("Content-Disposition", `attachment; filename="${file.filename}"`);
    res.setHeader("Cache-Control", "no-store");
    res.send(file.bytes);
  };
}
