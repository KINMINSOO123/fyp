# Smart Bakery Logical View — Canonical Proposed Class Specification

**Document status:** Proposed design; not implementation-verified  
**System:** Smart Bakery Food Waste Reduction System  
**Purpose:** Canonical classifier specification for the Chapter 4 Logical View  
**Diagram output:** This document specifies diagram content but does not draw either diagram  
**Source status:** No Smart Bakery Flutter, TypeScript backend or Python ML implementation currently exists

## 1. Design status and scope

Every classifier in this document is explicitly **proposed**. A classifier must not be described as implemented until a later source audit verifies a corresponding `.dart`, `.ts` or `.py` declaration.

The final Logical View is divided into two proposed class diagrams:

| Diagram | Scope |
|---|---|
| **Core Application Logical View** | Flutter Views and API client; TypeScript Controllers, Business Services, Repos and external-data adapters; central bakery domain models |
| **Machine-Learning Logical View** | TypeScript ML orchestration boundary; `FastApiMlClient`; language-neutral ML DTO contract; Python feature, prediction, training and evaluation service classes |

This split keeps each diagram readable while showing the complete TypeScript-to-FastAPI boundary. Classifiers marked **Both** are boundary elements repeated in both diagrams for traceability.

## 2. Canonical architecture decisions

| # | Canonical decision |
|---:|---|
| 1 | The design is labelled **Proposed Logical View**, never implementation-verified. |
| 2 | Node.js/Express owns all Supabase PostgreSQL access. TypeScript Business Services use TypeScript Repos; only Repos use the Supabase database client. |
| 3 | FastAPI does not import or call Supabase. TypeScript prepares validated prediction/training input and persists relevant returned prediction, model-version and feature-importance data through TypeScript Repos. |
| 4 | Express router files are registration modules, not UML classes. They instantiate/map route handlers to Controller classes and are excluded from the class diagrams. |
| 5 | TypeScript Controllers, Business Services, Repos and external-service adapters are proposed as constructor-injected classes. |
| 6 | FastAPI route functions are thin endpoint functions and are excluded as classifiers. They validate Pydantic DTOs, call a Python service class and serialize its result. |
| 7 | Flutter screen-level classes use the `View` suffix consistently. |
| 8 | `DailyPrediction` is the only canonical prediction-domain name. `DemandPrediction` is retired. |
| 9 | Every repository name uses the `Repo` suffix. The shared base is `BaseRepo<T>`. |
| 10 | The prediction target is `unitsSold`. `lostSales` is retained for analysis but is not the current training target. |
| 11 | Simulated operational data is represented by `DailyProduction`, `SalesTransaction` and `DailyResult`. `WasteRecord` is now required for manager-confirmed disposal; `SimulationRun` and `LeftoverRecord` remain excluded. |
| 12 | The permitted primary chains are `View → API Client → Controller → Service → Repo → Supabase`, `Service → External Adapter → External API`, and `TypeScript Service → FastApiMlClient → FastAPI endpoint → Python Service`. |
| 13 | `PredictionOrchestrationService` and `FastApiMlClient` are mandatory proposed boundary classes. |
| 14 | Starter Flutter classes, private `State` classes, small widgets, utility functions, framework types and nonessential database-row classes are excluded. |

## 3. UML conventions

| Stereotype | Meaning |
|---|---|
| `<<proposed view>>` | Flutter screen-level presentation class |
| `<<proposed client>>` | Flutter HTTP client boundary |
| `<<proposed controller>>` | TypeScript request-handling class called by an Express router module |
| `<<proposed service>>` | TypeScript or Python business/application service class |
| `<<proposed repository>>` | TypeScript Supabase data-access class |
| `<<proposed abstract repository>>` | Proposed abstract generic TypeScript Repo base |
| `<<proposed external adapter>>` | TypeScript client for an external HTTP/provider boundary |
| `<<proposed domain model>>` | Central business entity/data model |
| `<<proposed enumeration>>` | Closed set of canonical domain values |
| `<<proposed DTO>>` | Typed request, response or calculation result with no database identity |
| `<<proposed model wrapper>>` | Python wrapper around trained estimators |
| `<<proposed artifact store>>` | Python file-based model persistence component; not a database Repo |

Relationship notation used in the tables:

- **Dependency**: caller uses another classifier but does not own its lifecycle.
- **Association**: stable domain link between instances.
- **Composition**: parent owns nested data or an internal object’s lifecycle.
- **Inheritance**: concrete Repo extends `BaseRepo<T>`.
- **Interface realisation**: not used in this canonical version because no provider interface is required by the final decisions. It can be introduced later only with an explicit requirement.

For a constructor-injected technical dependency, multiplicity `1` means one required collaborator per object instance. Domain multiplicities describe persisted business relationships.

When a Service merely consumes, creates or returns a DTO/domain object without storing it as an attribute, that relationship is a **dependency**, not lifecycle ownership. In the Repo catalogue, “manages `0..*`” denotes a navigable **association** from one Repo instance to zero or more persisted instances of its bound domain type.

## 4. Flutter Views and API client

These are screen-level classes only. Flutter `State` subclasses, navigation helpers, cards, charts, badges and other small widgets are deliberately excluded.

| Final canonical name | UML stereotype | Architectural package/layer | Main responsibility | Essential attributes | Essential operations | Relationships, type and multiplicity | Diagram |
|---|---|---|---|---|---|---|---|
| `PredictionView` | `<<proposed view>>` | `flutter.presentation` / Presentation | Support the manager’s morning workflow: generate/review a `DailyPrediction`, request a feasible recommendation and confirm the final production decision | `apiClient: ApiClient`; `selectedDate: Date`; displayed prediction/recommendation state | `generatePrediction()`; `loadRecommendation()`; `confirmProductionDecision()` | Has exactly `1` `ApiClient` (**dependency**); displays `0..*` `DailyPrediction` and `0..*` `ProductionRecommendation` DTOs (**dependency**, not ownership of persistent entities) | Core |
| `ModelManagementView` | `<<proposed view>>` | `flutter.presentation.admin` / Presentation | Allow the System Administrator to initiate training, review origin-labelled evaluation, activate a candidate and restore a previous valid version | `apiClient: ApiClient`; selected model/evaluation state | `trainCandidate()`; `evaluateCandidate()`; `activateCandidate()`; `restoreVersion()` | Has exactly `1` `ApiClient` (**dependency**); displays `0..*` `ModelVersion` and `ModelMetrics` DTOs (**dependencies**) | ML |
| `InventoryView` | `<<proposed view>>` | `flutter.presentation` / Presentation | Display ingredient/FIFO batch state and initiate authorised restock or discard operations | `apiClient: ApiClient`; inventory display state | `loadInventory()`; `restockIngredient()`; `discardBatch()` | Has exactly `1` `ApiClient` (**dependency**); displays `0..*` `InventoryBatch` DTOs (**dependency**) | Core |
| `PosSimulationView` | `<<proposed view>>` | `flutter.presentation` / Presentation | Manually start the POS simulation and display produced, sold, leftover and lost-sales results | `apiClient: ApiClient`; `selectedDate: Date`; displayed result state | `runSimulation()`; `loadDailyResults()` | Has exactly `1` `ApiClient` (**dependency**); displays `0..*` `DailyProduction`, `SalesTransaction` and `DailyResult` DTOs (**dependency**) | Core |
| `LeftoverManagementView` | `<<proposed view>>` | `flutter.presentation` / Presentation | Review remaining unallocated leftovers and let the Bakery Manager confirm donation or waste actions | `apiClient: ApiClient`; `selectedDate: Date`; selected category/allocation state | `loadLeftovers()`; `recordDonation()`; `recordWaste()`; `markDonationStatus()` | Has exactly `1` `ApiClient` (**dependency**); displays `0..*` `DailyResult`, `Donation`, `WasteRecord` and `CharityPartner` DTOs (**dependencies**) | Core |
| `DashboardView` | `<<proposed view>>` | `flutter.presentation` / Presentation | Present read-only operational, waste, donation and financial summaries | `apiClient: ApiClient`; `period`; displayed summary state | `loadOperationalSummary()`; `loadWasteSummary()`; `loadFinancialSummary()` | Has exactly `1` `ApiClient` (**dependency**); displays aggregated `DailyResult`/`Donation` data (**dependency**) | Core |
| `ApiClient` | `<<proposed client>>` | `flutter.infrastructure` / Presentation client boundary | Add authentication token, send typed REST requests to Express and map JSON to Dart DTOs | `baseUrl: Uri`; `authTokenProvider`; HTTP client instance | `get<T>()`; `post<T>()`; `put<T>()`; `patch<T>()`; `delete<T>()` | Used by `1..*` Views (**dependency**); sends requests to `0..*` TypeScript Controller endpoints (**cross-process dependency**) | Core |

