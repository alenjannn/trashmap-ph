# TrashMap PH HOW TOs

## Purpose
Fast setup guide for teammates testing on own devices using own keys/projects.

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
Create root file `.env.local`:

```bash
NEXT_PUBLIC_SUPABASE_URL=your_supabase_project_url
NEXT_PUBLIC_SUPABASE_ANON_KEY=your_supabase_anon_key
SUPABASE_SERVICE_ROLE_KEY=your_service_role_legacy_jwt
ORS_API_KEY=your_openrouteservice_api_key
OPTIMIZER_CRON_SECRET=your_random_secret
DEMO_SEED_SECRET=your_random_secret
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

## HOW TO 10: Test Full Day 3 Flow
1. Start web:
   ```bash
   npm run dev
   ```
2. Seed deterministic demo data:
   ```bash
   curl -X POST http://localhost:3000/api/demo/day3-seed -H "Authorization: Bearer your_demo_seed_secret"
   ```
3. Open LGU dashboard and confirm:
   - report pins visible
   - hotspot circle visible
   - route polylines visible
   - fleet + fuel savings panels updating
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
