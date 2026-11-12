# Module 3: Inventory and Production Recommendations — Detailed Proposed Design

**Design revision - 2026-10-16:** At the user's request, FEFO replaces the report's FIFO policy: eligible batches are consumed by `expiry_date ASC, received_date ASC, id ASC`. The DOCX/report mirror remain unchanged; this is an explicit departure from Sections 4.5.3-4.5.4 and 4.9.3, including BR-INV-05/FR-INV-06. Other report requirements still apply.

Reconciled on 2026-10-11 from the latest `RSW_SooKinMin_Project1 (1).docx`, especially FR-INV-01–12, Sections 4.5.3–4.5.4, Table 4.27 and Sections 4.7.2/4.9.3. That is a historical design audit. **Current local status (2026-11-11):** Node and Flutter additionally implement the user-requested restock preview, request and administrator receipt/review flow. `20261111000100_restock_requests.sql` is staged, not applied or live-verified. This extension requires a separate report revision; it is not claimed as an original report requirement.

See [module mapping](MODULE.md), [architecture](../ARCHITECTURE.md), [canonical schema](../../database_canonical_design.md), [logical design](../../logical_view_canonical_design.md), [POS transaction](../pos_simulation/README.md) and [traceability](../../planning_documents_change_report.md).

## 1. Ownership, permissions and data

Technical Module 3 delivers Inventory and Smart Production Recommendation and supports reporting, alerts and administration. It serves one bakery on Android, operating over configured active categories and ingredients. Four categories and five ingredients are example seeds; the reference workload includes up to 20 active categories.

| Capability | Role | Planned boundary |
|---|---|---|
| Ingredient/category/recipe administration | SYSTEM_ADMINISTRATOR | Implemented `InventoryAdminController → InventoryAdminService → InventoryAdminRepo`; staged RPC for atomic writes |
| Batch receipt/restock and stock removal | SYSTEM_ADMINISTRATOR | Same implemented Node boundary; staged atomic batch/snapshot/movement/audit RPC |
| Restock request and desired-stock preview | BAKERY_MANAGER | `RestockController → RestockService → RestockRepo`; server derives desired quantities and shortage |
| Restock review, linked receipt and cancellation | SYSTEM_ADMINISTRATOR | `RestockAdminScreen`; existing `POST /api/admin/inventory/batches` receipt path with optional request item/key; staged atomic wrapper RPC |
| Recommendation review | BAKERY_MANAGER | `RecommendationController → RecommendationEngine` |
| Production confirmation/revision | BAKERY_MANAGER | `ProductionDecisionController → ProductionDecisionService` |
| Permitted inventory/report viewing | Both ACTIVE roles | Read Service/Repo DTOs |
| Production ingredient deduction | Internal to manager-authorized POS | `TransactionRecordingService`, `SimulationCommitRepo`, `FefoBatchService` |

Every request validates JWT and the ACTIVE stored profile before permissions. Administrator accounts cannot confirm production; manager accounts cannot mutate catalogue/inventory. Never accept actor, role or feasibility claims from the client. Flutter ordinary CRUD uses Node. Supabase Auth, recipient-only foreground Realtime and FCM background notifications remain platform exceptions; FastAPI has no database access.

Recipes store positive `grams_per_unit`. Ingredient inventory, batches and movements use grams. Whole-product quantities are nonnegative integers. `inventory` is a maintained cache, while date-specific batch eligibility is the production source of truth. Batch `unit_cost` is an immutable receipt snapshot, normalized in this plan to MYR/kg. Current ingredient master prices remain separate reporting configuration.

## 2. Planned Services, Repos and interfaces