Flutter authentication may use Supabase Authentication for session/JWT issuance, but this is a platform-authentication operation rather than Supabase database access. No Flutter class may query Supabase PostgreSQL tables.

## 5. TypeScript Controller classes

Express router modules create routes and delegate to these classes. Router modules are not UML classifiers.

| Final canonical name | UML stereotype | Architectural package/layer | Main responsibility | Essential attributes | Essential operations | Relationships, type and multiplicity | Diagram |
|---|---|---|---|---|---|---|---|
| `PredictionController` | `<<proposed controller>>` | `backend.controllers` / Application | Validate prediction requests and delegate manual prediction generation/retrieval | `predictionService: PredictionOrchestrationService` | `generatePrediction(request)`; `getPrediction(date)` | Has exactly `1` `PredictionOrchestrationService` (**dependency**) | Both |
| `ModelManagementController` | `<<proposed controller>>` | `backend.controllers` / Application | Validate System-Administrator-only training, evaluation, activation, restoration and model-status requests | `modelManagementService: ModelManagementService` | `trainCandidate(request)`; `evaluateCandidate(request)`; `activateCandidate(id)`; `restoreVersion(id)`; `getActiveModels()` | Has exactly `1` `ModelManagementService` (**dependency**) | ML |
| `RecommendationController` | `<<proposed controller>>` | `backend.controllers` / Application | Delegate recommendation generation and manager decision confirmation | `recommendationEngine: RecommendationEngine`; `decisionService: ProductionDecisionService` | `generateRecommendation(date)`; `confirmProductionDecision(request)`; `getProductionDecisions(date)` | Has `1` `RecommendationEngine` and `1` `ProductionDecisionService` (**dependencies**) | Core |
| `InventoryController` | `<<proposed controller>>` | `backend.controllers` / Application | Validate and delegate inventory, batch, restock and discard operations | `inventoryService: InventoryService` | `listInventory()`; `listBatches()`; `restock(request)`; `discardBatch(id)` | Has exactly `1` `InventoryService` (**dependency**) | Core |
| `PosSimulationController` | `<<proposed controller>>` | `backend.controllers` / Application | Validate and delegate manager-initiated simulation and result retrieval | `simulationService: PosSimulationService` | `runSimulation(request)`; `getDailyResults(date)`; `getSales(date)` | Has exactly `1` `PosSimulationService` (**dependency**) | Core |
| `LeftoverManagementController` | `<<proposed controller>>` | `backend.controllers` / Application | Validate and delegate manager-confirmed leftover, donation and waste operations | `leftoverService: LeftoverManagementService` | `getAllocation(date, categoryId)`; `recommendAction(request)`; `recordDonation(request)`; `recordWaste(request)`; `updateDonationStatus(id, status)` | Has exactly `1` `LeftoverManagementService` (**dependency**) | Core |
| `ReportController` | `<<proposed controller>>` | `backend.controllers` / Application | Validate weekly-report and supported export requests | `reportService: ReportService` | `getWeeklyReport(weekStart)`; `exportWeeklyReport(weekStart, format)` | Has exactly `1` `ReportService` (**dependency**) | Core |
| `DashboardController` | `<<proposed controller>>` | `backend.controllers` / Application | Return read-only dashboard summaries | `dashboardService: DashboardService` | `getOperationalSummary(period)`; `getWasteSummary(period)`; `getFinancialSummary(period)` | Has exactly `1` `DashboardService` (**dependency**) | Core |

Controllers contain no Supabase client, SQL/query logic, production calculation, FIFO algorithm, simulation algorithm, model training or external HTTP calls.

## 6. TypeScript Business Service classes

