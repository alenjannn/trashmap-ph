# TrashMap PH Team Handoff Context

## Purpose
This file gives full project context for teammates and their AI assistants.
Main goal: continue development safely without direct changes to `main`.

## System Overview
TrashMap PH is split into 3 connected parts:

1. **LGU Dashboard (Web)**
   - Stack: Next.js + TypeScript + Leaflet + Tailwind
   - Path: `src/`
   - Role: admin-side operations view (live map, live incident feed, hotspot display)

2. **Client App (Mobile)**
   - Stack: Flutter + Dart + Supabase Flutter
   - Path: `client_app/`
   - Role: citizen/driver-side app (auth, report submission, map, schedules)

3. **Backend / Data**
   - Stack: Supabase (Postgres + PostGIS + Realtime + Auth)
   - Schema path: `supabase/schema.sql`
   - Role: auth, storage of reports/profiles/hotspots, realtime updates
   - **RLS (high level):** `anon` + `authenticated` JWT see only what policies allow. **Service role** (web server, `SUPABASE_SERVICE_ROLE_KEY`) bypasses RLS—use for optimizers, demo seeds, and `ROUTE_OPS_SECRET` route APIs.
   - Fleet tables (`routes`, `route_stops`, `route_progress`, `trucks`): **admin** sees all; **driver** sees/updates rows tied to an **active** `route_assignments` row for that user.
   - `reports`, `schedules`, `recyclers`: read (+ report insert) for `anon`/`authenticated` for public/citizen flows.
   - `collection_points`: public read active pins; authenticated insert/update; **delete** only **admin** profile.
   - `app_user_profiles`: full driver roster (`role = 'driver'`) visible only to **admin** (assignment dropdown); everyone still reads own row via `profiles_select_own`.

## Current Architecture and Data Flow
1. Mobile user signs in/up via Supabase Auth.
2. Citizen drops pin and submits report from Flutter.
3. Report row saved in `reports` table.
4. Supabase Realtime pushes report updates to:
   - Flutter map
   - LGU dashboard map + feed
5. Postgres trigger runs hotspot refresh logic.
6. Hotspots stored in `hotspots` table and rendered on LGU map.

## Day-by-Day Build Summary (Day 1 to Day 4)
### Day 1 - Foundation and UI Shells
- Project scaffolding completed for web (`Next.js`) and mobile (`Flutter`).
- Initial role-aware UI shell established for `admin`, `citizen`, and `driver`.
- Core Supabase project setup prepared (`Auth`, `Database`, `Realtime`, `PostGIS`).

### Day 2 - Core Data Flow and Live Map
- Citizen report pipeline connected end-to-end (mobile submit -> `reports` table).
- LGU dashboard map migrated from mock pins to live Supabase data.
- Realtime subscriptions enabled so new reports appear without refresh.
- Hotspot generation implemented in database trigger/function workflow.
- Incident feed panel added and tied to incoming live report stream.

### Day 3 - Route Optimization and Driver Operations
- Added route stack in schema: `routes`, `route_stops`, `route_progress`.
- Implemented optimizer service in `src/lib/route-optimizer.ts`:
  - ORS integration (`ORS_API_KEY`) for distance/ETA estimates.
  - Automatic fallback to mock estimator when ORS fails/unavailable.
- Added APIs:
  - `POST /api/optimize-routes` (manual optimize trigger)
  - `POST /api/optimize-routes/scheduled` (cron/secret protected trigger)
  - `POST /api/demo/day3-seed` (deterministic demo seed)
- LGU dashboard upgraded:
  - Route polylines rendered on map.
  - Realtime route/progress subscriptions integrated.
  - Fleet status reflects route progress.
  - Fuel savings panel added for demo KPI storytelling.
- Flutter driver mode upgraded:
  - Driver sees assigned route + ordered stops.
  - Driver confirms pickups and updates progress in Supabase.
  - LGU dashboard reflects updates in near real time.

### Day 4 - Full Feature Completion and Polish
- Added Day 4 schema stack:
  - `collection_points`
  - `risk_zones`
  - `gamification_points`
  - `report_verifications`
- Added collection-point-first route planning in optimizer.
- Updated web map legend + semantics (pin colors in `src/components/map/lgu-map.tsx`):
  - orange = reported garbage
  - teal = collection point (distinct from route lines)
  - red = hotspot
  - blue = missed pickup
  - amber = risk zone
  - route polylines = per-route colors from dashboard (not a single “green routes” swatch)
