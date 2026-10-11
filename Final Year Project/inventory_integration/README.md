# Module 3: Inventory and Production Recommendations — Detailed Proposed Design

Reconciled on 2026-10-11 from the latest `RSW_SooKinMin_Project1 (1).docx`, especially FR-INV-01–12, Sections 4.5.3–4.5.4, Table 4.27 and Sections 4.7.2/4.9.3. These are proposed contracts, algorithms and verification plans; no backend files, migrations or test results are represented as implemented.

See [module mapping](MODULE.md), [architecture](../ARCHITECTURE.md), [canonical schema](../../database_canonical_design.md), [logical design](../../logical_view_canonical_design.md), [POS transaction](../pos_simulation/README.md) and [traceability](../../planning_documents_change_report.md).

## 1. Ownership, permissions and data

Technical Module 3 delivers Inventory and Smart Production Recommendation and supports reporting, alerts and administration. It serves one bakery on Android, operating over configured active categories and ingredients. Four categories and five ingredients are example seeds; the reference workload includes up to 20 active categories.

| Capability | Role | Planned boundary |
|---|---|---|
| Ingredient/category/recipe administration | SYSTEM_ADMINISTRATOR | `InventoryController` / `RecipeController` → `InventoryService` / `RecipeService` → Repos |
| Batch receipt/restock and inventory adjustments | SYSTEM_ADMINISTRATOR | `InventoryController → InventoryService`; transactional batch/snapshot/movement updates |
| Recommendation review | BAKERY_MANAGER | `RecommendationController → RecommendationEngine` |
| Production confirmation/revision | BAKERY_MANAGER | `ProductionDecisionController → ProductionDecisionService` |
| Permitted inventory/report viewing | Both ACTIVE roles | Read Service/Repo DTOs |
| Production ingredient deduction | Internal to manager-authorized POS | `TransactionRecordingService`, `SimulationCommitRepo`, `FifoBatchService` |

Every request validates JWT and the ACTIVE stored profile before permissions. Administrator accounts cannot confirm production; manager accounts cannot mutate catalogue/inventory. Never accept actor, role or feasibility claims from the client. Flutter ordinary CRUD uses Node. Supabase Auth, recipient-only foreground Realtime and FCM background notifications remain platform exceptions; FastAPI has no database access.

Recipes store positive `grams_per_unit`. Ingredient inventory, batches and movements use grams. Whole-product quantities are nonnegative integers. `inventory` is a maintained cache, while date-specific batch eligibility is the production source of truth. Batch `unit_cost` is an immutable receipt snapshot, normalized in this plan to MYR/kg. Current ingredient master prices remain separate reporting configuration.

## 2. Planned Services, Repos and interfaces

| Class | Planned method/responsibility |
|---|---|
| `InventoryService` | `getInventory(date)`, `recordBatch(input, actor)`, `adjustBatch(input, actor)`; validate and atomically update batches, snapshots, movements and audit |
| `RecipeService` | Read/validate one recipe specification per category; administrator changes with positive quantities and unique category–ingredient pairs |
| `RecommendationEngine` | `recommend(targetDate)`; read stored predictions and build one shared temporary ingredient balance |
| `ProductionDecisionService` | `confirmOrRevise(input, actor)`; joint feasibility, replacement quantity, required reason, serialized confirmation |
| `FifoBatchService` | `consumeWithinTransaction(transaction, decisions, targetDate)`; exact receipt-ordered batch movements validated and applied through transaction-scoped Repos |
| `IngredientCostService` | `calculateFromMovements(movements, batchSnapshots)`; reporting-only consumption costs grouped by production decision |
| `InventoryRepo`, `InventoryBatchRepo`, `InventoryLogRepo` | Inventory/batch/movement reads and transaction-scoped writes/locks |
| `IngredientRepo`, `BreadCategoryRepo`, `RecipeRepo` | Catalogue/configuration persistence and deterministic category order |
| `DailyPredictionRepo`, `ProductionDecisionRepo`, `DailyProductionRepo` | Stored prediction, outstanding commitments and processed-state lookup |

Controllers delegate to Services. Services use Repos for PostgreSQL; route modules only register class handlers. No `RecommendationEngine` method generates predictions, calls FastAPI or trains a model. Financial values never determine production quantities.

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

## 6. FIFO movement algorithm, query and indexes

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
ORDER BY received_date ASC, id ASC
FOR UPDATE;
```

Proposed matching indexes:

```sql
CREATE INDEX idx_inventory_batches_fifo
  ON inventory_batches (ingredient_id, received_date, id)
  WHERE status = 'ACTIVE';
CREATE INDEX idx_inventory_batches_expiry
  ON inventory_batches (status, expiry_date);
```

The first query is FIFO by receipt order; expiry-first would be FEFO. The separate expiry index/query is for eligibility and alerts, not consumption order.

For all included confirmed decisions, acquire inventory locks in deterministic ingredient order, revalidate all outstanding commitments, then consume eligible batches in receipt/ID order. Within the date operation, process category decisions deterministically (display order) so each movement has one production-decision owner for reporting. Each deduction records negative `change_grams`, exact `batch_id`, `production_decision_id` and a shared `operation_id`. Update batch remainders/status and inventory caches in the same transaction as the POS result/history. Reject shortage instead of storing negative stock.

### FIFO versus FEFO verification fixture

For production on October 8, batch A was received October 1 and expires October 30; batch B was received October 3 and expires October 10. Both are valid. FIFO consumes A before B even though B expires sooner. Equal receipt dates use ascending ID. A batch expired October 7 is excluded regardless of receipt order.

## 7. Ingredient cost and report integration

`IngredientCostService.calculateFromMovements` uses actual PRODUCTION_DEDUCTION movements for the decision and immutable batch `unit_cost` snapshots:

```text
ingredient_cost =
  sum(abs(change_grams) / 1000 * referenced_batch.unit_cost)
