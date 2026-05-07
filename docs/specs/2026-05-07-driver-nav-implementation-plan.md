# Implementation Plan — Driver Navigation, Permanent Assignments, Live Tracking

**Spec:** `docs/specs/2026-05-07-driver-nav-permanent-assign-live-tracking.md`
**Date:** 2026-05-07
**Approach:** 7 phases, each independently shippable. Each phase ends with a verification checklist. Do not start a phase until the previous phase's checklist is green.

---

## Phase 0 — Prerequisites (~2 min)

No card required. ORS already configured.

- [ ] Confirm `ORS_API_KEY` present in `.env.local`.
- [ ] Confirm ORS key works: `curl "https://api.openrouteservice.org/v2/directions/driving-car?api_key=<key>&start=121.0437,14.5995&end=121.0500,14.6000"` returns 200 with GeoJSON.

That's it. Proceed to Phase 1.

---

## Phase 1 — Schema (1–2 h)

**Goal:** All new DB objects exist; RLS policies in place; existing data unaffected.

### Files
- `trashmap-ph/supabase/schema.sql` (append new section "Permanent assignments + live telemetry")

### Tasks
1. Append the entire SQL block from spec section 5 (5.1–5.5) to `schema.sql`.
2. Verify `public.is_current_user_admin()` is defined earlier in the file (it is, from prior work). If not, move the new section after that definition.
3. Run the new SQL in Supabase SQL Editor (or `psql`) to apply.

### Verification
- [ ] `select column_name from information_schema.columns where table_name='route_templates' and column_name in ('start_hour','end_hour');` → 2 rows.
- [ ] `select count(*) from public.route_template_assignments;` → 0 (table exists, empty).
- [ ] `select count(*) from public.truck_pings;` → 0.
- [ ] `select polrelid::regclass, polname from pg_policy where polrelid::regclass::text in ('route_template_assignments','truck_pings');` → 4 rows.
- [ ] Existing dashboard still loads weekly routes (no regression).

---

## Phase 2 — Server: assignments + start endpoint + gate (4–6 h)

**Goal:** Admin can permanently assign a driver to a template; driver can call `/start` and get gate decisions.

### Files
- `src/app/api/routes/templates/[id]/assignments/route.ts` (NEW)
- `src/app/api/routes/templates/[id]/assignments/[assignmentId]/route.ts` (NEW)
- `src/app/api/routes/templates/[id]/start/route.ts` (NEW)
- `src/lib/route-gate.ts` (NEW — `computeGate` function)
- `src/lib/ors-directions.ts` (MODIFY — add `getORSStepInstructions(stops): Promise<{steps, polyline}>` helper that calls ORS `/v2/directions/driving-car/json` with `instructions: true`, parses out step `instruction`, `distance`, `duration`, and waypoint coords)
- `src/app/api/routes/templates/route.ts` (MODIFY — accept `startHour`, `endHour` on POST)

### Tasks
1. **`src/lib/route-gate.ts`** — pure function `computeGate(template, now)` per spec 6.
2. **POST `/assignments`** — admin auth check, look up template, insert row catching unique-violation as `alreadyActive`, return 200.
3. **GET `/assignments`** — admin auth check, return active rows joined with `app_user_profiles` for display name + masked email (reuse `mask_email`).
4. **DELETE `/assignments/[assignmentId]`** — admin auth check, set `is_active=false`, `unassigned_at=now()`.
5. **POST `/start`** — driver auth (Supabase JWT in `Authorization: Bearer`), assignment ownership check, gate compute, materialize-or-fetch today's route (extract reusable helper `materializeForToday(templateId)` from existing `/materialize/route.ts`), call new `getORSStepInstructions` helper for turn-by-turn steps, create per-day `route_assignments` if missing, return `{gate, routeId, stops, polyline, steps, message}`. If `gate ∈ {early, late}` and `force !== true`, return 412.
6. **Templates POST** — extend body parsing to accept `startHour` (default 6) and `endHour` (default 12) and persist.

### Verification
- [ ] Curl POST `/assignments` with admin token + valid driver UUID → 200, row visible in DB.
- [ ] Curl POST `/assignments` again same pair → 200 with `alreadyActive: true`.
- [ ] Curl DELETE → 200, `is_active=false` in DB.
- [ ] Curl POST `/start` on Tuesday for a Thursday template → 412 with `{gate: "early"}`.
- [ ] Curl POST `/start` with `force: true` → 200 with `routeId` populated and route exists in DB with `route_date=today, template_id=<id>`.
- [ ] Calling `/start` twice with `force: true` returns the same `routeId`.

---

