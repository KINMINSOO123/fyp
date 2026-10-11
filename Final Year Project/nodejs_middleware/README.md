# Module 1: Node.js Middleware + External API Adapters — Detailed Plan

**Build Order:** 2nd (depends on Module 0: Data Foundation)
**Status:** Detailed plan — ready for implementation
**Architecture:** View → Controller → Service → Repo/External Adapter (see `../ARCHITECTURE.md`)

> See `MODULE.md` in this folder for the high-level plan (sub-modules, routes, auth strategy, file structure).
> This README documents the concrete artifacts to build: function signatures, repo/service/controller logic, dependencies, error handling.

## Revision baseline (authoritative)

- Node.js/Express owns all Supabase PostgreSQL access through TypeScript `Repo` classes derived from `BaseRepo<T>`.
- Add class-based `PredictionOrchestrationService`, `ModelManagementService` and `FastApiMlClient`. Only the adapter communicates with thin FastAPI route modules.
- Model management is System-Administrator-only: training creates candidates; chronological, origin-labelled evaluation precedes activation; a previous valid version can be restored.
- Express routers are modules, not Controller classes. Controller classes call Services; Services call Repos or external adapters.
- Preserve user/access management, settings, audit logs, notifications, device tokens and FCM. Foreground Flutter clients use a Node.js boundary rather than subscribing directly to PostgreSQL changes.
- Module 4 uses `PosSimulationController`/`PosSimulationService`; Module 5 uses manager-confirmed leftover allocation and never auto-creates donations.

Any conflicting function-style or direct-realtime illustrative snippet below is superseded by this baseline and must be translated into the named classes before implementation.

---

## 1. Dependencies (from Module 0)

| Artifact | Used For |
|---|---|
| `backend/shared/types.ts` | Zod schemas for request/response validation (Model layer) |
| `backend/shared/index.ts` | Barrel export of types |
| `backend/supabase/schema/001_initial.sql` | Tables this module reads/writes |
| `backend/supabase/seed/constants.json` | Weather/holiday multipliers, bakery coords |

---

## 2. Artifacts to Build

> Layered per `../ARCHITECTURE.md`. TypeScript Repos are the only PostgreSQL callers. Services call Repos or adapters. Controller classes are thin HTTP handlers; Express router files only register routes.

