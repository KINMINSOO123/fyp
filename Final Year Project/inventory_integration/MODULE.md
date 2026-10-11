# Module 3: Inventory and Production Recommendations — Proposed Module Plan

Reconciled on 2026-10-11 against the latest `RSW_SooKinMin_Project1 (1).docx`, Sections 1.4.2, 3.5–3.6, 4.5.3–4.5.4, 4.7.2, 4.8 and 4.9.3. These components and checks are proposed for the Flutter starter repository, not implemented functionality. See the [detailed plan](README.md), [architecture](../ARCHITECTURE.md), [schema](../../database_canonical_design.md) and [traceability](../../planning_documents_change_report.md).

## 1. Scope, mapping and permissions

Technical Module 3 delivers **Inventory and Smart Production Recommendation** and contributes to **Reporting and Dashboard**, **Alerts and Notifications** and **System Administration**. The report's eight functional modules coexist with build modules 0–6.

System Administrators manage ingredients, batches, categories and recipes. Bakery Managers review recommendations and confirm/revise production. Administrators do not inherit manager actions. Both roles can view permitted reports; validate JWT and an ACTIVE stored profile before role checks. Roles and actor IDs come from Node, not request fields.

Operations cover configured active categories, including up to 20 in the reference workload. Four bread categories/five ingredients are example seeds. This module consumes stored predictions; prediction generation, cost-based production optimization, automatic buffers and background scheduling are outside its responsibilities.

## 2. Dependencies and planned components

Module 0 supplies normalized recipes, batches/cost snapshots, movements, decisions and unique prediction → decision → production → result links. Module 1 supplies Controller → Service → Repo boundaries and recipient notifications. Module 2 supplies stored predictions with mode-dependent confidence. Module 4 uses inventory logic inside its single atomic POS transaction.

| Component | Responsibility |
|---|---|
| `InventoryController`, `RecipeController` | Administrator mutations and permitted reads through Services |
| `RecommendationController`, `ProductionDecisionController` | Manager recommendation and confirmation workflow |
| `InventoryService`, `RecipeService` | Validated administration, snapshots/movements and auditing |
| `RecommendationEngine` | Reserve outstanding commitments and allocate shared balances in display order |
| `ProductionDecisionService` | Validate combined requirements and replace revised quantities atomically; no deduction |
| `FifoBatchService` | Valid receipt-ordered batch movements inside the POS transaction |
| `IngredientCostService` | Reporting-only actual FIFO movement costs using immutable batch snapshots |
| `InventoryRepo`, `InventoryBatchRepo`, `InventoryLogRepo`, `RecipeRepo`, `IngredientRepo`, `BreadCategoryRepo`, `DailyPredictionRepo`, `ProductionDecisionRepo` | Node persistence and transaction-scoped consistent reads/writes |
| `InventoryView`, `RecipeView`, `ProductionPlanningView` | Role-appropriate administration, confirmation and validation feedback |

Flutter uses Node for business CRUD. Supabase Authentication, recipient-only foreground Realtime and FCM background notifications remain explicit platform exceptions. FastAPI has no database access.

## 3. Joint production feasibility

For the production date, build a temporary balance from valid active batches, excluding expired batches and batches received after that date. First subtract all confirmed but unprocessed decisions for that date. If commitments exceed stock, report shortages and require correction.

Process unconfirmed categories in ascending `display_order`. For each category, `max_producible` is the minimum of `floor(remaining_grams / grams_per_unit)` over recipe ingredients. Recommend `min(predicted_units_sold, max_producible)`. Subtract its requirements before evaluating the next category. Missing/invalid recipes are configuration errors, not unlimited capacity.

On confirmation/revision, validate all outstanding decisions using the proposed quantity. Replace the previous quantity rather than counting both versions. Require a reason when changing the recommendation and recalculate affected recommendations. A feasible manager override above prediction is permitted with a reason; the system adds no automatic buffer. Options are `ACCEPT_RECOMMENDATION`, `REDUCE`, `MANUAL_OVERRIDE`.

Planning/confirmation changes no inventory or movement rows. A decision with committed `daily_production` is processed and excluded from outstanding commitments. POS revalidates current stock.

## 4. FIFO and cost

FIFO excludes expired/inactive batches and consumes valid batches by ascending `received_date`, then `id`. Expiry determines eligibility, not ordering. Expiry-first ordering is FEFO. The FIFO index is `(ingredient_id, received_date, id) WHERE status = 'ACTIVE'`; a separate expiry index supports alerts.

Movements retain `batch_id`, signed `change_grams`, `production_decision_id` and `operation_id`. Batch `unit_cost` is the immutable receipt snapshot, normalized in the proposed schema to MYR/kg. `IngredientCostService.calculateFromMovements` sums `abs(change_grams) / 1000 * batch.unit_cost` for production deductions. Current ingredient-master prices never replace these snapshots. Costs are reporting-only and cannot change predictions/recommendations.

## 5. Notifications and reports

Low-stock, expiry and external/system-failure events use `NotificationService` with intended `recipient_user_id`, per-type preferences and recipient-owned active FCM tokens. Recipient-only Supabase Realtime exposes relevant foreground events; Node owns writes/mark-read. Delivery states are PENDING, SUBMITTED, DELIVERED, FAILED and SKIPPED; submission is not delivery proof.

Manually requested weekly/other reports and Views share calculations. Inventory value and production cost retain batch cost history. Leftovers, donations and discarded waste remain distinct.

## 6. Implementation and verification plan

Implement later: schema/DTO invariants and Repos; administrator catalogue/restock services; shared-balance recommendations and serialized confirmation; FIFO movements/costs; atomic POS integration; Views; recipient events/reports; meaningful checks.

The [README](README.md) supplies algorithms, shared-ingredient examples, endpoints, SQL sketches and tests for concurrent commitments, replacement revisions, processed decisions, eligibility, FIFO versus FEFO, cost snapshots, cross-role rejection and 15-second recommendation performance. This planning change runs no migration or application test.
