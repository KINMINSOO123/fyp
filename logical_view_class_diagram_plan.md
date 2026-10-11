# Smart Bakery Logical View: Source Audit and Class-Diagram Plan

> **Status update — historical audit, not the current design authority:** This file preserves the source-audit evidence that the Smart Bakery implementation does not yet exist. Its earlier proposed classifier names and relationships predate the revised Chapter 3 requirements. Use `logical_view_canonical_design.md` as the current canonical proposed design.
>
> The revision introduces `DataOrigin` (`ACTUAL_TRANSACTION`, `IMPORTED_HISTORICAL`, `SIMULATION_GENERATED`), `DailySalesRecord`, `WasteRecord`, `ColdStartService`, candidate/evaluation/administrator-activation model lifecycle, `PredictionOrchestrationService`, `FastApiMlClient`, Node.js-only Supabase access, the stored-prediction POS baseline, manager-confirmed leftover allocation, and weekly PDF/CSV reporting. Any conflicting `DemandPrediction`, direct FastAPI Repo/Supabase access, `DailyResult`-as-training-history, auto-donation, double context multiplication or router-as-class recommendation later in this historical audit is superseded.

**Purpose:** Copy-ready technical audit for planning the Chapter 4 Logical View class diagram.  
**Audit scope:** Entire workspace at `C:\Users\ASUS\StudioProjects\fyp`  
**Reference baseline:** `FYP Report.md`, especially Sections 4.2, 4.3 and 4.4.2  
**Source policy:** Generated files, platform runner scaffolding, third-party types, tests and unimportant visual widgets are excluded.

## 1. Executive conclusion

The Smart Bakery application described in the report and module documents is **not implemented in this workspace yet**.

The workspace currently contains:

| Language area | Implemented project source found | Result |
|---|---:|---|
| Flutter/Dart application | `lib/main.dart` and `test/widget_test.dart` | Only the standard Flutter counter starter is present. |
| Node.js/Express TypeScript backend | 0 `.ts` or `.tsx` files | No `backend/` directory or backend implementation exists. |
| Python/FastAPI ML service | 0 project `.py` files | No `ml_server/` directory or ML implementation exists. The only `.py` file is the generated `ios/Flutter/ephemeral/flutter_lldb_helper.py`, which is excluded. |

The Markdown documents under `Final Year Project/` repeatedly describe themselves as a **plan ready for implementation**. Their code fences are design sketches or pseudocode, not source files. Therefore:

1. A class diagram claimed to be verified against the current Smart Bakery implementation cannot yet be produced.
2. The only implemented user-defined classes are three irrelevant Flutter counter-demo classes.
3. All Smart Bakery controllers, services, repositories, adapters, domain models and ML classes listed later in this document are **planned, not implemented**.
4. Chapter 4 itself states that the design must be updated according to what has actually been implemented (`FYP Report.md:1938`). A current diagram containing the planned Smart Bakery classes must therefore be labelled **Proposed Logical View**, not **Implemented Logical View**.

## 2. Audit boundaries and evidence

| Check | Evidence |
|---|---|
| Complete unignored and ignored file scan | `rg --files -uu` was used, then generated/build/vendor paths were excluded. |
| Dart source | Only `lib/main.dart` and `test/widget_test.dart`. |
| TypeScript source | No `.ts` or `.tsx` files anywhere in the workspace. |
| Python source | Only the excluded generated Flutter LLDB helper. |
| Backend manifests | No `package.json`, TypeScript configuration or backend source tree exists. |
| ML manifests | No `requirements.txt`, `pyproject.toml`, FastAPI application or ML source tree exists. |
| Flutter dependencies | `pubspec.yaml` contains only Flutter and Cupertino Icons; planned Dio, Supabase, Firebase, charting and serialization packages are absent. |
| Plan status | Module README files state “Detailed plan — ready for implementation”; module trees use wording such as “Artifacts to Build.” |

Platform runner types such as Android `MainActivity`, iOS/macOS runner classes and Windows C++ window wrappers were excluded because they are outside the requested languages or are generated/framework scaffolding. `test/widget_test.dart` declares no user-defined class.

## 3. Implemented user-defined types

### 3.1 Flutter Views and API clients

| Item | File path | Language | Functional module | Architectural layer | Main responsibility | Important attributes | Public methods | Extends / implements | Dependencies and relationship types | Logical View decision |
|---|---|---|---|---|---|---|---|---|---|---|
| `MyApp` | `lib/main.dart:7` | Dart | None; Flutter starter | Presentation / View bootstrap | Builds the counter-demo `MaterialApp` | None | Constructor; `build(BuildContext)` | Inherits `StatelessWidget` | Creates/depends on `MyHomePage` (**dependency**); framework inheritance from `StatelessWidget` (**inheritance**) | Exclude; it has no Smart Bakery responsibility. |
| `MyHomePage` | `lib/main.dart:38` | Dart | None; counter demo | Presentation / View | Stores a page title and creates counter state | `final String title` | Constructor; `createState()` | Inherits `StatefulWidget` | Creates `_MyHomePageState` (**composition/creation dependency**); framework inheritance (**inheritance**) | Exclude; unimportant starter widget. |
| `_MyHomePageState` | `lib/main.dart:56` | Dart | None; counter demo | Presentation / View state | Maintains and renders the demo counter | Private `_counter: int` | `build(BuildContext)`; `_incrementCounter()` is private | Inherits `State<MyHomePage>` | Framework-managed link to `MyHomePage` (**association**); framework inheritance (**inheritance**) | Exclude; private demo state. |

There are no implemented Flutter API clients, Smart Bakery Views, Dart DTOs, abstract classes, interfaces, mixins, enums or interface-realisations.

### 3.2 Requested backend and shared groups

| Requested group | Implemented items | Finding |
|---|---:|---|
| TypeScript Controllers | 0 | No TypeScript source exists. Planned controllers are Express `Router` constants, not implemented classes. |
| TypeScript Business Services | 0 | No TypeScript source exists. Planned services are mostly exported functions or object literals, not classes. |
| Domain Models | 0 | No Smart Bakery Dart, TypeScript or Python domain-model source exists. |
| Repositories | 0 | No TypeScript or Python repository source exists. |
| External-Service Adapters | 0 | No weather, holiday, FCM or ML client adapter source exists. |
| Python/FastAPI machine-learning classes | 0 | No project Python source exists. |
| Shared interfaces and DTOs | 0 | No `backend/shared/types.ts`, `ml_server/src/models.py` or Dart model files exist. |

## 4. Planned Flutter Views and API clients that are not implemented

The following are explicit planned types or strongly implied artifacts in the Flutter planning documents. “Implied” means the document names a file and responsibility but does not declare a class body; its final class name cannot yet be verified.