| # | Path | Layer | Purpose |
|---|---|---|---|
| 1 | `backend/package.json` | — | Dependencies + scripts |
| 2 | `backend/tsconfig.json` | — | TypeScript config |
| 3 | `backend/.env.example` | — | Env var template |
| 4 | `backend/src/app.ts` | — | Express app setup |
| 5 | `backend/src/server.ts` | — | Entry point |
| 6 | `backend/src/config/env.ts` | — | Zod-validated env config |
| 7 | `backend/src/config/supabase.ts` | — | Supabase client singleton (used by repos only) |
| 8 | `backend/src/middleware/auth.ts` | — | Supabase JWT verification |
| 9 | `backend/src/middleware/errorHandler.ts` | — | Centralized error handler |
| 10 | `backend/src/middleware/validateRequest.ts` | — | Zod request validation |
| 11 | `backend/src/repositories/baseRepo.ts` | Repo | Generic CRUD base class |
| 12 | `backend/src/repositories/bakerySettingsRepo.ts` | Repo | bakery_settings table |
| 13 | `backend/src/repositories/weatherRepo.ts` | Repo | weather_records table |
| 14 | `backend/src/repositories/calendarRepo.ts` | Repo | calendar_events table |
| 15 | `backend/src/repositories/systemLogRepo.ts` | Repo | system_logs table |
| 16 | `backend/src/adapters/openWeatherMapClient.ts` | Adapter | Raw OpenWeatherMap HTTP wrapper |
| 17 | `backend/src/adapters/nagerDateClient.ts` | Adapter | Raw Nager.Date HTTP wrapper |
| 18 | `backend/src/adapters/conditionMapper.ts` | Adapter | Weather condition mapping (pure function) |
| 19 | `backend/src/services/weatherService.ts` | Service | Weather logic + caching (calls weatherRepo + openWeatherMapClient) |
| 20 | `backend/src/services/calendarService.ts` | Service | Holiday logic + caching (calls calendarRepo + nagerDateClient) |
| 21 | `backend/src/services/contextService.ts` | Service | Parallel orchestrator (calls weather + calendar services) |
| 21a | `backend/src/adapters/fastApiMlClient.ts` | External Adapter | Typed prediction/training/evaluation HTTP boundary to FastAPI |
| 21b | `backend/src/services/predictionOrchestrationService.ts` | Service | Assemble validated `DailySalesRecord` history/context and persist predictions |
| 21c | `backend/src/services/modelManagementService.ts` | Service | Administrator candidate training/evaluation/activation/restoration |
| 21d | `backend/src/repositories/dailySalesRecordRepo.ts` | Repo | Validated historical units sold by `DataOrigin` |
| 21e | `backend/src/repositories/modelVersionRepo.ts` / `modelEvaluationRepo.ts` | Repo | Model lifecycle and origin-labelled evaluation persistence |
| 22 | `backend/src/controllers/*.ts` | Controller | Constructor-injected Controller classes; no `Router` instances |
| 22a | `backend/src/routes/*.ts` | Module | Thin Express registration mapping routes to Controller methods |
| 23 | `backend/src/utils/logger.ts` | — | Logging utility |
| 24 | `backend/src/utils/retryWithBackoff.ts` | — | Retry logic for external APIs |
| 25 | `backend/src/utils/apiError.ts` | — | Custom error class |

---

## 3. Dependencies (`package.json`)

```json
{
  "name": "bakery-backend",
  "version": "0.1.0",
  "scripts": {
    "dev": "tsx watch src/server.ts",
    "build": "tsc",
    "start": "node dist/server.js",
    "typecheck": "tsc --noEmit",
    "lint": "eslint src/"
  },
  "dependencies": {
    "express": "^4.19.0",
    "@supabase/supabase-js": "^2.42.0",
    "zod": "^3.23.0",
    "dotenv": "^16.4.0",
    "node-fetch": "^3.3.0",
    "cors": "^2.8.5",
    "helmet": "^7.1.0",
    "morgan": "^1.10.0"
  },
  "devDependencies": {
    "typescript": "^5.4.0",
    "tsx": "^4.7.0",
    "@types/express": "^4.17.0",
    "@types/cors": "^2.8.0",
    "@types/morgan": "^1.9.0",
    "eslint": "^8.57.0",
    "@typescript-eslint/eslint-plugin": "^7.0.0",
    "@typescript-eslint/parser": "^7.0.0"
  }
}
```

---

## 4. Config Layer

### 4.1 `src/config/env.ts`
Zod-validated environment variables — fails fast on startup if misconfigured.

```typescript
import { z } from 'zod';

const EnvSchema = z.object({
  PORT: z.coerce.number().default(3000),
  NODE_ENV: z.enum(['development', 'production', 'test']).default('development'),

  SUPABASE_URL: z.string().url(),
  SUPABASE_SERVICE_KEY: z.string().min(1),
  SUPABASE_JWT_SECRET: z.string().min(1),

  OPENWEATHERMAP_API_KEY: z.string().min(1),
  BAKERY_LAT: z.coerce.number(),
  BAKERY_LON: z.coerce.number(),

  NAGER_DATE_BASE_URL: z.string().url().default('https://date.nager.at'),

  ML_SERVER_URL: z.string().url().default('http://localhost:8000'),
});

export type Env = z.infer<typeof EnvSchema>;

export const env = EnvSchema.parse(process.env);
```

### 4.2 `src/config/supabase.ts`
Supabase client singleton using service-role key (bypasses RLS for backend operations).