## Phase 3 — Server: telemetry + end + report endpoints (3–4 h)

**Goal:** Driver pings stream to admin; ending a route auto-creates missed-pickup reports; admin can fetch full route report.

### Files
- `src/app/api/routes/[id]/telemetry/route.ts` (NEW)
- `src/app/api/routes/[id]/end/route.ts` (NEW)
- `src/app/api/routes/[id]/report/route.ts` (NEW)

### Tasks
1. **POST `/telemetry`** — driver JWT auth, verify driver owns active route assignment, insert `truck_pings` row, broadcast on Supabase Realtime channel `route:<id>:telemetry` via `supabase.channel(...).send({ type: 'broadcast', event: 'ping', payload: {...} })`. Return 204.
2. **POST `/end`** —
   a. Driver auth + ownership check.
   b. Select all `route_progress` for route where `status='pending'`.
   c. For each, update to `missed` and insert one `reports` row (type=`missed_pickup`, priority=`high`, lat/lng/title from the stop).
   d. Update `routes.status` based on result: 0 missed → `completed`, ≥1 missed → `completed_with_issues`.
   e. Set `routes.ended_at = now()`.
   f. Return `{missed: N, status}`.
3. **GET `/report`** — admin auth, fetch `routes` row + `app_user_profiles` for driver + `trucks` + `route_stops` ordered + `route_progress` + `truck_pings` ordered by `recorded_at`. Return single bundle.

### Verification
- [ ] POST `/telemetry` with driver token → 204; row in `truck_pings`. Broadcast event seen in a test Realtime subscriber.
- [ ] POST `/end` on a route with 1 pending stop → 200 `{missed: 1, status: 'completed_with_issues'}`. New `reports` row exists with `type=missed_pickup`.
- [ ] GET `/report` returns object with all expected keys non-null.

---

## Phase 4 — Web admin UI: assignments + report modal + live truck (1–1.5 days)

**Goal:** Admin dashboard reflects new endpoints; can permanently assign drivers, review completed routes, and watch live trucks.

### Files
- `src/components/layout/dashboard-shell.tsx` (MODIFY)
- `src/components/dashboard/route-report-modal.tsx` (NEW)
- `src/components/map/lgu-map.tsx` (MODIFY — add live truck markers)

### Tasks
1. **Driver Assignment panel rewrite** in `dashboard-shell.tsx`:
   - State: `selectedTemplateId`, `selectedDriverIds: string[]`, `templateAssignments: Record<string, AssignmentRow[]>`.
   - On template select, GET `/assignments`, populate `templateAssignments[templateId]`.
   - "Assign" button → POST per selected driver.
   - Render active assignments as removable chips (× → DELETE).
   - Remove the per-day "Manual / Auto" toggle (no longer needed; permanent assignment is simpler).

2. **Route Planner form** — add Start hour / End hour numeric inputs, default 6 / 12. Submit `startHour`/`endHour` in body.

3. **Today's Routes row → modal** — wrap each row in `<button>` with `cursor-pointer`. On click, set `selectedReportRouteId`, fetch `/report`, render `<RouteReportModal>`.

4. **`<RouteReportModal>`** — new component:
   - Same portal structure as `<DangerConfirmModal>`.
   - Sections per spec 7.3 (header, summary, stops table, breadcrumb playback, missed callout, close).
   - Breadcrumb playback: small `<MapContainer>` with route polyline + `<CircleMarker>` driven by scrubber state. Scrubber is `<input type="range">` mapped to ping index.

5. **Live truck markers** in `lgu-map.tsx`:
   - Subscribe to `route:<id>:telemetry` for every in-progress route.
   - Maintain `Record<routeId, latestPing>` state.
   - Render pulsing `<CircleMarker>` per route with rotated arrow icon (heading).
   - ETA pill via `<Tooltip>` showing `remainingStops × 8 min`.
   - Update legend.

### Verification
- [ ] Create weekly route with start/end hours → row in DB has those values.
- [ ] Assign driver → chip appears; refresh page → still appears.
- [ ] Un-assign → chip disappears; DB row `is_active=false`.
- [ ] Click completed route row → modal opens with all fields populated.
- [ ] Drag scrubber → marker moves to correct lat/lng.
- [ ] Open dashboard with one in-progress route, simulate POST `/telemetry` from `curl` → blue dot appears and moves on map.

---

## Phase 5 — Mobile: assigned templates list + preview screen (½ day)

**Goal:** Driver app shows permanent assignments and template preview; Start button works (gate dialog included). Uses existing `flutter_map`.

