# Module 1: Node.js Middleware + External API Adapters

**Build Order:** 2nd (depends on Module 0: Data Foundation)
**Status:** High-Level Plan — ready for detailed breakdown
**Architecture:** View → Controller → Service → Repo/External Adapter (see `../ARCHITECTURE.md`)

> **Revised ownership:** This Node.js/Express component is the sole owner of Supabase PostgreSQL access through TypeScript `Repo` classes. It supplies validated prediction/training/evaluation DTOs to FastAPI through `FastApiMlClient` and persists relevant returned results. Express router files remain thin registration modules; TypeScript Controllers, Services, Repos and adapters are designed as classes.

---

## 1. Goal

Build the **API Gateway & Orchestration Layer** — the single entry point for the Flutter app. It coordinates Supabase, the Python ML server, and external APIs (Weather, Holiday). This module sets up the skeleton; later modules fill in business logic.

---

## 2. Dependencies

- **Module 0 (Data Foundation)** — needs `shared/types.ts` (Zod schemas), Supabase schema, `constants.json`
- **`ARCHITECTURE.md`** — defines the layered pattern this module follows

---

## 3. Sub-Modules

| # | Sub-Module | Layer | Purpose |
|---|---|---|---|
| 1.1 | Express App Skeleton | — | App setup, env config, server entry point |
| 1.2 | Auth Middleware | — | Validates Supabase JWT tokens from Flutter app |
| 1.3 | Base Repository Pattern | Repo | Generic CRUD base class all repos extend |
| 1.4 | Domain Repositories | Repo | One file per table (weatherRepo, calendarRepo, etc.) |
| 1.5 | Weather Service | Service | OpenWeatherMap API logic + calls weatherRepo to cache |
| 1.6 | Holiday Service | Service | Nager.Date API logic + calls calendarRepo to cache |
| 1.7 | Context Service (Orchestrator) | Service | `Promise.all` — fetches weather + calendar in parallel |
| 1.8 | Route Skeleton | Module | Thin Express router registration; delegates to Controller classes |
| 1.9 | Error Handling & Logging | — | Centralized error handler, `system_logs` writer (via systemLogRepo) |
| 1.10 | Notification Service | Service | Unified alert/reminder emitter — writes `notifications` row + pushes via FCM; called by Modules 2, 3, 4, 5, 6 |
| 1.11 | FCM Push Adapter | External Adapter | Wraps `firebase-admin` SDK; broadcasts to device tokens supplied by the Service through a Repo |
| 1.12 | Notification & FCM Repos | Repo | `notificationRepo` (CRUD + findUnread + dedupe check) + `fcmTokenRepo` (CRUD by user_id) |
| 1.13 | Notification Controller | Controller | Endpoints for Flutter: list notifications, mark read, register/unregister FCM token |
| 1.14 | Reminder Settings Support | Service/Repo | Reads predefined prediction/simulation reminder times for Module 6 reminder emission |
| 1.15 | FastAPI ML Adapter | External Adapter | `FastApiMlClient` is the only TypeScript-to-FastAPI HTTP boundary |
| 1.16 | Prediction Orchestration | Service | `PredictionOrchestrationService` assembles validated `DailySalesRecord`/context input and persists `DailyPrediction` results |
| 1.17 | Model Management | Service | Administrator-only candidate training, chronological evaluation, activation and previous-version restoration |
| 1.18 | User/Settings/Audit Support | Controller/Service/Repo | Preserve user/access management, system settings and audit logging in the backend plan |

---

## 4. Resolved Decisions

| # | Decision | Choice | Rationale |
|---|---|---|---|
| 1 | Framework + language | Express + TypeScript | Master doc specifies Express; TypeScript gives type safety with Zod |
| 2 | Holiday source | Nager.Date API | Free, no OAuth, covers Malaysian public holidays |
| 3 | Weather API | OpenWeatherMap free tier | Master doc specifies; 1000 calls/day sufficient |
| 4 | API key management | `.env` file | Standard practice, simple |

---

## 5. Route Endpoints (Skeleton)

### Implemented in This Module