```typescript
import { createClient } from '@supabase/supabase-js';
import { env } from './env';

export const supabase = createClient(
  env.SUPABASE_URL,
  env.SUPABASE_SERVICE_KEY,
  { auth: { persistSession: false } }
);
```

---

## 5. Middleware

### 5.1 `src/middleware/auth.ts`
Verifies Supabase JWT from Flutter app's Authorization header.

```typescript
import { Request, Response, NextFunction } from 'express';

// Attaches decoded user to request
declare global {
  namespace Express {
    interface Request {
      user?: { id: string; email: string };
    }
  }
}

export async function authMiddleware(
  req: Request,
  res: Response,
  next: NextFunction
): Promise<void> {
  try {
    const authHeader = req.headers.authorization;
    if (!authHeader?.startsWith('Bearer ')) {
      res.status(401).json({ error: 'Missing authorization header' });
      return;
    }
    const token = authHeader.split(' ')[1];
    // Verify JWT using Supabase JWT secret (via jose library)
    // Or use Supabase auth.getUser(token) API
    // Attach decoded user to req.user
    next();
  } catch (err) {
    res.status(401).json({ error: 'Invalid token' });
  }
}
```

### 5.2 `src/middleware/errorHandler.ts`
Centralized error handler — catches all thrown errors, logs to `system_logs`, returns consistent JSON.

```typescript
import { Request, Response, NextFunction } from 'express';
import { ApiError } from '../utils/apiError';
import { logger } from '../utils/logger';

export function errorHandler(
  err: Error,
  req: Request,
  res: Response,
  next: NextFunction
): void {
  const statusCode = err instanceof ApiError ? err.statusCode : 500;
  logger.error({ err, path: req.path, method: req.method });

  res.status(statusCode).json({
    error: err.message,
    statusCode,
    ...(process.env.NODE_ENV === 'development' && { stack: err.stack }),
  });
}
```

### 5.3 `src/middleware/validateRequest.ts`
Zod schema validation for request body/params/query.

```typescript
import { Request, Response, NextFunction } from 'express';
import { ZodSchema } from 'zod';

export function validateRequest(schema: {
  body?: ZodSchema;
  params?: ZodSchema;
  query?: ZodSchema;
}) {
  return (req: Request, res: Response, next: NextFunction) => {
    try {
      if (schema.body) req.body = schema.body.parse(req.body);
      if (schema.params) req.params = schema.params.parse(req.params) as any;
      if (schema.query) req.query = schema.query.parse(req.query) as any;
      next();
    } catch (err) {
      res.status(400).json({ error: 'Validation failed', details: err });
    }
  };
}
```

---

## 6. Repositories (Repo Layer — Supabase only)

> Repos do ONLY Supabase queries. No business logic, no validation. See `../ARCHITECTURE.md` §4.2.

### 6.1 `src/repositories/baseRepo.ts`
Generic CRUD base class all repos extend. See `../ARCHITECTURE.md` §7 for full code.

```typescript
import { supabase } from '../config/supabase';

export class BaseRepo<T> {
  constructor(protected tableName: string) {}
  async findAll(filters?: Record<string, any>): Promise<T[]> { ... }
  async findOne(id: string): Promise<T | null> { ... }
  async insert(data: Partial<T>): Promise<T> { ... }
  async update(id: string, data: Partial<T>): Promise<T> { ... }
  async delete(id: string): Promise<void> { ... }
}
```

### 6.2 `src/repositories/weatherRepo.ts`
```typescript
export class WeatherRepo extends BaseRepo<WeatherRecord> {
  constructor() { super('weather_records'); }

  async findByDate(date: string): Promise<WeatherRecord | null> {
    const { data, error } = await supabase
      .from('weather_records').select('*').eq('date', date).single();
    if (error) throw error;
    return data;
  }

  async upsert(record: WeatherRecord): Promise<WeatherRecord> {
    const { data, error } = await supabase
      .from('weather_records').upsert(record, { onConflict: 'date' })
      .select().single();
    if (error) throw error;
    return data;
  }
}
export const weatherRepo = new WeatherRepo();
```