### Files
- `client_app/pubspec.yaml` (MODIFY — add `connectivity_plus` only)
- `client_app/lib/screens/assigned_templates_screen.dart` (NEW)
- `client_app/lib/screens/template_preview_screen.dart` (NEW)
- `client_app/lib/services/api_client.dart` (MODIFY — add new endpoint methods)
- `client_app/lib/screens/auth_gate.dart` (MODIFY — route to new screen post-login)

### Tasks
1. **Pubspec** — add `connectivity_plus: ^6.0.5`; `flutter pub get`. (`flutter_map` + `latlong2` + `geolocator` already present.)
2. **`assigned_templates_screen.dart`** —
   - On init, query `route_template_assignments` joined with `route_templates` filtered by `driver_id = auth.uid()` and `is_active = true`.
   - Render `ListView` with each row: name, day, time-window (`Thu 06:00–12:00`), badge (on-time/early/late chip).
   - Pull-to-refresh.
3. **`template_preview_screen.dart`** —
   - `FlutterMap` with `TileLayer(urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png', userAgentPackageName: 'ph.trashmap.driver')`.
   - `PolylineLayer` for route polyline + `MarkerLayer` for numbered stop pins.
   - "Start Route" full-width button → `apiClient.startTemplate(templateId, force: false)`.
   - On 412, show `AlertDialog` with copy from spec 8.3, retry with `force: true` on confirm.
   - On 200, push `navigation_screen` (placeholder until Phase 6).
4. **`api_client.dart`** — methods: `getMyAssignedTemplates`, `startTemplate(id, force)`, `getRouteDirections(id)`, `endRoute(id)`, `postTelemetry(id, ping)`.
5. **`auth_gate.dart`** — after login, if `app_user_profiles.role == 'driver'`, push `assigned_templates_screen` instead of current home.

### Verification
- [ ] App builds without changes to Android Gradle.
- [ ] Logged-in driver sees their assigned templates; un-assigned templates do not appear.
- [ ] Tap Thursday template on Tuesday → tap Start → "early" dialog appears → confirm → route starts (placeholder screen for now).
- [ ] OSM tiles load correctly with custom User-Agent header (verify via charles/mitmproxy on dev device).

---

## Phase 6 — Mobile: navigation screen + custom turn-by-turn HUD + telemetry + end route (1.5 days)

**Goal:** Functional turn-by-turn driving experience using `flutter_map` + ORS step instructions; pings stream; end-route confirms missed pickups server-side.

### Files
- `client_app/lib/screens/navigation_screen.dart` (NEW)
- `client_app/lib/services/telemetry_service.dart` (NEW)
- `client_app/lib/widgets/turn_by_turn_hud.dart` (NEW — top HUD card)
- `client_app/lib/utils/geo.dart` (NEW — Haversine, point-on-polyline distance)

### Tasks
1. **`utils/geo.dart`** — pure functions:
   - `haversineMeters(LatLng a, LatLng b)`
   - `distanceToPolylineMeters(LatLng p, List<LatLng> polyline)` (perpendicular distance to nearest segment)
   - `bearing(LatLng a, LatLng b)` for camera heading

2. **`telemetry_service.dart`** —
   - `Geolocator.getPositionStream(LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: 15))`.
   - Throttle to one POST per 20s.
   - For each position, POST `/api/routes/[id]/telemetry`.
   - On error, append to in-memory queue (capped 500).
   - `connectivity_plus` listener: on reconnect, drain queue oldest-first.
   - Expose `ValueNotifier<Position?> currentPosition` so screens can subscribe without spawning a second `getPositionStream`.

3. **`widgets/turn_by_turn_hud.dart`** —
   - Stateless widget. Inputs: `currentStep`, `distanceToStepMeters`, `nextStopLabel`, `etaMinutes`.
   - Card UI: large maneuver icon (use Lucide-style Flutter icons: `Icons.turn_left`, `Icons.turn_right`, `Icons.straight`, `Icons.flag`), primary instruction, secondary stop+ETA.

4. **`navigation_screen.dart`** —
   - State: `steps`, `currentStepIndex`, `polyline`, `currentPosition`, `currentStopIndex`, `isOffRoute`.
   - In `initState`:
     - Read `routeId`, `stops`, `polyline`, `steps` from route arguments (passed from `template_preview_screen`).
     - Start `TelemetryService(routeId)`.
     - Subscribe to `telemetryService.currentPosition` ValueNotifier.
   - On each position update:
     - Compute distance to current step waypoint. If <25m → `currentStepIndex++`.
     - Recompute distance to current stop. If <50m → enable "Confirm pickup" button.
     - Compute `distanceToPolylineMeters`. If >75m for >15s → set `isOffRoute = true`.
     - Move map camera with `mapController.moveAndRotate(currentPosition, 17, bearing)`.
   - In `dispose`: stop telemetry service.
   - UI:
     - `FlutterMap` full-screen with TileLayer + PolylineLayer + MarkerLayer (stops + driver dot).
     - `Positioned` top: `<TurnByTurnHud>`.
     - `Positioned` bottom: "Confirm pickup" + "End Route" buttons.
     - Off-route banner overlay if `isOffRoute`.
   - "End Route" → confirm dialog → `apiClient.endRoute(routeId)` → toast → `Navigator.popUntil(assigned)`.