| Final canonical name | UML stereotype | Architectural package/layer | Main responsibility | Essential attributes | Essential operations | Relationships, type and multiplicity | Diagram |
|---|---|---|---|---|---|---|---|
| `PredictionOrchestrationService` | `<<proposed service>>` | `backend.services.prediction` / Business | Assemble validated next-day input from suitable `DailySalesRecord` history and contextual data, call FastAPI, map results to `DailyPrediction`, and persist them | `dailySalesRecordRepo`; `dailyPredictionRepo`; `modelVersionRepo`; `contextService`; `mlClient` | `generatePrediction(targetDate)`; `getPrediction(targetDate)`; `buildPredictionRequest(targetDate)` | Has `1` each `DailySalesRecordRepo`, `DailyPredictionRepo`, `ModelVersionRepo`, `ContextService`, `FastApiMlClient` (**dependencies**); creates `1` `PredictionRequest`; receives `1` `PredictionResponse`; persists `1..*` `DailyPrediction` records | Both |
| `ModelManagementService` | `<<proposed service>>` | `backend.services.prediction` / Business | Enforce System-Administrator-only model lifecycle: assemble validated `DailySalesRecord`/context data, request candidate training and origin-labelled chronological evaluation, then activate or restore an approved version | `dailySalesRecordRepo`; `weatherRepo`; `calendarRepo`; `modelVersionRepo`; `featureImportanceRepo`; `modelEvaluationRepo`; `mlClient` | `trainCandidate(dateRange, administratorId)`; `evaluateCandidate(modelId, holdoutRange)`; `activateCandidate(modelId, administratorId)`; `restoreVersion(modelId, administratorId)`; `getActiveModels()`; `buildTrainingRequest(dateRange)`; `buildEvaluationRequest(holdoutRange, modelVersions)` | Has exactly `1` of each listed Repo and `1` `FastApiMlClient` (**dependencies**); creates `1` `TrainingRequest` or `EvaluationRequest`; receives `1` `TrainingResult` or `EvaluationResult`; changes activation only after a valid evaluation | ML |
| `RecommendationEngine` | `<<proposed service>>` | `backend.services.recommendation` / Business | Convert stored predictions, recipes and current usable inventory into feasible production quantities and options | `dailyPredictionRepo`; `recipeRepo`; `inventoryService` | `generateRecommendation(targetDate)`; `calculateRequirements(categoryId, quantity)`; `calculateMaxProducible(requirements)` | Has `1` `DailyPredictionRepo`, `1` `RecipeRepo`, `1` `InventoryService` (**dependencies**); consumes `1..*` `DailyPrediction`; creates `1..*` `ProductionRecommendation` DTOs (**composition of result data**) | Core |
| `InventoryService` | `<<proposed service>>` | `backend.services.inventory` / Business | Manage usable FIFO batches, restocking, expiry/discard and production deduction/reversal | `inventoryBatchRepo` | `listBatches()`; `getAvailableQuantity(ingredientId, date)`; `restock(request)`; `deductFifo(requirements, date)`; `reverseDeduction(reference)`; `discardBatch(id, reason)` | Has exactly `1` `InventoryBatchRepo` (**dependency**); controls `0..*` `InventoryBatch` records; depends on `0..*` `Recipe`/requirement data | Core |
| `ProductionDecisionService` | `<<proposed service>>` | `backend.services.recommendation` / Business | Validate final selected quantity, enforce reason/feasibility rules and persist the manager’s decision without deducting inventory | `decisionRepo` | `confirmDecision(command)`; `getDecisions(targetDate)` | Has exactly `1` `ProductionDecisionRepo` (**dependency**); creates or updates `1` `ProductionDecision` for one category/date | Core |
| `PosSimulationService` | `<<proposed service>>` | `backend.services.pos` / Business | Validate confirmed production/inventory, use the stored `DailyPrediction` as the already-contextualised baseline, and coordinate atomic simulation completion | `dailyPredictionRepo`; `decisionService`; `contextService`; `recordingService` | `simulateDay(targetDate, options)`; `getDailyResults(date)`; `getSales(date)` | Has `1` `DailyPredictionRepo`, `1` `ProductionDecisionService`, `1` `ContextService` (traceability/display only), and `1` `TransactionRecordingService` (**dependencies**); produces `1..*` each `DailyProduction`, `SalesTransaction`, `DailyResult` without reapplying context multipliers | Core |
| `TransactionRecordingService` | `<<proposed service>>` | `backend.services.pos` / Business | Execute the simulation write unit: deduct FIFO exactly once before sales, persist operational results, create simulation-origin sales history, and reverse/roll back deduction if later processing fails | `dailyProductionRepo`; `salesTransactionRepo`; `dailyResultRepo`; `dailySalesRecordRepo`; `inventoryService` | `recordCompletedSimulation(dayData)`; `reverseFailedSimulation(reference)` | Has exactly `1` of each listed Repo and `1` `InventoryService` (**dependencies**); persists `1..*` production/result/transaction records and exactly `1` `DailySalesRecord` per completed category/day | Core |
| `LeftoverManagementService` | `<<proposed service>>` | `backend.services.leftover` / Business | Recommend an action, validate available unallocated leftovers, and record only the Bakery Manager’s confirmed donation or waste | `dailyResultRepo`; `charityPartnerRepo`; `donationRepo`; `wasteRepo` | `getAllocation(date, categoryId)`; `recommendAction(request)`; `recordDonation(command)`; `recordWaste(command)`; `updateDonationStatus(id, status)` | Has exactly `1` of each listed Repo (**dependencies**); reads `1` `DailyResult`; creates `0..*` `Donation`/`WasteRecord` while enforcing `donated + wasted ≤ leftover` | Core |
| `DashboardService` | `<<proposed service>>` | `backend.services.reporting` / Business | Aggregate read-only prediction, production, sales, leftover-allocation, donation, waste and financial summaries | `dailyPredictionRepo`; `dailyResultRepo`; `donationRepo`; `wasteRepo` | `getOperationalSummary(period)`; `getWasteSummary(period)`; `getFinancialSummary(period)` | Has `1` each `DailyPredictionRepo`, `DailyResultRepo`, `DonationRepo`, `WasteRepo` (**dependencies**); reads but never mutates `0..*` domain records | Core |
| `ReportService` | `<<proposed service>>` | `backend.services.reporting` / Business | Generate weekly reports and delegate supported PDF/CSV rendering | `dailyResultRepo`; `donationRepo`; `wasteRepo`; `exportAdapter` | `generateWeeklyReport(weekStart)`; `exportWeeklyReport(weekStart, format)` | Has `1` each `DailyResultRepo`, `DonationRepo`, `WasteRepo`, `ReportExportAdapter` (**dependencies**); creates exactly `1` weekly report DTO per request | Core |
| `ContextService` | `<<proposed service>>` | `backend.services.context` / Business | Resolve weather/holiday context from cache or external providers and return a canonical `DailyContext` | `weatherRepo`; `calendarRepo`; `weatherClient`; `calendarClient` | `getContext(date, forceRefresh = false)` | Has `1` each `WeatherRepo`, `CalendarRepo`, `OpenWeatherMapClient`, `NagerDateClient` (**dependencies**); creates `1` `DailyContext` composed of `0..1` `WeatherRecord` and `0..*` `CalendarEvent` | Core |

### Service constraints

- `RecommendationEngine` works only with units, recipe quantities and inventory quantities. It does not depend on selling price, ingredient cost or financial services.
- `ProductionDecisionService.confirmDecision()` records a decision only. FIFO deduction occurs later during POS simulation.
- `DashboardService` is read-only with respect to source operational records.
- `PredictionOrchestrationService` and `ModelManagementService` are the only TypeScript services permitted to call `FastApiMlClient`.
- FastAPI results are persisted by the TypeScript services through TypeScript Repos.
- `PosSimulationService` must not multiply the stored prediction by weather, holiday, season or other contextual factors again.
- `LeftoverManagementService` never creates a donation or waste allocation without Bakery Manager confirmation.

## 7. TypeScript Repo classes

`BaseRepo<T>` is proposed as abstract so it cannot be used without a specific domain/table binding. All Supabase query construction is confined to this package.

