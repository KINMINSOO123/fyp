import { AppError } from "../../shared/AppError.js";
import type { AiSuggestionsRepo, CatalogueContext } from "./ai-suggestions.repo.js";
import { GeminiClient } from "./gemini.client.js";

type Repo = Pick<AiSuggestionsRepo, "loadContext">;
type Generator = Pick<GeminiClient, "generate">;
type DraftIngredient = { ingredientName: string; gramsPerBread: number };
type DraftSuggestion = { name: string; description: string; reason: string;
  recipe: DraftIngredient[] };

function record(value: unknown): value is Record<string, unknown> {
  return !!value && typeof value === "object" && !Array.isArray(value);
}
function exactKeys(value: Record<string, unknown>, keys: string[]): boolean {
  return Object.keys(value).length === keys.length &&
    keys.every((key) => Object.hasOwn(value, key));
}
function text(value: unknown, max: number): string | null {
  if (typeof value !== "string") return null;
  const cleaned = value.trim();
  return cleaned && cleaned.length <= max ? cleaned : null;
}
function key(value: string): string {
  return value.normalize("NFKC").toLocaleLowerCase("en")
    .replace(/[^\p{L}\p{N}]+/gu, " ").trim();
}

export function validateDrafts(raw: unknown): DraftSuggestion[] {
  if (!record(raw) || !exactKeys(raw, ["suggestions"]) ||
      !Array.isArray(raw.suggestions) || raw.suggestions.length < 1 ||
      raw.suggestions.length > 3) {
    throw new AppError(502, "AI_INVALID_RESPONSE",
      "The AI returned an invalid suggestion format. Please try again.");
  }
  const names = new Set<string>();
  return raw.suggestions.map((item: unknown) => {
    if (!record(item) || !exactKeys(item,
      ["name", "description", "reason", "recipe"]) ||
        !Array.isArray(item.recipe) || item.recipe.length < 1 ||
        item.recipe.length > 15) {
      throw new AppError(502, "AI_INVALID_RESPONSE",
        "The AI returned an invalid recipe. Please try again.");
    }
    const name = text(item.name, 100);
    const description = text(item.description, 300);
    const reason = text(item.reason, 300);
    if (!name || !description || !reason || names.has(key(name))) {
      throw new AppError(502, "AI_INVALID_RESPONSE",
        "The AI returned incomplete or duplicate suggestions. Please try again.");
    }
    names.add(key(name));
    const ingredientNames = new Set<string>();
    const recipe = item.recipe.map((entry: unknown): DraftIngredient => {
      if (!record(entry) || !exactKeys(entry,
        ["ingredientName", "gramsPerBread"])) {
        throw new AppError(502, "AI_INVALID_RESPONSE",
          "The AI returned an invalid recipe ingredient. Please try again.");
      }
      const ingredientName = text(entry.ingredientName, 100);
      const gramsPerBread = entry.gramsPerBread;
      if (!ingredientName || ingredientNames.has(key(ingredientName)) ||
          typeof gramsPerBread !== "number" || !Number.isFinite(gramsPerBread) ||
          gramsPerBread <= 0 || gramsPerBread > 2000 ||
          Math.abs(gramsPerBread * 1000 - Math.round(gramsPerBread * 1000)) > 1e-6) {
        throw new AppError(502, "AI_INVALID_RESPONSE",
          "The AI returned an invalid recipe quantity. Please try again.");
      }
      ingredientNames.add(key(ingredientName));
      return { ingredientName, gramsPerBread };
    });
    return { name, description, reason, recipe };
  });
}

function promptFor(description: string, context: CatalogueContext): string {
  const categories = context.categories.map((category) => ({
    name: category.name,
    ...(category.description ? { description: category.description.slice(0, 100) } : {}),
    recipe: category.recipe.map((item) =>
      [item.ingredientName, item.gramsPerBread]),
  }));
  const ingredients = context.ingredients.map((ingredient) =>
    [ingredient.name, ingredient.availableGrams]);
  return `Suggest 1 to 3 distinct bread categories for this bakery. ` +
    `Request: ${JSON.stringify(description)}. ` +
    `Use the catalogue as context, but create new bread names. ` +
    `Give short descriptions and reasons. Every draft recipe quantity must be grams per ONE bread. ` +
    `You may suggest a new ingredient; do not pretend it is in stock. ` +
    `Drafts need human review and trial baking. ` +
    `Existing categories: ${JSON.stringify(categories)}. ` +
    `Active ingredients [name,available valid grams]: ${JSON.stringify(ingredients)}.`;
}

export class AiSuggestionsService {
  constructor(private readonly providedRepo?: Repo,
    private readonly generator: Generator = new GeminiClient()) {}

  private async repo(): Promise<Repo> {
    return this.providedRepo ?? new (await import("./ai-suggestions.repo.js"))
      .AiSuggestionsRepo();
  }

  async generate(input: unknown) {
    if (!record(input) || !exactKeys(input, ["description"])) {
      throw new AppError(400, "VALIDATION_ERROR",
        "Enter only a bread description.");
    }
    const description = text(input.description, 500);
    if (!description || description.length < 10) {
      throw new AppError(400, "VALIDATION_ERROR",
        "Describe the bread in 10 to 500 characters.");
    }
    const context = await (await this.repo()).loadContext();
    const ingredientsByName = new Map(context.ingredients.map((ingredient) =>
      [key(ingredient.name), ingredient]));
    const drafts = validateDrafts(await this.generator.generate(
      promptFor(description, context)));
    return { suggestions: drafts.map((draft) => ({
      ...draft,
      recipe: draft.recipe.map((item) => {
        const match = ingredientsByName.get(key(item.ingredientName));
        return { ...item, ingredientId: match?.id ?? null,
          availability: !match ? "NOT_IN_INVENTORY" :
            match.availableGrams > 0 ? "AVAILABLE" : "OUT_OF_STOCK",
          availableGrams: match?.availableGrams ?? 0 };
      }),
    })) };
  }
}
