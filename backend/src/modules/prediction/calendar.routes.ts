import { Router } from "express";
import { CalendarController } from "./calendar.controller.js";

const router = Router();
const controller = new CalendarController();
router.get("/", controller.list);
router.post("/", controller.add);
export default router;
