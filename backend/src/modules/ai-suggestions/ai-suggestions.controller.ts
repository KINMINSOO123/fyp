import type { RequestHandler } from "express";
import { AiSuggestionsService } from "./ai-suggestions.service.js";
import { AiReviewService } from "./ai-review.service.js";

export class AiSuggestionsController {
  constructor(private readonly service: Pick<AiSuggestionsService, "generate"> =
    new AiSuggestionsService(), private readonly review: Pick<AiReviewService,
      "catalogue" | "create"> = new AiReviewService()) {}
  generate: RequestHandler = async (req, res) => {
    res.json({ data: await this.service.generate(req.body) });
  };
  reviewCatalogue: RequestHandler = async (_req, res) => {
    res.json({ data: await this.review.catalogue() });
  };
  createReviewed: RequestHandler = async (req, res) => {
    res.status(201).json({ data: await this.review.create(req.auth!.userId, req.body) });
  };
}
