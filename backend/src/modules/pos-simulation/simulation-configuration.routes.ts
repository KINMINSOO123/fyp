import { Router } from "express";
import { SimulationConfigurationController } from
  "./simulation-configuration.controller.js";

const router = Router();
const controller = new SimulationConfigurationController();
router.get("/", controller.get);
router.put("/baselines/:categoryId", controller.baseline);
router.patch("/scenario", controller.scenario);
export default router;