### 6.3 `src/repositories/calendarRepo.ts`
```typescript
export class CalendarRepo extends BaseRepo<CalendarEvent> {
  constructor() { super('calendar_events'); }

  async findByDate(date: string): Promise<CalendarEvent[]> {
    const { data, error } = await supabase
      .from('calendar_events').select('*').eq('date', date);
    if (error) throw error;
    return data ?? [];
  }

  async upsertMany(events: CalendarEvent[]): Promise<void> {
    if (events.length === 0) return;
    const { error } = await supabase
      .from('calendar_events').upsert(events, { onConflict: 'date,event_type' });
    if (error) throw error;
  }
}
export const calendarRepo = new CalendarRepo();
```

### 6.4 `src/repositories/bakerySettingsRepo.ts`
```typescript
export class BakerySettingsRepo extends BaseRepo<BakerySettings> {
  constructor() { super('bakery_settings'); }

  async getSingle(): Promise<BakerySettings | null> {
    const { data, error } = await supabase
      .from('bakery_settings').select('*').limit(1).single();
    if (error) throw error;
    return data;
  }
}
export const bakerySettingsRepo = new BakerySettingsRepo();
```

### 6.5 `src/repositories/systemLogRepo.ts`
```typescript
export class SystemLogRepo extends BaseRepo<SystemLog> {
  constructor() { super('system_logs'); }
}
export const systemLogRepo = new SystemLogRepo();
```

---

## 7. Adapters (External API Clients — raw HTTP only)

> Adapters do ONLY raw HTTP calls to external services. No DB, no business logic. Called by services.

### 7.1 `src/adapters/conditionMapper.ts`
Maps OpenWeatherMap conditions → canonical conditions used by the system.

```typescript
import { WeatherMultipliers } from '../../shared/types';

const CONDITION_MAP: Record<string, string> = {
  'Clear': 'sunny',
  'Rain': 'rainy',
  'Drizzle': 'rainy',
  'Clouds': 'cloudy',
  'Thunderstorm': 'thunderstorm',
  'Haze': 'haze',
  'Mist': 'haze',
  'Fog': 'haze',
  'Snow': 'snow',
};

export function mapCondition(
  owmCondition: string,
  tempC: number
): string {
  if (tempC > 32) return 'very_hot';
  return CONDITION_MAP[owmCondition] ?? 'cloudy';
}

export function getMultiplier(
  condition: string,
  multipliers: WeatherMultipliers
): number {
  return multipliers[condition] ?? 1.0;
}
```

### 7.2 `src/adapters/openWeatherMapClient.ts`
Raw HTTP wrapper — no DB, no business logic. Called by weatherService.

```typescript
import { env } from '../config/env';
import { retryWithBackoff } from '../utils/retryWithBackoff';

export const openWeatherMapClient = {
  async fetchWeather(date: string): Promise<RawOWMResponse> {
    const isToday = date === new Date().toISOString().split('T')[0];
    const endpoint = isToday ? '/data/2.5/weather' : '/data/2.5/forecast';
    const url = `${OWM_BASE}${endpoint}?lat=${env.BAKERY_LAT}&lon=${env.BAKERY_LON}&units=metric&appid=${env.OPENWEATHERMAP_API_KEY}`;
    return retryWithBackoff(() => fetchJson(url));
  },
};
```

### 7.3 `src/adapters/nagerDateClient.ts`
Raw HTTP wrapper — no DB, no business logic. Called by calendarService.

