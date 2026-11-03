import type { RequestHandler } from "express";
import { UserAdministrationService } from "./user-administration.service.js";
import { AppError } from "../../shared/AppError.js";

export class UserAdministrationController {
  private readonly userService = new UserAdministrationService();

  listUsers: RequestHandler = async (req, res): Promise<void> => {
    const result = await this.userService.listUsers(req.query);

    res.json({
      data: result.users,
      pagination: {
        page: result.page,
        pageSize: result.pageSize,
        total: result.total,
      },
    });
  };

  createUser: RequestHandler = async (req, res): Promise<void> => {
    const actor = req.auth;

    if (!actor) {
      throw new AppError(
        401,
        "UNAUTHENTICATED",
        "Please sign in to continue.",
      );
    }

    const createdUser = await this.userService.createUser(
      actor.userId,
      req.body,
    );

    res.status(201).json({
      data: createdUser,
    });
  };

  updateUser: RequestHandler = async (req, res): Promise<void> => {
    const actor = req.auth;

    if (!actor) {
      throw new AppError(
        401,
        "UNAUTHENTICATED",
        "Please sign in to continue.",
      );
    }

    const targetUserId = req.params.userId;

    if (typeof targetUserId !== "string") {
      throw new AppError(
        400,
        "VALIDATION_ERROR",
        "A valid user ID is required.",
      );
    }

    const updatedUser = await this.userService.updateUser(
      actor.userId,
      targetUserId,
      req.body,
    );

    res.json({
      data: updatedUser,
    });
  };
}