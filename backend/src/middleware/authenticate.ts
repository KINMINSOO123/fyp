import type { RequestHandler } from "express";
import { AppError } from "../shared/AppError.js";
import { AuthService } from "../modules/auth/auth.service.js";

export function createAuthenticate(
  authService: Pick<AuthService, "authenticate"> = new AuthService(),
): RequestHandler {
  return async (req, _res, next): Promise<void> => {
    const authorization = req.get("Authorization");

    const match = authorization?.match(/^Bearer ([^\s]+)$/i);

    if (!match) {
      throw new AppError(
        401,
        "UNAUTHENTICATED",
        "A Bearer token is required.",
      );
    }

    const accessToken = match[1];

    req.auth = await authService.authenticate(accessToken);
    next();
  };
}

export const authenticate = createAuthenticate();
