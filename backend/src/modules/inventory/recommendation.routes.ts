import { Router } from "express";
import { RecommendationController } from "./recommendation.controller.js";

const router = Router();
const controller = new RecommendationController();

router.get("/recommendations/:date", controller.getPlan);
router.put("/production-decisions", controller.confirm);

export default router;
