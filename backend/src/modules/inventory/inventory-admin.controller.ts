import type { RequestHandler } from "express";
import { AppError } from "../../shared/AppError.js";
import { InventoryAdminService } from "./inventory-admin.service.js";

export class InventoryAdminController {
  constructor(private readonly service: Pick<InventoryAdminService,
    "listCategories" | "listIngredients" | "listRecipes" | "listBatches" |
    "saveCategory" | "saveIngredient" | "replaceRecipe" | "receiveBatch" |
    "adjustBatch"> = new InventoryAdminService()) {}

  private actor(req: Parameters<RequestHandler>[0]): string {
    if (!req.auth) throw new AppError(401, "UNAUTHENTICATED", "Please sign in to continue.");
    return req.auth.userId;
  }

  listCategories: RequestHandler = async (_req, res) => {
    res.json({ data: await this.service.listCategories() });
  };
  listIngredients: RequestHandler = async (_req, res) => {
    res.json({ data: await this.service.listIngredients() });
  };
  listRecipes: RequestHandler = async (req, res) => {
    res.json({ data: await this.service.listRecipes(req.params.categoryId as string) });
  };
  listBatches: RequestHandler = async (req, res) => {
    res.json({ data: await this.service.listBatches(req.query) });
  };
  createCategory: RequestHandler = async (req, res) => {
    res.status(201).json({ data: await this.service.saveCategory(this.actor(req), req.body) });
  };
  updateCategory: RequestHandler = async (req, res) => {
    res.json({ data: await this.service.saveCategory(this.actor(req), req.body, req.params.categoryId as string) });
  };
  createIngredient: RequestHandler = async (req, res) => {
    res.status(201).json({ data: await this.service.saveIngredient(this.actor(req), req.body) });
  };
  updateIngredient: RequestHandler = async (req, res) => {
    res.json({ data: await this.service.saveIngredient(this.actor(req), req.body, req.params.ingredientId as string) });
  };
  replaceRecipe: RequestHandler = async (req, res) => {
    res.json({ data: await this.service.replaceRecipe(this.actor(req), req.params.categoryId as string, req.body) });
  };
  receiveBatch: RequestHandler = async (req, res) => {
    res.status(201).json({ data: await this.service.receiveBatch(this.actor(req), req.body) });
  };
  adjustBatch: RequestHandler = async (req, res) => {
    res.json({ data: await this.service.adjustBatch(this.actor(req), req.params.batchId as string, req.body) });
  };
}
