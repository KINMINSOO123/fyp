import { Router } from "express";
import { InventoryAdminController } from "./inventory-admin.controller.js";
import { requireRole } from "../../middleware/requireRole.js";

export function createInventoryRouter(controller = new InventoryAdminController()) {
const router = Router();

router.get("/categories", controller.listCategories);
router.post("/categories", requireRole("SYSTEM_ADMINISTRATOR"), controller.createCategory);
router.patch("/categories/:categoryId", requireRole("SYSTEM_ADMINISTRATOR"), controller.updateCategory);
router.get("/categories/:categoryId/recipe", controller.listRecipes);
router.put("/categories/:categoryId/recipe", requireRole("SYSTEM_ADMINISTRATOR"), controller.replaceRecipe);
router.get("/ingredients", controller.listIngredients);
router.post("/ingredients", requireRole("SYSTEM_ADMINISTRATOR"), controller.createIngredient);
router.patch("/ingredients/:ingredientId", requireRole("SYSTEM_ADMINISTRATOR"), controller.updateIngredient);
router.get("/batches", controller.listBatches);
router.post("/batches", requireRole("BAKERY_MANAGER"), controller.receiveBatch);
router.patch("/batches/:batchId/stock", requireRole("BAKERY_MANAGER"), controller.adjustBatch);

return router;
}

export default createInventoryRouter();
