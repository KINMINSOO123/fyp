import { AppError } from "../../shared/AppError.js";

export function restockFulfilment(requestedGrams: number,
  cancelledGrams: number, receiptGrams: number[]) {
  const receivedGrams = receiptGrams.reduce((sum, value) => sum + value, 0);
  const outstandingGrams = Math.round(
    (requestedGrams - cancelledGrams - receivedGrams) * 1000) / 1000;
  if (![requestedGrams, cancelledGrams, receivedGrams,
      outstandingGrams].every(Number.isFinite) || requestedGrams <= 0 ||
      cancelledGrams < 0 || receiptGrams.some((value) => value <= 0 ||
        !Number.isFinite(value)) || outstandingGrams < 0) {
    throw new AppError(503, "RESTOCK_DATA_INVALID",
      "Restock quantities are inconsistent.");
  }
  return { requestedGrams, receivedGrams, cancelledGrams,
    outstandingGrams };
}
