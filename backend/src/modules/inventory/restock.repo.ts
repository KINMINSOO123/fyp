import { supabaseAdmin } from "../../config/supabase.js";
import { AppError } from "../../shared/AppError.js";
import { RecommendationRepo } from "./recommendation.repo.js";
import type { PlanningInput } from "./recommendation-engine.js";
import { restockFulfilment } from "./restock-fulfilment.js";

export type RestockSnapshot = { desiredQuantities: Array<{
  breadCategoryId: string; desiredQty: number }>;
  shortages: Array<{ ingredientId: string; additionalGrams: number }> };

function writeError(error: { code?: string; message: string }): Error {
  if (error.code === "42501") return new AppError(403, "FORBIDDEN",
    "The required bakery role is not active.");
  if (error.code === "P0002") return new AppError(404,
    "RESTOCK_NOT_FOUND", error.message);
  if (["P0001", "23505", "23514", "23503", "22023", "22P02"].includes(
    error.code ?? "")) return new AppError(409, "RESTOCK_CONFLICT",
    error.message);
  if (["PGRST202", "42883", "42P01", "42703"].includes(error.code ?? "")) {
    return new AppError(503, "RESTOCK_SCHEMA_NOT_READY",
      "Apply the restock migration before using this feature.");
  }
  return new Error("Unable to save the restock change.");
}

export class RestockRepo {
  async loadPlanning(date: string): Promise<PlanningInput> {
    return new RecommendationRepo().load(date);
  }

  async submit(actorUserId: string, date: string, snapshot: RestockSnapshot) {
    const { data, error } = await supabaseAdmin.rpc("submit_restock_request", {
      p_actor_user_id: actorUserId, p_production_date: date,
      p_expected_plan: snapshot,
    });
    if (error) throw writeError(error);
    if (!data || typeof data.id !== "string") throw new Error(
      "Restock submission returned no request ID.");
    return data as { id: string; productionDate: string; status: string };
  }

  async receiveLinked(actorUserId: string, itemId: string,
    receiptKey: string, payload: Record<string, unknown>) {
    const { data, error } = await supabaseAdmin.rpc("receive_restock_batch", {
      p_actor_user_id: actorUserId, p_item_id: itemId,
      p_receipt_key: receiptKey, p_payload: payload,
    });
    if (error) throw writeError(error);
    if (!data || typeof data.id !== "string") throw new Error(
      "Restock receipt returned no batch ID.");
    return data as { id: string; restockRequestId: string;
      alreadyRecorded: boolean };
  }

  async cancel(actorUserId: string, requestId: string, reason: string) {
    const { data, error } = await supabaseAdmin.rpc(
      "cancel_restock_outstanding", {
        p_actor_user_id: actorUserId, p_request_id: requestId,
        p_reason: reason,
      });
    if (error) throw writeError(error);
    return data as { id: string; status: string };
  }

  async list(requesterUserId: string | null) {
    let query = supabaseAdmin.from("restock_requests")
      .select("id,production_date,requester_user_id,desired_quantities,status,cancellation_reason,created_at,updated_at,closed_at")
      .order("created_at", { ascending: false }).limit(50);
    if (requesterUserId) query = query.eq("requester_user_id", requesterUserId);
    const { data: requests, error } = await query;
    if (error || !requests) throw new AppError(503, "RESTOCK_UNAVAILABLE",
      "Unable to load restock requests.");
    const ids = requests.map((row) => row.id);
    if (!ids.length) return [];
    const { data: items, error: itemError } = await supabaseAdmin
      .from("restock_request_items")
      .select("id,request_id,ingredient_id,requested_grams,cancelled_grams,ingredients(name)")
      .in("request_id", ids);
    if (itemError || !items) throw new AppError(503, "RESTOCK_UNAVAILABLE",
      "Unable to load restock items.");
    const itemIds = items.map((item) => item.id);
    const batches = itemIds.length ? await supabaseAdmin.from("inventory_batches")
      .select("id,restock_request_item_id,initial_quantity_grams,received_date,expiry_date,unit_cost")
      .in("restock_request_item_id", itemIds) : { data: [], error: null };
    if (batches.error || !batches.data) throw new AppError(503,
      "RESTOCK_UNAVAILABLE", "Unable to load linked receipts.");
    const byItem = new Map<string, Array<Record<string, unknown>>>();
    for (const batch of batches.data) {
      const list = byItem.get(batch.restock_request_item_id!) ?? [];
      list.push({ id: batch.id, quantityGrams: Number(batch.initial_quantity_grams),
        receivedDate: batch.received_date, expiryDate: batch.expiry_date,
        unitCostSnapshot: Number(batch.unit_cost) });
      byItem.set(batch.restock_request_item_id!, list);
    }
    return requests.map((request) => ({ id: request.id,
      productionDate: request.production_date,
      requesterUserId: request.requester_user_id,
      desiredQuantities: request.desired_quantities,
      status: request.status, cancellationReason: request.cancellation_reason,
      createdAt: request.created_at, updatedAt: request.updated_at,
      closedAt: request.closed_at,
      items: items.filter((item) => item.request_id === request.id)
        .map((item) => {
          const receipts = byItem.get(item.id) ?? [];
          const amounts = restockFulfilment(Number(item.requested_grams),
            Number(item.cancelled_grams), receipts.map((batch) =>
              Number(batch.quantityGrams)));
          return { id: item.id, ingredientId: item.ingredient_id,
            ingredientName: (item.ingredients as unknown as { name: string }).name,
            ...amounts,
            receipts };
        }),
    }));
  }
}
