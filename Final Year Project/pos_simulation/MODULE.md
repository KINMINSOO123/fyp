# Module 4: POS Simulation — Proposed Module Plan

**Design revision - 2026-10-16:** At the user's request, FEFO replaces the report's FIFO policy: eligible batches are consumed by `expiry_date ASC, received_date ASC, id ASC`. The DOCX/report mirror remain unchanged; this is an explicit departure from Sections 4.5.3-4.5.4 and 4.9.3, including BR-INV-05/FR-INV-06. Other report requirements still apply.

Reconciled on 2026-10-11 against the latest `RSW_SooKinMin_Project1 (1).docx`, Sections 1.4.2, 3.5–3.6, 4.5.3–4.5.4, 4.7.2, 4.8 and 4.9.3. As of 2026-11-09, Node POS initiation and reads, a Flutter screen, and the atomic `complete_pos_simulation` migration are implemented locally. The migration is staged, not applied or verified live; notifications and reporting/export integration remain planned. See the [detailed transaction plan](README.md), [schema](../../database_canonical_design.md), [architecture](../ARCHITECTURE.md) and [traceability](../../planning_documents_change_report.md).

## 1. Scope and functional-module mapping

Technical Module 4 delivers **POS and Sales Simulation**, supplying data to **Demand Prediction**, **Leftover, Donation and Waste Management**, **Reporting and Dashboard**, and **Alerts and Notifications**. It simulates one bakery's operations. Customer ordering/payment, delivery/marketplaces and real POS hardware are excluded.

A Bakery Manager manually initiates simulation; a System Administrator cannot run it. The date defaults to today in the bakery timezone. Every included active category requires that date's stored prediction and explicit manager-confirmed production decision; zero confirmed production is valid. No fallback quantity or operational override bypasses confirmation.

## 2. Dependencies and proposed components

Modules 0–1 provide normalized tables, row locking, JWT/ACTIVE-profile/role checks and Controller → Service → Repo boundaries. Module 2 supplies stored contextualised predictions. Module 3 supplies joint feasibility, FEFO and costs. Module 5 receives completed results for manual allocation/reports.

| Component | Responsibility |
|---|---|
| `PosSimulationController` | Manager initiation and permitted reads; thin router is a separate module |
| `PosSimulationService` | Strict request/date validation and bakery-local default date |
| `PosSimulationRepo` | Protected single RPC commit plus permitted result/transaction reads |
| `complete_pos_simulation` SQL function | One transaction with shared-stock checks, FEFO batch movements, sales variation, production, results, history and audit |
| `PosSimulationScreen` | Date, prerequisites, explicit run action, retry and simulated labels |

## 3. Mandatory atomic workflow

1. Verify JWT, ACTIVE profile and manager permission; validate date, predictions and confirmed decisions.
2. Use the stored contextualised prediction as baseline. Do not reapply weather, holiday or season factors or call external context services during the transaction.
3. Start one Node-owned PostgreSQL transaction. Serialize the date's production plan; lock decisions and shared inventory/batches deterministically. Re-read prerequisites, reject processed decisions and validate combined requirements.
4. Deduct valid batches by ascending `expiry_date`, then `received_date`, then `id`, excluding expired/inactive batches. Update snapshots and linked movements exactly once before sales processing.
5. Process sales using configured stochastic/time-slot variation. Persist production, transactions, `DailyResult` and one validated `DailySalesRecord` per category with `SIMULATION_GENERATED` origin and source-result reference.
6. Commit all writes together. Any failure rolls back batches, snapshots, movements, production, transactions, results and simulation history. Decisions remain unprocessed; retry revalidates stock. Recipient notifications after commit remain planned.

Unique prediction → decision → production → result links and locks prevent double deduction. No `SimulationRun` or `LeftoverRecord` table is required. Deliver recipient notifications after commit; push failure cannot cause rerunning production.

## 4. Calculations and provenance

```text
units_sold = min(simulated_demand, produced)
lost_sales = max(0, simulated_demand - produced)
estimated_demand = units_sold + lost_sales
leftover = produced - units_sold
sales_prediction_error = units_sold - predicted_units_sold
leftover_rate_pct = leftover / produced * 100, or Not Applicable when produced = 0
revenue = sum(transaction.quantity * transaction.unit_price)
ingredient_cost = sum(abs(production_movement.change_grams) / 1000 * batch.unit_cost)
gross_profit = revenue - ingredient_cost
gross_profit_margin_pct = gross_profit / revenue * 100, or Not Applicable when revenue = 0
```

The proposed cost convention is MYR/kg; immutable batch cost snapshots and transaction price snapshots preserve history. Signed error and negative gross profit/margin are valid. Donated/unallocated leftovers are not automatically waste. Financial output is reporting-only and simulation-labelled. Do not add detailed transactions to their daily totals. ML still targets `DailySalesRecord.unitsSold`.

## 5. Contracts and retry policy

`POST /api/simulations` accepts `{ date?: ISODate }`; Node derives the default date and actor. Reject client production/actor/role/feasibility fields. `GET /api/simulations/today` gives the bakery-local date. `GET /api/simulations/:date` and `GET /api/simulations/:date/transactions` return permitted filtered/paginated data to either active role.

A completed decision cannot be simulated again. Duplicates return `409 ALREADY_SIMULATED` with a stored-result link and no writes. Re-simulation/retrospective correction are future work until an explicit atomic policy covers exact original batch movements, transactions, linked history, reports and leftover allocations. Correction batches/separate reversal commits do not substitute for rollback. Pure test fixtures must not write operational data or share a confirmation-bypassing endpoint.

## 6. Implementation and verification plan

Implemented locally: manager-only initiation; both-role result/transaction reads; a Flutter simulation View; a staged single-transaction RPC with locks, FEFO/cost calculations, sales, history and audit. Still required: apply and verify the migration, recipient events after commit, reports/exports, functional/failure/performance checks. Atomicity is a prerequisite for operational use.

The [README](README.md) specifies duplicate/concurrent requests, failure injection after each write stage, FEFO versus FIFO, snapshot costs/prices, zero production, signed error, single-context logic, role rejection and a 12-hour simulation within 30 seconds for up to 20 categories. All are planned checks, not completed results.