| Planned item | Intended file path | Language | Functional module | Layer | Main responsibility | Important attributes | Public methods | Extends / implements | Dependencies and relationship types |
|---|---|---|---|---|---|---|---|---|---|
| `ApiClient` | `flutter_app/lib/services/api_client.dart` | Dart | Shared mobile infrastructure | Presentation / API client | Singleton HTTP client for the Express API | Static `_instance`; composed `_dio: Dio` | Factory constructor; `setAuthToken`; generic `get`, `post`, `put` | No user-defined parent | Owns `Dio` (**composition**); uses `ApiEndpoints` (**dependency**); communicates with TypeScript controllers over REST (**dependency**) |
| `ApiEndpoints` | `flutter_app/lib/services/api_endpoints.dart` | Dart | Shared mobile infrastructure | Presentation utility | Stores base URL and route builders | Static route constants | `financialFor`, `sales`, `waste`, `donationsForDate`, `donationsSummary` | None | Used by `ApiClient` and Views (**dependency**) |
| `HomeView` | `flutter_app/lib/views/home_view.dart` | Dart | Reporting and Dashboard | Presentation / View | Dashboard navigation shell | No field shown in widget class | `createState()` | Inherits `StatefulWidget` | Creates `_HomeViewState` (**composition/creation dependency**) |
| `_HomeViewState` | Same as `HomeView` | Dart | Reporting and Dashboard | Presentation / View state | Holds selected dashboard tab and navigation | `_currentIndex`; `_views` | `build()`; private `_navigateTo()` | Inherits `State<HomeView>` | Associated with `HomeView`; contains Morning/Midday/Evening Views (**association/composition**) |
| `LoginView` (implied) | `flutter_app/lib/views/login_view.dart` | Dart | User and Access Management | Presentation / View | Login and session entry | Not specified | Not specified | Not specified | Uses `AuthService` (**dependency**) |
| `MorningView` | `flutter_app/lib/views/morning_view.dart` | Dart | Demand Prediction; Inventory and Recommendation | Presentation / View | Displays prediction, feasible plan, constraints and stock status | None shown | `build()` | Inherits `StatelessWidget` | Uses `ApiClient` and planned widgets (**dependencies**) |
| `MiddayView` (implied) | `flutter_app/lib/views/midday_view.dart` | Dart | POS and Reporting | Presentation / View | Displays current sales progress | Not specified | Not specified | Not specified | Uses `ApiClient` and `MiddayViewData` (**dependencies**) |
| `EveningView` (implied) | `flutter_app/lib/views/evening_view.dart` | Dart | POS; Leftover/Donation; Reporting | Presentation / View | Runs manual POS simulation and displays end-of-day results | Not specified | Not specified | Not specified | Uses `ApiClient` and `EveningViewData` (**dependencies**) |
| `InventoryView` (implied) | `flutter_app/lib/views/inventory_view.dart` | Dart | Inventory and Recommendation | Presentation / View | Shows stock, FIFO batches, expiry and quality | Not specified | Not specified | Not specified | Uses `ApiClient` and inventory DTOs (**dependencies**) |
| `SalesView` (implied) | `flutter_app/lib/views/sales_view.dart` | Dart | POS and Reporting | Presentation / View | Shows time-slot distribution and sales trends | Not specified | Not specified | Not specified | Uses `ApiClient` and result DTOs (**dependencies**) |
| `WasteView` (implied) | `flutter_app/lib/views/waste_view.dart` | Dart | Leftover, Donation and Waste; Reporting | Presentation / View | Shows waste rate and donation impact | Not specified | Not specified | Not specified | Uses `ApiClient`, donation and result DTOs (**dependencies**) |
| `PredictionView` (implied) | `flutter_app/lib/views/prediction_view.dart` | Dart | Demand Prediction; Reporting | Presentation / View | Shows accuracy, confidence and feature importance | Not specified | Not specified | Not specified | Uses `ApiClient` and prediction DTOs (**dependencies**) |
| `FinancialSummaryView` (implied) | `flutter_app/lib/views/financial_summary_view.dart` | Dart | Reporting and Dashboard | Presentation / View | Reporting-only revenue, cost and profit view | Not specified | Not specified | Not specified | Uses `ApiClient` and `FinancialSummary` (**dependencies**) |
| `WeeklySummaryView` (implied) | `flutter_app/lib/views/weekly_summary_view.dart` | Dart | Reporting and Dashboard | Presentation / View | Displays category-level weekly results | Not specified | Not specified | Not specified | Uses `ApiClient` and `CategoryWeeklySummary` (**dependencies**) |
| `NotificationsView` (implied) | `flutter_app/lib/views/notifications_view.dart` | Dart | Alerts and Notifications | Presentation / View | Lists alerts and supports mark-read actions | Not specified | Not specified | Not specified | Uses mobile `NotificationService` and REST API (**dependencies**) |
| `ReminderSettingsView` (implied) | `lib/features/settings/reminder_settings_view.dart` | Dart | Alerts; System Administration | Presentation / View | Configures predefined reminder times | Not specified | Not specified | Not specified | Uses reminder endpoints/settings DTO (**dependency**) |
| `AuthService` (implied) | `flutter_app/lib/services/auth_service.dart` | Dart | User and Access Management | Client adapter | Wraps Supabase Authentication | Session/client references not specified | Login, logout and session operations not specified | No interface specified | Depends on Supabase Auth (**dependency**) |
| `FcmService` (implied) | `flutter_app/lib/services/fcm_service.dart` | Dart | Alerts and Notifications | Client adapter | Initializes FCM and manages device tokens/background messages | Firebase messaging/token state not specified | Register, refresh and unregister token operations are planned | No interface specified | Depends on Firebase Messaging and Node notification endpoints (**dependencies**) |
| Mobile `NotificationService` (implied) | `flutter_app/lib/services/notification_service.dart` | Dart | Alerts and Notifications | Client adapter | Subscribes to Realtime notifications and performs REST list/read actions | Realtime subscription state not specified | Subscribe, list, mark-read and mark-all-read operations are planned | No interface specified | Directly uses Supabase Realtime and indirectly uses backend notification controller (**dependencies**) |

The detailed Flutter example also names `PredictionCard`, `DonationCard`, `WasteChart`, `InventoryChecklist`, `LowStockBadge`, `ConstraintWarning`, `StatusIndicator`, `SalesTrackingTable`, `DailyResultsCard`, `FinancialCard`, `WasteProfitCorrelationChart` and `NotificationBell`. They are planned presentation-only widgets and should be excluded from the focused Logical View.

## 5. Planned TypeScript Controllers that are not implemented

The detailed plans declare controllers as Express `Router` constants. They are **modules/objects, not classes**, have no class attributes and do not extend or implement user-defined types. If the implementation remains functional, a UML diagram should label them `<<controller module>>` rather than falsely presenting them as concrete classes.

| Planned controller module | Intended path | Functional module | Public route operations | Main responsibility | Depends on | Relationship type |
|---|---|---|---|---|---|---|
| `healthController` | `backend/src/controllers/healthController.ts` | System Administration | `GET /health` | Return service health | Express only | Framework dependency |
| `bakerySettingsController` | `backend/src/controllers/bakerySettingsController.ts` | System Administration | `GET /bakery-settings` | Return bakery settings | Pseudocode directly imports Supabase | **Direct database dependency; planned violation** |
| `weatherController` | `backend/src/controllers/weatherController.ts` | External Data Integration | `GET /weather/:date`; `POST /weather/refresh` | Validate and delegate weather requests | `weatherService` | Controller-to-service dependency |
| `calendarController` | `backend/src/controllers/calendarController.ts` | External Data Integration | `GET /calendar/:date`; `POST /calendar/refresh` | Validate and delegate holiday requests | `calendarService` | Controller-to-service dependency |
| `contextController` | `backend/src/controllers/contextController.ts` | Demand Prediction support | `GET /context/:date` | Return combined weather/calendar context | `contextService.fetchContext` | Controller-to-service dependency |
| `predictionController` | `backend/src/controllers/predictionController.ts` | Demand Prediction | Planned `POST /predictions`; `GET /predictions/:date` | Orchestrate manual prediction generation and reads | A Node prediction service/client is not actually specified | Intended dependency is unclear; current plan remains a stub |
| `inventoryController` | `backend/src/controllers/inventoryController.ts` | Inventory and Recommendation | Inventory list, restock, deduct, log, batches, expiring, quality, discard and low-stock routes | Validate inventory requests and call service functions | `inventoryService` | Controller-to-service dependency |
| `recipeController` | `backend/src/controllers/recipeController.ts` | Inventory and Recommendation | List/get/update recipe routes | Validate and delegate recipe operations | `recipeService` | Controller-to-service dependency |
| `recommendationController` | `backend/src/controllers/recommendationController.ts` | Inventory and Recommendation | Get recommendation; create/get production decisions | Generate feasible plan and capture manager choice | `recommendationEngine`; `productionDecisionService` | Controller-to-service dependencies |
| `summaryController` | `backend/src/controllers/summaryController.ts` | Reporting and Dashboard | `GET /summary/weekly` | Return weekly category summary | `weeklySummaryService` | Controller-to-service dependency |
| `salesController` | `backend/src/controllers/salesController.ts` | POS and Sales Simulation | Simulate; get sales/results; correct results; query slot/category | Validate and delegate simulation/reporting actions | `simulationService`; repositories for reads in the sketch; `manualCorrectionService` | Mixed controller-to-service and possible controller-to-repository dependencies |
| `donationController` | `backend/src/controllers/donationController.ts` | Leftover, Donation and Waste | Charity CRUD; record/auto donation; date and summary reads | Validate and delegate donation workflows | `donationService`; charity repository is used by planned handlers | Mixed dependency; should be service-only |
| `dashboardController` | `backend/src/controllers/dashboardController.ts` | Reporting and Dashboard | Morning, midday, evening, prediction, inventory, sales, waste and financial routes | Return aggregated dashboard DTOs | `dashboardService`; `financialSummaryService` | Controller-to-service dependencies |
| `notificationController` | `backend/src/controllers/notificationController.ts` | Alerts and Notifications | List/read notifications; register/unregister FCM token | Expose notification centre and token management | `notificationService`; planned notification/token repositories | Should depend on service only |
| `reminderController` | `backend/src/controllers/reminderController.ts` | Alerts; System Administration | Reminder settings and optional test emission | Maintain predefined reminder times and test reminders | `operationReminderService`; settings service/repository | Controller-to-service dependency intended |

Chapter 4 also names `AuthController`, `SimulationController` and `ReportController`. Those names do not match the detailed plan, which relies on Supabase Auth, `salesController` and `dashboardController`/`summaryController` respectively.

## 6. Planned TypeScript Business Services that are not implemented

Most planned TypeScript services are exported functions or object literals, not classes. “Important attributes” are therefore absent; the dependencies shown below would become injected fields only if these modules were refactored into classes.