```typescript
import { env } from '../config/env';
import { retryWithBackoff } from '../utils/retryWithBackoff';

export const nagerDateClient = {
  async fetchYearHolidays(year: number): Promise<RawNagerResponse[]> {
    const url = `${env.NAGER_DATE_BASE_URL}/api/v3/PublicHolidays/${year}/MY`;
    return retryWithBackoff(() => fetchJson(url));
  },
};
```

---

## 8. Services (Service Layer — business logic + calls repos)

> Services contain business logic. They call repos for DB access and adapters for external HTTP. No direct Supabase calls.

### 8.1 `src/services/weatherService.ts`
```typescript
import { weatherRepo } from '../repositories/weatherRepo';
import { openWeatherMapClient } from '../adapters/openWeatherMapClient';
import { conditionMapper } from '../adapters/conditionMapper';

interface GetWeatherOptions { forceRefresh?: boolean; }

export const weatherService = {
  async getWeather(date: string, opts?: GetWeatherOptions): Promise<WeatherRecord> {
    // 1. Check cache via repo
    if (!opts?.forceRefresh) {
      const cached = await weatherRepo.findByDate(date);
      if (cached) return cached;
    }

    // 2. Fetch from external API via adapter
    const data = await openWeatherMapClient.fetchWeather(date);

    // 3. Map condition (pure function)
    const condition = conditionMapper.map(data.weather[0].main, data.main.temp);
    const record: WeatherRecord = {
      date,
      condition,
      temp_high_c: data.main.temp_max,
      temp_low_c: data.main.temp_min,
      humidity_pct: data.main.humidity,
    };

    // 4. Store via repo
    return weatherRepo.upsert(record);
  },
};
```

### 8.2 `src/services/calendarService.ts`
```typescript
import { calendarRepo } from '../repositories/calendarRepo';
import { nagerDateClient } from '../adapters/nagerDateClient';

const HOLIDAY_MULTIPLIERS: Record<string, number> = {
  'public_holiday': 1.30,
  'school_holiday': 0.90,
  'religious_holiday': 1.10,
  'local_event': 1.15,
};

const TYPE_MAP: Record<string, string> = {
  'Public': 'public_holiday',
  'Bank': 'public_holiday',
  'School': 'school_holiday',
  'Observance': 'religious_holiday',
};

export const calendarService = {
  async getHolidays(date: string, opts?: { forceRefresh?: boolean }): Promise<CalendarEvent[]> {
    // 1. Check cache via repo
    if (!opts?.forceRefresh) {
      const cached = await calendarRepo.findByDate(date);
      if (cached.length > 0) return cached;
    }

    // 2. Fetch from external API via adapter
    const year = parseInt(date.split('-')[0]);
    const holidays = await nagerDateClient.fetchYearHolidays(year);

    // 3. Filter + map types (business logic)
    const events: CalendarEvent[] = holidays
      .filter((h: any) => h.date === date)
      .map((h: any) => ({
        date: h.date,
        event_type: TYPE_MAP[h.type] ?? 'local_event',
        event_name: h.localName || h.name,
        demand_multiplier: HOLIDAY_MULTIPLIERS[TYPE_MAP[h.type] ?? 'local_event'] ?? 1.0,
      }));

    // 4. Store via repo
    await calendarRepo.upsertMany(events);
    return events;
  },
};
```

### 8.3 `src/services/contextService.ts` (Orchestrator)
The key pattern — parallel API calls (2.5x faster than sequential). Calls two services.

```typescript
import { weatherService } from './weatherService';
import { calendarService } from './calendarService';

export interface DailyContext {
  date: string;
  weather: {
    condition: string;
    temp_high_c: number;
    temp_low_c: number;
    humidity_pct: number;
    demand_multiplier: number;
  } | null;
  calendar: {
    event_type: string;
    event_name: string;
    demand_multiplier: number;
  }[];
}

export async function fetchContext(date: string): Promise<DailyContext> {
  const [weather, calendar] = await Promise.all([
    weatherService.getWeather(date),       // service → repo + adapter
    calendarService.getHolidays(date),     // service → repo + adapter
  ]);

  return {
    date,
    weather: weather ? {
      condition: weather.condition,
      temp_high_c: weather.temp_high_c,
      temp_low_c: weather.temp_low_c,
      humidity_pct: weather.humidity_pct,
      demand_multiplier: getWeatherMultiplier(weather.condition),
    } : null,
    calendar,
  };
}
```

