import { Router } from "express";
import { requireRole } from "../../middleware/requireRole.js";
import { CharityPartnerController, LeftoverManagementController } from
  "./leftover.controller.js";

export const leftoverRouter = Router();
export const donationRouter = Router();
export const wasteRouter = Router();
export const charityAdminRouter = Router();
const leftovers = new LeftoverManagementController();
const charities = new CharityPartnerController();

leftoverRouter.get("/", leftovers.list);
leftoverRouter.get("/charities", requireRole("BAKERY_MANAGER"),
  leftovers.activeCharities);
leftoverRouter.get("/:resultId/recommendation", requireRole("BAKERY_MANAGER"),
  leftovers.recommendation);
donationRouter.get("/", leftovers.listDonations);
donationRouter.post("/", requireRole("BAKERY_MANAGER"), leftovers.donate);
donationRouter.patch("/:donationId/status", requireRole("BAKERY_MANAGER"),
  leftovers.advanceDonation);
wasteRouter.post("/", requireRole("BAKERY_MANAGER"), leftovers.recordWaste);
charityAdminRouter.get("/", charities.list);
charityAdminRouter.post("/", charities.create);
charityAdminRouter.patch("/:partnerId", charities.update);