| Planned service classifier | Intended path | Functional module | Main responsibility | Public operations | Main dependencies | Relationship types |
|---|---|---|---|---|---|---|
| `weatherService` | `backend/src/services/weatherService.ts` | External Data Integration | Retrieve/cache canonical weather | `getWeather(date, options)` | `WeatherRepo`; `openWeatherMapClient`; condition mapper | Dependencies on repository and adapter |
| `calendarService` | `backend/src/services/calendarService.ts` | External Data Integration | Retrieve/cache and map holiday data | `getHolidays(date, options)` | `CalendarRepo`; `nagerDateClient` | Dependencies on repository and adapter |
| `contextService` | `backend/src/services/contextService.ts` | Demand Prediction support | Fetch weather and calendar in parallel | `fetchContext(date)` | `weatherService`; `calendarService` | Service-to-service dependencies |
| Backend `notificationService` | `backend/src/services/notificationService.ts` | Alerts and Notifications | Persist, deduplicate and emit alerts/reminders | Planned `emit(...)`, list/read operations | `NotificationRepo`; `FcmTokenRepo`; `pushService` | Dependencies on repositories and push adapter/service |
| `pushService` | `backend/src/services/pushService.ts` | Alerts and Notifications | Broadcast background pushes | Planned multicast send operation | `firebaseAdminClient`; `FcmTokenRepo` | Dependencies on adapter and repository |
| `operationReminderService` | `backend/src/services/operationReminderService.ts` | Alerts; Operations | Emit prediction/simulation reminders without running those operations | `emitOperationReminder(input)` | Backend `notificationService`; bakery settings | Service dependencies |
| `recipeService` | `backend/src/services/recipeService.ts` | Inventory and Recommendation | Read and update category recipes | `getAllRecipes`; `getRecipe`; `updateRecipe` | `RecipeRepo`; logger | Repository dependency |
| `ingredientCalculator` | `backend/src/services/ingredientCalculator.ts` | Inventory and Recommendation | Compute required grams and maximum producible units | `calculateRequirements`; `calculateMaxProducible`; `calculateMaxProducibleFromRequirements` | `recipeService`; inventory DTOs | Service/DTO dependencies |
| `constraintChecker` | `backend/src/services/constraintChecker.ts` | Inventory and Recommendation | Detect shortages and feasible maximum | `checkConstraints` | `ingredientCalculator`; constraint DTOs | Service/DTO dependencies |
| `fifoBatchService` | `backend/src/services/fifoBatchService.ts` | Inventory and Recommendation | Create batches, deduct FIFO and discard batches | `createRestockBatch`; `deductFifo`; `discardBatch` | `InventoryRepo`; `InventoryBatchRepo`; `InventoryLogRepo` | Repository dependencies; controls several records |
| `inventoryQualityService` | `backend/src/services/inventoryQualityService.ts` | Inventory and Recommendation | Detect expired active batches, mismatches, negatives and missing recipes | `runInventoryQualityChecks` | Inventory, batch and recipe repositories | Repository dependencies |
| `inventoryService` | `backend/src/services/inventoryService.ts` | Inventory and Recommendation | Inventory reads, dated maps, restock, production deduction/reversal and alerts | `getInventory`; map methods; `restock`; `deductForProduction`; `reverseProductionDeduction`; low-stock/batch/quality/log methods | Inventory repositories; `fifoBatchService`; `recipeService`; `inventoryQualityService` | Repository and service dependencies |
| `productionDecisionService` | `backend/src/services/productionDecisionService.ts` | Inventory and Recommendation | Validate and save the manager’s final quantity and audit it | `saveProductionDecision`; `getProductionDecisions` | `ProductionDecisionRepo`; `SystemLogRepo` | Repository dependencies |
| `recommendationEngine` | `backend/src/services/recommendationEngine.ts` | Inventory and Recommendation | Combine ML demand, recipes and inventory into feasible options | `generateRecommendation(date)` | Direct `fetch` to FastAPI; `InventoryRepo`; inventory/calculator/constraint services | Repository/service dependencies; direct external dependency |
| `ingredientCostCalculator` | `backend/src/services/ingredientCostCalculator.ts` | Financial Reporting | Reporting-only ingredient cost per unit/production | `costPerGram`; `costPerUnit`; `costForProduction` | `recipeService`; `IngredientRepo` | Service/repository dependencies |
| `weeklySummaryService` | `backend/src/services/weeklySummaryService.ts` | Reporting and Dashboard | Aggregate weekly production, sales, waste, donation and finance | `getWeeklySummary(weekStart)` | `DailyResultRepo`; `DonationRepo`; category data | Repository dependencies |
| `salesDistributionService` | `backend/src/services/salesDistributionService.ts` | POS and Sales Simulation | Distribute simulated sales by time slot | `distributeSold`; `randomTimeInSlot`; `randomInt` | Slot DTOs/constants | DTO dependency |
| `transactionRecordingService` | `backend/src/services/transactionRecordingService.ts` | POS and Sales Simulation | Persist transactions, production/results and deduct inventory | `recordDay`; `clearDateData` | Sales, production and result repositories; `inventoryService`; cost calculator | Repository and service dependencies |
| `simulationService` | `backend/src/services/simulationService.ts` | POS and Sales Simulation | Calculate demand/stock-outs and coordinate a simulation | `simulateDay(date, options)` | Context, predictions, decisions, distribution, recording and notification services | Service/repository dependencies |
| `manualCorrectionService` | `backend/src/services/manualCorrectionService.ts` | POS and Sales Simulation | Correct daily-result values, recompute derived/financial fields and audit | Planned `correctDailyResult(...)` | `DailyResultRepo`; cost calculator; `SystemLogRepo` | Repository/service dependencies |
| `donationService` | `backend/src/services/donationService.ts` | Leftover, Donation and Waste | Record/auto-allocate donations and calculate impact summaries | `autoDonateLeftovers`; `getDonationsForDate`; `getWeeklyDonationSummary` | `DonationRepo`; `CharityPartnerRepo`; `DailyResultRepo`; notification service | Repository and service dependencies |
| `dashboardService` | `backend/src/services/dashboardService.ts` | Reporting and Dashboard | Aggregate data for operational dashboard views | `getMorningView`; `getMiddayView`; `getEveningView`; prediction/inventory/sales/waste view methods | Many read repositories and operational services | Dependencies; broad orchestration responsibility |
| `financialSummaryService` | `backend/src/services/financialSummaryService.ts` | Financial Reporting | Aggregate cached revenue/cost/profit and correlation series | `getSummary(period, date?)` | `DailyResultRepo`; sales/category data | Repository dependencies |

Two architecturally necessary services are missing from the detailed TypeScript artifacts:

| Missing service | Why it is needed |
|---|---|
| `PredictionOrchestrationService` or `PredictionService` | `predictionController` needs a service that prepares context, invokes FastAPI, validates/maps the response and returns/stores the result. The detailed plan leaves the Node prediction controller as a stub and lets `recommendationEngine` call FastAPI directly. |
| `BakerySettingsService` | The planned `bakerySettingsController` queries Supabase directly. A service is required to preserve Controller → Service → Repository. |

## 7. Planned External-Service Adapters that are not implemented

| Planned adapter/classifier | Intended path | Language | Module / layer | Main responsibility | Public operations | Dependencies | Relationship type |
|---|---|---|---|---|---|---|---|
| `openWeatherMapClient` | `backend/src/adapters/openWeatherMapClient.ts` | TypeScript | External Data / adapter | Raw OpenWeatherMap HTTP access | `fetchWeather(date)` | Environment config; retry utility; HTTP | External dependency |
| `nagerDateClient` | `backend/src/adapters/nagerDateClient.ts` | TypeScript | External Data / adapter | Raw Nager.Date HTTP access | `fetchYearHolidays(year)` | Environment config; retry utility; HTTP | External dependency |
| `conditionMapper` | `backend/src/adapters/conditionMapper.ts` | TypeScript | External Data / mapper | Convert provider weather codes into canonical values | `mapCondition`; `getMultiplier` | Weather multiplier DTO | DTO dependency |
| `firebaseAdminClient` | `backend/src/adapters/firebaseAdminClient.ts` | TypeScript | Alerts / adapter | Initialize Firebase Admin and expose messaging client | Not specified | Firebase Admin SDK | External dependency |
| `pushService` | `backend/src/services/pushService.ts` | TypeScript | Alerts / external gateway | Send multicast background notifications | Send/broadcast operation not fully specified | Firebase client and token repository | Adapter/service dependency |
| `MachineLearningClient` | No detailed file is defined | TypeScript | Demand Prediction / adapter | Encapsulate Express-to-FastAPI requests and response mapping | Proposed `predict`, `retrain`, `evaluate`, `getActiveModel` | FastAPI REST API and ML DTOs | Missing adapter; should realise an ML-client interface |
| Mobile `AuthService` | Planned Flutter service path | Dart | User Access / adapter | Supabase authentication | Not specified | Supabase Auth | External dependency |
| Mobile `FcmService` | Planned Flutter service path | Dart | Alerts / adapter | Firebase messaging/token lifecycle | Not specified | Firebase Messaging; backend token endpoints | External dependency |

No adapter interface or interface-realisation is actually declared in source or in the detailed pseudocode. Chapter 4’s proposed `WeatherService`, `HolidayService`, notification-provider and prediction-model interfaces therefore remain conceptual only.

## 8. Planned Repositories that are not implemented

These are the only substantial planned TypeScript class hierarchy. `BaseRepo<T>` is a concrete generic class in the pseudocode, not an abstract class, and no repository interface is defined.