---

## 8. Controllers (Controller Layer — thin HTTP handlers)

### 8.1 `src/controllers/healthController.ts`
```typescript
import { Router } from 'express';

export const healthController = Router();

healthController.get('/health', (req, res) => {
  res.json({ status: 'ok', timestamp: new Date().toISOString() });
});
```

### 8.2 `src/controllers/bakerySettingsController.ts`
```typescript
import { Router } from 'express';
import { supabase } from '../config/supabase';

export const bakerySettingsController = Router();

bakerySettingsController.get('/bakery-settings', async (req, res, next) => {
  try {
    const { data, error } = await supabase
      .from('bakery_settings')
      .select('*')
      .limit(1)
      .single();
    if (error) throw error;
    res.json(data);
  } catch (err) { next(err); }
});
```

### 8.3 `src/controllers/weatherController.ts`
```typescript
import { Router } from 'express';
import { weatherService } from '../services/weatherService';

export const weatherController = Router();

weatherController.get('/weather/:date', async (req, res, next) => {
  try {
    const { date } = req.params;
    const weather = await weatherService.getWeather(date);
    res.json(weather);
  } catch (err) { next(err); }
});

weatherController.post('/weather/refresh', async (req, res, next) => {
  try {
    const { date } = req.body;
    const weather = await weatherService.getWeather(date, { forceRefresh: true });
    res.json(weather);
  } catch (err) { next(err); }
});
```

### 8.4 `src/controllers/calendarController.ts`
```typescript
import { Router } from 'express';
import { calendarService } from '../services/calendarService';

export const calendarController = Router();

calendarController.get('/calendar/:date', async (req, res, next) => {
  try {
    const { date } = req.params;
    const events = await calendarService.getHolidays(date);
    res.json(events);
  } catch (err) { next(err); }
});

calendarController.post('/calendar/refresh', async (req, res, next) => {
  try {
    const { date } = req.body;
    const events = await calendarService.getHolidays(date, { forceRefresh: true });
    res.json(events);
  } catch (err) { next(err); }
});
```

### 8.5 `src/controllers/contextController.ts`
```typescript
import { Router } from 'express';
import { fetchContext } from '../services/contextService';

export const contextController = Router();

contextController.get('/context/:date', async (req, res, next) => {
  try {
    const { date } = req.params;
    const context = await fetchContext(date);
    res.json(context);
  } catch (err) { next(err); }
});
```

### 8.6 Stub Controllers (return 501 until later modules)

> **Superseded sketch:** Controller files must declare constructor-injected classes, not `Router()` objects. Use `PredictionController`, `InventoryController`, `PosSimulationController`, `LeftoverManagementController` and `DashboardController`; map their methods from separate thin `routes/*.ts` modules. The following pre-revision snippet is retained only as historical planning context and must not be implemented.

```typescript
// predictionController.ts, inventoryController.ts, salesController.ts,
// donationController.ts, dashboardController.ts
import { Router } from 'express';

export const predictionController = Router();

predictionController.post('/predictions', (req, res) => {
  res.status(501).json({ error: 'Not implemented — Module 2' });
});
predictionController.get('/predictions/:date', (req, res) => {
  res.status(501).json({ error: 'Not implemented — Module 2' });
});
// (same pattern for inventory, sales, donation, dashboard stubs)
```

