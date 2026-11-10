import { Router } from "express";
import { requireRole } from "../../middleware/requireRole.js";
import { PosSimulationController } from "./pos-simulation.controller.js";

const router = Router();
const controller = new PosSimulationController();

router.post("/", requireRole("BAKERY_MANAGER"), controller.run);
router.get("/today", controller.getToday);
router.get("/:date/transactions", controller.getTransactions);
router.get("/:date", controller.getResult);

export default router;
