import { supabaseAdmin } from "../../config/supabase.js";
import { AppError } from "../../shared/AppError.js";

export class InventoryAdminRepo {
  async listCategories() {
    const { data, error } = await supabaseAdmin.from("bread_categories")
      .select("id, name, description, display_order, shelf_life_hours, selling_price, is_active")
      .order("display_order", { ascending: true });
    if (error || !data) throw new Error("Unable to load bread categories.");
    return data.map((row) => ({ id: row.id, name: row.name,
      description: row.description, displayOrder: row.display_order,
      shelfLifeHours: row.shelf_life_hours,
      sellingPrice: Number(row.selling_price), isActive: row.is_active }));
  }

  async listIngredients() {
    const [ingredients, inventory] = await Promise.all([
      supabaseAdmin.from("ingredients")
        .select("id, name, unit, unit_cost, reorder_threshold, is_active")
        .order("name", { ascending: true }),
      supabaseAdmin.from("inventory").select("ingredient_id, quantity_grams"),
    ]);
    if (ingredients.error || !ingredients.data || inventory.error || !inventory.data) {
      throw new Error("Unable to load ingredients and inventory.");
    }
    const stock = new Map(inventory.data.map((row) =>
      [row.ingredient_id, Number(row.quantity_grams)]));
    return ingredients.data.map((row) => ({ id: row.id, name: row.name,
      unit: row.unit, referenceUnitCost: Number(row.unit_cost),
      reorderThresholdGrams: Number(row.reorder_threshold),
      isActive: row.is_active, snapshotQuantityGrams: stock.get(row.id) ?? 0 }));
  }

  async listRecipes(categoryId: string) {
    const { data, error } = await supabaseAdmin.from("recipes")
      .select("ingredient_id, grams_per_unit")
      .eq("bread_category_id", categoryId)
      .order("ingredient_id", { ascending: true });
    if (error || !data) throw new Error("Unable to load the category recipe.");
    return data.map((row) => ({ ingredientId: row.ingredient_id,
      gramsPerUnit: Number(row.grams_per_unit) }));
  }

  async listBatches(ingredientId: string | null, page: number) {
    let query = supabaseAdmin.from("inventory_batches")
      .select("id, ingredient_id, received_date, expiry_date, initial_quantity_grams, remaining_quantity_grams, unit_cost, source, status", { count: "exact" });
    if (ingredientId) query = query.eq("ingredient_id", ingredientId);
    const { data, count, error } = await query
      .order("received_date", { ascending: false })
      .order("id", { ascending: false }).range((page - 1) * 50, page * 50 - 1);
    if (error || !data || count === null) throw new Error("Unable to load inventory batches.");
    return { items: data.map((row) => ({ id: row.id,
      ingredientId: row.ingredient_id, receivedDate: row.received_date,
      expiryDate: row.expiry_date,
      initialQuantityGrams: Number(row.initial_quantity_grams),
      remainingQuantityGrams: Number(row.remaining_quantity_grams),
      unitCostSnapshot: Number(row.unit_cost), source: row.source,
      status: row.status })), page, pageSize: 50, total: count };
  }

  async mutate(actorUserId: string, action: string, payload: Record<string, unknown>) {
    const { data, error } = await supabaseAdmin.rpc("apply_inventory_admin_change_with_audit", {
      p_actor_user_id: actorUserId, p_action: action, p_payload: payload,
    });
    if (error) {
      if (error.code === "42501") throw new AppError(403, "FORBIDDEN", "Administrator permission is required.");
      if (error.code === "P0002") throw new AppError(404, "INVENTORY_ITEM_NOT_FOUND", error.message);
      if (error.code === "P0001" || error.code === "22023" ||
          error.code === "22P02" || error.code === "22007" ||
          error.code === "23502" || error.code === "23505" || error.code === "23514" ||
          error.code === "23503") {
        throw new AppError(409, "INVENTORY_CONFLICT", error.message);
      }
      if (error.code === "PGRST202") throw new AppError(503, "INVENTORY_SCHEMA_NOT_READY",
        "The inventory-administration migration is not available.");
      throw new Error("Unable to save the inventory change.");
    }
    if (!data || typeof data !== "object" || Array.isArray(data)) {
      throw new Error("Inventory mutation returned an invalid result.");
    }
    return data;
  }
}
