import { Router } from "express";
import { requireRole } from "../../middleware/requireRole.js";
import { PredictionController } from "./prediction.controller.js";

const router = Router();
const controller = new PredictionController();

router.post("/", requireRole("BAKERY_MANAGER"), controller.generate);
router.get("/next", controller.nextDay);
router.get("/:date", controller.listByDate);

export default router;
