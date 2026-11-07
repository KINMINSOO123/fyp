import { Router } from "express";
import { InventoryAdminController } from "./inventory-admin.controller.js";

const router = Router();
const controller = new InventoryAdminController();

router.get("/categories", controller.listCategories);
router.post("/categories", controller.createCategory);
router.patch("/categories/:categoryId", controller.updateCategory);
router.get("/categories/:categoryId/recipe", controller.listRecipes);
router.put("/categories/:categoryId/recipe", controller.replaceRecipe);
router.get("/ingredients", controller.listIngredients);
router.post("/ingredients", controller.createIngredient);
router.patch("/ingredients/:ingredientId", controller.updateIngredient);
router.get("/batches", controller.listBatches);
router.post("/batches", controller.receiveBatch);
router.patch("/batches/:batchId/stock", controller.adjustBatch);

export default router;
