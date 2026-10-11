# Module 6: Operation Reminders + Testing

**Build Order:** 7th (depends on Modules 0, 1, 2, 3, 4, 5)
**Status:** High-Level Plan - ready for detailed breakdown
**Architecture:** View -> Controller -> Service -> Repo/External Adapter (see `../ARCHITECTURE.md`)

---

## 1. Goal

Build a **manager-controlled daily workflow** supported by reminder notifications and a full testing strategy.

This module no longer automates prediction generation, POS simulation, donation, or model retraining. Instead, the bakery manager manually triggers the important actions from the dashboard:

1. Generate tomorrow's demand prediction.
2. Review the smart recommendation and record the production decision.
3. Run today's POS simulation.
4. Review leftovers and confirm any donation or waste allocation.

Model training/evaluation/activation/restoration is separately and manually controlled by the System Administrator.

The system may send reminder notifications at predefined times, but those reminders only prompt the manager. They do not execute the workflow automatically.

---

## 2. Dependencies

- **Module 0 (Data Foundation)** - needs `notifications`, `fcm_tokens`, `system_logs`, and reminder-related settings in `bakery_settings` or constants
- **Module 1 (Node.js Middleware)** - needs `notificationService`, `pushService`, `notificationRepo`, and `fcmTokenRepo`
- **Module 2 (ML Prediction)** - exposes prediction plus candidate training/evaluation APIs; Node.js restricts model lifecycle actions to the System Administrator
- **Module 3 (Inventory + Integration)** - provides smart recommendation and production decision capture
- **Module 4 (POS Simulation)** - exposes manual simulation trigger
- **Module 5 (Donation + Dashboard)** - provides dashboard buttons, notification center, and summary views
- **`../ARCHITECTURE.md`** - defines the layered pattern this module follows

---

## 3. Sub-Modules

| # | Sub-Module | Layer | Purpose |
|---|---|---|---|
| 6.1 | Operation Reminder Settings | Model/Config | Store predefined reminder times, e.g. prediction reminder time and simulation reminder time |
| 6.2 | Operation Reminder Service | Service | Emits `prediction_reminder` and `simulation_reminder` notifications at the configured times |
| 6.3 | Manual Prediction Trigger Test | Test | Verifies manager-initiated prediction flow: dashboard/API -> ML `/predict` -> stored prediction -> recommendation |
| 6.4 | Manual Simulation Trigger Test | Test | Verifies manager-initiated simulation flow: dashboard/API -> POS simulation -> leftovers/donation/dashboard |
| 6.5 | Reminder Notification Test | Test | Verifies reminders are emitted at the configured time and do not run prediction/simulation automatically |
| 6.6 | Unit Tests | Test | Pure function tests with Vitest + pytest |
| 6.7 | Integration Tests | Test | Multi-service + real DB tests with Vitest |
| 6.8 | E2E Test | Test | Full manager-controlled daily cycle plus administrator model lifecycle |
| 6.9 | Provenance/Evaluation Test | Test | Verifies DataOrigin, chronological holdout, zero-actual metric handling and simulation-based labels |

---

## 4. Resolved Decisions

| # | Decision | Choice | Rationale |
|---|---|---|---|
| 1 | Daily workflow trigger | Manual manager actions | Easier to deploy, test, demonstrate, and defend for a student FYP |
| 2 | Reminder behavior | Notify only; never execute core operations | Keeps the system helpful without adding background automation complexity |
| 3 | Reminder types | `prediction_reminder`, `simulation_reminder` | Makes notification rows clear and auditable |
| 4 | Low-confidence behavior | Emit `low_confidence` below a configurable threshold, initially 75% | Manager still makes the final decision; final confidence formula remains unapproved |
| 5 | Testing frameworks | Vitest (Node.js) + pytest (Python) | Modern, fast, good TypeScript support / standard Python |

---

## 5. Reminder Flow

| Reminder | Example Time | Notification Type | Manager Action |
|---|---|---|---|
| Prediction reminder | 6:00 AM daily | `prediction_reminder` | Tap notification -> open dashboard -> press **Generate Tomorrow's Prediction** |
| Simulation reminder | 6:00 PM daily | `simulation_reminder` | Tap notification -> open dashboard -> press **Run Today's POS Simulation** |

The reminder service must not call:

- `ML_SERVER_URL/predict`
- `ML_SERVER_URL/retrain`
- `PosSimulationService.simulateDay`
- `LeftoverManagementService.recordDonation` or `recordWaste`
- `recommendationEngine.generateRecommendation`

