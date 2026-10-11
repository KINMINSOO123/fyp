# Module 6: Operation Reminders + Testing - Detailed Plan

**Build Order:** 7th (depends on Modules 0, 1, 2, 3, 4, 5)
**Status:** Detailed plan - ready for implementation
**Architecture:** View -> Controller -> Service -> Repo/External Adapter (see `../ARCHITECTURE.md`)

> See `MODULE.md` in this folder for the high-level plan. This README documents the concrete reminder and testing artifacts to build.

## Revision baseline (authoritative)

The test plan must cover the revised cross-module contracts in addition to reminders:

- `DataOrigin` validation and `DailySalesRecord` creation after successful simulation;
- System-Administrator-only candidate training, chronological evaluation, activation and previous-version restoration;
- MAE/RMSE/MAPE/R² zero-actual handling and simulation-based evaluation labelling;
- `ColdStartService` below 30 suitable records and configurable cold-start/confidence thresholds;
- stored-prediction simulation baseline, no double context, FIFO once and rollback/reversal;
- manager-confirmed donation/waste allocation and remaining leftover;
- weekly PDF/CSV reports plus preserved access/settings/audit/notification/device-token/FCM modules;
- Node.js-only PostgreSQL access and thin Express/FastAPI route modules.

---

## 1. Dependencies

| Artifact | Used For |
|---|---|
| Module 0 `notifications` table | Store reminder and alert rows |
| Module 0 `fcm_tokens` table | Send background push notifications |
| Module 0 `system_logs` table | Audit reminder emission and manual operation completion |
| Module 1 `notificationService.emit` | Shared notification entry point |
| Module 2 ML server `/predict` endpoint | Called only after manager presses Generate Prediction |
| Module 2 model lifecycle through Node.js | System-Administrator-only candidate training/evaluation/activation/restoration |
| Module 3 `recommendationEngine.generateRecommendation` | Runs after manual prediction generation |
| Module 4 `PosSimulationService.simulateDay` | Runs after manager presses Run POS Simulation |
| Module 5 dashboard | Hosts action buttons, reminder settings, and notification center |

---

## 2. Artifacts to Build

### Backend - Reminder Support

| # | Path | Layer | Purpose |
|---|---|---|---|
| 1 | `backend/src/services/operationReminderService.ts` | Service | Emits `prediction_reminder` and `simulation_reminder`; never runs prediction/simulation |
| 2 | `backend/src/controllers/reminderController.ts` | Controller | Optional endpoints for reminder settings and test emission |
| 3 | Update `backend/src/repositories/bakerySettingsRepo.ts` | Repo | Read/write predefined reminder times if stored in `bakery_settings` |
| 4 | Update `backend/src/services/notificationService.ts` | Service | Accept reminder notification types |

### Flutter - Manager Workflow

| # | Path | Layer | Purpose |
|---|---|---|---|
| 5 | `lib/features/dashboard/morning_view.dart` | View | Add/keep **Generate Tomorrow's Prediction** button |
| 6 | `lib/features/dashboard/evening_view.dart` | View | Add/keep **Run Today's POS Simulation** button |
| 7 | `lib/features/notifications/notifications_view.dart` | View | Show reminder notifications alongside other alerts |
| 8 | `lib/features/settings/reminder_settings_view.dart` | View | Optional controls for predefined reminder times |

### Testing

| # | Path | Layer | Purpose |
|---|---|---|---|
| 9 | `backend/tests/unit/services/operationReminderService.test.ts` | Test | Emits correct reminder type/title/message |
| 10 | `backend/tests/integration/reminderNotification.test.ts` | Test | Inserts notification row and broadcasts through FCM adapter mock |
| 11 | `backend/tests/integration/recommendationFlow.test.ts` | Test | Manual prediction -> recommendation |
| 12 | `backend/tests/integration/simulationFlow.test.ts` | Test | Manual simulation -> transactions/results/inventory |
| 13 | `backend/tests/integration/leftoverAllocationFlow.test.ts` | Test | Simulation leftovers → recommendation → manager-confirmed donation/waste |
| 14 | `backend/tests/e2e/managerDailyCycle.test.ts` | Test | Reminder -> manual prediction -> decision -> manual simulation -> dashboard |
| 15 | `ml_server/tests/unit/test_confidenceService.py` | Test | Confidence calculation |
| 16 | `ml_server/tests/integration/test_prediction_service.py` | Test | Prediction endpoint with supplied DTOs and no database |
| 17 | `ml_server/tests/integration/test_model_training_service.py` | Test | Candidate training from supplied validated DTOs |