| Planned class | Intended path | Module | Layer | Important attribute | Public methods | Extends / implements | Dependencies and relationship types |
|---|---|---|---|---|---|---|---|
| `BaseRepo<T>` | `backend/src/repositories/baseRepo.ts` | Shared data access | Repository | Protected `tableName` | `findAll`; `findOne`; `insert`; `update`; `delete` | No user-defined parent/interface | Uses Supabase client (**dependency**); parent of concrete repos (**inheritance**) |
| `WeatherRepo` | `backend/src/repositories/weatherRepo.ts` | External Data | Repository | Inherited `tableName = weather_records` | Inherited CRUD; `findByDate`; `upsert` | Extends `BaseRepo<WeatherRecord>` | Depends on `WeatherRecord`; database association |
| `CalendarRepo` | `backend/src/repositories/calendarRepo.ts` | External Data | Repository | `calendar_events` table | Inherited CRUD; `findByDate`; `upsertMany` | Extends `BaseRepo<CalendarEvent>` | Depends on `CalendarEvent`; database association |
| `BakerySettingsRepo` | `backend/src/repositories/bakerySettingsRepo.ts` | System Administration | Repository | `bakery_settings` table | Inherited CRUD; `getSingle` | Extends `BaseRepo<BakerySettings>` | Depends on `BakerySettings` |
| `SystemLogRepo` | `backend/src/repositories/systemLogRepo.ts` | System Administration | Repository | `system_logs` table | Inherited CRUD | Extends `BaseRepo<SystemLog>` | Depends on `SystemLog` |
| `NotificationRepo` | `backend/src/repositories/notificationRepo.ts` | Alerts and Notifications | Repository | `notifications` table | Planned CRUD, `findUnread`, deduplication query | Intended to extend `BaseRepo<Notification>` | Depends on `Notification` |
| `FcmTokenRepo` | `backend/src/repositories/fcmTokenRepo.ts` | Alerts and Notifications | Repository | `fcm_tokens` table | Planned find/upsert/delete by user or token | Intended to extend `BaseRepo<FcmToken>` | Depends on `FcmToken` |
| `BreadCategoryRepo` | `backend/src/repositories/breadCategoryRepo.ts` | Inventory; shared catalog | Repository | `bread_categories` table | Planned CRUD/`findAll` | Intended to extend `BaseRepo<BreadCategory>` | Depends on `BreadCategory` |
| `IngredientRepo` | `backend/src/repositories/ingredientRepo.ts` | Inventory | Repository | `ingredients` table | Planned CRUD/`findAll` | Intended to extend `BaseRepo<Ingredient>` | Depends on `Ingredient` |
| `RecipeRepo` | `backend/src/repositories/recipeRepo.ts` | Inventory and Recommendation | Repository | `recipes` table | Inherited CRUD; `findAllWithNames`; `findByCategory`; `updateGramsPerUnit` | Extends `BaseRepo<any>` in sketch | Depends on recipe/domain rows; joins category and ingredient |
| `InventoryRepo` | `backend/src/repositories/inventoryRepo.ts` | Inventory and Recommendation | Repository | `inventory` table | Inherited CRUD; `findByIngredientId`; `findAllWithIngredients`; `findLowStock` | Extends `BaseRepo<Inventory>` | Depends on `Inventory` and `Ingredient` |
| `InventoryBatchRepo` | `backend/src/repositories/inventoryBatchRepo.ts` | Inventory and Recommendation | Repository | `inventory_batches` table | Inherited CRUD; `findUsableByIngredient`; filter/expiry queries | Extends `BaseRepo<any>` in sketch | Depends on `InventoryBatch` and `Ingredient` |
| `InventoryLogRepo` | `backend/src/repositories/inventoryLogRepo.ts` | Inventory and Recommendation | Repository | `inventory_log` table | Inherited CRUD; `findByFilters`; `findMovementsUntil` | Extends `BaseRepo<any>` in sketch | Depends on inventory movement records |
| `PredictionRepo` | `backend/src/repositories/predictionRepo.ts` | Demand Prediction | Repository | `daily_predictions` table | Inherited CRUD; `findByDate` | Extends `BaseRepo<any>` in sketch | Depends on `DailyPrediction` |
| `ProductionDecisionRepo` | `backend/src/repositories/productionDecisionRepo.ts` | Inventory and Recommendation | Repository | `production_decisions` table | Inherited CRUD; `findByDate`; `upsertDecision` | Extends `BaseRepo<any>` in sketch | Depends on `ProductionDecision` |
| `DailyProductionRepo` | `backend/src/repositories/dailyProductionRepo.ts` | POS and Sales Simulation | Repository | `daily_production` table | Inherited CRUD; `findByDate`; `deleteByDate`; `upsert` | Extends `BaseRepo<DailyProduction>` | Depends on `DailyProduction` |
| `SalesTransactionRepo` | `backend/src/repositories/salesTransactionRepo.ts` | POS and Sales Simulation | Repository | `sales_transactions` table | Inherited CRUD; date/slot/category queries; `deleteByDate`; `insertMany` | Extends `BaseRepo<SalesTransaction>` | Depends on `SalesTransaction` |
| `DailyResultRepo` | `backend/src/repositories/dailyResultRepo.ts` | POS; Reporting | Repository | `daily_results` table | Date/range reads; delete; upsert plus inherited CRUD | Extends `BaseRepo<DailyResult>` in final sketch | Depends on `DailyResult`; duplicated across Module 3 and 4 plans |
| `CharityPartnerRepo` | `backend/src/repositories/charityPartnerRepo.ts` | Leftover and Donation | Repository | `charity_partners` table | Inherited CRUD; `findActive` | Extends `BaseRepo<CharityPartner>` | Depends on `CharityPartner` |
| `DonationRepo` | `backend/src/repositories/donationRepo.ts` | Leftover and Donation | Repository | `donations` table | Date/range reads; insert; update status plus inherited CRUD | Extends `BaseRepo<Donation>` in final sketch | Depends on `Donation`; duplicated across Module 3 and 5 plans |
| `ModelVersionRepo` | No detailed TypeScript class file is specified | Demand Prediction Reporting | Repository | `ml_model_versions` table | Planned active/version reads | Intended BaseRepo relationship is unclear | Duplicates ownership with Python `modelVersionRepo` |
| `FeatureImportanceRepo` | No detailed TypeScript class file is specified | Demand Prediction Reporting | Repository | `feature_importance` table | Planned version-based reads | Intended BaseRepo relationship is unclear | Duplicates ownership with Python `featureImportanceRepo` |

All planned repository-to-`BaseRepo` links are **inheritance**. Service-to-repository links are **dependencies**, not composition, unless repository instances are later injected and lifecycle-owned by a service. Domain objects returned by repositories are data dependencies/associations.

## 9. Planned Domain Models that are not implemented

The TypeScript design uses Zod schemas with inferred type aliases. These are pure data shapes, not classes and have no public methods, inheritance or interface implementation. The data-foundation plan promises one TypeScript schema per database table and equivalent Pydantic models, but explicitly sketches only a subset.

| Planned domain model/type | Planned language/path | Functional module | Layer | Important attributes | Important associations / relationship types |
|---|---|---|---|---|---|
| `BakerySettings` | TypeScript `backend/shared/types.ts` | System Administration | Domain Model | Bakery identity, location/hours and configuration/reminder settings | Used by settings/context/reminder services (**association/dependency**) |
| `BreadCategory` | TypeScript `backend/shared/types.ts` | Inventory; shared catalog | Domain Model | `id`, `name`, `display_order`, `shelf_life_hours`, `selling_price`, `is_active` | One category has recipe rows, predictions, decisions, production, sales and results (**associations**) |
| `Ingredient` | TypeScript `backend/shared/types.ts` | Inventory | Domain Model | `id`, `name`, `unit`, `unit_cost`, `reorder_threshold` | Associated with recipes, inventory snapshot and batches |
| `Recipe` | Promised TypeScript schema | Inventory and Recommendation | Domain Model | `bread_category_id`, `ingredient_id`, `grams_per_unit` | Links `BreadCategory` and `Ingredient` (**associations**) |
| `Inventory` | Promised TypeScript schema | Inventory | Domain Model | `id`, `ingredient_id`, `quantity_grams`, timestamps | Associated with one `Ingredient`; summarises its batches |
| `InventoryBatch` | TypeScript `backend/shared/types.ts` | Inventory | Domain Model | IDs, received/expiry dates, initial/remaining grams, source, status | Associated with `Ingredient`; controlled by FIFO service |
| `InventoryLog` | Promised TypeScript schema | Inventory | Domain Model | Inventory/batch IDs, signed change, reason, effective date | Associated with `Inventory` and optionally `InventoryBatch` |
| `WeatherRecord` | Promised TypeScript schema | External Data | Domain Model | Date, condition, high/low temperature, humidity | Associated with prediction context and optionally `DailyPrediction` |
| `CalendarEvent` | Promised TypeScript schema | External Data | Domain Model | Date, event type/name, demand multiplier | Composed into `DailyContext` |
| `MLModelVersion` | Promised TypeScript/Python model | Demand Prediction | Domain Model | Category ID, version, model type/path, metrics, active flag, timestamps | Associated with `BreadCategory`, `DailyPrediction`, feature importance |
| `DailyPrediction` | TypeScript `backend/shared/types.ts`; planned Python `models.py`; planned Dart model | Demand Prediction | Domain Model | Date, category ID, predicted demand, confidence, model/weather IDs, timestamp | Associated with `BreadCategory`, `MLModelVersion`, `WeatherRecord` |
| `ProductionDecision` | TypeScript shared type; planned Python and Dart model | Inventory and Recommendation | Domain Model | Date/category/prediction IDs; predicted, recommended, max and final quantities; option/reason/confirmer/timestamps | Associated with `DailyPrediction`, `BreadCategory` and authenticated user |
| `DailyProduction` | TypeScript shared type | POS and Sales Simulation | Domain Model | Date, category ID, decision ID, recommended/actual quantity, adjustment reason | Associated with `ProductionDecision` and `BreadCategory` |
| `SalesTransaction` | TypeScript shared type | POS and Sales Simulation | Domain Model | Date/time/slot, category, quantity, unit price, subtotal | Associated with `BreadCategory`; aggregated into `DailyResult` |
| `DailyResult` | TypeScript shared type; planned Dart model | POS; Reporting | Domain Model | Date/category/prediction IDs; predicted, produced, sold, leftover, demand, lost sales, waste/error and finance fields | Associated with `BreadCategory`, `DailyPrediction`, sales and donations |
| `CharityPartner` | TypeScript shared type | Leftover and Donation | Domain Model | ID, name, contact information, active flag | One partner has many `Donation` records (**association**) |
| `Donation` | TypeScript shared type; planned Dart model | Leftover and Donation | Domain Model | Partner/date/category IDs, quantity, status, notes, timestamp | Associated with `CharityPartner` and optionally `BreadCategory` |
| `FeatureImportance` | Promised TypeScript/Python model | Demand Prediction | Domain Model | Model version ID, feature name, score and rank | Associated with `MLModelVersion` |
| `SystemLog` | Promised TypeScript model | System Administration | Domain Model | Event type, severity, payload and timestamp | Written by multiple services (**dependency**) |
| `Notification` | High-level plan only | Alerts and Notifications | Domain Model | Type, title, message, related ID, read/delivery status and timestamp | Associated with recipient/device events; emitted by modules 2–6 |
| `FcmToken` | High-level plan only | Alerts and Notifications | Domain Model | User ID, token, device information and timestamps/status | Associated with authenticated user; used by push service |
| `UserProfile` | Mentioned in Chapter 4 only | User and Access | Domain Model | Role/profile fields are not specified in detailed data plan | Associated with authentication, decisions and notification tokens; missing planned schema |

