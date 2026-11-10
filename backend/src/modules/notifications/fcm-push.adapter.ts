import { createSign } from "node:crypto";
import { readFile } from "node:fs/promises";

type ServiceAccount = { project_id: string; client_email: string;
  private_key: string };
type Fetch = typeof fetch;

function encoded(value: unknown): string {
  return Buffer.from(JSON.stringify(value)).toString("base64url");
}

export class FcmPushAdapter {
  private cached?: { token: string; expiresAt: number };
  constructor(private readonly transport: Fetch = fetch,
    private readonly credentialsPath = process.env.GOOGLE_APPLICATION_CREDENTIALS) {}

  private async credentials(): Promise<ServiceAccount> {
    if (!this.credentialsPath) throw new Error("FCM_NOT_CONFIGURED");
    const source = JSON.parse(await readFile(this.credentialsPath, "utf8")) as
      Partial<ServiceAccount>;
    if (typeof source.project_id !== "string" ||
        typeof source.client_email !== "string" ||
        typeof source.private_key !== "string") {
      throw new Error("FCM_NOT_CONFIGURED");
    }
    return source as ServiceAccount;
  }

  private async accessToken(account: ServiceAccount): Promise<string> {
    if (this.cached && this.cached.expiresAt > Date.now() + 60_000) {
      return this.cached.token;
    }
    const issued = Math.floor(Date.now() / 1000);
    const payload = `${encoded({ alg: "RS256", typ: "JWT" })}.${encoded({
      iss: account.client_email,
      scope: "https://www.googleapis.com/auth/firebase.messaging",
      aud: "https://oauth2.googleapis.com/token",
      iat: issued, exp: issued + 3600,
    })}`;
    const signer = createSign("RSA-SHA256");
    signer.update(payload);
    const jwt = `${payload}.${signer.sign(account.private_key).toString("base64url")}`;
    const response = await this.transport("https://oauth2.googleapis.com/token", {
      method: "POST", headers: { "Content-Type":
        "application/x-www-form-urlencoded" },
      body: new URLSearchParams({ grant_type:
        "urn:ietf:params:oauth:grant-type:jwt-bearer", assertion: jwt }),
      signal: AbortSignal.timeout(5000),
    });
    if (!response.ok) throw new Error("FCM_AUTH_FAILED");
    const body = await response.json() as Record<string, unknown>;
    if (typeof body.access_token !== "string" ||
        typeof body.expires_in !== "number") throw new Error("FCM_AUTH_FAILED");
    this.cached = { token: body.access_token,
      expiresAt: Date.now() + body.expires_in * 1000 };
    return body.access_token;
  }

  async send(token: string, title: string, message: string):
    Promise<{ providerMessageId: string }> {
    const account = await this.credentials();
    const accessToken = await this.accessToken(account);
    const response = await this.transport(
      `https://fcm.googleapis.com/v1/projects/${encodeURIComponent(account.project_id)}/messages:send`, {
        method: "POST",
        headers: { Authorization: `Bearer ${accessToken}`,
          "Content-Type": "application/json" },
        body: JSON.stringify({ message: { token,
          notification: { title, body: message } } }),
        signal: AbortSignal.timeout(5000),
      });
    if (!response.ok) {
      const body = await response.json().catch(() => null) as
        { error?: { details?: Array<{ errorCode?: string }> } } | null;
      if (body?.error?.details?.some((item) =>
        item.errorCode === "UNREGISTERED")) throw new Error("FCM_UNREGISTERED");
      throw new Error("FCM_SUBMISSION_FAILED");
    }
    const body = await response.json() as { name?: unknown };
    if (typeof body.name !== "string" || !body.name) {
      throw new Error("FCM_SUBMISSION_FAILED");
    }
    // Provider acceptance proves submission, not delivery or reading.
    return { providerMessageId: body.name };
  }
}