### 8.7 `src/controllers/index.ts` — Controller Aggregator
```typescript
import { Router } from 'express';
import { healthController } from './healthController';
import { bakerySettingsController } from './bakerySettingsController';
import { weatherController } from './weatherController';
import { calendarController } from './calendarController';
import { contextController } from './contextController';
import { predictionController } from './predictionController';
import { inventoryController } from './inventoryController';
import { salesController } from './salesController';
import { donationController } from './donationController';
import { dashboardController } from './dashboardController';

export const router = Router();

router.use(healthController);
router.use(bakerySettingsController);
router.use(weatherController);
router.use(calendarController);
router.use(contextController);
router.use(predictionController);
router.use(inventoryController);
router.use(salesController);
router.use(donationController);
router.use(dashboardController);
```

---

## 9. App Setup

### 9.1 `src/app.ts`
```typescript
import express from 'express';
import cors from 'cors';
import helmet from 'helmet';
import morgan from 'morgan';
import { router } from './controllers';
import { healthController } from './controllers/healthController';
import { errorHandler } from './middleware/errorHandler';
import { authMiddleware } from './middleware/auth';

export const app = express();

app.use(helmet());
app.use(cors());
app.use(express.json());
app.use(morgan('dev'));

// Health check is public (no auth)
app.use('/api/health', healthController);

// All other /api routes require auth
app.use('/api', authMiddleware, router);

app.use(errorHandler);
```

### 9.2 `src/server.ts`
```typescript
import { app } from './app';
import { env } from './config/env';

app.listen(env.PORT, () => {
  console.log(`Server running on port ${env.PORT}`);
});
```

---

## 10. Utilities

### 10.1 `src/utils/apiError.ts`
```typescript
export class ApiError extends Error {
  constructor(
    public statusCode: number,
    message: string,
    public details?: unknown
  ) {
    super(message);
    this.name = 'ApiError';
  }
}

export class NotFoundError extends ApiError {
  constructor(resource: string) {
    super(404, `${resource} not found`);
  }
}

export class ExternalApiError extends ApiError {
  constructor(service: string, message: string) {
    super(502, `${service} API error: ${message}`);
  }
}
```

### 10.2 `src/utils/retryWithBackoff.ts`
```typescript
export async function retryWithBackoff<T>(
  fn: () => Promise<T>,
  maxRetries: number = 3,
  baseDelayMs: number = 1000
): Promise<T> {
  let lastError: Error;

  for (let attempt = 0; attempt < maxRetries; attempt++) {
    try {
      return await fn();
    } catch (err) {
      lastError = err as Error;
      if (attempt < maxRetries - 1) {
        const delay = baseDelayMs * Math.pow(2, attempt);
        await new Promise(resolve => setTimeout(resolve, delay));
      }
    }
  }
  throw lastError!;
}
```

### 10.3 `src/utils/logger.ts`
```typescript
type LogLevel = 'info' | 'warn' | 'error';

function log(level: LogLevel, message: string, meta?: unknown) {
  const timestamp = new Date().toISOString();
  const entry = { timestamp, level, message, ...(meta && { meta }) };
  console.log(JSON.stringify(entry));
  // Also write to system_logs table (async, fire-and-forget)
}

export const logger = {
  info: (msg: string, meta?: unknown) => log('info', msg, meta),
  warn: (msg: string, meta?: unknown) => log('warn', msg, meta),
  error: (msg: string, meta?: unknown) => log('error', msg, meta),
};
```

---

## 11. Request/Response Flow