Those calls happen only after an authenticated manager action.

---

## 6. Manager-Controlled Daily Cycle

```text
Configured morning time
  -> System emits prediction_reminder notification
  -> Manager taps notification or opens dashboard
  -> Manager presses Generate Tomorrow's Prediction
  -> Module 2 creates prediction
  -> Module 3 creates inventory-aware recommendation
  -> Manager records production decision

Configured evening time
  -> System emits simulation_reminder notification
  -> Manager taps notification or opens dashboard
  -> Manager presses Run Today's POS Simulation
  -> Module 4 records sales, stock-outs, financial snapshots, DailyResult and SIMULATION_GENERATED DailySalesRecord
  -> Module 5 recommends leftover action
  -> Manager confirms donation or waste; remaining unallocated leftover updates
```

If prediction confidence is below 75%, the prediction flow emits `low_confidence` through Module 1's `notificationService`. This is an advisory alert, not an automatic override.

---

## 7. File Structure

```text
backend/src/
  services/
    operationReminderService.ts     # Emits reminder notifications only
    ... existing services from Modules 1, 3, 4, 5
  controllers/
    reminderController.ts           # Optional settings/test endpoints for reminders
  ... existing app structure

backend/tests/
  unit/
    services/
      operationReminderService.test.ts
      ingredientCalculator.test.ts
      constraintChecker.test.ts
      salesDistributionService.test.ts
      recommendationEngine.test.ts
  integration/
    recommendationFlow.test.ts
    simulationFlow.test.ts
    donationFlow.test.ts
    reminderNotification.test.ts
  e2e/
    managerDailyCycle.test.ts

ml_server/tests/
  unit/
    test_confidenceService.py
    test_coldStartService.py
    test_featureEngineering.py
    test_evaluationService.py
  integration/
    test_predictService.py
    test_trainService.py
  conftest.py
```

---

## 8. Testing Strategy

| Level | Scope | Framework | DB? | Example |
|---|---|---|---|---|
| Unit | Pure functions, no DB | Vitest / pytest | No | `calculateMaxProducible`, `distributeSold`, `calculate_confidence` |
| Integration | Multiple services + real DB | Vitest | Yes | Recommendation flow, simulation flow, donation flow, reminder notification flow |
| E2E | Full manager-controlled daily cycle | Vitest | Yes + ML server | Reminder -> manual prediction -> decision capture -> manual simulation -> donation/dashboard |
| UAT | Supervisor/friends operate the app | Manual checklist | Demo DB | Press the two main buttons and verify the dashboard updates |

---

## 9. Integration Points

| Talks To | Direction | Purpose |
|---|---|---|
| Module 1 `notificationService` | Internal call | Emit prediction/simulation reminders and low-confidence alerts |
| Module 2 ML server through FastApiMlClient | HTTP | Prediction plus System-Administrator-initiated candidate training/evaluation; activation/restoration stays in Node.js |
| Module 3 recommendationEngine | Internal call | Runs after manager generates prediction |
| Module 4 `PosSimulationService` | Internal call | Runs after manager presses simulation button |
| Module 5 dashboard | UI | Shows buttons, reminders, results, and notification center |
| Supabase `system_logs` | Repo call | Audit manual operation and reminder events |

---

## 10. What This Module Does NOT Include

- Automatic prediction generation
- Automatic POS simulation
- Automatic donation
- Automatic nightly model retraining
- Background scheduler setup for running core workflows automatically

Prototype report wording:

> In the prototype implementation, prediction generation and POS simulation are manually initiated by the bakery manager to simplify deployment, testing, and demonstration. The system sends reminder notifications at predefined times so the manager knows when to run each process. In a production environment, these operations could be automated using scheduled background jobs.

Required revised assertions:

- fewer than 30 suitable `DailySalesRecord` rows selects `ColdStartService`;
- candidate training is rejected for a Bakery Manager and allowed for a System Administrator;
- activation is impossible before valid evaluation; previous valid version restoration is audited;
- chronological holdout ordering is enforced;
- zero actuals remain in MAE/RMSE and are excluded only from MAPE;
- any evaluation containing `SIMULATION_GENERATED` rows is labelled simulation-based;
- POS context is not multiplied into the stored prediction again;
- FIFO is deducted exactly once and reversed/rolled back on a later failure;
- no donation/waste is created before manager confirmation, and combined allocation cannot exceed leftover;
- weekly report PDF/CSV export and user/settings/audit/notification/device-token/FCM plans remain covered.

---

**Module Status:** High-level plan complete. Ready for detailed breakdown on your signal.