| Class | Planned method/responsibility |
|---|---|
| `InventoryService` | `getInventory(date)`, `recordBatch(input, actor)`, `adjustBatch(input, actor)`; validate and atomically update batches, snapshots, movements and audit |
| `InventoryAdminController`, `InventoryAdminService`, `InventoryAdminRepo` | Implemented administrator-only catalogue/recipe/batch API; strict input validation; staged `apply_inventory_admin_change_with_audit` RPC |
| `RecipeService` | Read/validate one recipe specification per category; administrator changes with positive quantities and unique category–ingredient pairs |
| `RecommendationEngine` | `recommend(targetDate)`; read stored predictions and build one shared temporary ingredient balance |
| `ProductionDecisionService` | `confirmOrRevise(input, actor)`; joint feasibility, replacement quantity, required reason, serialized confirmation |
| `FefoBatchService` | `consumeWithinTransaction(transaction, decisions, targetDate)`; exact expiry-ordered batch movements validated and applied through transaction-scoped Repos |
| `IngredientCostService` | `calculateFromMovements(movements, batchSnapshots)`; reporting-only consumption costs grouped by production decision |
| `InventoryRepo`, `InventoryBatchRepo`, `InventoryLogRepo` | Inventory/batch/movement reads and transaction-scoped writes/locks |
| `IngredientRepo`, `BreadCategoryRepo`, `RecipeRepo` | Catalogue/configuration persistence and deterministic category order |
| `DailyPredictionRepo`, `ProductionDecisionRepo`, `DailyProductionRepo` | Stored prediction, outstanding commitments and processed-state lookup |

Controllers delegate to Services. Services use Repos for PostgreSQL; route modules only register class handlers. No `RecommendationEngine` method generates predictions, calls FastAPI or trains a model. Financial values never determine production quantities.

## Restock request extension - 2026-11-11

This is a user-requested technical extension to the report's inventory flow. The `SYSTEM_ADMINISTRATOR` is the bakery business administrator, not a separate IT-only account. `EXT-RST-01` covers joint desired-quantity shortages; `EXT-RST-02` covers manager-confirmed requests and duplicate prevention; `EXT-RST-03` covers recipient administrator notification; `EXT-RST-04` covers linked partial batch receipts; `EXT-RST-05` covers audited cancellation of outstanding grams; and `EXT-RST-06` covers role enforcement. These are local extension IDs, not IDs claimed to occur in the current report.

`GET /api/restock-requests/preview/:date` shows each unprocessed category's desired units: confirmed manager-selected units where a decision exists, otherwise the stored prediction. It sums each recipe's grams across all categories before comparing with valid batch stock on the production date. Processed production is excluded because its stock was already deducted. The preview reports `requiredGrams`, `availableGrams` and positive `additionalGrams` per ingredient even when the sequential production recommendation is feasible at a lower quantity. It does not reserve stock.

The manager sees the date, desired units and ingredient shortfalls in Production Planning and explicitly confirms `POST /api/restock-requests` with the displayed snapshot. Node recomputes it and the staged `submit_restock_request` RPC recomputes it again under the same inventory-master and production-date locks used by inventory and production decisions. A changed preview returns a conflict; a partial unique index prevents a second active request for the date. The request stores its manager, production date, desired category snapshot, status and timestamps; item rows store requested shortfall grams. Submission changes neither `inventory` nor `production_decisions`. The existing `ADMINISTRATIVE_EVENT` notification path targets active administrators according to their personal preferences; notification delivery remains best effort after commit.

`GET /api/admin/restock-requests` lists pending and historical requests with requested, received, cancelled and outstanding grams. The administrator records each physical receipt through the **existing** `POST /api/admin/inventory/batches` contract, adding `restockRequestItemId` and a UUID `receiptKey`. `receive_restock_batch` locks the request and inventory, checks outstanding quantity, calls the existing audited `RECEIVE_BATCH` operation once, links the new batch to the request item, and updates request status in that same transaction. A repeated identical receipt key returns the original batch without another stock increment; a changed replay is rejected. Each batch retains actual receipt date, expiry date, source and MYR/kg cost snapshot. Partial receipts remain `PARTIALLY_RECEIVED`; all quantities fulfilled become `FULFILLED`. `POST /api/admin/restock-requests/:id/cancel` cancels only outstanding grams with an audit reason; a wholly unreceived request becomes `CANCELLED`, while a partly received and then cancelled request becomes `CLOSED`. Cancellation and status updates never increment stock.