| Final canonical name | UML stereotype | Architectural package/layer | Main responsibility | Essential attributes | Essential operations | Relationships, type and multiplicity | Diagram |
|---|---|---|---|---|---|---|---|
| `BaseRepo<T>` | `<<proposed abstract repository>>` | `backend.repos` / Data Access | Provide common typed CRUD and hold the only shared Supabase database client dependency | `tableName: string`; protected `supabaseClient` | `findAll(filters)`; `findOne(id)`; `insert(data)`; `update(id, data)`; `delete(id)` | Parent of `1..*` concrete Repos (**inheritance**); depends on exactly `1` Supabase database client (**dependency**) | Both |
| `DailyPredictionRepo` | `<<proposed repository>>` | `backend.repos` / Data Access | Persist and retrieve category/date predictions | Inherited base attributes | Inherited CRUD; `findByDate(date)`; `upsertMany(predictions)` | Extends `BaseRepo<DailyPrediction>` (**inheritance**); manages `0..*` `DailyPrediction` | Both |
| `DailySalesRecordRepo` | `<<proposed repository>>` | `backend.repos` / Data Access | Persist/query validated historical sales by date, category and `DataOrigin` for prediction, training and evaluation | Inherited base attributes | Inherited CRUD; `findSuitableHistory(categoryId, beforeDate, limit)`; `findValidatedRange(range, origins?)`; `upsertFromSimulation(result)` | Extends `BaseRepo<DailySalesRecord>` (**inheritance**); manages `0..*` `DailySalesRecord` | Both |
| `DailyResultRepo` | `<<proposed repository>>` | `backend.repos` / Data Access | Persist/query detailed results of completed POS simulations | Inherited base attributes | Inherited CRUD; `findByDate(date)`; `findByDateRange(from,to)`; `updateUnallocatedLeftover(id, quantity)`; `deleteByDate(date)` | Extends `BaseRepo<DailyResult>` (**inheritance**); manages `0..*` `DailyResult` | Both |
| `RecipeRepo` | `<<proposed repository>>` | `backend.repos` / Data Access | Retrieve/update recipe rows with category/ingredient identifiers | Inherited base attributes | Inherited CRUD; `findByCategory(categoryId)`; `findAllWithNames()`; `updateQuantity(categoryId, ingredientId, amount)` | Extends `BaseRepo<Recipe>` (**inheritance**); manages `0..*` `Recipe` | Core |
| `InventoryBatchRepo` | `<<proposed repository>>` | `backend.repos` / Data Access | Persist/query usable FIFO ingredient batches | Inherited base attributes | Inherited CRUD; `findUsableByIngredient(id,date)`; `findExpiringSoon(until)`; `findByReference(reference)` | Extends `BaseRepo<InventoryBatch>` (**inheritance**); manages `0..*` `InventoryBatch` | Core |
| `ProductionDecisionRepo` | `<<proposed repository>>` | `backend.repos` / Data Access | Persist/retrieve the manager’s final production choices | Inherited base attributes | Inherited CRUD; `findByDate(date)`; `upsertDecision(decision)` | Extends `BaseRepo<ProductionDecision>` (**inheritance**); manages `0..*` `ProductionDecision` | Core |
| `DailyProductionRepo` | `<<proposed repository>>` | `backend.repos` / Data Access | Persist/retrieve actual daily production records | Inherited base attributes | Inherited CRUD; `findByDate(date)`; `upsert(production)`; `deleteByDate(date)` | Extends `BaseRepo<DailyProduction>` (**inheritance**); manages `0..*` `DailyProduction` | Core |
| `SalesTransactionRepo` | `<<proposed repository>>` | `backend.repos` / Data Access | Persist/retrieve simulated sales transactions | Inherited base attributes | Inherited CRUD; `insertMany(items)`; `findByDate(date)`; `findByCategory(date,categoryId)`; `deleteByDate(date)` | Extends `BaseRepo<SalesTransaction>` (**inheritance**); manages `0..*` `SalesTransaction` | Core |
| `CharityPartnerRepo` | `<<proposed repository>>` | `backend.repos` / Data Access | Persist/retrieve active charity partners | Inherited base attributes | Inherited CRUD; `findActive()` | Extends `BaseRepo<CharityPartner>` (**inheritance**); manages `0..*` `CharityPartner` | Core |
| `DonationRepo` | `<<proposed repository>>` | `backend.repos` / Data Access | Persist/retrieve donations and status changes | Inherited base attributes | Inherited CRUD; `findByDate(date)`; `findByDateRange(from,to)`; `updateStatus(id,status)` | Extends `BaseRepo<Donation>` (**inheritance**); manages `0..*` `Donation` | Core |
| `WasteRepo` | `<<proposed repository>>` | `backend.repos` / Data Access | Persist/retrieve manager-confirmed waste allocations | Inherited base attributes | Inherited CRUD; `findByDate(date)`; `findByDateRange(from,to)` | Extends `BaseRepo<WasteRecord>` (**inheritance**); manages `0..*` `WasteRecord` | Core |
| `WeatherRepo` | `<<proposed repository>>` | `backend.repos` / Data Access | Cache canonical weather records by date | Inherited base attributes | Inherited CRUD; `findByDate(date)`; `upsert(record)` | Extends `BaseRepo<WeatherRecord>` (**inheritance**); manages `0..*` `WeatherRecord` | Core |
| `CalendarRepo` | `<<proposed repository>>` | `backend.repos` / Data Access | Cache canonical public-holiday/event records | Inherited base attributes | Inherited CRUD; `findByDate(date)`; `upsertMany(events)` | Extends `BaseRepo<CalendarEvent>` (**inheritance**); manages `0..*` `CalendarEvent` | Core |
| `ModelVersionRepo` | `<<proposed repository>>` | `backend.repos` / Data Access | Persist/read ML model metadata returned by FastAPI | Inherited base attributes | Inherited CRUD; `findActive()`; `activateVersion(id)`; `deactivatePrevious(categoryId)` | Extends `BaseRepo<ModelVersion>` (**inheritance**); manages `0..*` `ModelVersion` | ML |
| `FeatureImportanceRepo` | `<<proposed repository>>` | `backend.repos` / Data Access | Persist/read ranked feature importance returned by FastAPI | Inherited base attributes | Inherited CRUD; `replaceForModel(modelVersionId, items)`; `findByModelVersion(id)` | Extends `BaseRepo<FeatureImportance>` (**inheritance**); manages `0..*` `FeatureImportance` | ML |
| `ModelEvaluationRepo` | `<<proposed repository>>` | `backend.repos` / Data Access | Persist origin-labelled chronological-holdout evaluation results | Inherited base attributes | Inherited CRUD; `findByModelVersion(id)`; `insertResult(result)` | Extends `BaseRepo<ModelEvaluation>` (**inheritance**); manages `0..*` `ModelEvaluation` | ML |

Repos for users/access, settings, audit logs, notifications and device tokens remain required by the wider system plan. They are excluded only from these two focused diagrams and must not be removed from implementation planning.

## 8. TypeScript external-service adapter classes

| Final canonical name | UML stereotype | Architectural package/layer | Main responsibility | Essential attributes | Essential operations | Relationships, type and multiplicity | Diagram |
|---|---|---|---|---|---|---|---|
| `FastApiMlClient` | `<<proposed external adapter>>` | `backend.adapters` / Infrastructure | Encapsulate all TypeScript-to-FastAPI HTTP communication and typed DTO serialization | `baseUrl: Uri`; HTTP client; timeout/retry settings | `predict(request: PredictionRequest)`; `train(request: TrainingRequest)`; `evaluate(request: EvaluationRequest)` | Used by exactly `2` selected services: `PredictionOrchestrationService` and `ModelManagementService` (**dependencies**); sends `PredictionRequest`/`TrainingRequest`/`EvaluationRequest` and receives `PredictionResponse`/`TrainingResult`/`EvaluationResult` (**cross-process dependencies**) | Both |
| `OpenWeatherMapClient` | `<<proposed external adapter>>` | `backend.adapters` / Infrastructure | Retrieve raw weather data and map provider failures to application errors | `baseUrl`; `apiKey`; HTTP client | `fetchWeather(date, location)` | Used by `1` `ContextService` (**dependency**); calls OpenWeatherMap (**external dependency**) | Core |
| `NagerDateClient` | `<<proposed external adapter>>` | `backend.adapters` / Infrastructure | Retrieve Malaysian public-holiday data and map provider failures | `baseUrl`; `countryCode = "MY"`; HTTP client | `fetchYear(year)` | Used by `1` `ContextService` (**dependency**); calls Nager.Date (**external dependency**) | Core |
| `ReportExportAdapter` | `<<proposed external adapter>>` | `backend.adapters.reporting` / Infrastructure | Render an already-generated weekly report into a supported PDF or CSV payload without changing source data | supported formats `PDF`, `CSV` | `export(report, format): BinaryPayload` | Used by exactly `1` `ReportService` (**dependency**); depends on a PDF/CSV rendering library hidden from the UML (**external dependency**) | Core |

External adapters never call Repos or Supabase. Services decide caching and call the appropriate Repo.

## 9. Canonical domain models and core DTO

Domain models are pure data structures. Business calculations belong to Services. Operations are therefore limited to construction/serialization and are omitted from the UML operation compartments.

