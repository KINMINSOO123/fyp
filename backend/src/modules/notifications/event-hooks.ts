import type { BusinessEvent } from "./notification-event.service.js";
import { NotificationEventService } from "./notification-event.service.js";
import { randomUUID } from "node:crypto";
import { AppError } from "../../shared/AppError.js";

export type EventPublisher = Pick<NotificationEventService, "publish">;

// The operational transaction is already committed when this is called.
// A notification provider failure must not turn a committed mutation into an
// apparent business failure that the client might retry.
export async function publishBestEffort(publisher: EventPublisher,
  events: BusinessEvent[]): Promise<void> {
  const results = await Promise.allSettled(events.map((event) =>
    publisher.publish(event)));
  if (results.some((result) => result.status === "rejected")) {
    // Keep event payloads, device tokens and provider credentials out of logs.
    console.error("One or more notification events could not be recorded.");
  }
}

export async function publishFailureBestEffort(publisher: EventPublisher,
  error: unknown, scope: "PREDICTION" | "MODEL" | "SIMULATION") {
  if (error instanceof AppError && error.statusCode < 500) return;
  const type = scope === "MODEL" ? "MODEL_OPERATION_FAILURE" :
    error instanceof AppError && error.statusCode === 503 ?
      "EXTERNAL_SERVICE_FAILURE" : "SYSTEM_FAILURE";
  await publishBestEffort(publisher, [{ type, severity: "CRITICAL",
    title: `${scope.toLowerCase()} operation failed`,
    message: `A ${scope.toLowerCase()} operation failed. Review server status before retrying.`,
    eventKey: `failure:${scope}:${randomUUID()}` }]);
}