After a receipt, the manager refreshes Production Planning. Valid batch stock is recalculated; pending request quantities are never included. Confirmation and POS still perform their own stock checks. FEFO ordering, prediction and model evaluation are unchanged. No supplier, purchase order or payment integration is added.

Proposed response mapping:

| DTO field | Meaning / SQL mapping |
|---|---|
| `breadCategoryId`, `targetDate`, `predictionId` | Requested category/date and existing stored prediction |
| `predictedUnitsSold` | `daily_predictions.predicted_units_sold` |
| `predictionMode`, `confidence`, `modelVersionId` | MODEL requires numeric [0,100]/version; COLD_START requires null/null |
| `recommendedProduction` | Feasible sequential allocation; confirmation snapshot `recommended_production` |
| `maxProducible` | Server-calculated whole-unit capacity at the relevant planning step |
| `ingredientRequirements`, `shortages` | Per-ingredient required/available/shortfall grams; explicit quantities and units |
| `outstandingCommitments` | Confirmed decisions with no committed production |
| `remainingPlanningBalance` | Temporary balance after ordered allocations; not stored stock |
| `finalSelectedQty`, `selectedOption`, `decisionReason` | Confirmation input; maps to corresponding snake_case columns |
| `confirmedBy`, `confirmedAt` | Derived/stored by Node, never writable client fields |

## 3. Valid inventory and outstanding decisions

For date `D`, usable batches satisfy:

```text
status = ACTIVE
received_date <= D
expiry_date >= D
remaining_quantity_grams > 0
```

This plan treats the printed expiry date as the last usable date, matching the canonical schema mapping. Expired, discarded, depleted and future-received batches are excluded. Validate expiry later than receipt at restock. On relevant application requests, identify expired/soon-expiring batches and compute valid totals; no daily scheduler is required.

A confirmed decision is outstanding exactly when no committed `daily_production` references its unique `production_decision_id`. The production link, rather than a client flag, establishes processed state. Rolled-back simulation creates no such link and leaves the commitment outstanding. Processed decisions are immutable in current scope.

Proposed Repo query sketch; not an implemented SQL file:

```sql
SELECT d.*
FROM production_decisions AS d
WHERE d.target_date = :target_date
  AND NOT EXISTS (
    SELECT 1 FROM daily_production AS p
    WHERE p.production_decision_id = d.id
  )
ORDER BY d.bread_category_id, d.id;
```

Keep all commitments for the date in the comparison, even when a request focuses on a single category. Do not subtract already processed decisions again: their stock has already been consumed.

## 4. Joint recommendation algorithm

Section 4.9.3 makes feasibility a property of the complete date plan.

```text
recommend(date):
  categories = configured active categories ordered by display_order
  predictions = stored predictions for those categories and date
  recipes = validated positive gram requirements
  balance = sum usable batch remainders per ingredient for date

  outstanding = confirmed decisions for date with no committed production
  for each outstanding decision:
    subtract recipe requirements * final_selected_qty from balance

  if any balance < 0:
    return commitment shortages; require stock/decision correction

  for each category not already confirmed or processed, in display_order:
    require stored prediction and valid recipe
    max_producible =
      min(floor(balance[ingredient] / grams_per_unit) for each recipe row)
    recommended_production = min(predicted_units_sold, max_producible)
    record recommendation and its balance/shortage explanation
    subtract recipe requirements * recommended_production from balance

  return recommendations, commitments, remaining temporary balance
```

A missing ingredient balance means zero available stock. An absent/invalid recipe is a configuration error; do not calculate infinity from an empty recipe. `display_order` is unique, and quantities/gram arithmetic must not introduce negative rounding residuals. Recommendations never exceed predicted sales automatically; there is no automatic production buffer.

The maximum for an unconfirmed category describes its sequential planning step, after earlier recommendations. Unconfirmed recommendations do not become stock deductions or binding commitments. A manager override may redistribute those unconfirmed allocations; the confirmation Service must recheck combined confirmed requirements and recalculate affected recommendations.

