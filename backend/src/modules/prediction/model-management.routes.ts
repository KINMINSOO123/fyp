import { Router } from "express";
import { ModelManagementController } from "./model-management.controller.js";

const router = Router();
const controller = new ModelManagementController();

router.get("/", controller.list);
router.get("/categories", controller.categories);
router.get("/:modelVersionId", controller.detail);
router.post("/train", controller.train);
router.post("/:modelVersionId/evaluate", controller.evaluate);
router.post("/:modelVersionId/activate", controller.activate);
router.post("/:modelVersionId/restore", controller.restore);

export default router;
