import assert from "node:assert/strict";
import { test } from "node:test";
import { AppError } from "../../shared/AppError.js";
import { AiSuggestionsService, validateDrafts } from "./ai-suggestions.service.js";

const context = {
  categories: [{ name: "Coconut Bun", description: "Sweet bun",
    recipe: [{ ingredientName: "Flour", gramsPerBread: 65 }] }],
  ingredients: [
    { id: "flour-id", name: "Flour", availableGrams: 500 },
    { id: "yeast-id", name: "Yeast", availableGrams: 0 },
  ],
};
const draft = { suggestions: [{ name: "Pandan Bun",
  description: "Soft pandan bread", reason: "Similar to the bakery's sweet buns",
  recipe: [
    { ingredientName: "Flour", gramsPerBread: 60 },
    { ingredientName: "Yeast", gramsPerBread: 3 },
    { ingredientName: "Pandan paste", gramsPerBread: 4 },
  ] }] };

test("AI suggestions use catalogue context and exactly one provider request", async () => {
  const calls: string[] = [];
  const service = new AiSuggestionsService(
    { async loadContext() { return context; } },
    { async generate(prompt) { calls.push(prompt); return draft; } },
  );
  const result = await service.generate({ description: "A pandan coconut bun" });
  assert.equal(calls.length, 1);
  assert.match(calls[0]!, /Coconut Bun/);
  assert.match(calls[0]!, /available valid grams/);
  assert.deepEqual(result.suggestions[0]?.recipe.map((item) => item.availability),
    ["AVAILABLE", "OUT_OF_STOCK", "NOT_IN_INVENTORY"]);
  assert.equal(result.suggestions[0]?.recipe[2]?.ingredientId, null);
});

test("invalid request fields never call Gemini", async () => {
  let called = 0;
  const service = new AiSuggestionsService(
    { async loadContext() { return context; } },
    { async generate() { called++; return draft; } },
  );
  for (const input of [null, { description: "short" },
    { description: "A coconut-style bun", role: "SYSTEM_ADMINISTRATOR" },
    { description: "x".repeat(501) }]) {
    await assert.rejects(service.generate(input), (error) =>
      error instanceof AppError && error.code === "VALIDATION_ERROR");
  }
  assert.equal(called, 0);
});

test("invalid provider recipes are rejected before display", () => {
  const base = draft.suggestions[0]!;
  for (const recipe of [
    [{ ingredientName: "Flour", gramsPerBread: 0 }],
    [{ ingredientName: "Flour", gramsPerBread: 2001 }],
    [{ ingredientName: "Flour", gramsPerBread: 2 },
      { ingredientName: "flour", gramsPerBread: 3 }],
  ]) {
    assert.throws(() => validateDrafts({ suggestions: [{ ...base, recipe }] }),
      (error) => error instanceof AppError && error.code === "AI_INVALID_RESPONSE");
  }
  assert.throws(() => validateDrafts({ suggestions: Array(4).fill(base) }),
    (error) => error instanceof AppError && error.code === "AI_INVALID_RESPONSE");
});