### Shared-ingredient example

Hypothetical stock is flour 1,000 g, butter 300 g and yeast 30 g. Category C already has an outstanding confirmed quantity of 2, requiring 100/10/1 g per unit respectively. Reserve C's 200/20/2 g first.

| Category / display order | Recipe grams per unit (flour/butter/yeast) | Predicted | Balance before (g) | Maximum | Recommendation | Balance after (g) |
|---|---|---:|---|---:|---:|---|
| A / 1 | 100 / 20 / 2 | 6 | 800 / 280 / 28 | 8 | 6 | 200 / 160 / 16 |
| B / 2 | 100 / 50 / 1 | 4 | 200 / 160 / 16 | 2 | 2 | 0 / 60 / 14 |

The plan consumes 1,000 g flour in total including C. Calculating A and B independently from the same original 1,000 g would incorrectly reuse stock. If C's confirmed requirement alone exceeded a valid ingredient balance, return a shortage before recommending more.

## 5. Confirmation and revision transaction

`PUT /api/production-decisions` accepts this proposed request contract:

```typescript
const ProductionDecisionRequest = z.object({
  predictionId: z.string().uuid(),
  finalSelectedQty: z.number().int().nonnegative(),
  selectedOption: z.enum([
    'ACCEPT_RECOMMENDATION', 'REDUCE', 'MANUAL_OVERRIDE',
  ]),
  decisionReason: z.string().trim().min(1).nullable(),
}).strict();
```

Node loads the prediction's date/category. Reject extra actor/role/recommended/max/feasible fields. All snapshots are derived from stored data and a fresh recommendation. Option invariants are:

- ACCEPT_RECOMMENDATION: selected equals recommendation, reason is null.
- REDUCE: selected is below recommendation, nonblank reason required.
- MANUAL_OVERRIDE: nonblank reason required, selected quantity must be jointly feasible. It may exceed predicted sales.

Planned transaction:

1. Verify manager permission; serialize confirmation and simulation for this production date using the same transaction-level plan lock. This also protects the first decision when no row yet exists.
2. Lock/read the current prediction, outstanding decisions and relevant recipe/inventory records consistently. Administrator catalogue/restock mutations share the corresponding row locks.
3. Reject changes to processed decisions. Build the comparison plan from all other outstanding decisions, excluding the old version of the decision being revised.
4. Recalculate the current recommendation and selected category's feasible capacity after reserving the other commitments. Validate the proposed quantity and option/reason against current data.
5. Verify, for every ingredient, `sum(outstanding selected quantities * grams_per_unit) <= valid stock`. An override is never accepted merely because the client displays “feasible”.
6. Upsert the one decision for that prediction, replacing its quantity and storing refreshed snapshots, manager identity and audit. Commit without changing any inventory/batch/movement quantity.
7. Return recalculated recommendations for affected unconfirmed categories.

Production-date serialization and shared ingredient locks prevent two simultaneous confirmations from oversubscribing a shared ingredient. Use a stable lock order and transaction retry for serialization/deadlock failures. A date-level advisory transaction lock is a proposed mechanism and is not a new table or business entity.

If C in the example is revised after A=6 and B=2 are confirmed, replacing C=2 with C=3 requires 1,100 g flour and must fail with a 100 g shortage. Replacing C=2 with C=1 uses 900 g, not 1,100 g: the old quantity is removed before adding the new one.

## 6. FEFO movement algorithm, query and indexes

Deduction belongs to the atomic POS unit of work, after combined stock revalidation and before sales processing. Confirmation never deducts.

Proposed transaction-scoped Repo query:

```sql
SELECT id, ingredient_id, received_date, expiry_date,
       remaining_quantity_grams, unit_cost
FROM inventory_batches
WHERE ingredient_id = :ingredient_id
  AND status = 'ACTIVE'
  AND received_date <= :production_date
  AND expiry_date >= :production_date
  AND remaining_quantity_grams > 0
ORDER BY expiry_date ASC, received_date ASC, id ASC
FOR UPDATE;
```