| Final canonical name | UML stereotype | Architectural package/layer | Main responsibility | Essential attributes only | Essential operations | Relationships, type and multiplicity | Diagram |
|---|---|---|---|---|---|---|---|
| `DataOrigin` | `<<proposed enumeration>>` | `shared.domain` / Model | Classify the provenance of a historical daily sales record | `ACTUAL_TRANSACTION`; `IMPORTED_HISTORICAL`; `SIMULATION_GENERATED` | None | Used by every `DailySalesRecord`; included in evaluation origin labels (**dependency**) | Both |
| `BreadCategory` | `<<proposed domain model>>` | `shared.domain` / Model | Identify one bakery product category | `id`; `name`; `shelfLifeHours`; `isActive`; `sellingPrice` (reporting only) | None | `1` category ↔ `0..*` `Recipe`, `DailyPrediction`, `ProductionDecision`, `DailyProduction`, `SalesTransaction`, `DailyResult` (**associations**) | Core |
| `Ingredient` | `<<proposed domain model>>` | `shared.domain` / Model | Identify one ingredient and its operational unit | `id`; `name`; `unit`; `reorderThreshold`; `unitCost` (reporting only) | None | `1` ingredient ↔ `0..*` `Recipe`; `1` ingredient ↔ `0..*` `InventoryBatch` (**associations**) | Core |
| `Recipe` | `<<proposed domain model>>` | `shared.domain` / Model | State the ingredient amount required for one unit of a category | `breadCategoryId`; `ingredientId`; `quantityPerUnit` | None | Each recipe row associates exactly `1` `BreadCategory` and exactly `1` `Ingredient`; each parent has `0..*` recipe rows (**associations**) | Core |
| `InventoryBatch` | `<<proposed domain model>>` | `shared.domain` / Model | Represent FIFO/expiry-controlled ingredient stock | `id`; `ingredientId`; `receivedDate`; `expiryDate`; `initialQuantity`; `remainingQuantity`; `status`; `source`; `reference` | None | Each batch associates exactly `1` `Ingredient`; one ingredient has `0..*` batches (**association**) | Core |
| `DailyPrediction` | `<<proposed domain model>>` | `shared.domain` / Model | Persist the predicted next-day units sold for one category | `id`; `targetDate`; `breadCategoryId`; `predictedUnitsSold`; `confidence`; `modelVersionId?`; `createdAt` | None | Each prediction associates exactly `1` `BreadCategory` and `0..1` `ModelVersion`; one prediction has `0..1` `ProductionDecision` and `0..1` `DailyResult` (**associations**) | Both |
| `ProductionRecommendation` | `<<proposed DTO>>` | `shared.contracts` / Model | Carry the calculated feasible production plan without database identity | `targetDate`; `breadCategoryId`; `predictionId`; `predictedUnitsSold`; `recommendedQuantity`; `maxProducible`; `ingredientRequirements`; `constraints`; `options` | None | Depends on exactly `1` `DailyPrediction`; contains `0..*` requirement/constraint/option value objects (**composition**) | Core |
| `ProductionDecision` | `<<proposed domain model>>` | `shared.domain` / Model | Persist the manager-confirmed production quantity | `id`; `targetDate`; `breadCategoryId`; `predictionId`; `recommendedQuantity`; `maxProducible`; `finalSelectedQuantity`; `selectedOption`; `decisionReason?`; `confirmedByUserId`; `confirmedAt` | None | Each decision associates exactly `1` `DailyPrediction` and `1` `BreadCategory`; one decision has `0..1` `DailyProduction` (**associations**) | Core |
| `DailyProduction` | `<<proposed domain model>>` | `shared.domain` / Model | Persist actual simulated production for one category/day | `id`; `productionDate`; `breadCategoryId`; `productionDecisionId`; `recommendedQuantity`; `actualProduced`; `adjustmentReason?` | None | Each record associates exactly `1` `BreadCategory` and `1` `ProductionDecision`; one record has `0..1` `DailyResult` (**associations**) | Core |
| `SalesTransaction` | `<<proposed domain model>>` | `shared.domain` / Model | Represent one simulated sale event | `id`; `saleDate`; `saleTime`; `timeSlot`; `breadCategoryId`; `quantity`; `unitPrice`; `subtotal` | None | Each transaction associates exactly `1` `BreadCategory`; one category/day has `0..*` transactions (**association**) | Core |
| `DailyResult` | `<<proposed domain model>>` | `shared.domain` / Model | Persist the detailed result of one completed category/day POS simulation | `id`; `resultDate`; `breadCategoryId`; `predictionId`; `dailyProductionId`; `predictedUnitsSold`; `produced`; `unitsSold`; `leftover`; `remainingUnallocatedLeftover`; `estimatedDemand`; `lostSales`; `wasteRatePct`; `revenue`; `ingredientCost`; `grossProfit` | None | Each result associates exactly `1` `BreadCategory`, `1` `DailyPrediction` and `1` `DailyProduction`; logically aggregates `0..*` `SalesTransaction`; creates exactly `1` simulation-origin `DailySalesRecord` after successful completion (**association/dependency**) | Both |
| `DailySalesRecord` | `<<proposed domain model>>` | `shared.domain` / Model | Store one validated category/day units-sold observation used by prediction, model training and evaluation | `id`; `salesDate`; `breadCategoryId`; `unitsSold`; `dataOrigin: DataOrigin`; `isValidated`; `sourceReferenceId?`; `createdAt` | None | Each record associates exactly `1` `BreadCategory` and exactly `1` `DataOrigin`; a simulation-generated record references exactly `1` `DailyResult`, while actual/imported records reference `0` `DailyResult` (**associations**) | Both |
| `CharityPartner` | `<<proposed domain model>>` | `shared.domain` / Model | Identify an approved charity partner | `id`; `name`; `contactInfo?`; `isActive` | None | One partner associates with `0..*` `Donation`; each donation has exactly `1` partner (**association**) | Core |
| `Donation` | `<<proposed domain model>>` | `shared.domain` / Model | Persist a Bakery-Manager-confirmed surplus donation and fulfilment status | `id`; `donationDate`; `dailyResultId`; `charityPartnerId`; `breadCategoryId`; `quantity`; `status`; `confirmedByUserId`; `notes?` | None | Each donation associates exactly `1` `DailyResult`, `1` `CharityPartner` and `1` `BreadCategory`; each result/category has `0..*` donations (**associations**) | Core |
| `WasteRecord` | `<<proposed domain model>>` | `shared.domain` / Model | Persist a Bakery-Manager-confirmed disposal allocation with its reason | `id`; `wasteDate`; `dailyResultId`; `breadCategoryId`; `quantity`; `disposalReason`; `confirmedByUserId`; `createdAt` | None | Each waste record associates exactly `1` `DailyResult` and `1` `BreadCategory`; each result/category has `0..*` waste records (**associations**) | Core |
| `WeatherRecord` | `<<proposed domain model>>` | `shared.domain` / Model | Cache canonical weather context for one date/location | `id`; `date`; `condition`; `temperatureHighC`; `temperatureLowC`; `humidityPct` | None | One `DailyContext` contains `0..1` weather record (**composition in DTO**); Repo manages `0..*` records | Core |
| `CalendarEvent` | `<<proposed domain model>>` | `shared.domain` / Model | Cache a canonical holiday/event and demand multiplier | `id`; `date`; `eventType`; `eventName`; `demandMultiplier` | None | One `DailyContext` contains `0..*` calendar events (**composition in DTO**) | Core |
| `DailyContext` | `<<proposed DTO>>` | `shared.contracts` / Model | Carry contextual data used by prediction and simulation | `date`; `weather?`; `calendarEvents` | None | Composes `0..1` `WeatherRecord` and `0..*` `CalendarEvent` (**composition**) | Both |
| `ModelVersion` | `<<proposed domain model>>` | `shared.domain` / Model | Persist candidate/active/inactive model metadata while the artifact remains in FastAPI storage | `id`; `breadCategoryId`; `version`; `modelType`; `artifactKey`; `lifecycleStatus`; `trainedAt`; `activatedAt?`; `activatedByUserId?` | None | One version associates with exactly `1` `BreadCategory`, `0..*` `DailyPrediction`, `FeatureImportance` and `ModelEvaluation`; at most `1` version per category is active (**associations**) | ML |
| `FeatureImportance` | `<<proposed domain model>>` | `shared.domain` / Model | Persist one ranked feature-importance value | `id`; `modelVersionId`; `featureName`; `importanceScore`; `rank` | None | Each importance row associates exactly `1` `ModelVersion`; one model version has `0..*` rows (**association**) | ML |
| `ModelEvaluation` | `<<proposed domain model>>` | `shared.domain` / Model | Persist an origin-labelled evaluation of a model against chronologically later holdout observations | `id`; `modelVersionId`; `holdoutStart`; `holdoutEnd`; `dataOrigins`; `evaluationLabel`; `mae`; `rmse`; `mape`; `rSquared`; `sampleCount`; `mapeSampleCount`; `evaluatedAt` | None | Each evaluation associates exactly `1` `ModelVersion` and `1..*` `DataOrigin` values; one model version has `0..*` evaluations (**associations**) | ML |