| Method | Path | Purpose |
|---|---|---|
| GET | `/api/health` | Health check |
| GET | `/api/bakery-settings` | Get bakery config (1 row) |
| GET | `/api/weather/:date` | Get weather for a date (fetch + cache) |
| POST | `/api/weather/refresh` | Force-refresh weather from API |
| GET | `/api/calendar/:date` | Get holidays/events for a date |
| POST | `/api/calendar/refresh` | Force-refresh holidays from API |
| GET | `/api/context/:date` | Orchestrated: weather + calendar in parallel |
| GET | `/api/notifications` | List notifications (filter `?unread_only=true`) |
| POST | `/api/notifications/:id/read` | Mark a single notification as read |
| POST | `/api/notifications/read-all` | Mark all unread notifications as read |
| POST | `/api/fcm/register` | Register/refresh a Flutter device's FCM token `{ token, device_info? }` |
| DELETE | `/api/fcm/unregister` | Revoke a token on logout `{ token }` |

### Stub Endpoints (Filled by Later Modules)

| Method | Path | Filled By |
|---|---|---|
| POST | `/api/predictions` | Module 2 (ML + Prediction) |
| GET | `/api/predictions/:date` | Module 2 |
| POST | `/api/models/train` | Module 2; System Administrator only; creates candidates |
| POST | `/api/models/:id/evaluate` | Module 2; chronological, origin-labelled evaluation |
| POST | `/api/models/:id/activate` | Module 2; System Administrator activation |
| POST | `/api/models/:id/restore` | Module 2; restore previous valid version |
| GET/PUT | `/api/inventory` | Module 3 (Inventory) |
| GET/POST | `/api/sales` | Module 4 (POS) |
| POST | `/api/donations` | Module 5; manager-confirmed donation |
| POST | `/api/waste-records` | Module 5; manager-confirmed waste |
| GET | `/api/reports/weekly` | Module 5; weekly report |
| GET | `/api/reports/weekly/export` | Module 5; PDF/CSV export |
| GET | `/api/dashboard/morning` | Module 5 (Dashboard) |
| GET | `/api/dashboard/midday` | Module 5 |
| GET | `/api/dashboard/evening` | Module 5 |

---

## 6. External API Services (Service Layer)

> Services contain business logic + API call orchestration. They call repos for DB caching and adapters for raw HTTP calls. See `../ARCHITECTURE.md`.

### 6.1 Weather Service (calls openWeatherMapClient + weatherRepo)

```
weatherService.getWeather(date)
  ↓
1. weatherRepo.findByDate(date)              ← Repo (Supabase)
   ├─ EXISTS & fresh → return cached record
   └─ NOT EXISTS → continue to API call
2. openWeatherMapClient.fetch(date)          ← Adapter (raw HTTP)
   ├─ Endpoint: /data/2.5/forecast (for tomorrow)
   ├─ Endpoint: /data/2.5/weather (for today)
   └─ Params: lat, lon (bakery location), units=metric, appid
3. conditionMapper.mapCondition(owmCond, temp)  ← Pure function
   ├─ "Clear" → "sunny"
   ├─ "Rain", "Drizzle" → "rainy"
   ├─ "Clouds" → "cloudy"
   ├─ "Thunderstorm" → "thunderstorm"
   ├─ temp > 32 → "very_hot" (override)
   └─ "Haze", "Mist" → "haze"
4. weatherRepo.upsert(record)                ← Repo (Supabase)
5. RETURN weather record (with multiplier from constants)
```

### 6.2 Holiday Service (calls nagerDateClient + calendarRepo)

