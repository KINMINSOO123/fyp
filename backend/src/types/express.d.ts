import type { UserProfile } from "../modules/profile/profile.model.js";

declare global {
  namespace Express {
    interface Request {
      auth?: UserProfile;
    }
  }
}