### Operational-data rule

`DailyProduction`, `SalesTransaction` and `DailyResult` are the selected model set for the simulation itself:

- `DailyProduction` records what was produced.
- `SalesTransaction` records simulated sale events.
- `DailyResult` aggregates category/day outcomes, including `leftover`, `remainingUnallocatedLeftover` and `lostSales`.
- A successful simulation creates one validated `DailySalesRecord` per category with `dataOrigin = SIMULATION_GENERATED`.
- `Donation` and `WasteRecord` record only manager-confirmed allocations made after the simulation.

No `SimulationRun` or `LeftoverRecord` classifier is selected. `WasteRecord` is selected because disposal quantity, reason, category and manager confirmation are now explicit requirements.

### Prediction-target rule

`DailySalesRecord.unitsSold` is the current ML target supplied in prediction, training and evaluation data. `DailyResult.lostSales` and `DailyResult.estimatedDemand` remain analytical fields and are not training targets. Simulation-generated history may support development training, but any evaluation containing it must be labelled simulation-based and must not be presented as real-world accuracy.

## 10. Shared Node.js–FastAPI DTO contract

These DTOs define the process boundary. Their schemas are proposed and must be implemented consistently in TypeScript and Python (or generated from one versioned schema). The TypeScript backend validates and supplies the data; FastAPI does not retrieve missing data from Supabase.

| Final canonical name | UML stereotype | Architectural package/layer | Main responsibility | Essential attributes only | Essential operations | Relationships, type and multiplicity | Diagram |
|---|---|---|---|---|---|---|---|
| `PredictionCategoryInput` | `<<proposed DTO>>` | `shared.ml_contracts` / Integration Contract | Carry validated, category-specific `DailySalesRecord` history and raw context needed for one prediction | `breadCategoryId`; `salesHistory`; `targetDate`; `weather?`; `calendarEvents`; `coldStartConfig` | None | Associates with exactly `1` `BreadCategory`; composes `0..*` dated sales observations with `DataOrigin` and `0..*` context/config values (**association/composition**) | ML |
| `PredictionRequest` | `<<proposed DTO>>` | `shared.ml_contracts` / Integration Contract | Request next-day units-sold predictions for one or more categories | `requestId`; `targetDate`; `categoryInputs`; `activeArtifactsByCategory` | None | Composes `1..*` `PredictionCategoryInput` and references `0..1` active model artifact per category (**composition/association**); sent by `FastApiMlClient` to the FastAPI prediction endpoint (**dependency**) | ML |
| `PredictionResult` | `<<proposed DTO>>` | `shared.ml_contracts` / Integration Contract | Return one category's predicted units sold, confidence and prediction mode | `breadCategoryId`; `predictedUnitsSold`; `confidence`; `predictionMode`; `modelVersion?`; `warnings` | None | Associates with exactly `1` category identity; composed by exactly `1` `PredictionResponse` (**composition**) | ML |
| `PredictionResponse` | `<<proposed DTO>>` | `shared.ml_contracts` / Integration Contract | Return the complete result of a prediction request | `requestId`; `targetDate`; `results`; `generatedAt` | None | Composes `1..*` `PredictionResult` (**composition**); returned by `PredictionService` through FastAPI to `FastApiMlClient` (**dependency**) | ML |
| `TrainingObservation` | `<<proposed DTO>>` | `shared.ml_contracts` / Integration Contract | Carry one validated category/day training/evaluation row whose target is units sold | `date`; `breadCategoryId`; `unitsSold`; `dataOrigin`; `weather?`; `calendarEvents`; `laggedUnitsSold` | None | Derived by TypeScript from exactly `1` `DailySalesRecord` plus `DailyContext` (**dependencies**); many observations are composed by training/evaluation requests (**composition**) | ML |
| `TrainingRequest` | `<<proposed DTO>>` | `shared.ml_contracts` / Integration Contract | Request category-model training from validated historical observations | `requestId`; `observationsByCategory`; `trainingConfig`; `requestedBy`; `requestedAt` | None | Composes observations for `1..*` categories, with `1..*` `TrainingObservation` per included category (**composition**); sent by `FastApiMlClient` to the FastAPI training endpoint (**dependency**) | ML |
| `ModelMetrics` | `<<proposed DTO>>` | `shared.ml_contracts` / Integration Contract | Carry model-quality measurements and their data-origin label for a category/model version | `breadCategoryId`; `modelVersion`; `mae`; `rmse`; `mape`; `rSquared`; `sampleCount`; `mapeSampleCount`; `dataOrigins`; `evaluationLabel` | None | Composed by `TrainingResult` and `EvaluationResult` (**composition**); MAPE excludes only zero-actual observations while MAE/RMSE retain them | ML |
| `TrainingResult` | `<<proposed DTO>>` | `shared.ml_contracts` / Integration Contract | Return trained model metadata, evaluation metrics and feature importance | `requestId`; `trainedModels`; `metrics`; `featureImportance`; `completedAt`; `warnings` | None | Composes `1..*` `ModelMetrics` and feature-importance values (**composition**); returned by `ModelTrainingService` to `FastApiMlClient` (**dependency**) | ML |
| `EvaluationRequest` | `<<proposed DTO>>` | `shared.ml_contracts` / Integration Contract | Request evaluation of specified candidate/existing model versions against chronologically later validated holdout observations | `requestId`; `modelArtifactsByCategory`; `holdoutObservationsByCategory`; `requestedAt` | None | Composes chronologically ordered observations for `1..*` categories, with `1..*` `TrainingObservation` per category (**composition**); references exactly `1` model artifact per included category (**association**); sent by `FastApiMlClient` to the FastAPI evaluation endpoint (**dependency**) | ML |
| `EvaluationResult` | `<<proposed DTO>>` | `shared.ml_contracts` / Integration Contract | Return evaluation-only results without changing the active model | `requestId`; `metrics`; `evaluatedAt`; `warnings` | None | Composes `1..*` `ModelMetrics` (**composition**); returned by `ModelEvaluationService` to `FastApiMlClient` (**dependency**) | ML |

