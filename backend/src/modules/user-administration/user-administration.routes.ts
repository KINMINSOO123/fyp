import { Router } from "express";
import { UserAdministrationController } from "./user-administration.controller.js";

const userAdministrationRouter = Router();
const controller = new UserAdministrationController();

userAdministrationRouter.get("/", controller.listUsers);
userAdministrationRouter.post("/", controller.createUser);
userAdministrationRouter.patch("/:userId", controller.updateUser);

export default userAdministrationRouter;