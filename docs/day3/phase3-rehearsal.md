# Day 3 Phase 3 Rehearsal Runbook

## Purpose
Repeatable Day 3 demo flow with stable data:
- optimize routes
- show route polylines
- show driver confirmations
- show realtime fleet progress + fuel savings

## Pre-Run Checklist
- Web app running (`npm run dev`).
- Flutter app running on emulator/device (driver account available).
- Supabase schema applied with Day 3 tables:
  - `routes`
  - `route_stops`
  - `route_progress`
- Env keys set:
  - `NEXT_PUBLIC_SUPABASE_URL`
  - `SUPABASE_SERVICE_ROLE_KEY`
  - `ORS_API_KEY` (optional, fallback to mock if unavailable)
  - `OPTIMIZER_CRON_SECRET` (for scheduled route endpoint)
  - `DEMO_SEED_SECRET` (for demo seed endpoint)

## Step 1: Seed Day 3 Demo State (Deterministic)
Use protected seed endpoint to reset and prepare demo data.

`POST /api/demo/day3-seed` with header:
- `Authorization: Bearer <DEMO_SEED_SECRET>`

Expected result:
- new optimized routes generated
- stops generated
- first stop per route marked as completed
- fuel settings seeded (`app_config.fuel_settings`)

## Step 2: LGU Dashboard Validation
1. Open dashboard map.
2. Confirm:
   - route polylines visible
   - fleet panel shows non-zero progress on at least one truck
   - fuel savings panel shows values
3. Click `Optimize Now`.
4. Confirm route refresh and success status message.

## Step 3: Driver Flow Validation
1. Login as driver in Flutter app.
2. Confirm:
   - route polyline visible
   - stop list loaded
3. Press `Confirm Pickup` for one pending stop.
4. Confirm local success toast/snackbar.

## Step 4: Realtime Loop Validation (Critical)
After driver confirms stop:
1. Check LGU dashboard updates within seconds.
2. Confirm:
   - truck progress percent increases
   - status changes (`en_route`/`collecting`/`idle`) reflect latest state
   - fuel savings panel remains populated

## Step 5: Scheduled Trigger Validation (Optional)
Use schedule endpoint manually to simulate cron:

`POST /api/optimize-routes/scheduled` with header:
- `Authorization: Bearer <OPTIMIZER_CRON_SECRET>`

Expected:
- success response
- `triggeredBy: "schedule"`
- mode is `ors` or `mock` depending ORS availability

## Demo Script (Judge-Facing)
1. Show LGU dashboard with live map + routes + savings.
2. Trigger `Optimize Now` to show route generation.
3. Switch to Flutter driver mode.
4. Confirm one pickup stop.
5. Return to dashboard and show realtime fleet progress change.

## Known Fallback Behavior
- If ORS is down or key invalid:
  - optimizer auto-switches to `mock`
  - system still generates deterministic routes
  - demo flow remains intact

## Exit Criteria
- End-to-end loop runs 3 times consecutively with no manual DB edits.
- No blocking web build/lint errors.
- Driver confirm action consistently updates LGU dashboard in realtime.
