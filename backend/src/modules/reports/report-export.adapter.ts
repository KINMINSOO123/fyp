import type { Report, ReportRow } from "./report.service.js";

export type ReportFile = { filename: string; contentType: string; bytes: Buffer };

function csvCell(value: string | number | null): string {
  if (value === null) return "";
  let content = String(value);
  // Keep category names as data when a CSV is opened by spreadsheet software.
  if (/^[\s]*[=+@-]/.test(content) && typeof value === "string") {
    content = `'${content}`;
  }
  return `"${content.replaceAll('"', '""')}"`;
}

function rate(value: number | null): Array<string | number> {
  return value === null ? ["", "Not Applicable"] : [value, "Applicable"];
}

function csv(report: Report): Buffer {
  const headings = ["date", "bread_category_id", "bread_category_name",
    "data_origin", "predicted_units_sold", "produced", "units_sold",
    "lost_sales", "estimated_demand", "sales_prediction_error",
    "leftover", "donated", "wasted", "remaining_unallocated",
    "leftover_rate_pct", "leftover_rate_status",
    "discarded_waste_rate_pct", "discarded_waste_rate_status",
    "sales_fulfilment_pct", "sales_fulfilment_status",
    "revenue_myr", "ingredient_cost_myr",
    "gross_profit_myr", "gross_profit_margin_pct", "gross_profit_margin_status",
    "evaluation_units_sold", "evaluation_data_origin",
    "evaluation_prediction_error"];
  const lines = [headings.join(",")];
  for (const row of report.rows) {
    lines.push([
      row.date, row.breadCategoryId, row.breadCategoryName, row.dataOrigin,
      row.predictedUnitsSold, row.produced, row.unitsSold, row.lostSales,
      row.estimatedDemand, row.salesPredictionError, row.leftover,
      row.donated, row.wasted, row.remainingUnallocated,
      ...rate(row.leftoverRatePct), ...rate(row.discardedWasteRatePct),
      ...rate(row.salesFulfilmentPct), row.revenue, row.ingredientCost,
      row.grossProfit, ...rate(row.grossProfitMarginPct),
      row.evaluationUnitsSold, row.evaluationDataOrigin,
      row.evaluationPredictionError,
    ].map((value) => csvCell(value)).join(","));
  }
  return Buffer.from(`\uFEFF${lines.join("\r\n")}\r\n`, "utf8");
}

function pdfSafe(value: string): string {
  return value.normalize("NFKD").replace(/[^\x20-\x7e]/g, "?")
    .replaceAll("\\", "\\\\").replaceAll("(", "\\(")
    .replaceAll(")", "\\)");
}

function pdfLine(value: string, x: number, y: number, size = 9): string {
  return `BT /F1 ${size} Tf ${x} ${y} Td (${pdfSafe(value)}) Tj ET\n`;
}

function shortName(value: string): string {
  return value.length > 28 ? `${value.slice(0, 25)}...` : value;
}

function pdfRow(row: ReportRow, y: number): string {
  const line1 = `${row.date}  ${shortName(row.breadCategoryName)}  Pred ${row.predictedUnitsSold}  Produced ${row.produced}  Sold ${row.unitsSold}  Left ${row.leftover}  Donate ${row.donated}  Waste ${row.wasted}`;
  const line2 = `    Error ${row.salesPredictionError}  Revenue RM ${row.revenue.toFixed(2)}  Cost RM ${row.ingredientCost.toFixed(2)}  Profit RM ${row.grossProfit.toFixed(2)}`;
  const line3 = row.evaluationDataOrigin === null ?
    "    Comparable observation: Not Available" :
    `    Comparable ${row.evaluationDataOrigin}: ${row.evaluationUnitsSold} sold, error ${row.evaluationPredictionError}`;
  return pdfLine(line1, 36, y) + pdfLine(line2, 36, y - 12) +
    pdfLine(line3, 36, y - 24);
}

