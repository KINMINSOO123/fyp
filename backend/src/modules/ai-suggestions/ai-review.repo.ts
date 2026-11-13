import { supabaseAdmin } from "../../config/supabase.js";
import { AppError } from "../../shared/AppError.js";

export class AiReviewRepo {
  async catalogue() {
    const [categories, ingredients] = await Promise.all([
      supabaseAdmin.from("bread_categories").select("id,name,display_order"),
      supabaseAdmin.from("ingredients").select("id,name,is_active,unit")
        .order("name", { ascending: true }),
    ]);
    if (categories.error || !categories.data || ingredients.error || !ingredients.data)
      throw new AppError(503, "AI_CONTEXT_UNAVAILABLE", "Inventory catalogue is unavailable.");
    return { categories: categories.data.map((row) => ({ id: row.id, name: row.name,
      displayOrder: row.display_order })),
    ingredients: ingredients.data.map((row) => ({ id: row.id, name: row.name,
      isActive: row.is_active, unit: row.unit })) };
  }
  async create(actor: string, requestId: string, payload: Record<string, unknown>) {
    const { data, error } = await supabaseAdmin.rpc("create_reviewed_ai_bread_with_audit", {
      p_actor_user_id: actor, p_request_id: requestId, p_payload: payload,
    });
    if (error) {
      if (error.code === "42501") throw new AppError(403, "FORBIDDEN", "Administrator permission is required.");
      if (error.code === "PGRST202") throw new AppError(503, "AI_REVIEW_SCHEMA_NOT_READY",
        "Apply the reviewed-bread migration before adding a draft.");
      if (["22023", "23505", "23514", "23503", "P0001"].includes(error.code))
        throw new AppError(409, "AI_REVIEW_CONFLICT", error.message);
      throw new AppError(503, "AI_REVIEW_UNAVAILABLE", "Unable to save the reviewed bread.");
    }
    return data;
  }
}
