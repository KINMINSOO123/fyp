import { Router } from "express";
import { KlHolidayController } from "./kl-holiday.controller.js";

const router = Router();
const controller = new KlHolidayController();
router.get("/", controller.list);
router.post("/refresh", controller.refresh);
export default router;