```

Round once at the report's currency precision after summation. Include ingredients consumed for all produced units, including bread later unsold or donated. Do not estimate historical cost using recipe grams times the current ingredient master price.

Example: consuming 600 g from a RM4/kg batch and 400 g from a RM7/kg batch costs RM5.20. Changing the current ingredient price to RM9/kg leaves the stored production cost at RM5.20. Each category's cost derives from its own decision-linked movements, preventing duplicated cost when several categories share batches.

Module 4 snapshots transaction selling prices and stores consistent daily totals. Module 5 computes revenue, gross profit and margin from those totals and FIFO costs, allowing negative profit/margin and displaying zero-denominator percentages as Not Applicable. Financial outputs are reporting-only and simulation-labelled. Weekly/other CSV and PDF exports use the same backend calculations as Views.

## 8. Endpoints, Views and recipient events

| Method/path | Permission | Responsibility |
|---|---|---|
| `GET /api/inventory` | Both, permitted visibility | Date-aware valid stock, low stock, expiry/batch and movement views |
| `/api/admin/ingredients` | Administrator CRUD | Validated metadata; deactivate referenced items instead of deleting history |
| `/api/admin/categories` | Administrator CRUD | Active status, unique display order, base and catalogue values |
| `/api/admin/recipes` | Administrator CRUD | One positive-quantity recipe specification/category |
| `/api/admin/batches` | Administrator CRUD within integrity rules | Receipt/restock/correction preserving history and immutable cost snapshot |
| `GET /api/recommendations/:date` | Manager | Stored-prediction joint planning and shortage explanations |
| `PUT /api/production-decisions` | Manager | Explicit confirmed quantity or unprocessed revision |

There is no public ingredient-deduction endpoint: POS invokes the protected internal transaction. Referenced batches and movements cannot be deleted or recosted by generic CRUD; administrative operations preserve audit/history.

`InventoryView`/`RecipeView` expose administrator changes and permitted read states. `ProductionPlanningView` displays the stored prediction, mode-aware confidence, joint capacity and shortages; it never shows a cold-start percentage. `ProductionPlanningView` requires explicit confirmation, an override/reduction reason and refreshed affected recommendations. An administrator may resolve requested restocking; managers cannot bypass permissions to restock themselves.

Low-stock, expiry and external/system-failure events pass through Module 1's `NotificationService`. Notification rows identify one `recipient_user_id`; preferences are per type/user. Foreground visibility and read state are recipient-only through Supabase Realtime's narrow read policy. Node owns writes/mark-read. Push uses only active valid tokens belonging to that opted-in recipient and records PENDING, SUBMITTED, DELIVERED, FAILED or SKIPPED attempts; SUBMITTED is not confirmed delivery. No global broadcast/deduplication assumption applies.

## 9. Implementation order and planned verification

Future implementation order:

1. Align canonical recipe/batch/decision types, partial FIFO index and unique operational-chain constraints.
2. Implement Repo read/lock/update contracts, administrator catalogue/restock validation and audit.
3. Implement joint temporary-balance recommendations and serialized confirmation/revision.
4. Implement receipt-ordered movement planning and snapshot cost calculations.
5. Integrate those components into the single POS transaction before exposing operational simulation.
6. Add Views, recipient event integration and shared report/export inputs.
7. Execute the following meaningful tests when implementation exists.

| Planned check | Expected result |
|---|---|
| Shared three-ingredient example in Section 4 | A=6 and B=2 after reserving C=2; flour allocated once |
| Outstanding commitments exceed stock | Explicit shortage; no additional recommendation or confirmation |
| Revision C=2 → C=1 or C=3 | Previous quantity replaced; feasible revision accepted, overcommitment rejected |
| Simultaneous confirmations for shared stock | Serialized joint check; combined requirement never exceeds valid stock |
| Concurrent confirmation versus simulation/admin inventory change | Consistent locks, fresh feasibility; no lost commitment or negative stock |
| Processed versus failed simulation decision | Processed excluded from planning; rolled-back attempt remains outstanding |
| No recipe, inactive ingredient, zero stock and zero prediction | Configuration rejection where invalid; valid zero capacities/quantities without negative values |
| Receipt-order/expiry-order fixture and equal dates | A before B; equal receipts ordered by ID; expired/inactive/future batches excluded |
| Confirmation inventory comparison | No batch/snapshot/movement changes |
| 600 g at RM4/kg + 400 g at RM7/kg; later master-price change | Historical cost RM5.20, same in result/View/CSV/PDF |
| Manager tries admin mutation; administrator tries confirmation | Rejected before mutation; ACTIVE-profile validation enforced |
| COLD_START recommendation and all-cold-start dashboard | Null confidence carried through; low-confidence heuristic label without number |
| Low-stock/expiry event and opted-out recipient | Personal visibility only; push skipped and delivery state recorded |

Reference checks: Android 10+, >=4 GB RAM, stable network >=10 Mbps, up to 20 categories, 365 daily records/category and 50-row pages. Recommendation completes within 15 seconds; at least 95% of specified screen requests complete within 3 seconds. Check 360×640 to 412×915 dp layouts and the Module 6 >=80% independent UAT task criterion. These are planned thresholds, not measured results.