---

## 3. Reminder Service Contract

```typescript
type ReminderKind = 'prediction_reminder' | 'simulation_reminder';

type ReminderInput = {
  kind: ReminderKind;
  scheduledFor: string; // ISO timestamp or HH:mm setting resolved to today
};

export async function emitOperationReminder(input: ReminderInput) {
  const copy = input.kind === 'prediction_reminder'
    ? {
        title: "Generate tomorrow's prediction",
        message: "It is time to generate the next demand prediction.",
      }
    : {
        title: "Run today's POS simulation",
        message: "It is time to simulate today's sales and update leftovers.",
      };

  return notificationService.emit({
    type: input.kind,
    severity: 'info',
    title: copy.title,
    message: copy.message,
    relatedId: null,
  });
}
```

Important rule:

```text
Reminder service -> notificationService only
Reminder service -> never calls prediction, recommendation, simulation, donation, or retrain services
```

---

## 4. Manual Operation Flow

### 4.1 Generate Tomorrow's Prediction

```text
Manager presses Generate Tomorrow's Prediction
  -> Flutter POST /api/predictions
  -> Node.js validates auth and fetches weather/calendar context
  -> Node.js calls ML server /predict
  -> Prediction rows are stored
  -> Recommendation engine reads prediction + inventory + recipes
  -> Dashboard shows recommended production quantity and options
  -> Manager records follows/reduces/overrides decision
```

If any prediction confidence is below the configurable threshold (initially 75%), the flow emits:

```text
type: low_confidence
severity: warning
message: Manager should use judgment before accepting the recommendation.
```

### 4.2 Run Today's POS Simulation

```text
Manager presses Run Today's POS Simulation
  -> Flutter POST /api/sales/simulate
  -> Node.js validates auth
  -> Simulation consumes manager-selected production decision when available
  -> Sales transactions, DailyResult and SIMULATION_GENERATED DailySalesRecord are written
  -> Stock-out alerts are emitted if lost_sales > 0
  -> System recommends leftover action; Bakery Manager confirms donation or waste
  -> Dashboard summaries refresh
```

---

## 5. E2E Test Scenario

```text
1. Seed bread categories, recipes, inventory, weather/calendar context, detailed DailyResult rows and validated SIMULATION_GENERATED DailySalesRecord history.
2. Emit prediction_reminder and assert a notification row exists.
3. Call manual prediction endpoint and assert daily_predictions are created.
4. Assert recommendation is generated from prediction + inventory, not financial values.
5. Record a production_decisions row.
6. Emit simulation_reminder and assert a notification row exists.
7. Call manual simulation endpoint and assert sales_transactions, daily_results, and financial snapshots are created.
8. Assert no donation/waste exists until manager confirmation; then verify allocation and dashboard summaries.
9. Assert no automatic prediction/simulation/retrain occurred before the manual calls.
```

---

## 6. Verification Checklist

| # | Check | Expected Result |
|---|---|---|
| 1 | `prediction_reminder` emitted | Notification center shows reminder; no prediction rows created by the reminder itself |
| 2 | `simulation_reminder` emitted | Notification center shows reminder; no sales rows created by the reminder itself |
| 3 | Generate prediction button pressed | Prediction and recommendation are created |
| 4 | Low confidence prediction forced | `low_confidence` warning appears |
| 5 | Run simulation button pressed | Sales/results/history update; donation/waste remains absent until manager confirmation |
| 6 | Search code for scheduler dependencies | No background workflow scheduler is required for the prototype |

---

## 7. Report Wording

Use this wording in the report or viva:

> The prototype uses manager-initiated prediction generation and POS simulation rather than fully automated scheduled jobs. Reminder notifications are sent at predefined times to guide the manager, but the manager remains responsible for triggering the workflow. This keeps deployment and UAT simple while preserving the core intelligent functions of demand prediction, inventory-aware recommendation, simulation, donation, and reporting. In a production system, these reminders could be upgraded into scheduled background jobs.

---

**Plan Status:** Complete. Ready for implementation on your signal.