Proposed matching indexes:

```sql
CREATE INDEX idx_inventory_batches_fefo
  ON inventory_batches (ingredient_id, expiry_date, received_date, id)
  WHERE status = 'ACTIVE';
CREATE INDEX idx_inventory_batches_expiry
  ON inventory_batches (status, expiry_date);
```

The first query implements FEFO: earliest expiry, then earliest receipt, then lowest ID. The separate status/expiry index supports eligibility checks and alerts.

For all included confirmed decisions, acquire inventory locks in deterministic ingredient order, revalidate all outstanding commitments, then consume eligible batches in expiry/receipt/ID order. Within the date operation, process category decisions deterministically (display order) so each movement has one production-decision owner for reporting. Each deduction records negative `change_grams`, exact `batch_id`, `production_decision_id` and a shared `operation_id`. Update batch remainders/status and inventory caches in the same transaction as the POS result/history. Reject shortage instead of storing negative stock.

### FEFO versus FIFO verification fixture

For production on October 8, batch A was received October 1 and expires October 30; batch B was received October 3 and expires October 10. Both are valid. FEFO consumes B before A because B expires sooner. Equal expiry dates use earliest receipt; equal expiry and receipt dates use ascending ID. A batch expired October 7 is excluded regardless of receipt order.

## 7. Ingredient cost and report integration

`IngredientCostService.calculateFromMovements` uses actual PRODUCTION_DEDUCTION movements for the decision and immutable batch `unit_cost` snapshots:

```text
ingredient_cost =
  sum(abs(change_grams) / 1000 * referenced_batch.unit_cost)
```

Round once at the report's currency precision after summation. Include ingredients consumed for all produced units, including bread later unsold or donated. Do not estimate historical cost using recipe grams times the current ingredient master price.

Example: consuming 600 g from a RM4/kg batch and 400 g from a RM7/kg batch costs RM5.20. Changing the current ingredient price to RM9/kg leaves the stored production cost at RM5.20. Each category's cost derives from its own decision-linked movements, preventing duplicated cost when several categories share batches.

Module 4 snapshots transaction selling prices and stores consistent daily totals. Module 5 computes revenue, gross profit and margin from those totals and FEFO costs, allowing negative profit/margin and displaying zero-denominator percentages as Not Applicable. Financial outputs are reporting-only and simulation-labelled. Weekly/other CSV and PDF exports use the same backend calculations as Views.

## 8. Endpoints, Views and recipient events

| Method/path | Permission | Responsibility |
|---|---|---|
| `GET /api/inventory` | Both, planned | Date-aware valid stock, low stock, expiry and movement views |
| `GET/POST /api/admin/inventory/ingredients`; `PATCH /api/admin/inventory/ingredients/:ingredientId` | Administrator, implemented | Validated ingredient metadata; no historical deletion |
| `GET/POST /api/admin/inventory/categories`; `PATCH /api/admin/inventory/categories/:categoryId` | Administrator, implemented | Inactive-first category creation, recipe-before-activation, unique display order |
| `GET/PUT /api/admin/inventory/categories/:categoryId/recipe` | Administrator, implemented | Atomic replacement of a positive, unique ingredient recipe |
| `GET/POST /api/admin/inventory/batches`; `PATCH /api/admin/inventory/batches/:batchId/stock` | Administrator, implemented | Receipt and reasoned stock removal; batch cost snapshot and signed movement in staged RPC |
| `GET /api/recommendations/:date` with optional `revisingPredictionId` | Manager | Stored-prediction joint planning, shortage explanations and a fresh revision preview |
| `PUT /api/production-decisions` | Manager | Explicit confirmed quantity or unprocessed revision |
| `GET /api/restock-requests/preview/:date`; `POST/GET /api/restock-requests` | Manager | Desired-quantity shortfall, confirmed request and own status/history |
| `GET /api/admin/restock-requests`; `POST /api/admin/restock-requests/:id/cancel` | Administrator | Review partial fulfilment; cancel only outstanding grams with reason |
| `POST /api/admin/inventory/batches` with `restockRequestItemId`, `receiptKey` | Administrator | Existing batch receipt, linked to request item and idempotent retry |