// Small dependency-free, paginated PDF. Every figure comes from the same
// Report object used by JSON and CSV; this renderer never queries the DB.
function pdf(report: Report): Buffer {
  const streams: string[] = [];
  let content = "";
  let y = 748;
  const pageStart = () => {
    content += pdfLine("Smart Bakery - Simulated Operational Report", 36, 760, 15);
    content += pdfLine(`${report.filters.fromDate} to ${report.filters.toDate} | ${report.filters.period} | category ${report.filters.breadCategoryId ?? "All"}`, 36, 739);
    content += pdfLine(`Generated ${report.generatedAt} | ${report.timezone}`, 36, 725);
    content += pdfLine("SIMULATED DATA - financial figures are reporting-only direct ingredient costs", 36, 711);
    y = 691;
  };
  const finish = () => {
    content += pdfLine(`Page ${streams.length + 1}`, 36, 30);
    streams.push(content);
    content = "";
  };
  pageStart();
  const totals = report.totals;
  const displayRate = (value: number | null) => value === null ?
    "Not Applicable" : `${value.toFixed(2)}%`;
  for (const text of [
    `Results ${totals.resultCount} | Predicted ${totals.predictedUnitsSold} | Produced ${totals.produced} | Sold ${totals.unitsSold} | Lost sales ${totals.lostSales}`,
    `Leftover ${totals.leftover} | Donated ${totals.donated} | Discarded ${totals.wasted} | Unallocated ${totals.remainingUnallocated}`,
    `Prediction error ${totals.salesPredictionError} | Fulfilment ${displayRate(totals.salesFulfilmentPct)}`,
    `Leftover rate ${displayRate(totals.leftoverRatePct)} | Discarded waste rate ${displayRate(totals.discardedWasteRatePct)}`,
    `Revenue RM ${totals.revenue.toFixed(2)} | Ingredient cost RM ${totals.ingredientCost.toFixed(2)}`,
    `Gross profit RM ${totals.grossProfit.toFixed(2)} | Margin ${displayRate(totals.grossProfitMarginPct)}`,
  ]) {
    content += pdfLine(text, 36, y);
    y -= 16;
  }
  y -= 15;
  if (!report.rows.length) content += pdfLine("No completed results for these filters.", 36, y);
  for (const row of report.rows) {
    if (y < 75) {
      finish();
      pageStart();
    }
    content += pdfRow(row, y);
    y -= 40;
  }
  finish();

  const objects: string[] = [];
  const add = (value: string) => { objects.push(value); return objects.length; };
  const catalogId = add("");
  const pagesId = add("");
  const fontId = add("<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>");
  const pageIds: number[] = [];
  for (const stream of streams) {
    const streamId = add(`<< /Length ${Buffer.byteLength(stream, "latin1")} >>\nstream\n${stream}endstream`);
    pageIds.push(add(`<< /Type /Page /Parent ${pagesId} 0 R /MediaBox [0 0 612 792] /Resources << /Font << /F1 ${fontId} 0 R >> >> /Contents ${streamId} 0 R >>`));
  }
  objects[catalogId - 1] = `<< /Type /Catalog /Pages ${pagesId} 0 R >>`;
  objects[pagesId - 1] = `<< /Type /Pages /Kids [${pageIds.map((id) => `${id} 0 R`).join(" ")}] /Count ${pageIds.length} >>`;
  let output = "%PDF-1.4\n";
  const offsets = [0];
  for (let i = 0; i < objects.length; i++) {
    offsets.push(Buffer.byteLength(output, "latin1"));
    output += `${i + 1} 0 obj\n${objects[i]}\nendobj\n`;
  }
  const xref = Buffer.byteLength(output, "latin1");
  output += `xref\n0 ${objects.length + 1}\n0000000000 65535 f \n`;
  for (const offset of offsets.slice(1)) {
    output += `${String(offset).padStart(10, "0")} 00000 n \n`;
  }
  output += `trailer\n<< /Size ${objects.length + 1} /Root ${catalogId} 0 R >>\nstartxref\n${xref}\n%%EOF\n`;
  return Buffer.from(output, "latin1");
}

export class ReportExportAdapter {
  render(report: Report, format: "CSV" | "PDF"): ReportFile {
    const filename = `Smart_Bakery_${report.filters.period}_${report.filters.fromDate}_to_${report.filters.toDate}.${format.toLowerCase()}`;
    return format === "CSV" ?
      { filename, contentType: "text/csv; charset=utf-8", bytes: csv(report) } :
      { filename, contentType: "application/pdf", bytes: pdf(report) };
  }
}