The contract intentionally carries raw validated observations and context, not a precomputed feature matrix. `FeaturePreparationService` owns feature derivation, preventing training-serving skew inside the ML service. Validation occurs at both process boundaries: TypeScript validates application and data-availability rules; FastAPI validates DTO shape and ML-specific constraints.

## 11. Python/FastAPI machine-learning classes

FastAPI route functions are thin endpoint functions and are not UML classes. They perform request-schema validation, invoke one service operation and serialize its result. None of the following classifiers depends on Supabase, a TypeScript Repo or a database driver.

| Final canonical name | UML stereotype | Architectural package/layer | Main responsibility | Essential attributes only | Essential operations | Relationships, type and multiplicity | Diagram |
|---|---|---|---|---|---|---|---|
| `PredictionService` | `<<proposed service>>` | `ml.services` / ML Application | Select active-model or cold-start mode per category and coordinate feature preparation, artifact loading, prediction and confidence | `featurePreparationService`; `confidenceService`; `coldStartService`; `artifactStore`; `minimumHistoryDays = 30` | `predict(request: PredictionRequest): PredictionResponse` | Depends on exactly `1` `FeaturePreparationService`, `ConfidenceService`, `ColdStartService` and `ModelArtifactStore` (**dependencies**); uses `1` loaded `CategoryPredictor` only when at least `30` suitable records and an active artifact are supplied; consumes/returns prediction DTOs (**dependencies**) | ML |
| `FeaturePreparationService` | `<<proposed service>>` | `ml.services` / ML Application | Apply one canonical feature definition to prediction and training data | `featureSchemaVersion`; `requiredHistoryDays` | `preparePredictionFeatures(input: PredictionCategoryInput)`; `prepareTrainingFeatures(observations: TrainingObservation[])`; `validateFeatureCompleteness(data)` | Used by `PredictionService` and `ModelTrainingService` (**dependencies**); consumes `1..*` observations and produces feature matrices/value objects (**dependency/composition**) | ML |
| `ModelTrainingService` | `<<proposed service>>` | `ml.services` / ML Application | Train category-specific models, evaluate them, persist artifacts and return metadata | `featurePreparationService`; `evaluationService`; `artifactStore`; `trainingConfig` | `train(request: TrainingRequest): TrainingResult` | Depends on exactly `1` `FeaturePreparationService`, `1` `ModelEvaluationService` and `1` `ModelArtifactStore` (**dependencies**); creates/trains `1` `CategoryPredictor` per included category (**dependency**); consumes/returns training DTOs (**dependencies**) | ML |
| `ModelEvaluationService` | `<<proposed service>>` | `ml.services` / ML Application | Evaluate units-sold predictions on chronologically later holdout data and label results by origin | `metricDefinitions`; `artifactStore` | `evaluate(actualUnitsSold, predictedUnitsSold, origins): ModelMetrics`; `evaluateRequest(request: EvaluationRequest): EvaluationResult` | Used by `ModelTrainingService` (**dependency**); depends on exactly `1` `ModelArtifactStore` to load `1` `CategoryPredictor` per requested category (**dependencies**); creates `1` `ModelMetrics` per category/model; excludes zero actuals only from MAPE (**composition**) | ML |
| `ConfidenceService` | `<<proposed service>>` | `ml.services` / ML Application | Calculate a dedicated model-agreement indicator and expose low-confidence status without claiming a probability formula | configurable `lowConfidenceThreshold = 75%`; unapproved `confidencePolicy` placeholder | `calculateFromTreeVariance(predictor, features): number`; `isLowConfidence(score): boolean` | Used by `PredictionService` (**dependency**); depends on Random Forest tree variance/model agreement from `CategoryPredictor` (**dependency**). The final formula remains unresolved | ML |
| `ColdStartService` | `<<proposed service>>` | `ml.services` / ML Application | Produce a configurable heuristic prediction when fewer than 30 suitable historical sales records are supplied | `baseUnitsByCategory`; `contextAdjustmentFactors`; `coldStartConfidence`; configuration version | `predict(input: PredictionCategoryInput): PredictionResult`; `canUseTrainedModel(recordCount): boolean` | Used by exactly `1` `PredictionService` (**dependency**); consumes configured values supplied in the request/configuration boundary and returns `1` cold-start `PredictionResult` (**dependency**) | ML |
| `CategoryPredictor` | `<<proposed model wrapper>>` | `ml.models` / ML Domain | Encapsulate one bread category's random-forest model, linear-regression baseline and feature schema | `breadCategoryId`; `modelVersion`; `featureNames`; `randomForestModel`; `linearRegressionModel` | `train(features, unitsSold)`; `predict(features)`; `predictBaseline(features)`; `getFeatureImportance()` | Created by `ModelTrainingService` and loaded by `PredictionService`/`ModelEvaluationService` (**dependencies**); composes exactly `1` primary estimator and `1` baseline estimator (**composition**). Library estimator classes are excluded from the UML | ML |
| `ModelArtifactStore` | `<<proposed artifact store>>` | `ml.infrastructure` / ML Infrastructure | Save and load versioned local/deployed model artifacts without database access | `artifactDirectory`; `serializationFormat`; `schemaVersion` | `save(predictor: CategoryPredictor): artifactKey`; `load(artifactKey): CategoryPredictor`; `exists(artifactKey)` | Used by `PredictionService` and `ModelTrainingService` (**dependencies**); stores/loads `0..*` `CategoryPredictor` artifacts (**association**) | ML |

### Thin FastAPI endpoint modules

| Endpoint module operation (not a classifier) | Permitted delegation | Returned contract |
|---|---|---|
| `POST /predict` route function | Validate `PredictionRequest` → `PredictionService.predict()` | `PredictionResponse` |
| `POST /train` route function | Validate `TrainingRequest` → `ModelTrainingService.train()` | `TrainingResult` |
| `POST /evaluate` route function | Validate `EvaluationRequest` → `ModelEvaluationService.evaluateRequest()` | `EvaluationResult` |

Endpoint functions must not prepare features, train estimators, access artifacts directly or access Supabase.

## 12. Required dependency direction

### Valid call paths

| Scenario | Canonical direction |
|---|---|
| Standard mobile operation | Flutter `View` → `ApiClient` → Express router module → Controller → Service → Repo → Supabase |
| Weather/calendar enrichment | Controller → `ContextService` → `OpenWeatherMapClient`/`NagerDateClient`; `ContextService` → `WeatherRepo`/`CalendarRepo` for cache persistence |
| Generate predictions | `PredictionController` → `PredictionOrchestrationService` → Repos for validated input → `FastApiMlClient` → thin FastAPI route → Python `PredictionService`; response → `PredictionOrchestrationService` → `DailyPredictionRepo` |
| Train/evaluate models | `ModelManagementController` → `ModelManagementService` → `DailySalesRecordRepo`/context Repos for validated history → `FastApiMlClient` → thin FastAPI route → `ModelTrainingService`/`ModelEvaluationService`; response → `ModelManagementService` → model metadata/evaluation Repos |
| Activate/restore model | System Administrator → `ModelManagementController` → `ModelManagementService` → `ModelVersionRepo`; no candidate becomes active automatically |
| POS simulation | `PosSimulationController` → `PosSimulationService` → `TransactionRecordingService` → FIFO deduction once → operational Repos → `DailySalesRecordRepo`; any later failure reverses/rolls back the deduction |
| Leftover allocation | Bakery Manager → `LeftoverManagementController` → `LeftoverManagementService` → `DonationRepo`/`WasteRepo`/`DailyResultRepo`; the recommendation itself performs no write |

