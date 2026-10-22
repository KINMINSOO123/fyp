# Smart Bakery Logical View audit and diagram plan

**Design revision - 2026-10-16:** At the user's request, FEFO replaces the report's FIFO policy: eligible batches are consumed by `expiry_date ASC, received_date ASC, id ASC`. The DOCX/report mirror remain unchanged; this is an explicit departure from Sections 4.5.3-4.5.4 and 4.9.3, including BR-INV-05/FR-INV-06. Other report requirements still apply.

## Historical audit snapshot

The earlier planning audit, associated with the July 2026 planning set, found only the Flutter counter starter (`lib/main.dart`, `test/widget_test.dart`) and no Smart Bakery TypeScript backend, Python ML service, schema migrations or generated database types. That finding is historical evidence, not an approval of the proposed backend. This file did not establish a precise original audit date; none is invented here. The separately dated database audit remains labelled 31 July 2026 in [database_schema_verification.md](database_schema_verification.md).

Earlier catalogues described route objects as Controllers, Python Supabase Repos, scheduled reminder classes, direct client CRUD and automatic donation. Those obsolete proposals have been removed from active diagram instructions. Git history retains the old snapshot. `FYP Report.md` was the earlier report reference and is now user-deleted; no link or implementation instruction depends on it.

## Current source review: 2026-10-11

The repository remains a Flutter starter plus plans. The current `lib/main.dart` defines the counter-demo MyApp, MyHomePage and private state; none is a bakery domain class. Planning code fences are not implemented files. No application/backend/database/ML tests were executed for this Markdown reconciliation.

Use the latest RSW_SooKinMin_Project1 DOCX as report authority and [its repository Markdown mirror](RSW_SooKinMin_Project1.docx.md) for navigation. [logical_view_canonical_design.md](logical_view_canonical_design.md) supplies the reconciled proposed classifier catalogue. Current diagrams must be labelled **Proposed Logical View** until implementation inspection can verify classes and relationships.

## Diagram contents

| Diagram | Include | Exclude |
|---|---|---|
| Core Application | Flutter Views/ApiClient/platform exceptions; TypeScript Controllers, Services, Repos and adapters; central domain associations | Counter widgets/private State/framework classes; Express router modules; database credentials |
| Machine Learning | PredictionOrchestrationService, ModelManagementService, FastApiMlClient, DTOs, Python feature/prediction/cold-start/confidence/training/evaluation classes and artifact store | FastAPI route functions as UML classes; Python application Repos/Supabase; automatic model activation |

Use dependency arrows for calls, associations for domain links and multiplicities reflecting database constraints. Do not present constructor-injected Services/Repos as lifecycle composition. Keep `DailyPrediction`, `DailySalesRecord`, `DailyResult`, `Controller`, `Service`, `Repo` and `View` naming consistent with the canonical catalogue.

The platform exception diagram must show Supabase Authentication, foreground recipient-only Supabase Realtime and FCM. Ordinary database CRUD remains `ApiClient -> Controller -> Service -> Repo`. A recipient-only notification SELECT policy must not imply general client table access. FastApiMlClient supplies validated DTOs to thin routes delegating to Python Services.

## Planned diagram and contract checks

1. Cover all eight functional modules, including concrete profiles/accounts/roles, settings, audit, notifications and charity administration; map to technical modules 0-6 without renumbering report modules.
2. Trace manager-only operations separately from administrator management; both roles retain own-profile/personal-notification and permitted-report access. Verify stored single role/ACTIVE status and final-admin protection.
3. Show stored prediction -> confirmed decision -> production -> result uniqueness, source-specific DailySalesRecord relationships, and normalized allocation links. Do not add SimulationRun or LeftoverRecord.
4. Show RecommendationEngine reading stored predictions and accounting for shared ingredients/commitments; it does not invoke ML. Confirmed decisions have no inventory-deduction association until processing.
5. Show SimulationCommitRepo as a single atomic transaction boundary covering FEFO inventory movements and all operational/history writes. Consumption order is expiry_date then received_date then id, with eligibility excluding expired/inactive batches. No independent commits or correction-batch recovery arrows.
6. Check DTO MODEL requires numeric confidence/modelVersionId; COLD_START has both null. ConfidenceService owns the report formula. History uses distinct validated category/day unitsSold with exact origin priority; training/evaluation/activation/restoration are distinct.
7. Check notification recipient/preferences/token/delivery relationships and delivery states; all mark-read/write paths use Node. PendingActionService has request-time dependencies, no timer/scheduler.
8. Trace ReportService/ReportRepo/ReportExportAdapter for common CSV/PDF/UI calculations, simulation labels, FEFO cost snapshots, signed error/profit and Not Applicable percentages.
9. Show manager-confirmed donation/waste and dedicated status updates; cancellation/reallocation semantics remain an open decision, not an invented transition policy.
10. Once actual implementation exists, compare declarations, signatures, dependency injection, FK constraints and real tests to these diagrams. Until then record checks as design review/planned validation rather than implementation verification.

## Review output and unresolved design work

The [change report](planning_documents_change_report.md) records the current reconciliation, report section references and requirement traceability. The [testing plan](Final%20Year%20Project/operation_reminders_testing/README.md) contains measurable NFR checks. The remaining business decision is cancelled-donation accounting/transition rules. First activation requires a valid reviewed evaluation and explicit administrator confirmation; shared half-away-from-zero rounding is a documented engineering convention, not a new report requirement. Re-simulation and scheduled reminders remain future scope.