The report also names `ProductionRecommendation`, `SimulationRun`, `LeftoverRecord` and `WasteRecord`. The detailed database/type plans do not define these as standalone domain models:

- recommendation output is represented by `CategoryRecommendation`/`FullRecommendation`;
- simulation is represented by `DailyProduction`, `SalesTransaction`, `DailyResult` and `SimulationSummary`;
- leftover and waste are fields/derived values in `DailyResult`;
- donation is a separate entity.

This should be made explicit before choosing class names for the diagram.

## 10. Planned Shared Interfaces and DTOs that are not implemented

These items contain data only. Unless stated otherwise, public methods are **none**, and there is no extends/implements relationship. Zod `extend()` is schema composition, not class inheritance.

| Planned interface/DTO | Intended path / language | Module / layer | Main responsibility | Important attributes | Dependencies and relationship types |
|---|---|---|---|---|---|
| `Env` | `backend/src/config/env.ts`; TypeScript | Shared configuration | Validated environment shape | Server, Supabase, external API and ML URL settings | Inferred from Zod schema (**dependency**) |
| Express `Request.user` augmentation | `backend/src/middleware/auth.ts`; TypeScript | User Access / API boundary | Add authenticated user information to Express request | User ID/email/role shape not finalised | Extends Express namespace structurally |
| `GetWeatherOptions` | `backend/src/services/weatherService.ts`; TypeScript | External Data / request option | Control cache refresh | `forceRefresh?` | Used by `weatherService` (**dependency**) |
| `DailyContext` | `backend/src/services/contextService.ts`; TypeScript | Demand Prediction / DTO | Carry target date, canonical weather and calendar events | `date`, nullable `weather`, `calendar[]` | Composes weather/calendar subobjects (**composition**) |
| `RecipeMap` | `backend/shared/types.ts`; TypeScript | Inventory / DTO | Map category → ingredient → grams per unit | Nested `Record<string,...>` | Used by recipe/calculation services |
| `InventoryMap` | `backend/shared/types.ts`; TypeScript | Inventory / DTO | Map ingredient name → available grams | `Record<string, number>` | Used by calculator/recommendation services |
| `InventoryItem` | `backend/shared/types.ts`; TypeScript | Inventory / response DTO | Inventory list row with ingredient metadata | IDs/name, grams, unit, threshold, low-stock flag, timestamp | Composes inventory and ingredient data |
| `ExpiringBatchAlert` | `backend/shared/types.ts`; TypeScript | Inventory; Alerts | Add expiry urgency to a batch | All batch fields plus `days_until_expiry`, `severity` | Zod-schema extension of `InventoryBatch` (**structural composition**) |
| `InventoryQualityIssue` | `backend/shared/types.ts`; TypeScript | Inventory / response DTO | Describe a quality/integrity problem | `code`, `severity`, `message`, optional ingredient/category/batch IDs | Associates with affected domain IDs |
| `IngredientRequirement` | `backend/shared/types.ts`; TypeScript | Recommendation / DTO | Required/available grams for one ingredient | IDs/name, grams per unit, units, total/have grams, sufficient flag | Associated with `Ingredient`; composed by recommendation |
| `Constraint` | `backend/shared/types.ts`; TypeScript | Recommendation / DTO | Describe an ingredient shortage | Ingredient fields, have/need/shortfall grams, max producible | Derived from `IngredientRequirement` (**dependency**) |
| `RecommendationOption` | `backend/shared/types.ts`; TypeScript | Recommendation / DTO | Present reduced-production or ordering choice | ID/action/quantity/order items/note/recommended flag | Composed by `CategoryRecommendation` |
| `CategoryRecommendation` | `backend/shared/types.ts`; TypeScript | Recommendation / response DTO | Full feasible recommendation for one category | Category, prediction/confidence, recommended/max quantity, requirements, constraints, options | Composes requirement, constraint and option DTOs (**composition**) |
| `CategoryWeeklySummary` | `backend/shared/types.ts`; TypeScript | Reporting / response DTO | Category weekly operations/finance summary | Produced/sold/leftover/donated, waste trend and finance totals | Aggregates `DailyResult`/`Donation` data |
| `RecipeRow` | `backend/src/services/recipeService.ts`; TypeScript interface | Inventory / internal DTO | Simplified recipe ingredient row | Ingredient ID/name, grams per unit | Associated with `Ingredient` |
| Duplicate local `IngredientRequirement` | `backend/src/services/ingredientCalculator.ts`; TypeScript interface | Recommendation / internal DTO | Same responsibility/fields as shared type | Same seven fields as shared DTO | Duplicate dependency shape; should be removed or imported |
| `CheckResult` | `backend/src/services/constraintChecker.ts`; TypeScript interface | Recommendation / internal DTO | Return constraint check outcome | `constraints[]`, `max_producible`, `has_constraints` | Composes `Constraint` objects |
| `FifoDeduction` | `backend/src/services/fifoBatchService.ts`; TypeScript interface | Inventory / internal DTO | Record grams deducted from one batch | Batch/ingredient IDs, expiry, deducted grams | Associated with `InventoryBatch` |
| Duplicate local `InventoryItem` | `backend/src/services/inventoryService.ts`; TypeScript interface | Inventory / internal DTO | Same inventory-list row as shared DTO | Same fields as shared type | Duplicate shape; should be imported from shared types |
| `FullRecommendation` | `backend/src/services/recommendationEngine.ts`; TypeScript interface | Recommendation / response DTO | Top-level recommendation response | Date, category recommendations, low-stock alerts, expiring batches, quality data | Composes `CategoryRecommendation` and alert/quality DTOs |
| `SimulateRequest` | `backend/shared/types.ts`; TypeScript | POS / request DTO | Configure manual simulation | `date`, optional production overrides, `dryRun`, `forceRefresh` | Consumed by `salesController` |
| `SimulationSummary` | `backend/shared/types.ts`; TypeScript | POS / response DTO | Return category and total simulation results | Per-category prediction/production/demand/sales/waste/finance; totals; context; dry-run flag | Composes category result subobjects |
| `SlotAllocation` | `backend/src/services/salesDistributionService.ts`; TypeScript interface | POS / internal DTO | Units sold by morning/afternoon/evening | Three slot quantities | Used by distribution service |
| `SlotWeights` | Same file; TypeScript interface | POS / internal DTO | Weight per sales time slot | Three numeric weights | Input to distribution service |
| `DayData` | `backend/src/services/transactionRecordingService.ts`; TypeScript interface | POS / internal DTO | Bundle one completed simulated day for persistence | Date, per-category production/results/transactions and context | Composes transaction/production/result data |
| `SimulateOptions` | `backend/src/services/simulationService.ts`; TypeScript interface | POS / internal option DTO | Optional overrides/dry-run/refresh controls | Override map and Boolean flags | Maps from `SimulateRequest` |
| `AutoDonateRequest` | `backend/shared/types.ts`; TypeScript | Donation / request DTO | Request automatic donation for a date | Body containing `date` | Consumed by donation controller/service |
| `DonationSummary` | `backend/shared/types.ts`; TypeScript | Donation / response DTO | Result of donation allocation | Date/status/partner/total/donation ID/items | Composes donated category items |
| `WeeklyDonationSummary` | `backend/shared/types.ts`; TypeScript | Donation / response DTO | Weekly donation/social-impact summary | Week range, donated/meals totals, charity breakdown | Aggregates `Donation`/`CharityPartner` |
| `MorningViewData` | `backend/shared/types.ts`; TypeScript | Dashboard / response DTO | Prediction/recommendation dashboard payload | Date, weather, holidays, category plans, low-stock and readiness | Composes context and recommendation data |
| `MiddayViewData` | `backend/shared/types.ts`; TypeScript | Dashboard / response DTO | Current sales-progress payload | Date/time, category progress/status, overall status | Aggregates prediction and transaction data |
| `EveningViewData` | `backend/shared/types.ts`; TypeScript | Dashboard / response DTO | End-of-day operations/donation/ML payload | Category results/finance, totals, donation and model metrics | Composes result, donation and model data |
| `FinancialSummary` | `backend/shared/types.ts`; TypeScript | Financial Reporting / response DTO | Reporting-only totals and waste/profit chart series | Period/date range, totals, category values, correlation chart | Aggregates cached result/transaction data |
| `ReminderKind` | `backend/src/services/operationReminderService.ts`; TypeScript union | Alerts / enum-like type | Limit reminder types | `prediction_reminder` or `simulation_reminder` | Used by `ReminderInput` |
| `ReminderInput` | Same file; TypeScript type | Alerts / request DTO | Describe reminder emission | Kind and scheduling/message data | Composes `ReminderKind` |
| `LogLevel` | `backend/src/utils/logger.ts`; TypeScript union | Shared utility | Limit log severity | `info`, `warn`, `error` | Used by logger |