### Explicitly forbidden dependencies

| Forbidden dependency | Reason |
|---|---|
| Flutter View or `ApiClient` → Supabase database | Bypasses application policy and the repository boundary |
| Controller → Repo, Supabase or external adapter | Skips business orchestration in the Service layer |
| Service → Supabase client directly | Database access belongs to Repos |
| Repo → Service or Controller | Reverses the intended dependency direction |
| External adapter → Repo or Supabase | Adapters isolate external APIs; Services own orchestration and caching decisions |
| Any Python/FastAPI classifier → Supabase or TypeScript Repo | Node.js/Express is the sole database owner |
| TypeScript prediction/model Service → FastAPI route directly | All cross-process ML calls must pass through `FastApiMlClient` |
| FastAPI endpoint function → feature/model/artifact implementation details | Endpoint functions delegate to Python Services |

No interface realisation is selected in this focused proposal. The design uses class inheritance only for `BaseRepo<T>`. Interfaces may be introduced later at test or dependency-inversion boundaries when a concrete substitution requirement is agreed; they should not be added solely to make the UML more elaborate.

## 13. Classifier selection for the Chapter 4 diagrams

The following are the recommended diagram memberships. “Both” means the classifier appears only as a boundary/reference in each diagram; its full details should be shown in the diagram where it is most relevant.

### Core application diagram

| Package/layer | Selected classifiers |
|---|---|
| Flutter presentation | `PredictionView`, `InventoryView`, `PosSimulationView`, `LeftoverManagementView`, `DashboardView` |
| Flutter integration | `ApiClient` |
| TypeScript controllers | `PredictionController`, `RecommendationController`, `InventoryController`, `PosSimulationController`, `LeftoverManagementController`, `DashboardController`, `ReportController` |
| TypeScript services | `PredictionOrchestrationService`, `RecommendationEngine`, `InventoryService`, `ProductionDecisionService`, `PosSimulationService`, `TransactionRecordingService`, `LeftoverManagementService`, `DashboardService`, `ReportService`, `ContextService` |
| Repositories | `BaseRepo<T>`, `DailyPredictionRepo`, `DailySalesRecordRepo`, `DailyResultRepo`, `RecipeRepo`, `InventoryBatchRepo`, `ProductionDecisionRepo`, `DailyProductionRepo`, `SalesTransactionRepo`, `CharityPartnerRepo`, `DonationRepo`, `WasteRepo`, `WeatherRepo`, `CalendarRepo` |
| External adapters | `FastApiMlClient` as an ML boundary, `OpenWeatherMapClient`, `NagerDateClient`, `ReportExportAdapter` |
| Core domain/DTO | `DataOrigin`, `BreadCategory`, `Ingredient`, `Recipe`, `InventoryBatch`, `DailyPrediction`, `ProductionRecommendation`, `ProductionDecision`, `DailyProduction`, `SalesTransaction`, `DailyResult`, `DailySalesRecord`, `CharityPartner`, `Donation`, `WasteRecord`, `WeatherRecord`, `CalendarEvent`, `DailyContext` |

For readability, Chapter 4 may collapse related CRUD controllers/Repos into package blocks in the overview and expand only the prediction, recommendation, inventory and simulation collaborations in detailed class diagrams. This is a presentation choice, not a change to the canonical classifier catalogue.

### Machine-learning diagram

| Package/layer | Selected classifiers |
|---|---|
| TypeScript ML orchestration | `ModelManagementView`, `PredictionController`, `PredictionOrchestrationService`, `ModelManagementController`, `ModelManagementService`, `FastApiMlClient` |
| TypeScript persistence boundary | `DailySalesRecordRepo`, `DailyPredictionRepo`, `WeatherRepo`, `CalendarRepo`, `ModelVersionRepo`, `FeatureImportanceRepo`, `ModelEvaluationRepo` |
| Shared ML contract | `PredictionCategoryInput`, `PredictionRequest`, `PredictionResult`, `PredictionResponse`, `TrainingObservation`, `TrainingRequest`, `ModelMetrics`, `TrainingResult`, `EvaluationRequest`, `EvaluationResult` |
| Python ML services/infrastructure | `PredictionService`, `FeaturePreparationService`, `ModelTrainingService`, `ModelEvaluationService`, `ConfidenceService`, `ColdStartService`, `CategoryPredictor`, `ModelArtifactStore` |
| Referenced domain concepts | `DataOrigin`, `BreadCategory`, `DailyPrediction`, `DailySalesRecord`, `DailyContext`, `ModelVersion`, `ModelEvaluation`, `FeatureImportance` |

## 14. Naming migration and exclusions

### Canonical naming

| Earlier or ambiguous term | Final canonical term | Rationale |
|---|---|---|
| `DemandPrediction` | `DailyPrediction` | One consistent prediction entity throughout the report |
| Screen/Page suffix for selected Flutter screens | `View` | One presentation-layer convention |
| Repository suffix or inconsistent DAO names | `Repo`, including `BaseRepo<T>` | One concise repository convention |
| Generic TypeScript `PredictionService` | `PredictionOrchestrationService` | Distinguishes Node orchestration from Python model inference |
| Generic simulation controller/service names | `PosSimulationController` / `PosSimulationService` | Makes the operational scope explicit |

### Excluded from the class diagrams

| Excluded element | Treatment |
|---|---|
| Starter Flutter application classes, private `State` classes and small visual widgets | Implementation details; do not show |
| Express router files | Modules that map HTTP routes to Controller operations; do not model as classes |
| FastAPI route functions | Thin module-level endpoints; show only as a process boundary or note |
| Utility functions, configuration objects and dependency-injection bootstrap | Supporting implementation details; do not show |
| Express, FastAPI, Supabase SDK, Flutter framework and scikit-learn classes | Third-party/framework classifiers; mention only as technology annotations |
| Every Supabase table | Include only the selected domain concepts and Repos needed for the two architectural stories |
| `SimulationRun`, `LeftoverRecord` | Not selected because simulation identity/outcome and remaining leftover are represented by `DailyProduction`, `SalesTransaction` and `DailyResult` |
| User/settings/audit/notification/token classifiers | Preserve in the wider system plan; exclude only from these focused diagrams unless their interactions are being explained |

## 15. Unresolved issues

- Define and version the exact JSON/OpenAPI schemas and decide whether TypeScript/Python DTOs are generated from one source.
- Finalise the feature list, missing-data policy and mathematical definition/calibration of `confidence`; the history threshold is fixed at fewer than 30 suitable records and the initial low-confidence threshold is configurable at 75%.
- Decide the production artifact-storage, retention and backup process behind `ModelArtifactStore` and `ModelVersion.artifactKey`; candidate/evaluation/administrator-activation lifecycle rules are resolved.
- Specify transaction and idempotency rules for POS re-simulation, FIFO inventory deduction and multi-Repo writes.
- Decide whether foreground notifications use authenticated polling, SSE or a Node.js WebSocket relay; FCM remains the planned background delivery channel and Flutter must not subscribe directly to PostgreSQL changes.
