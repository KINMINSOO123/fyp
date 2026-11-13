import { GoogleGenAI } from "@google/genai";
import { AppError } from "../../shared/AppError.js";

const responseJsonSchema = {
  type: "object", additionalProperties: false, required: ["suggestions"],
  properties: { suggestions: { type: "array", minItems: 1, maxItems: 3,
    items: { type: "object", additionalProperties: false,
      required: ["name", "description", "reason", "recipe"],
      properties: {
        name: { type: "string" }, description: { type: "string" },
        reason: { type: "string" },
        recipe: { type: "array", minItems: 1, maxItems: 15,
          items: { type: "object", additionalProperties: false,
            required: ["ingredientName", "gramsPerBread"],
            properties: { ingredientName: { type: "string" },
              gramsPerBread: { type: "number", minimum: 0 } } } },
      } } } },
};

export class GeminiClient {
  async generate(prompt: string): Promise<unknown> {
    const apiKey = process.env.GEMINI_API_KEY?.trim();
    const model = process.env.GEMINI_MODEL?.trim() || "gemini-3.5-flash-lite";
    if (!apiKey) throw new AppError(503, "AI_NOT_CONFIGURED",
      "AI suggestions are not configured on the server.");
    if (!/^gemini-[a-z0-9.-]+$/.test(model)) throw new AppError(503,
      "AI_NOT_CONFIGURED", "The configured Gemini model is invalid.");
    try {
      const client = new GoogleGenAI({ apiKey });
      const response = await client.models.generateContent({
        model, contents: prompt,
        config: { responseMimeType: "application/json", responseJsonSchema,
          maxOutputTokens: 1600, temperature: 0.6,
          httpOptions: { timeout: 20000 } },
      });
      if (!response.text) throw new AppError(502, "AI_INVALID_RESPONSE",
        "The AI returned no usable suggestions. Please try again.");
      try { return JSON.parse(response.text) as unknown; }
      catch { throw new AppError(502, "AI_INVALID_RESPONSE",
        "The AI returned an invalid suggestion format. Please try again."); }
    } catch (error) {
      if (error instanceof AppError) throw error;
      const status = typeof error === "object" && error !== null &&
        "status" in error ? Number(error.status) : NaN;
      if (status === 429) throw new AppError(429, "AI_RATE_LIMITED",
        "Gemini's request limit was reached. Please try again later.");
      if (status === 401 || status === 403 || status === 404)
        throw new AppError(503, "AI_CONFIGURATION_INVALID",
          "The server's Gemini key or model is unavailable. Ask the administrator to check its configuration.");
      throw new AppError(503, "AI_UNAVAILABLE",
        "Gemini is temporarily unavailable. Please try again.");
    }
  }
}
