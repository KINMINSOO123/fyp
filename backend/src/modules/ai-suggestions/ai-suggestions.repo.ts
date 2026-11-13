import { supabaseAdmin } from "../../config/supabase.js";
import { AppError } from "../../shared/AppError.js";

export type CatalogueContext = {
  categories: Array<{ name: string; description: string | null;
    recipe: Array<{ ingredientName: string; gramsPerBread: number }> }>;
  ingredients: Array<{ id: string; name: string; availableGrams: number }>;
};

function bakeryToday(timezone: string): string {
  const parts = new Intl.DateTimeFormat("en-US", { timeZone: timezone,
    year: "numeric", month: "2-digit", day: "2-digit" })
    .formatToParts(new Date());
  const value = (type: string) => parts.find((part) => part.type === type)?.value;
  return `${value("year")}-${value("month")}-${value("day")}`;
}

export class AiSuggestionsRepo {
  async loadContext(): Promise<CatalogueContext> {
    const { data: settings, error: settingsError } = await supabaseAdmin
      .from("bakery_settings").select("timezone")
      .eq("singleton_guard", true).single();
    if (settingsError || !settings) throw new AppError(503,
      "AI_CONTEXT_UNAVAILABLE", "Bakery settings are unavailable.");
    const today = bakeryToday(settings.timezone);
    const [categories, ingredients, recipes, batches] = await Promise.all([
      supabaseAdmin.from("bread_categories")
        .select("id,name,description,display_order")
        .eq("is_active", true).order("display_order", { ascending: true }),
      supabaseAdmin.from("ingredients").select("id,name")
        .eq("is_active", true).order("name", { ascending: true }),
      supabaseAdmin.from("recipes")
        .select("bread_category_id,ingredient_id,grams_per_unit"),
      supabaseAdmin.from("inventory_batches")
        .select("ingredient_id,remaining_quantity_grams")
        .eq("status", "ACTIVE").lte("received_date", today)
        .gte("expiry_date", today).gt("remaining_quantity_grams", 0),
    ]);
    if ([categories, ingredients, recipes, batches].some((result) =>
      result.error || !result.data)) {
      throw new AppError(503, "AI_CONTEXT_UNAVAILABLE",
        "The current bread and ingredient catalogue is unavailable.");
    }
    const ingredientNames = new Map(ingredients.data!.map((row) =>
      [row.id, row.name]));
    const stock = new Map<string, number>();
    for (const batch of batches.data!) {
      const grams = Number(batch.remaining_quantity_grams);
      if (!Number.isFinite(grams) || grams < 0) throw new AppError(503,
        "AI_CONTEXT_UNAVAILABLE", "Ingredient stock is invalid.");
      stock.set(batch.ingredient_id, (stock.get(batch.ingredient_id) ?? 0) + grams);
    }
    const recipeByCategory = new Map<string, CatalogueContext["categories"][number]["recipe"]>();
    for (const row of recipes.data!) {
      const ingredientName = ingredientNames.get(row.ingredient_id);
      if (!ingredientName) continue;
      const grams = Number(row.grams_per_unit);
      if (!Number.isFinite(grams) || grams <= 0) continue;
      const rows = recipeByCategory.get(row.bread_category_id) ?? [];
      rows.push({ ingredientName, gramsPerBread: grams });
      recipeByCategory.set(row.bread_category_id, rows);
    }
    return {
      categories: categories.data!.map((row) => ({ name: row.name,
        description: row.description,
        recipe: recipeByCategory.get(row.id) ?? [] })),
      ingredients: ingredients.data!.map((row) => ({ id: row.id, name: row.name,
        availableGrams: stock.get(row.id) ?? 0 })),
    };
  }
}