- Removed Fuel Savings panel from active dashboard UI.
- Added dashboard panels:
  - `Risk Zones`
  - `Barangay Leaderboard`
- Flutter updates shipped:
  - Live `Schedule` tab from `schedules`
  - Live `Directory` tab from `recyclers` (list + map + details)
  - New `Rewards` tab (points + leaderboard + before/after verification submit)
- Added `POST /api/demo/day4-seed` endpoint for deterministic Day 4 reset.

## Current Implementation Status (Important)
- Auth and role routing active (`admin`, `citizen`, `driver`).
- Dashboard now realtime for `reports`, `hotspots`, `collection_points`, `risk_zones`, `routes`, `route_stops`, `route_progress`.
- Hotspot rendering keeps red hotspot indicator visible over orange report pins.
- Route optimization supports ORS-first with resilient fallback mode and collection-point-first stop selection.
- Driver route confirmation flow active in Flutter app.
- Demo seeding/rehearsal flow available for repeatable hackathon run (`/api/demo/day3-seed`, `/api/demo/day4-seed`).
- **Not fully finished yet:** dedicated Flutter missed-pickup submission flow (DB supports type already).

## Quick Repo Map
- `docs/TEST_ACCOUNTS.md`: demo **admin / citizen / driver** credentials (dev only; mirrored in `TEST_ACCOUNTS.txt`)
- `supabase/schema.sql`: tables, RLS, hotspot SQL functions/triggers
- `src/lib/route-ops.ts`: template `zone_id` resolution (explicit id → CP zones → any zone → default zone row), shared route/admin DB helpers
- `src/components/layout/dashboard-shell.tsx`: dashboard data orchestration + realtime subscriptions
- `src/components/map/lgu-map.tsx`: hotspot/report map rendering behavior
- `client_app/lib/services/supabase_service.dart`: Supabase init via `--dart-define`
- `client_app/lib/screens/report_screen.dart`: current report submit flow
- `client_app/lib/screens/map_screen.dart`: mobile map + realtime report channel

## Teammate Setup (Web + Mobile + Supabase)

### 1) Clone repository
```bash
git clone <repo-url>
cd trashmap-ph
```

### 2) Install web dependencies
```bash
npm install
```

### 3) Create web env file (`.env.local` at repo root)
```bash
NEXT_PUBLIC_SUPABASE_URL=your_supabase_project_url
NEXT_PUBLIC_SUPABASE_ANON_KEY=your_supabase_anon_key
SUPABASE_SERVICE_ROLE_KEY=your_service_role_legacy_jwt
ORS_API_KEY=your_openrouteservice_api_key
# Day 3/4: OPTIMIZER_CRON_SECRET, DEMO_SEED_SECRET, ROUTE_OPS_SECRET — see HOW TOs.md
```

### 4) Run web dashboard
```bash
npm run dev
```
Open: `http://localhost:3000`