```
1. Flutter sends request with JWT
   GET /api/context/2026-06-26
   Authorization: Bearer <supabase-jwt>
       ↓
2. Express app receives
   ├─ helmet (security headers)
   ├─ cors (allow Flutter origin)
   ├─ express.json (parse body)
   ├─ morgan (log request)
       ↓
3. Auth middleware
   ├─ Extract JWT from header
   ├─ Verify with Supabase
   ├─ Attach user to req.user
   └─ If invalid → 401
       ↓
4. Controller handler (contextController — Controller)
   └─ Calls fetchContext('2026-06-26') from contextService
       ↓
5. contextService (Service — orchestrator, Promise.all)
   ├─ weatherService.getWeather()
   │   ├─ weatherRepo.findByDate() → Supabase cache (Repo)
   │   └─ if miss: openWeatherMapClient.fetch() → weatherRepo.upsert()
   └─ calendarService.getHolidays()
       ├─ calendarRepo.findByDate() → Supabase cache (Repo)
       └─ if miss: nagerDateClient.fetchYear() → calendarRepo.upsertMany()
        ↓
6. Both services return → combined DailyContext object
        ↓
7. Response sent to Flutter (Controller → res.json)
   200 OK { date, weather, calendar }
        ↓
8. If error at any step:
   └─ errorHandler middleware
      ├─ systemLogRepo.insert() (Repo → Supabase)
      └─ Return structured error JSON
```

---

## 12. TypeScript Config (`tsconfig.json`)

```json
{
  "compilerOptions": {
    "target": "ES2022",
    "module": "ESNext",
    "moduleResolution": "bundler",
    "esModuleInterop": true,
    "strict": true,
    "outDir": "dist",
    "rootDir": "src",
    "resolveJsonModule": true,
    "skipLibCheck": true,
    "forceConsistentCasingInFileNames": true
  },
  "include": ["src", "shared"],
  "exclude": ["node_modules", "dist"]
}
```

---

## 13. Verification Plan

| Step | Command | Expected Result |
|---|---|---|
| 1 | `cd backend && npm install` | Dependencies installed |
| 2 | `npm run dev` | Server starts on port 3000 |
| 3 | `GET /api/health` | 200 `{ status: "ok" }` |
| 4 | `GET /api/bakery-settings` (with JWT) | Returns bakery config row |
| 5 | `GET /api/weather/2026-06-26` (with JWT) | Returns weather (cached or fetched) |
| 6 | `GET /api/calendar/2026-06-26` (with JWT) | Returns holidays for date |
| 7 | `GET /api/context/2026-06-26` (with JWT) | Returns combined weather + calendar |
| 8 | `GET /api/predictions/today` | 501 Not Implemented (stub) |
| 9 | `GET /api/health` (no JWT) | 200 (health is public) |
| 10 | `GET /api/weather/today` (no JWT) | 401 Unauthorized |
| 11 | `npm run typecheck` | No type errors |
| 12 | `npm run lint` | No lint errors |

---

## 14. Implementation Order

1. Create `package.json`, `tsconfig.json`, `.env.example`
2. Create `src/config/env.ts` + `src/config/supabase.ts`
3. Create `src/utils/` (logger, apiError, retryWithBackoff)
4. Create `src/middleware/` (auth, errorHandler, validateRequest)
5. Create `src/repositories/baseRepo.ts` (generic CRUD base)
6. Create `src/repositories/` (bakerySettingsRepo, weatherRepo, calendarRepo, systemLogRepo)
7. Create `src/adapters/` (conditionMapper, openWeatherMapClient, nagerDateClient)
8. Create `src/services/` (weatherService, calendarService, contextService)
9. Create `src/controllers/` (all controllers + stubs + index)
10. Create `src/app.ts` + `src/server.ts`
11. Install deps: `npm install`
12. Verify: run server + test endpoints

---

## 15. Open Items for Implementation

| # | Item | Notes |
|---|---|---|
| 1 | JWT verification method | Use `jose` library to verify with Supabase JWT secret, OR use Supabase `auth.getUser(token)` API |
| 2 | Weather cache TTL | How long before re-fetching? Suggest: today = 1 hour, tomorrow = 3 hours |
| 3 | Holiday caching | Yearly refresh is enough (holidays don't change after Jan 1) |
| 4 | Rate limiting | Add `express-rate-limit` for production? |

---

**Plan Status:** Complete. Ready for implementation on your signal.
