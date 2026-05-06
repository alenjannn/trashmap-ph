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

## Current Architecture and Data Flow
1. Mobile user signs in/up via Supabase Auth.
2. Citizen drops pin and submits report from Flutter.
3. Report row saved in `reports` table.
4. Supabase Realtime pushes report updates to:
   - Flutter map
   - LGU dashboard map + feed
5. Postgres trigger runs hotspot refresh logic.
6. Hotspots stored in `hotspots` table and rendered on LGU map.

## Current Implementation Status (Important)
- Auth and role routing are active (`admin`, `citizen`, `driver`).
- Dashboard uses live Supabase data and Realtime (no static mock pins).
- Hotspot generation is in Postgres trigger/function flow in `supabase/schema.sql`.
- Hotspot map rendering uses meter-based circle radius + zoom-aware overlay behavior.
- Flutter app has live report fetch + realtime map updates.
- Photo picker UI exists in Flutter report screen.
- **Not fully finished yet:** photo upload to Supabase Storage + storing `photo_url` in report row.
- **Not fully finished yet:** dedicated Flutter missed-pickup submission flow (DB supports type already).

## Quick Repo Map
- `supabase/schema.sql`: tables, RLS, hotspot SQL functions/triggers
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
ORS_API_KEY=your_openrouteservice_api_key
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
- Respect role-based access behavior (`admin`, `citizen`, `driver`).
- Do not alter hotspot SQL thresholds/logic without explicit team decision.
- Treat this file as source of truth for onboarding and workflow policy.

## Known Next Priorities
1. Finish photo upload to Supabase Storage from Flutter report flow.
2. Add dedicated Flutter missed-pickup report submission screen/flow.
3. Continue map UX polish while preserving current hotspot visibility behavior.