```
calendarService.getHolidays(date)
  ↓
1. calendarRepo.findByDate(date)             ← Repo (Supabase)
   ├─ EXISTS → return cached
   └─ NOT EXISTS → continue to API call
2. nagerDateClient.fetchYear(year)           ← Adapter (raw HTTP)
   ├─ Endpoint: /api/v3/PublicHolidays/{year}/MY
   └─ Returns: array of public holidays for Malaysia
3. MAP: Nager.Date → canonical event_type (in service)
   ├─ type: "Public" → event_type: "public_holiday"
   ├─ type: "Bank" → event_type: "public_holiday"
   ├─ type: "School" → event_type: "school_holiday"
   └─ type: "Observance" → event_type: "religious_holiday"
4. APPLY: demand_multiplier per event_type (from constants)
   ├─ public_holiday → 1.30
   ├─ school_holiday → 0.90
   └─ religious_holiday → 1.10 (default, varies)
5. calendarRepo.upsertMany(events)           ← Repo (Supabase)
6. RETURN calendar events for the date
```

**Note:** Nager.Date covers public holidays only. Bakery-specific events (local festivals, school nearby) can be added manually via dashboard or constants.json in a future phase.

### 6.3 Notification Service (shared alert/reminder emitter — used by Modules 2, 3, 4, 5, 6)

The unified `NotificationService.emit()` is the single entry point for every alert in the system. It persists through `NotificationRepo`, notifies foreground clients through an authenticated Node.js polling/SSE/WebSocket boundary, and sends background/closed-app push through FCM via `FcmPushAdapter`. Flutter must not subscribe directly to PostgreSQL changes. The service also enforces the spam guard: no new row if an unread alert of the same `type + related_id` already exists.

Module 6 may use this service for `prediction_reminder` and `simulation_reminder`, but those reminders only notify the manager. They must not call prediction, recommendation, simulation, donation, or retraining services.

```
notificationService.emit({ type, severity, title, message, relatedId })
  ↓
1. notificationRepo.findUnreadByTypeAndRelatedId(type, relatedId)   ← Repo (Supabase)
   ├─ EXISTS → return null (dedupe — alert already pending, do nothing)
   └─ NOT EXISTS → continue
2. notificationRepo.insert({ type, severity, title, message, related_id, is_read: false })
   ← Node.js foreground-notification boundary publishes or exposes the new notification
3. pushService.broadcast(notificationRow)                          ← firebase-admin
   ├─ fcmTokenRepo.findAll()                                       ← Repo (Supabase)
   │   → [token1, token2, ...] (all staff devices; no role filter — single-bakery scope)
   ├─ if severity in ['warning', 'critical']:
   │     admin.messaging.sendEachMulticast({ tokens, notification: { title, body }, data: { type, related_id } })
   │     → auto lock-screen tray popup (no Flutter code needed)
   └─ if severity == 'info':
   │     admin.messaging.sendEachMulticast({ tokens, data: { title, body, type, related_id } })
   │     → app handles (no auto popup; informational)
4. Remove invalid/expired tokens returned by FCM (cleanup loop)
5. systemLogRepo.insert({ event_type: 'notification_emitted', payload: { type, related_id } })
   ← Audit trail
6. RETURN inserted notification row
```

**Severity → FCM payload mode:**
- `warning` / `critical` → FCM `notification` message (auto lock-screen tray display)
- `info` → FCM `data` message (app handles; no auto popup)

### 6.4 FCM Token Lifecycle

```
On Flutter login success:
  ├─ FirebaseMessaging.getInstance().getToken() → token
  ├─ POST /api/fcm/register { token, device_info } → fcmTokenRepo.upsert(token, user_id, device_info)
  └─ Authenticated Node.js notification polling/SSE/WebSocket connection begins (foreground updates)

On Flutter onTokenRefresh (Firebase rotates periodically):
  ├─ GET new token
  └─ POST /api/fcm/register { token } → updates fcm_tokens row

On Flutter logout:
  └─ DELETE /api/fcm/unregister { token } → fcmTokenRepo.deleteByToken()
     ← prevents former staff / logged-out users from continuing to receive alerts

Multi-device: one user may have multiple rows in fcm_tokens (phone + tablet).
Broadcast hits all of them via sendEachMulticast (one firebase-admin call).
```

### 6.5 Push Service (FCM adapter)