### 5) Supabase account and project setup (Required)
1. Go to [https://supabase.com](https://supabase.com).
2. Click **Start your project** (or **Sign In** if account already exists).
3. Create account (GitHub/Google/email).
4. In Supabase dashboard, click **New Project**.
5. Fill:
   - Organization
   - Project name
   - Database password (save this securely)
   - Region (pick closest to team)
6. Wait for project to finish provisioning.

### 6) Get Supabase keys and URLs
Inside project dashboard:
1. Left sidebar -> **Project Settings** (gear icon).
2. Go to **API**.
3. Copy:
   - **Project URL** -> use for:
     - `NEXT_PUBLIC_SUPABASE_URL` (web)
     - `SUPABASE_URL` (flutter `--dart-define`)
   - **anon public key** -> use for:
     - `NEXT_PUBLIC_SUPABASE_ANON_KEY` (web)
     - `SUPABASE_ANON_KEY` (flutter `--dart-define`)

### 7) Apply database schema
1. In Supabase dashboard left sidebar -> **SQL Editor**.
2. Click **New Query**.
3. Open local file `supabase/schema.sql`, copy all SQL, paste into editor.
4. Click **Run**.
5. Verify key tables exist in **Table Editor** (`reports`, `hotspots`, `app_user_profiles`, etc.).

### 8) Verify extensions and realtime
1. Left sidebar -> **Database** -> **Extensions**.
2. Confirm **postgis** enabled.
3. Left sidebar -> **Database** -> **Replication** (or realtime publication section).
4. Confirm realtime includes needed tables (`reports`, `hotspots`, and other live tables used by app).

## Flutter + Android Studio Emulator Onboarding (Critical)

### A) Install required software
1. **Flutter SDK (stable)**  
   - Install guide: [https://docs.flutter.dev/get-started/install](https://docs.flutter.dev/get-started/install)
   - Add Flutter to PATH.
2. **Android Studio (latest stable)**  
   - Install with default Android components.
3. **JDK 17**  
   - Required by Android project config (`client_app/android/app/build.gradle.kts` uses Java 17).

### B) Install Android SDK packages in Android Studio
Path:
1. Open **Android Studio**.
2. Click **More Actions** (welcome screen) or top menu **File**.
3. Go to **Settings** (or **Preferences** on macOS).
4. Navigate: **Appearance & Behavior > System Settings > Android SDK**.
5. In **SDK Platforms** tab, check at least one stable platform (example: Android 14 / API 34).
6. Go to **SDK Tools** tab, check these:
   - **Android SDK Build-Tools**
   - **Android SDK Command-line Tools (latest)**
   - **Android Emulator**
   - **Android SDK Platform-Tools**
   - **Google USB Driver** (Windows, if physical device testing)
7. Click **Apply** -> **OK** and wait install complete.

### C) Accept Android licenses and verify Flutter
Run in terminal:
```bash
flutter doctor
flutter doctor --android-licenses
```
Accept all prompts (`y`).

Expected:
- `flutter doctor` should show no critical Android toolchain errors.

### D) Create Android emulator (AVD)
Path:
1. Android Studio -> **Tools > Device Manager**  
   (or welcome screen **More Actions > Virtual Device Manager**).
2. Click **Create Device**.
3. Choose device profile (Pixel 6/7 recommended).
4. Click **Next**.
5. Select system image:
   - Recommended: stable API image (x86_64 for Intel/AMD)
   - Download if missing.
6. Finish wizard with default settings.
7. Start emulator from Device Manager (play icon).

### E) Install Flutter package dependencies
```bash
cd client_app
flutter pub get
```

### F) Run Flutter app with Supabase defines (required)
`client_app/lib/services/supabase_service.dart` reads compile-time values:
- `SUPABASE_URL`
- `SUPABASE_ANON_KEY`

Run command:
```bash
flutter run --dart-define=SUPABASE_URL=your_supabase_project_url --dart-define=SUPABASE_ANON_KEY=your_supabase_anon_key
```

If these values missing, app shows Supabase config warning and auth/data will not initialize.

### G) Optional but recommended Flutter tools
- VS Code extensions:
  - Flutter
  - Dart
- Android Studio plugins:
  - Flutter
  - Dart
- Useful commands:
```bash
flutter clean
flutter pub get
flutter devices
flutter run
```

### H) Common emulator troubleshooting
1. **No devices found**
   - Run `flutter devices`.
   - Ensure emulator running.
   - Restart ADB:
     ```bash
     adb kill-server
     adb start-server
     flutter devices
     ```
2. **Gradle/JDK issues**
   - Re-check JDK 17 installation.
   - Re-open Android Studio and sync Gradle.
3. **Slow emulator**
   - Enable hardware acceleration (HAXM/Hyper-V/WHPX depending OS).
4. **Build stuck after dependency changes**
   - Run:
     ```bash
     flutter clean
     flutter pub get
     flutter run
     ```

## Branch and Collaboration Policy (Main Developer Protected Flow)

### Rules
1. `main` is protected by main developer.
2. Teammates **must not** push directly to `main`.
3. All work goes to personal feature branches.
4. Merge to `main` only after main developer review/decision.

### Branch naming
- `feature/<name>-<task>`
- `fix/<name>-<bug>`
- `chore/<name>-<topic>`

Example:
- `feature/jane-photo-upload`
- `fix/mark-hotspot-style`

### Daily Git workflow for teammates
```bash
git checkout main
git pull origin main
git checkout -b feature/<name>-<task>
# make changes
git add .
git commit -m "feat: short clear message"
git push -u origin feature/<name>-<task>
```
Then open PR to `main` and request main developer review.

## Handoff Notes for AI Assistants
- Prefer existing architecture and naming patterns.
- Do not re-introduce mock/static map data.
- Keep Supabase integration realtime-first.
- Respect role-based access behavior (`admin`, `citizen`, `driver`) **and** table RLS in `schema.sql` (fleet data is not world-readable via anon key).
- Do not alter hotspot SQL thresholds/logic without explicit team decision.
- Treat this file as source of truth for onboarding and workflow policy.

## Agentic IDE Fast Context (For New Teammate)
- Start by reading this file, then `supabase/schema.sql`, then `src/components/layout/dashboard-shell.tsx`.
- When debugging route flow, inspect in order:
  1. `src/lib/route-ops.ts` (zone resolution, progress helpers)
  2. `src/lib/route-optimizer.ts`
  3. `src/app/api/optimize-routes/route.ts`
  4. `src/app/api/optimize-routes/scheduled/route.ts`
  5. `client_app/lib/screens/driver_shell.dart`
- Always verify env:
  - Web `.env.local`: `NEXT_PUBLIC_SUPABASE_URL`, `NEXT_PUBLIC_SUPABASE_ANON_KEY`, `SUPABASE_SERVICE_ROLE_KEY`, `ORS_API_KEY`, `OPTIMIZER_CRON_SECRET`, `DEMO_SEED_SECRET`
  - Flutter run defines: `SUPABASE_URL`, `SUPABASE_ANON_KEY`
- For Day 3 reset, call `POST /api/demo/day3-seed` with `Authorization: Bearer <DEMO_SEED_SECRET>`.
- For Day 4 full reset, call `POST /api/demo/day4-seed` with `Authorization: Bearer <DEMO_SEED_SECRET>`.

## Known Next Priorities
1. Add dedicated Flutter missed-pickup report submission screen/flow.
2. Harden Supabase Storage policy checklist for `report-photos` verification uploads.
3. Continue map UX polish while preserving hotspot and risk-zone readability.

## RLS troubleshooting (symptoms)
- **Dashboard shows no routes / empty fleet** while logged in as **citizen** or **driver**: expected—open dashboard as **admin** (`app_user_profiles.role = 'admin'`) for fleet + today’s routes.
- **Driver sees no route**: check active `route_assignments` for that `auth.uid()`; RLS hides routes without assignment.
- **PostgREST permission / policy errors** after git pull: re-run full `supabase/schema.sql` on your Supabase project.
- **Driver roster empty in admin UI**: only admins may list other users’ driver profiles; confirm logged-in user has admin profile row.

## Day 4 Handoff Addendum (Latest)
### Scope Completed
- Admin route planner supports map-based weekly route drafting from `collection_points`.
- Route confirmation modal includes recurrence day + route ops token input.
- Admin can assign drivers for planned routes (manual/auto support in APIs).
- Driver app supports route lifecycle actions: `Start Route`, per-stop pickup confirmation, `End Route`.
- Dashboard now reflects pickup confirmations and route status changes through realtime-backed refresh flows.
- Citizen and admin notifications wired for route lifecycle events (`route_started`, `truck_arriving`, `route_completed`).
- Route audit trail persisted in `route_audit_logs` for timeline/history visibility.

### Day 4 Runtime Requirements
- `ROUTE_OPS_SECRET` must exist in web `.env.local`.
- Dashboard route operations must send matching ops token to protected HTTP APIs (Bearer header).
- Protected server routes include materialize/delete flows (e.g. `DELETE` handlers under `src/app/api/routes/`, `src/app/api/collection-points/`, `src/app/api/routes/templates/`)—all use service client + ops auth, not RLS-patched anon key.
- Database: re-apply `supabase/schema.sql` when pulling main (RLS policies, indexes, notification dedupe constraints, `zones`/`collection_points` helpers).

### Day 4 Validation Checklist
1. Create weekly route from dashboard map and confirm template is saved.
2. Assign driver to created route.
3. In driver app, start route and complete at least one stop.
4. Confirm pickup appears in admin pickup report/timeline.
5. Trigger arriving alert and verify citizen/admin notification visibility.
6. End route and verify final status + audit entries.

### Known Fixed Defect (Driver UUID Error)
- Symptom: `PostgrestException(... invalid input syntax for type uuid: "", code: 22P02 ...)`.
- Root cause: empty UUID value used in route query filter when no assignment/user ID existed.
- Fix applied in `client_app/lib/screens/driver_shell.dart`: early return when `userId` or `assignedRouteId` missing, no UUID query issued with empty string.
