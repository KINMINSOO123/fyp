import { Router } from "express";
import { ProfileController } from "./profile.controller.js";

const profileRouter = Router();
const profileController = new ProfileController();

profileRouter.get("/me", profileController.getMe);
profileRouter.patch("/me", profileController.updateMe);

export default profileRouter;