### Enum finding

There are no implemented or planned TypeScript `enum` declarations, Python `Enum` classes or Dart enums. The plans instead use Zod enums and string-literal unions for:

- time slot;
- inventory-batch status;
- quality issue code and severity;
- production-decision option;
- recommendation action;
- weekly trend;
- donation status;
- dashboard status;
- financial period;
- log level;
- reminder kind.

These may be drawn as UML enumerations only if the eventual implementation creates or consistently owns those value sets. They must not be reported as implemented enums today.

## 11. Planned Python/FastAPI machine-learning classes that are not implemented

No ML/FastAPI Python source exists. The following class declarations appear only inside Markdown code fences.

| Planned item | Intended path | Language | Functional module | Layer | Main responsibility | Important attributes | Public methods | Extends / implements | Dependencies and relationship types |
|---|---|---|---|---|---|---|---|---|---|
| `Settings` | `ml_server/src/config/env.py` | Python | Shared ML configuration | Configuration | Load Supabase, model and training settings | Supabase URL/key, model directory, minimum days, RF parameters, test ratio | No custom public method | Inherits `BaseSettings` | Pydantic-settings inheritance; used by training/persistence (**dependency**) |
| `CategoryPredictor` | `ml_server/src/services/trainService.py` | Python | Demand Prediction | ML Business Service / model wrapper | Own one category’s Random Forest primary model and Linear Regression baseline | `category_name`, `rf`, `lr` | `train`; `predict`; `predict_baseline`; `feature_importance` | No user-defined parent/interface | Owns sklearn estimators (**composition**); uses confidence function (**dependency**) |
| `PredictRequest` | `ml_server/src/controllers/predict_controller.py` | Python | Demand Prediction | API DTO | Validate `/predict` input | `target_date: str` | No custom method | Inherits Pydantic `BaseModel` | Used by predict endpoint (**dependency**) |
| `DailyPrediction` | `ml_server/src/models.py` | Python | Demand Prediction | Domain Model / DTO | Mirror a daily-prediction record | ID/date/category/demand/confidence/model/weather IDs/timestamp | No custom method | Inherits `BaseModel` | Associations to category/model/weather by ID |
| `ProductionDecision` | `ml_server/src/models.py` | Python | Inventory and Recommendation | Domain Model / DTO | Mirror a production-decision record | IDs/date; predicted/recommended/max/final quantities; option/reason/confirmer/timestamps | No custom method | Inherits `BaseModel` | Associations to prediction/category/user by ID |

The nested `Settings.Config` sketch only sets `.env` configuration and should be omitted from the Logical View. No Python abstract base class, `Protocol`, interface, dataclass or `Enum` is declared.

The data-foundation document promises 19 Pydantic table models but explicitly declares only `DailyPrediction` and `ProductionDecision`. The remaining 17 names and fields cannot be treated as verified Python classes.

### 11.1 Planned Python function modules represented as conceptual classifiers

Chapter 4 names ML service classes, but the detailed plan implements their responsibilities as procedural modules/functions. If shown in a class diagram before refactoring, label them `<<Python module>>`, not concrete class.

| Conceptual classifier / planned module | Intended path | Layer | Responsibility | Public operations | Dependencies and relationship types |
|---|---|---|---|---|---|
| `FeaturePreparationService` / feature module | `ml_server/src/features/feature_engineering.py` | ML Business Service | Build 14 training/prediction features | `map_monsoon_season`; `calculate_slope`; `build_features`; `build_prediction_features` | Depends on pandas/numpy and context/sales data |
| Python `PredictionService` | `ml_server/src/services/predictService.py` | ML Business Service | Load active models/fallback, predict all categories and store results | `predict(target_date)` | Depends on prediction/category/model-version repos, feature module, model persistence, cold-start/confidence services |
| `ModelTrainingService` | `ml_server/src/services/trainService.py` | ML Business Service | Train and compare RF/LR by category | `train_category_model`; `train_all_categories` | Depends on `CategoryPredictor`, training/category repos, feature/evaluation/quality/persistence modules |
| `ModelEvaluationService` | `ml_server/src/services/evaluationService.py` | ML Business Service | Calculate MAE, RMSE, MAPE and R² | `evaluate(model, X_test, y_test)` | Depends on sklearn metrics/numpy |
| `ConfidenceService` | `ml_server/src/services/confidenceService.py` | ML Business Service | Convert RF tree variance into stability score | `calculate_confidence` | Depends on trained RF estimator |
| `ColdStartService` | `ml_server/src/services/coldStartService.py` | ML Business Service | Heuristic prediction when model/history is unavailable | `cold_start_predict` | Depends on constants/context/category mapping |
| `DataQualityService` | `ml_server/src/services/dataQualityService.py` | ML Business Service | Check row count, missing weather, stock-outs and zero sales | `check_training_quality` | Depends on training dataframe |
| `ModelArtifactStore` / persistence module | `ml_server/src/modelPersistence/persistence.py` | Infrastructure | Save/load joblib model files | `save_model`; `load_model` | Depends on filesystem/joblib/settings |
| `TrainingDataRepository` module | `ml_server/src/repositories/trainingDataRepo.py` | Repository | Fetch/merge results, weather and calendar training data | `fetch_training_data` | Direct Supabase dependency |
| Python `PredictionRepository` module | `ml_server/src/repositories/predictionRepo.py` | Repository | Fetch context/history and store predictions | `fetch_prediction_context`; `fetch_recent_sales`; `store_predictions` | Direct Supabase dependency |
| `BreadCategoryRepository` module | `ml_server/src/repositories/breadCategoryRepo.py` | Repository | Retrieve active categories | `get_all` | Direct Supabase dependency |
| `ModelVersionRepository` module | `ml_server/src/repositories/modelVersionRepo.py` | Repository | Read/insert/activate/deactivate model versions | Active/version/insert/deactivate methods | Direct Supabase dependency |
| `FeatureImportanceRepository` module | `ml_server/src/repositories/featureImportanceRepo.py` | Repository | Store and retrieve ranked importance values | `insert_many`; `find_by_version` | Direct Supabase dependency |

### 11.2 Planned FastAPI boundary modules

| Planned controller module | Intended path | Public operations | Finding |
|---|---|---|---|
| Health controller | `ml_server/src/controllers/health_controller.py` | `GET /health` | Router function, not class; framework-only operation |
| Predict controller | `ml_server/src/controllers/predict_controller.py` | `POST /predict` | Uses `PredictRequest`, then calls prediction service |
| Retrain controller | `ml_server/src/controllers/retrain_controller.py` | `POST /retrain` | Contains training persistence/versioning orchestration and directly calls repositories; too thick |
| Model controller | `ml_server/src/controllers/model_controller.py` | `GET /model/active`; `GET /model/{version}/importance` | Directly calls repositories; skips service layer |
| Evaluate controller | `ml_server/src/controllers/evaluate_controller.py` | `GET /evaluate` | Calls training service to produce evaluation data |

## 12. Chapter 4 design versus detailed plans

Every representative class named in Chapter 4 is unimplemented. Several names also differ from the more detailed module plans.

| Chapter 4 classifier | Detailed-plan counterpart | Finding |
|---|---|---|
| `LoginScreen` | `LoginView` | `Screen`/`View` naming drift; neither exists |
| `DashboardScreen` | `HomeView` plus Morning/Midday/Evening Views | One design class is split into several planned Views |
| `PredictionScreen` | `PredictionView` plus prediction content in `MorningView` | Overlapping display responsibility |
| `ProductionRecommendationScreen` | Recommendation content in `MorningView` | No dedicated planned View |
| `POSSimulationScreen` | Manual action in `EveningView` | No dedicated planned View |
| `AuthController` | Supabase Auth plus `authMiddleware` | No custom auth controller planned |
| `PredictionController` | `predictionController` stub | No detailed TypeScript implementation fills the stub |
| `SimulationController` | `salesController` | Naming mismatch |
| `ReportController` | `dashboardController` and `summaryController` | Responsibility split |
| TypeScript `PredictionService` | Missing Node orchestration service | Direct FastAPI calls are used instead |
| `ProductionRecommendationService` | `recommendationEngine` | Naming mismatch |
| `POSSimulationService` | `simulationService` | Naming mismatch |
| `LeftoverService` | `simulationService` plus `donationService` | Leftover responsibility is distributed |
| `ReportService` | `dashboardService`, `weeklySummaryService`, `financialSummaryService` | Responsibility split |
| `DemandPrediction` | `DailyPrediction` | Domain naming drift |
| `SimulationRun` | `SimulationSummary`, `DailyProduction`, `SalesTransaction`, `DailyResult` | No matching standalone entity |
| `LeftoverRecord` | `DailyResult.leftover` | No standalone model/table |
| `DonationRecord` | `Donation` | Naming drift |
| `PredictionRepository` | `PredictionRepo` | `Repository` versus `Repo` suffix drift |
| `ProductionRepository` | `ProductionDecisionRepo` and `DailyProductionRepo` | Responsibility split |
| `SimulationRepository` | Sales/production/result repositories | No matching single repository |
| `WeatherService` as external adapter | `weatherService` plus `openWeatherMapClient` | Service and provider adapter are separated in detailed plan |
| `HolidayService` as external adapter | `calendarService` plus `nagerDateClient` | Naming and role differ |
| `PushNotificationService` | `pushService` plus `firebaseAdminClient` | Responsibility split |
| `FeaturePreparationService` | Python feature-engineering functions | Not a class |
| Python `PredictionService` | Python `predict()` module function | Not a class |
| `ModelTrainingService` | Training functions plus `CategoryPredictor` | Responsibility split and mostly procedural |
| `ModelEvaluationService` | Python `evaluate()` function | Not a class |