There is no public ingredient-deduction endpoint: POS invokes the protected internal transaction. Referenced batches and movements cannot be deleted or recosted by generic CRUD; administrative operations preserve audit/history.

The implemented `InventoryAdminScreen` exposes category, ingredient, recipe and ordinary batch forms to the administrator; `RestockAdminScreen` reviews requests and uses the same batch receipt endpoint for linked arrivals. `ProductionPlanningScreen` displays prediction, mode-aware confidence, joint capacity and desired-production shortfalls, with manager confirmation before requesting stock. It never shows a cold-start percentage. Managers cannot use administrator receipt/cancellation routes.

Low-stock, expiry and external/system-failure events pass through Module 1's `NotificationService`. Notification rows identify one `recipient_user_id`; preferences are per type/user. Foreground visibility and read state are recipient-only through Supabase Realtime's narrow read policy. Node owns writes/mark-read. Push uses only active valid tokens belonging to that opted-in recipient and records PENDING, SUBMITTED, DELIVERED, FAILED or SKIPPED attempts; SUBMITTED is not confirmed delivery. No global broadcast/deduplication assumption applies.

## 9. Implementation order and planned verification

Remaining implementation order:

1. In an isolated database, apply and validate the existing confirmation/inventory RPCs and the new restock migration in filename order; verify locks, duplicate requests, partial receipts, retry keys, audited stock movements and rollback. The Node/Flutter paths exist but live database behavior is unverified.
2. Implement expiry-ordered production movement planning and batch snapshot cost calculations.
3. Integrate those components into the single POS transaction before exposing operational simulation.
4. Add recipient event integration and shared report/export inputs.
5. Complete the planned live, concurrency, performance and UAT checks below. Automated Node and Flutter tests cover the implemented planning and administrator UI/API boundaries only.

| Planned check | Expected result |
|---|---|
| Shared three-ingredient example in Section 4 | A=6 and B=2 after reserving C=2; flour allocated once |
| Outstanding commitments exceed stock | Explicit shortage; no additional recommendation or confirmation |
| Revision C=2 → C=1 or C=3 | Previous quantity replaced; feasible revision accepted, overcommitment rejected |
| Simultaneous confirmations for shared stock | Serialized joint check; combined requirement never exceeds valid stock |
| Concurrent confirmation versus simulation/admin inventory change | Consistent locks, fresh feasibility; no lost commitment or negative stock |
| Processed versus failed simulation decision | Processed excluded from planning; rolled-back attempt remains outstanding |
| No recipe, inactive ingredient, zero stock and zero prediction | Configuration rejection where invalid; valid zero capacities/quantities without negative values |
| Receipt-order/expiry-order fixture and equal dates | B before A; equal expiry dates ordered by receipt date, then ID; expired/inactive/future batches excluded |
| Confirmation inventory comparison | No batch/snapshot/movement changes |
| 600 g at RM4/kg + 400 g at RM7/kg; later master-price change | Historical cost RM5.20, same in result/View/CSV/PDF |
| Manager tries admin mutation; administrator tries confirmation | Rejected before mutation; ACTIVE-profile validation enforced |
| COLD_START recommendation and all-cold-start dashboard | Null confidence carried through; low-confidence heuristic label without number |
| Low-stock/expiry event and opted-out recipient | Personal visibility only; push skipped and delivery state recorded |

Reference checks: Android 10+, >=4 GB RAM, stable network >=10 Mbps, up to 20 categories, 365 daily records/category and 50-row pages. Recommendation completes within 15 seconds; at least 95% of specified screen requests complete within 3 seconds. Check 360×640 to 412×915 dp layouts and the Module 6 >=80% independent UAT task criterion. These are planned thresholds, not measured results.