```
pushService.broadcast(notificationRow)
  ↓
1. fcmTokenRepo.findAll()                 ← Supabase
2. if no tokens: return { sent: 0 }       ← no Flutter users registered yet
3. const msg = buildPayload(notificationRow)
   ├─ severity 'warning'|'critical': { notification: {title, body}, data: {type, related_id} }
   └─ severity 'info':                   { data: {title, body, type, related_id} }
4. const response = await admin.messaging.sendEachMulticast({ tokens, ...msg })
5. for each failed token in response:
   ├─ if error code in [messaging/invalid-registration-token,
   │                    messaging/registration-token-not-registered]:
   │     fcmTokenRepo.deleteByToken(token)   ← cleanup stale tokens
6. RETURN { sent: response.successCount, failed: response.failureCount }
```

---

## 7. Context Service (Orchestrator)

The key pattern from the master doc — parallel API calls. This is a **service** that calls two other services:

```typescript
// services/contextService.ts
import { weatherService } from './weatherService';
import { calendarService } from './calendarService';

export async function fetchContext(date: string) {
  const [weather, calendar] = await Promise.all([
    weatherService.getWeather(date),       // calls weatherRepo + openWeatherMapClient
    calendarService.getHolidays(date),     // calls calendarRepo + nagerDateClient
  ]);
  return { date, weather, calendar };
}
```

This is what makes Node.js the right choice — 2.5x faster than sequential calls.

---

## 8. Auth Strategy

```
Flutter App
  ↓ (sends Supabase JWT in Authorization header)
Node.js Middleware
  ├─ auth middleware extracts JWT
  ├─ verifies via Supabase Auth API (or jwt secret)
  ├─ if invalid → 401 Unauthorized
  └─ if valid → attach user to request, continue
  ↓
Route Handler
  ↓
Supabase (using service role key, bypasses RLS)
```

- Flutter authenticates via Supabase Auth SDK directly
- Sends JWT to Node.js in `Authorization: Bearer <token>`
- Node.js verifies JWT, then uses service-role key to query Supabase
- Database credentials never exposed to Flutter app

---

## 9. File Structure

> Follows the layered architecture from `../ARCHITECTURE.md`: Model → Repo → Service → Controller → View

```
backend/
├── src/
│   ├── app.ts                      # Express app setup
│   ├── server.ts                   # Entry point (listen)
│   ├── config/
│   │   ├── env.ts                  # Env vars (Zod-validated)
│   │   └── supabase.ts             # Supabase client singleton (used by repos)
│   ├── repositories/               # REPO layer — Supabase only, no business logic
│   │   ├── baseRepo.ts             # Generic CRUD base class
│   │   ├── bakerySettingsRepo.ts   # bakery_settings table
│   │   ├── weatherRepo.ts          # weather_records table
│   │   ├── calendarRepo.ts         # calendar_events table
│   │   ├── systemLogRepo.ts        # system_logs table
│   │   ├── notificationRepo.ts     # notifications table CRUD + findUnread + dedupe check
│   │   ├── fcmTokenRepo.ts         # fcm_tokens table CRUD (by user_id / by token)
│   │   ├── dailySalesRecordRepo.ts # validated historical units_sold + DataOrigin
│   │   ├── dailyPredictionRepo.ts
│   │   ├── modelVersionRepo.ts
│   │   └── modelEvaluationRepo.ts
│   ├── services/                   # SERVICE layer — business logic, calls repos
│   │   ├── weatherService.ts       # OpenWeatherMap API + calls weatherRepo to cache
│   │   ├── calendarService.ts      # Nager.Date API + calls calendarRepo to cache
│   │   ├── contextService.ts       # Promise.all(weather, calendar) orchestrator
│   │   ├── notificationService.ts  # Unified alert emitter — writes row + calls pushService
│   │   ├── predictionOrchestrationService.ts
│   │   └── modelManagementService.ts
│   ├── adapters/
│   │   ├── fastApiMlClient.ts      # only TypeScript → FastAPI HTTP boundary
│   │   ├── openWeatherMapClient.ts
│   │   ├── nagerDateClient.ts
│   │   └── fcmPushAdapter.ts
│   ├── routes/                     # thin Express registration modules
│   ├── adapters/                   # External API clients (HTTP only, called by services)
│   │   ├── openWeatherMapClient.ts # Raw OpenWeatherMap API wrapper
│   │   ├── nagerDateClient.ts      # Raw Nager.Date API wrapper
│   │   ├── conditionMapper.ts      # Weather condition mapping (pure function)
│   │   └── firebaseAdminClient.ts # firebase-admin initialization + exports messaging instance
│   ├── middleware/
│   │   ├── auth.ts                 # Supabase JWT verification
│   │   ├── errorHandler.ts         # Centralized error handling (logs via systemLogRepo)
│   │   └── validateRequest.ts      # Zod schema validation
│   ├── controllers/                # CONTROLLER layer — thin HTTP handlers
│   │   ├── index.ts                # Controller composition/registration support
│   │   ├── healthController.ts
│   │   ├── bakerySettingsController.ts # calls bakerySettingsRepo via service
│   │   ├── weatherController.ts    # calls weatherService
│   │   ├── calendarController.ts   # calls calendarService
│   │   ├── contextController.ts    # calls contextService
│   │   ├── predictionController.ts # stub → 501 Not Implemented (Module 2)
│   │   ├── inventoryController.ts  # stub (Module 3)
│   │   ├── posSimulationController.ts # stub (Module 4)
│   │   ├── leftoverManagementController.ts # stub (Module 5)
│   │   ├── dashboardController.ts  # stub (Module 5)
│   │   └── notificationController.ts # Notification list + mark-read + FCM token register/unregister
│   └── utils/
│       ├── logger.ts
│       ├── retryWithBackoff.ts     # Retry for external APIs
│       └── apiError.ts             # Custom error class
├── shared/                         # MODEL layer (from Module 0)
│   ├── types.ts                    # Zod schemas → inferred TS types
│   └── index.ts
├── supabase/                       # (from Module 0)
├── package.json
├── tsconfig.json
└── .env.example
```