Chapter 4 promises service, repository and external-adapter interfaces, composition through injected references and interface realisation. The detailed plans instead use direct imports of global repositories, router constants and singleton object literals. No service/repository/provider interface is defined.

## 13. Implemented classes not covered by the current design

| Implemented class | Coverage in design | Assessment |
|---|---|---|
| `MyApp` | Not named | Generic application bootstrap; its present demo responsibility is irrelevant |
| `MyHomePage` | Not named | Default counter page, not a missing Smart Bakery design element |
| `_MyHomePageState` | Not named | Private counter state, not architecturally important |

These classes should be replaced during implementation, not added to the Logical View merely to make the design match the starter template.

## 14. Duplicate or unclear responsibilities

| Issue | Evidence and effect | Recommended resolution before drawing |
|---|---|---|
| Controllers/services described as classes but planned as functions/objects | Express controllers are `Router` constants; most services/adapters are function modules or object literals | Choose class-based implementation, or label UML elements `<<module>>`/`<<router>>` instead of claiming classes |
| `Screen` versus `View` naming | Chapter 4 and Flutter module plan use different names | Select one convention, preferably the actual implementation names |
| Prediction workflow split across Views | `PredictionView` handles analytics while `MorningView` displays prediction/recommendation | Define `PredictionView` as analytics/history and `MorningView` as action/current plan |
| No dedicated recommendation or POS View | Chapter 4 names dedicated screens; detailed plan embeds them in Morning/Evening Views | Decide whether they are separate routes or workflow sections |
| TypeScript and Python both use `PredictionService` concept | Same name appears at two runtime boundaries | Package-qualify or rename to `PredictionOrchestrationService` (Node) and `ModelInferenceService` (Python) |
| `DemandPrediction` versus `DailyPrediction` | Report and data plan use different names | Standardise on one name across UML and DTOs |
| Duplicate `InventoryItem` | Shared Zod type and local service interface repeat the same fields | Keep the shared type as the single source |
| Duplicate `IngredientRequirement` | Shared Zod type and local calculator interface repeat the same fields | Import the shared type |
| Duplicate core schemas | `SalesTransaction` and `ProductionDecision` are defined in more than one module; optionality differs | Define them once in `backend/shared/types.ts` and extend only deliberately |
| Duplicate repository definitions | `DailyResultRepo` appears in Modules 3 and 4; `DonationRepo` in Modules 3 and 5 | Maintain one class per table and add methods incrementally |
| Cross-runtime repository ownership | Both Node and Python plan repositories over predictions/model metrics | Document read/write ownership and use package-qualified UML names |
| Missing Node prediction orchestration | Prediction controller remains a stub; recommendation engine performs raw FastAPI fetch | Add a focused Node prediction service plus ML adapter |
| Missing bakery-settings service | Controller pseudocode queries Supabase directly | Add `BakerySettingsService` |
| `dashboardService` is overly broad | Aggregates seven Views, ML metrics, inventory, sales, waste and finance | Split operational dashboard orchestration from prediction, inventory and finance reporting if it becomes difficult to test |
| `CategoryPredictor` boundary is broad | Owns RF/LR training, inference, confidence delegation and importance | Keep it as estimator wrapper; leave orchestration/persistence to training and prediction services |
| Missing typed ML responses | FastAPI endpoints return raw dictionaries | Add prediction item/response, retrain response, metrics, model-info, importance and error DTOs |
| No promised interfaces | No repository, provider, ML client or prediction-model ABC/Protocol/interface exists | Introduce only interfaces that will genuinely have implementations/mocks; otherwise remove interface-realisation claims |
| Flutter examples bypass DTOs | `MorningView` and widgets parse `Map<String,dynamic>` despite planned Dart models | Parse JSON in DTOs/client layer and give Views typed data |
| Flutter `ApiClient` is incomplete | It defines GET/POST/PUT, but FCM logout requires DELETE | Add the required verb in implementation |
| Flutter path conventions conflict | Plans use `flutter_app/lib/...`, current app uses root `lib/...`, reminder plan uses `lib/features/...` | Choose one physical layout before implementing |
| Notification artifacts disagree across plans | High-level Module 1 includes notification/FCM repos/services/controllers; detailed Module 1 build list omits them | Consolidate into one authoritative implementation list |
| Data-foundation model counts disagree | Detailed plan promises 19 schemas and omits notifications/FCM; high-level plan includes those tables; Dart plan says eight models but lists seven files | Update counts and definitive model list |
| ML component boundary conflicts | Chapter 4 says TypeScript supplies validated feature data; detailed ML plan sends only a date and lets Python read/write Supabase | Choose and document one contract |
| Training-target documents conflict | `FYP Report.md` and detailed ML plan use `sold`; older `fyp_food_waste.md` advocates `sold + lost_sales` | Treat the report/business rule (`sold`) as current and mark the older text obsolete or future work |
| Python training wiring is incomplete | `train_all_categories()` calls an undefined `get_bread_categories()` despite importing a category repository | Call the repository explicitly or introduce a service method |
| Python import naming conflicts | Predict controller import path/naming does not match planned `services/predictService.py` | Standardise Python file/module naming |
| TypeScript service export/import styles conflict | Individually exported functions are sometimes consumed as service objects, including recipe/inventory/condition modules | Select object/class or named-function style and use it consistently |
| `manualCorrectionService` lacks a detailed contract | It is listed and called, but its implementation is not defined | Specify inputs, outputs, repository calls and atomicity before UML inclusion |

## 15. Dependencies that violate or blur the intended architecture

The current implemented counter source has no architecture violation because it has no backend/data dependencies. The following are **violations or contradictions in planned pseudocode**, not implemented defects.

| Planned dependency | Classification | Why it is a problem | Required correction |
|---|---|---|---|
| `BakerySettingsController → Supabase` | Clear Controller → Database violation | Skips both Service and Repository | `BakerySettingsController → BakerySettingsService → BakerySettingsRepo → Supabase` |
| `SalesController → SalesTransactionRepo / DailyResultRepo` for reads | Clear Controller → Repository violation | Skips Service | Route all sales/result reads through a sales-query or simulation service |
| `DonationController → CharityPartnerRepo` | Clear Controller → Repository violation | Charity CRUD bypasses service | Add charity-partner operations to `DonationService` or a focused `CharityPartnerService` |
| FastAPI Retrain Controller → model repos and artifact persistence | Clear Controller → Repository/Infrastructure violation | Controller performs versioning, persistence and business orchestration | Move the complete workflow into `ModelTrainingService`/`RetrainingService` |
| FastAPI Model Controller → model/version/importance repos | Clear Controller → Repository violation | Skips service | Add `ModelInformationService` |
| `RecommendationEngine → fetch(ML_SERVER_URL)` | Adapter-abstraction gap | Raw provider/protocol call is embedded in business service | Introduce `MachineLearningClient`/`FastApiMlClient` dependency |
| Flutter mobile `NotificationService → Supabase Realtime notifications table` | Strict-rule contradiction | `ARCHITECTURE.md` says View never touches DB, while notification plan subscribes directly | Document Realtime as a formal read-only platform exception, or proxy notification events through backend infrastructure |
| Flutter `AuthService → Supabase Auth` and `FcmService → Firebase` | Documented platform exceptions but unclear in strict rule | The report allows these connections while the rule says View → Controller only | Rewrite the rule as “protected business operations go through Node”; list Auth/Realtime/FCM exceptions |
| Python ML repositories → Supabase | Cross-component contract contradiction, not an internal repo-layer violation | `ARCHITECTURE.md` permits Python repositories, but Chapter 4 says FastAPI requires validated data supplied by TypeScript | Decide whether Python owns ML persistence/data retrieval or receives all data from Node |
| Direct singleton imports everywhere | Design/OO gap | Promised interface realisation and injected composition are absent | Either introduce real interfaces/injection or remove those claims from the Logical View |

## 16. Recommended Chapter 4 Logical View scope

### 16.1 What can honestly appear now

No current Flutter class is suitable, and there are no backend or ML classes. Therefore the workspace does not yet support a meaningful **implementation-verified** Smart Bakery class diagram.

If a diagram is required before implementation, title it:

> **Proposed Logical View Class Diagram of the Smart Bakery Food Waste Reduction System**

Do not call it verified or implemented.

### 16.2 Focused proposed classifier set after implementation

The following is the recommended core. It covers the four project objectives without including every screen, CRUD class or utility. Items marked **gap-filler** are needed to repair a missing boundary in the current plans.

