import { Router } from "express";
import { AiSuggestionsController } from "./ai-suggestions.controller.js";

const router = Router();
const controller = new AiSuggestionsController();
router.post("/", controller.generate);
router.get("/review-context", controller.reviewCatalogue);
router.post("/reviewed", controller.createReviewed);
export default router;