### Verification
- [ ] Real Android device — start a test route. Polyline visible. First HUD instruction shown ("In 200 m, turn right onto Ortigas Avenue").
- [ ] Walk past a turn waypoint → HUD instantly advances to next step.
- [ ] Map camera follows position smoothly (no jitter).
- [ ] Walk perpendicular >75m for 15s → off-route banner appears.
- [ ] Approach a stop within 50m → "Confirm pickup" enables; tap → `route_progress` row flips to `confirmed`.
- [ ] Tap "End Route" with 1 unconfirmed stop → admin dashboard shows `completed_with_issues`, missed-pickup report appears.
- [ ] Toggle airplane mode mid-route → polyline + HUD continue (in-memory data); telemetry queues; toggle back → queue drains.

---

## Phase 7 — Polish, docs, rollout (0.5 day)

**Goal:** Production-ready quality; one-pager docs; pilot driver onboarded.

### Tasks
- [ ] Add unit tests for `computeGate` in `src/lib/route-gate.test.ts`.
- [ ] Add integration test for `/end` missed-pickup creation.
- [ ] Lint pass: `npm run lint --workspaces=false` (or `cd trashmap-ph && npm run lint`).
- [ ] Type-check pass.
- [ ] Smoke test full happy path: create template → assign driver → driver opens app → Start (on-time) → Confirm 4 of 4 → End → admin sees `completed`.
- [ ] Smoke test sad path: assign driver → Start (early, force) → confirm 2 of 4 → End → admin sees 2 missed reports + breadcrumb playback.
- [ ] Update `docs/HOW TOs.md`: short section "How to assign a driver permanently" + "How to review a completed route" (skip per user prior request? — confirm before doing).
- [ ] Tag commit: `feat: driver nav + permanent assignments + live tracking`.

### Verification
- [ ] All automated tests green.
- [ ] No new lint errors.
- [ ] Pilot driver completes one real route end-to-end without dev intervention.

---

## Dependencies between phases

```
Phase 0 (tokens)
    ↓
Phase 1 (schema)
    ↓
    ├── Phase 2 (assignments + start)
    │       ↓
    │       Phase 3 (telemetry + end + report)
    │             ↓
    │             ├── Phase 4 (web UI)
    │             └── Phase 5 (mobile preview)
    │                       ↓
    │                       Phase 6 (mobile nav + telemetry)
    │                             ↓
    │                             Phase 7 (polish)
```

Phase 4 and Phase 5 can run in parallel after Phase 3.

## Risk per phase

| Phase | Risk | Mitigation |
|-------|------|------------|
| 1 | RLS policy mistake locks out admin | Test with admin login immediately after applying. Keep `is_current_user_admin()` as the gate. |
| 2 | Gate logic timezone bug | Server runs in UTC; convert to Asia/Manila before extracting day/hour. Add tests. |
| 3 | Realtime broadcast doesn't fire | Use Supabase dashboard "Realtime" tab to verify channel + event during dev. |
| 4 | `<MapContainer>` crash on report modal | Reuse `panesReady` pattern from main map; mount once per modal open. |
| 5 | OSM tile usage policy violation | Set `userAgentPackageName: 'ph.trashmap.driver'` in `TileLayer`. Monitor request volume; switch to CartoCDN if pilot grows. |
| 6 | ORS step instructions unparseable / API fails | Server falls back to OSRM, then to synthetic single-step. App shows "Turn-by-turn unavailable" banner; map polyline still works. |
| 7 | Pilot driver runs into edge case | Have dev on standby for first run; collect logs. |

## Estimated total: 4–6 dev days

(Phase 0 ~2 min; Phase 1 ½ day; Phase 2 ¾ day; Phase 3 ½ day; Phase 4 1.5 days; Phase 5 ½ day; Phase 6 1.5 days; Phase 7 ½ day.)

Saved ~1 day vs. Mapbox plan: no SDK install, no token plumbing, no Android Gradle changes, no offline tile region setup.