---

## 10. Environment Variables (`.env.example`)

```
# Server
PORT=3000
NODE_ENV=development

# Supabase
SUPABASE_URL=http://localhost:54321
SUPABASE_SERVICE_KEY=your-service-key
SUPABASE_JWT_SECRET=your-jwt-secret

# External APIs
OPENWEATHERMAP_API_KEY=your-key
# Bakery coordinates (Kuala Lumpur default)
BAKERY_LAT=3.1390
BAKERY_LON=101.6869

# Nager.Date API (no key needed, base URL only)
NAGER_DATE_BASE_URL=https://date.nager.at

# Python ML Server
ML_SERVER_URL=http://localhost:8000

# FCM (Firebase Cloud Messaging)
# Service account JSON downloaded from Firebase Console → Project Settings → Service Accounts
FIREBASE_SERVICE_ACCOUNT_PATH=./firebase-service-account.json
# (Alternatively set FIREBASE_SERVICE_ACCOUNT_JSON inline, but file is preferred)
```

---

## 11. Integration Points

| Talks To | Direction | Protocol |
|---|---|---|
| Flutter App | Incoming | HTTP REST (JSON) |
| Supabase | Outgoing | Supabase JS client (PostgreSQL) |
| Supabase Realtime (optional) | Internal to Node.js | Node may observe changes; Flutter receives foreground updates only through an authenticated Node.js API/SSE/WebSocket boundary |
| Python ML Server | Outgoing | HTTP REST (JSON) |
| OpenWeatherMap | Outgoing | HTTP REST |
| Nager.Date | Outgoing | HTTP REST (no auth) |
| Firebase Cloud Messaging | Outgoing | HTTPS (firebase-admin `sendEachMulticast`) |

---

## 12. What This Module Does NOT Include

- ❌ Prediction business logic → Module 2
- ❌ Inventory constraint logic → Module 3
- ❌ POS simulation → Module 4
- ❌ Donation workflow → Module 5
- ❌ Background automation that runs core workflows automatically → out of prototype scope

---

## 13. Next Steps (Detailed Breakdown)

See `README.md` in this folder for the detailed plan (code structure, function signatures, adapter logic, error handling).

---

**Module Status:** High-level plan complete. Ready for detailed breakdown on your signal.