| Package / requested group | Core classifiers to include | Reason |
|---|---|---|
| Flutter Views and API clients | `MorningView`, `EveningView`, `ApiClient` | Shows manual prediction/recommendation and POS/end-of-day interaction through one client boundary |
| TypeScript Controllers | `PredictionController`, `RecommendationController`, `InventoryController`, `SalesController`, `DonationController` | One controller for each primary workflow |
| TypeScript Business Services | `PredictionOrchestrationService` **(gap-filler)**, `RecommendationEngine`, `InventoryService`, `ProductionDecisionService`, `SimulationService`, `TransactionRecordingService`, `DonationService` | Captures the principal business rules and orchestration |
| Domain Models | `BreadCategory`, `Ingredient`, `Recipe`, `InventoryBatch`, `DailyPrediction`, `ProductionDecision`, `SalesTransaction`, `DailyResult`, `Donation`, `CharityPartner` | Represents the central persisted state and cross-module associations |
| Repositories | `BaseRepo<T>`, `PredictionRepo`, `RecipeRepo`, `InventoryRepo`, `InventoryBatchRepo`, `ProductionDecisionRepo`, `SalesTransactionRepo`, `DailyResultRepo`, `DonationRepo` | Demonstrates repository inheritance and the major persistence boundaries |
| External-Service Adapters | `FastApiMlClient` **(gap-filler)** | Makes the Express-to-FastAPI boundary explicit instead of embedding raw `fetch` |
| Python/FastAPI ML | `PredictRequest`, `PredictionResponse` **(gap-filler DTO)**, `ModelInferenceService`, `FeaturePreparationService`, `CategoryPredictor`, `ModelTrainingService` | Shows the prediction/training responsibilities without exposing sklearn internals |

This core is already large. Use UML packages/swimlanes for Flutter, TypeScript Controller, TypeScript Service, Domain, Repository, Adapter and Python ML.

### 16.3 Optional classifiers if the page remains readable

| Concern | Optional classifiers |
|---|---|
| External context | `ContextService`, `WeatherService`, `CalendarService`, `OpenWeatherMapClient`, `NagerDateClient`, `DailyContext` |
| Alerts | `NotificationController`, backend `NotificationService`, `NotificationRepo`, `PushService`, `FirebaseAdminClient`, `Notification` |
| Reporting | `DashboardController`, `DashboardService`, `FinancialSummaryService`, `FinancialSummary` |
| Inventory detail | `FifoBatchService`, `InventoryLogRepo`, `InventoryLog`, `IngredientRequirement`, `Constraint`, `CategoryRecommendation` |
| ML persistence/evaluation | `TrainingDataRepository`, Python `PredictionRepository`, `ModelVersionRepository`, `ModelEvaluationService`, `ConfidenceService`, `MLModelVersion` |
| Other representative Views | `LoginView`, `InventoryView`, `NotificationsView` |

If optional areas cause visual clutter, place them in a second supporting class diagram rather than shrinking the main diagram until it is unreadable.

### 16.4 Exclude from the Logical View

| Exclude | Reason |
|---|---|
| `MyApp`, `MyHomePage`, `_MyHomePageState` | Counter-template implementation, unrelated to the system |
| Private Flutter `State` classes | Framework implementation detail |
| Cards, badges, charts, tables, indicators and notification-bell widgets | Unimportant presentation detail |
| `ApiEndpoints`, theme, logger and retry utilities | Utility/configuration detail |
| Health controllers, app/server bootstrap and environment settings | Infrastructure, not logical business structure |
| Express, FastAPI, Supabase, Dio, Pydantic and sklearn library classes | Third-party/framework types |
| All 19/21 database row types at once | The ERD should carry full database detail |
| Every CRUD controller/repository | Use representative architecture classes and core workflows |

## 17. Recommended relationships for the proposed diagram

Only draw relationships supported by the eventual code. The table below is the target design to implement and later verify.

| Source | Target | Relationship type | Meaning |
|---|---|---|---|
| `MorningView` / `EveningView` | `ApiClient` | Dependency | Views request backend operations through the mobile API client |
| `ApiClient` | TypeScript Controllers | Dependency over REST | Cross-process JSON request/response; not in-memory association |
| Each TypeScript Controller | Its Business Service | Dependency | Controller validates/delegates only |
| `PredictionController` | `PredictionOrchestrationService` | Dependency | Manually initiate prediction and map response |
| `PredictionOrchestrationService` | `FastApiMlClient` | Dependency | Invoke FastAPI through an adapter |
| `PredictionOrchestrationService` | `PredictionRepo` | Dependency | Read/store prediction records if Node owns persistence |
| `FastApiMlClient` | `ModelInferenceService` | REST dependency | Cross-process ML request/response |
| FastAPI predict endpoint | `PredictRequest` / `PredictionResponse` | Dependency | Validate input and serialize output |
| `ModelInferenceService` | `FeaturePreparationService` | Dependency | Build prediction features |
| `ModelInferenceService` | `CategoryPredictor` | Dependency | Execute trained estimator wrapper |
| `ModelTrainingService` | `CategoryPredictor` | Composition or strong association | Creates/trains category-specific predictor instances |
| `CategoryPredictor` | RF/LR model fields | Composition | Owns trained estimator objects; do not draw sklearn classes |
| Concrete TypeScript repos | `BaseRepo<T>` | Inheritance | Reuse common CRUD behavior |
| `RecommendationController` | `RecommendationEngine` | Dependency | Request a feasible production recommendation |
| `RecommendationEngine` | `PredictionOrchestrationService` / `PredictionRepo` | Dependency | Obtain predicted demand |
| `RecommendationEngine` | `InventoryService` and `RecipeRepo` | Dependencies | Evaluate grams and feasible quantities |
| `RecommendationEngine` | `DailyPrediction` / recommendation DTO | Dependency | Consume prediction and produce recommendation output |
| `InventoryController` | `InventoryService` | Dependency | Delegate stock operations |
| `InventoryService` | `InventoryRepo` and `InventoryBatchRepo` | Dependencies | Read/update inventory snapshot and FIFO batches |
| `InventoryBatch` | `Ingredient` | Association | Each batch belongs to one ingredient |
| `Recipe` | `BreadCategory` and `Ingredient` | Associations | Recipe row links category and ingredient |
| `ProductionDecisionService` | `ProductionDecisionRepo` | Dependency | Validate and persist manager choice |
| `ProductionDecision` | `DailyPrediction` and `BreadCategory` | Associations | Decision is based on a category prediction |
| `SalesController` | `SimulationService` | Dependency | Manually initiate POS simulation |
| `SimulationService` | `ProductionDecisionService`, context and recording services | Dependencies | Validate plan, derive demand and coordinate persistence |
| `TransactionRecordingService` | `SalesTransactionRepo`, `DailyResultRepo`, `InventoryService` | Dependencies | Persist sales/results and deduct production ingredients |
| `DailyResult` | `DailyPrediction` and `BreadCategory` | Associations | Result evaluates a prediction for a category |
| `DonationController` | `DonationService` | Dependency | Delegate donation operations |
| `DonationService` | `DailyResultRepo` and `DonationRepo` | Dependencies | Read leftover and persist donation |
| `Donation` | `CharityPartner` and `BreadCategory` | Associations | Donation goes to a partner and may identify a category |
| Provider implementation | Provider interface | Interface realisation | Draw only if a real interface/ABC/Protocol is implemented |

Do not use composition merely to mean “uses.” Use:

- **dependency** for Controller → Service, Service → Repository and Service → Adapter;
- **association** for stable domain links;
- **composition** only for owned nested lifecycle/data structures;
- **inheritance** for the real `BaseRepo<T>` hierarchy;
- **interface realisation** only after an actual interface and implementation exist.

## 18. Recommended implementation-and-verification plan

This is the safest order before finalising Figure 4.3:

| Step | Action | Verification output |
|---:|---|---|
| 1 | Choose one physical layout: root Flutter `lib/`, `backend/`, and `ml_server/` | Definitive source-tree document |
| 2 | Resolve naming drift (`View`/`Screen`, `Repo`/`Repository`, prediction service names and domain names) | Canonical naming table |
| 3 | Finalise shared request/response contracts, enum ownership and the Node ↔ FastAPI boundary | Versioned DTO/API contract |
| 4 | Decide class-based versus functional TypeScript/Python style | UML notation matches real source |
| 5 | Repair planned layer violations and add the missing settings/prediction/model-information services | Controller → Service → Repository checks pass |
| 6 | Implement typed Dart models and keep JSON parsing out of Views | No raw `Map<String,dynamic>` in architecturally important Views |
| 7 | Implement core domain, repository, service, controller and ML files | Source files exist and compile/type-check |
| 8 | Re-run the class audit from actual `.dart`, `.ts` and `.py` source | Verified inventory with real attributes/methods/dependencies |
| 9 | Select only the focused classifiers in Section 16 | Diagram remains readable |
| 10 | Draw Figure 4.3 and update Chapter 4 wording to actual names | Implemented Logical View matches source |

## 19. Copy-ready handoff note

When this document is supplied to another ChatGPT session, include this instruction:

> Use this audit as the source of truth. Do not claim that planned pseudocode is implemented. Do not create a final class diagram until actual Flutter, TypeScript and Python source exists, unless the diagram is explicitly titled “Proposed Logical View.” Preserve the View → Controller → Service → Repository rule, show cross-process REST links as dependencies, and keep the diagram focused on the core classifiers listed in Section 16.

## 20. Final audit verdict

| Question | Answer |
|---|---|
| Are Smart Bakery source classes implemented? | No |
| Can the current workspace support an implementation-verified Logical View? | No |
| Are the module documents still useful? | Yes, as proposed design input |
| Should the counter classes appear? | No |
| Are there implemented classes missing from the report? | Only irrelevant counter-template classes |
| Are there planned layer violations? | Yes; see Section 15 |
| Should the eventual diagram include every planned class? | No; use the focused set in Section 16 |
| Was any source code modified by this audit? | No; only this requested Markdown report was created |
