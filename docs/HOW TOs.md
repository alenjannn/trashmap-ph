# TrashMap PH HOW TOs

## Purpose
Fast setup guide for teammates testing on own devices using own keys/projects.

> **New devs:** read `docs/SYSTEM_OVERVIEW.md` first. It maps every system function (collection points, weekly routes, hotspots, schedules, community map, driver assigning, navigation HUD) to the exact tables, endpoints, and files you need to touch.

## HOW TO 1: Create Supabase Project
1. Go to [https://supabase.com](https://supabase.com) and sign in.
2. Click **New project**.
3. Set project name, DB password, region.
4. Wait until project status is healthy.

## HOW TO 2: Get Supabase Keys
In Supabase dashboard:
1. Open **Project Settings** -> **API**.
2. Copy values:
   - **Project URL**
   - **anon public key**
   - **service_role key (legacy JWT / starts with `eyJ...`)**

Use mapping:
- `NEXT_PUBLIC_SUPABASE_URL` = Project URL
- `NEXT_PUBLIC_SUPABASE_ANON_KEY` = anon public key
- `SUPABASE_SERVICE_ROLE_KEY` = service_role key (legacy JWT)
- Flutter `SUPABASE_URL` = Project URL
- Flutter `SUPABASE_ANON_KEY` = anon public key

## HOW TO 3: Get ORS API Key
1. Go to [https://openrouteservice.org/dev/#/signup](https://openrouteservice.org/dev/#/signup).
2. Create/login account.
3. Open dashboard and create API key.
4. Put key in:
   - `ORS_API_KEY=<your key>`

Note: ORS key may end with `=`. This is valid.

## HOW TO 4: Generate Secrets for Protected APIs
Need 2 secrets:
- `OPTIMIZER_CRON_SECRET`
- `DEMO_SEED_SECRET`

PowerShell:
```powershell
[guid]::NewGuid().ToString("N")
```
Run twice. Use outputs as secrets.

## HOW TO 5: Configure Web `.env.local`
Create root file `.env.local` (Day 4 also needs `ROUTE_OPS_SECRET`—see HOW TO 13):

```bash
NEXT_PUBLIC_SUPABASE_URL=your_supabase_project_url
NEXT_PUBLIC_SUPABASE_ANON_KEY=your_supabase_anon_key
SUPABASE_SERVICE_ROLE_KEY=your_service_role_legacy_jwt
ORS_API_KEY=your_openrouteservice_api_key
OPTIMIZER_CRON_SECRET=your_random_secret
DEMO_SEED_SECRET=your_random_secret
# Day 4 admin route HTTP ops:
# ROUTE_OPS_SECRET=your_strong_route_ops_secret
```

Restart dev server after changes:
```bash
npm run dev
```

## HOW TO 6: Start Web App (Terminal)
From project root:
```bash
npm install
npm run dev
```

Open:
- `http://localhost:3000`

If port busy, run:
```bash
npm run dev -- --port 3001
```

## HOW TO 7: Check Android Emulators/Devices in Terminal
### Option A: Default `flutter` in PATH
```bash
flutter devices
```

### Option B: Explicit Puro Flutter path (your setup example)
```powershell
& "C:\Users\YOUR_SYSTEM_NAME\.puro\envs\stable\flutter\bin\flutter.bat" devices
```

## HOW TO 8: Run Flutter App on Specific Emulator
From `client_app`:
```bash
flutter run --dart-define=SUPABASE_URL=your_supabase_project_url --dart-define=SUPABASE_ANON_KEY=your_supabase_anon_key
```

Specific emulator target example (`emulator-5554`) with explicit Flutter path:
```powershell
& "C:\Users\YOUR_SYSTEM_NAME\.puro\envs\stable\flutter\bin\flutter.bat" run -d emulator-5554 --dart-define=SUPABASE_URL="https://YOUR_PROJECT.supabase.co" --dart-define=SUPABASE_ANON_KEY="YOUR_REAL_ANON_KEY"
```

Tip:
- Start emulator first in Android Studio Device Manager before `flutter run`.
- Recheck connected devices anytime with `flutter devices`.
- Demo **citizen / driver / admin** logins: `docs/TEST_ACCOUNTS.md` (also `docs/TEST_ACCOUNTS.txt`).

## HOW TO 9: Apply Database Schema
1. Open Supabase **SQL Editor**.
2. Paste full `supabase/schema.sql`.
3. Run script.
4. Confirm tables exist:
   - `reports`
   - `hotspots`
   - `routes`
   - `route_stops`
   - `route_progress`
   - `zones`, `collection_points`, `route_templates`, `route_assignments`, … (see `schema.sql` head comments)
5. After pulling new code, **re-run the full script** (or your migration pipeline) so **RLS policies** stay in sync—otherwise the web/driver apps may get empty data or policy errors (see HOW TO 18).

## HOW TO 10: Test Full Day 3 Flow
1. Start web:
   ```bash
   npm run dev
   ```
2. Seed deterministic demo data:
   ```bash
   curl -X POST http://localhost:3000/api/demo/day3-seed -H "Authorization: Bearer your_demo_seed_secret"
   ```
3. Open LGU dashboard **as admin** and confirm:
   - report pins visible
   - hotspot circle visible
   - route polylines visible
   - fleet / route progress reflects live data (Fuel Savings panel removed from UI)
4. Open Flutter driver mode and confirm pickup.
5. Check LGU dashboard updates in near real time.

## HOW TO 11: Fix Common API Key Errors
- Error: `"Route optimizer requires NEXT_PUBLIC_SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY in server environment."`
  - Fix: set both in `.env.local`, restart web server.
- Error: `"Unable to prepare truck seed data. Invalid API key"`
  - Fix: wrong service role key type. Use legacy JWT `service_role` (`eyJ...`), not `sb_secret_...`.
- Error: `"Unable to persist route stops. Could not find the table 'public.route_stops' in the schema cache"`
  - Fix: re-run `supabase/schema.sql` in SQL Editor.

## HOW TO 12: Recommended Team Rule
- Each teammate uses own Supabase project + own keys on own machine.
- Never commit real keys/secrets to git.
- Share only placeholders in docs and `.env` templates.

## HOW TO 13: Day 4 Route Operations Setup
Day 4 route operations require one more server secret:
- `ROUTE_OPS_SECRET`

Update root `.env.local`:

```bash
NEXT_PUBLIC_SUPABASE_URL=your_supabase_project_url
NEXT_PUBLIC_SUPABASE_ANON_KEY=your_supabase_anon_key
SUPABASE_SERVICE_ROLE_KEY=your_service_role_legacy_jwt
ORS_API_KEY=your_openrouteservice_api_key
OPTIMIZER_CRON_SECRET=your_random_secret
DEMO_SEED_SECRET=your_random_secret
ROUTE_OPS_SECRET=your_strong_route_ops_secret
```

Restart dev server after env changes:
```bash
npm run dev
```

## HOW TO 14: Day 4 Admin Weekly Route Flow
1. Open LGU dashboard route planner.
2. Click **Create Weekly Route**.
3. Click collection points on map in desired order.
4. Click **Confirm Route**.
5. In modal, fill:
   - Route name
   - Recurrence day
   - Ops token (`ROUTE_OPS_SECRET` value)
6. Click **Create Route**.
7. Assign driver now or later in Route Assignment panel.

Expected result:
- New template saved (`route_templates`, `route_template_stops`)
- Assignment reflected in dashboard
- Audit logs visible in live route timeline

## HOW TO 15: Day 4 Driver Start/End and Pickup Flow
1. Login as driver in Flutter app.
2. Confirm assigned route appears.
3. Tap **Start Route**.
4. Confirm pickup per stop.
5. Tap **End Route**.

Expected result:
- Route status moves through `in_progress` -> `completed` / `completed_with_issues`
- Pickup confirmations update dashboard live
- Route audit and notification logs written

## HOW TO 16: Day 4 Notification Verification
Verify these notifications are emitted:
- `route_started` (admin + citizen zone)
- `truck_arriving` (admin + citizen zone)
- `route_completed` (admin + citizen zone)

Check tables:
- `route_notifications_log`
- `route_audit_logs`

## HOW TO 17: Day 4 Common Errors + Fix
- Error: `invalid input syntax for type uuid: ""` in driver app
  - Cause: empty route ID or user ID used in UUID filter.
  - Fix: ensure driver route load skips route query when assignment not found.
- Error: `Unauthorized route ops request`
  - Cause: wrong/missing ops token.
  - Fix: set `ROUTE_OPS_SECRET` in `.env.local`, restart server, input exact same token in admin modal.

## HOW TO 18: Row Level Security (empty data / permission errors)
Symptoms: dashboard shows **no routes** or **no trucks**; Supabase client errors mentioning **policy** / **permission**; driver cannot update stops despite assignment.

Checks:
1. **Re-apply** `supabase/schema.sql` on the Supabase project you are pointing at (team members often use different projects).
2. **Dashboard:** log in with a user whose `app_user_profiles.role` is **`admin`**. Citizens/drivers do **not** receive fleet-wide `routes` / `trucks` rows under current RLS.
3. **Driver app:** ensure `route_assignments` has an **active** row (`is_active = true`) linking `driver_id` to the route; without it, `routes` / `route_stops` / `trucks` are hidden.
4. **Citizen / anon:** `reports`, `schedules`, `recyclers` remain readable for map and tabs; fleet tables are not.
5. **Server-only work** (optimizer, demo seeds, HTTP DELETE/materialize with `ROUTE_OPS_SECRET`) uses **service role** and bypasses RLS—if those fail, check `SUPABASE_SERVICE_ROLE_KEY` in `.env.local`, not RLS.

## HOW TO 19: Assign Driver Permanently (Weekly Template)
1. Open dashboard route planner page as admin.
2. In **Driver Assignment** panel, paste `ROUTE_OPS_SECRET`.
3. Select weekly template.
4. Tick one or more drivers in **Add drivers** list.
5. Click **Assign selected**.
6. Confirm assigned chips appear.

Result:
- Rows created in `route_template_assignments` with `is_active=true`.
- Driver app shows template in **My weekly routes** list.

## HOW TO 20: Review Completed Route (Playback + Missed Pickup)
1. Open dashboard as admin.
2. In **Manage Data > Today's routes**, click route status row (not Delete button).
3. Route report modal opens with:
   - summary (truck, driver, status)
   - stops table
   - missed pickup callout (if any)
   - GPS playback map + scrubber
4. Drag scrubber to inspect breadcrumb sequence.

For routes ended with unresolved stops:
- Route status becomes `completed_with_issues`.
- `reports` rows with `report_type='missed_pickup'` should exist.

## HOW TO 21: Driver Navigation (Phase 6)
Pre-reqs: Phase 1 schema applied, driver assigned to a weekly template (HOW TO 19), Next.js reachable from device (`API_BASE_URL` resolves to a non-loopback URL on the emulator/device).

### Run app with API base URL
Android emulator (host loopback is `10.0.2.2`):
```powershell
& "C:\Users\YOUR_SYSTEM_NAME\.puro\envs\stable\flutter\bin\flutter.bat" run -d emulator-5554 ^
  --dart-define=SUPABASE_URL="https://YOUR_PROJECT.supabase.co" ^
  --dart-define=SUPABASE_ANON_KEY="YOUR_REAL_ANON_KEY" ^
  --dart-define=API_BASE_URL="http://10.0.2.2:3000"
```
iOS simulator: `--dart-define=API_BASE_URL="http://127.0.0.1:3000"`.
Physical device: use the dev machine's LAN IP (e.g. `http://192.168.1.42:3000`) and ensure firewall allows port 3000.

### Driver flow
1. Login as driver. **My weekly routes** list opens.
2. Tap a template. **Preview** shows polyline + ordered stops.
3. Tap **Start Route**. If outside the schedule window the app prompts Early/Late confirmation; tap **Start** to force.
4. **Navigation** screen opens:
   - Top HUD: next maneuver instruction + distance, ETA, stops counter, online/offline pill.
   - Map follows GPS. Truck arrow rotates with heading. Stops change color as their status updates (teal=pending, amber=arrived, green=completed, gray=skipped, red=missed).
   - Bottom sheet: per-stop **Confirm** / **Skip** actions.
5. Telemetry posts every 5 s to `/api/routes/:id/telemetry`. Offline pings buffer in memory and drain when connectivity returns.
6. Within 50 m of a stop for 3 s, the engine auto-flips it to `arrived` and writes `route_progress`.
7. Tap the red stop icon (top right) to **End Route**. Confirm dialog warns of unresolved stops; ending posts to `/api/routes/:id/end` which marks pending/arrived stops as `missed` and creates `report_type='missed_pickup'` rows.

### Verify on the dashboard
- Live truck arrow on map updates while driving.
- After end-route: route status = `completed_with_issues` (when unresolved) or `completed`. Truck status returns to `idle`.
- Open **Today's routes** → click route to see the playback modal.

## HOW TO 22: Deploy Web Dashboard to Vercel (GitHub import)

Pre-reqs: repo pushed to GitHub (`alenjannn/trashmap-ph` or your fork), Supabase project healthy, schema applied (HOW TO 9), `.env.local` working locally.

### Step 1 — Import repo
1. Open [https://vercel.com/new](https://vercel.com/new) → click **Import Git Repository**.
2. Pick the `trashmap-ph` repo.
3. **Root Directory** → leave **`./` (`trashmap-ph` root)**. The Next.js app lives at the repo root.
4. **Application Preset** → Vercel auto-detects **Next.js**. Leave it.
5. **Build / Output / Install** — leave all toggles off (use defaults). Defaults are correct: `next build`, no custom output dir, `npm install`.

### Step 2 — Environment variables
Open **Environment Variables** → click **Import .env** and paste your `.env.local` contents (or add each row by hand). Required:

| Variable | Where it comes from |
|---|---|
| `NEXT_PUBLIC_SUPABASE_URL` | Supabase Project Settings → API |
| `NEXT_PUBLIC_SUPABASE_ANON_KEY` | Supabase Project Settings → API (anon public) |
| `SUPABASE_SERVICE_ROLE_KEY` | Supabase Project Settings → API (legacy JWT, `eyJ...`, **not** `sb_secret_`) |
| `ORS_API_KEY` | OpenRouteService dashboard |
| `OPTIMIZER_CRON_SECRET` | Random — `[guid]::NewGuid().ToString("N")` |
| `CRON_SECRET` | **Same value** as `OPTIMIZER_CRON_SECRET` (Vercel cron auth header) |
| `DEMO_SEED_SECRET` | Random |
| `ROUTE_OPS_SECRET` | Random |
| `LGU_SUPABASE_AUTH_EMAIL` | Seeded admin email (e.g. `lgu-dashboard@trashmap.ph`) |
| `LGU_SUPABASE_AUTH_PASSWORD` | Seeded admin password |

Set each for **Production** and **Preview** scopes (default).

### Step 3 — Deploy
Click **Deploy**. First build ~2 min. When done:
- Vercel hands you `https://<project>.vercel.app`.
- Open `/` → admin login gate; sign in with `LGU_SUPABASE_AUTH_*`.

### Step 4 — Supabase auth domain whitelist
1. Supabase → **Authentication** → **URL Configuration**.
2. **Site URL** → set to `https://<project>.vercel.app`.
3. **Redirect URLs** → add `https://<project>.vercel.app/**` and (if you use a Vercel preview URL) `https://*-<team>.vercel.app/**`.

### Step 5 — Mobile app points at production
Rebuild the Flutter app with the Vercel URL:

```powershell
& "C:\Users\YOUR_SYSTEM_NAME\.puro\envs\stable\flutter\bin\flutter.bat" run -d emulator-5554 ^
  --dart-define=SUPABASE_URL="https://YOUR_PROJECT.supabase.co" ^
  --dart-define=SUPABASE_ANON_KEY="YOUR_ANON_KEY" ^
  --dart-define=API_BASE_URL="https://<project>.vercel.app"
```

For release builds, bake the URL into your CI command instead of `.env`.

### Step 6 — Verify cron (optional)
`vercel.json` schedules a daily optimizer run at `0 18 * * *` UTC (02:00 PHT) hitting `/api/optimize-routes/scheduled`. Vercel auto-sends `Authorization: Bearer ${CRON_SECRET}`. Confirm:
- Vercel project → **Settings → Cron Jobs** — entry visible.
- After first run, **Logs** show `triggeredBy: schedule`.

If you don't want cron yet, delete `vercel.json` (the file is opt-in for everything else; Next.js still works without it).

### Step 7 — Common deploy issues
| Symptom | Fix |
|---|---|
| Build OK, every API route 500s | Env vars missing/wrong scope. Re-check Production scope. |
| `Invalid API key` on first admin load | Used `sb_secret_…` instead of legacy JWT for `SUPABASE_SERVICE_ROLE_KEY`. |
| `Not signed in` from mobile after switching to Vercel URL | Forgot Step 4 (Supabase redirect whitelist). |
| Cron returns 401 | `CRON_SECRET` env not set OR not equal to `OPTIMIZER_CRON_SECRET`. |
| Realtime not updating dashboard in prod | Re-run schema (publication `supabase_realtime` membership) on the same Supabase project Vercel uses. |

### What `.vercelignore` skips
`client_app/` (Flutter), `docs/`, `supabase/`, screenshots, `.7z`. None of these are needed at runtime; trimming them keeps each deploy upload small. Edit `.vercelignore` if you add a new top-level dir Vercel doesn't need.
