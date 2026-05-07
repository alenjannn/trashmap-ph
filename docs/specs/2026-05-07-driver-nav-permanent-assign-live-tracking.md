# Driver Navigation, Permanent Weekly Assignments, and Live Tracking

**Date:** 2026-05-07
**Status:** Approved (design phase) → moving to implementation plan
**Owner:** TrashMap PH LGU operations
**Estimated effort:** 6–8 dev days (single dev)

---

## 1. Problem statement

Today the LGU dashboard and the driver Flutter app handle weekly routes as throwaway, per-day artefacts. Specifically:

1. **Mobile app has no turn-by-turn navigation.** Drivers see a static polyline on `flutter_map` and must mentally translate it into driving directions. The reference UX is Google Maps' "Drive" mode (image set 1 in chat).
2. **Missed pickups are invisible to admins.** When a driver ends a route with unconfirmed stops, those stops silently stay `pending` forever. There is no record in the Waste Report Feed.
3. **Completed routes can't be reviewed.** A row in "Today's Routes" with status `completed_with_issues` is not openable. The admin cannot see which stops failed, when, or who was driving.
4. **Driver↔route assignment is per-day, not per-template.** Admin must re-assign a driver every day to the freshly materialized run. A driver cannot be told "you own this Thursday route permanently" and just open the app any morning.
5. **No early/late guardrails.** A driver could start a Thursday route on Tuesday or at 11pm without any warning.
6. **No live ETA / truck tracking.** Admin cannot see where the truck is or when it'll finish.

This spec covers all six gaps in a single iteration.

## 2. Goals

- Drivers get **in-app turn-by-turn navigation** matching Google Maps quality, without leaving the TrashMap PH app.
- Admins **always know which pickups failed** because missed stops auto-create reports.
- Admins can **inspect any completed route** in a modal showing stops, statuses, timestamps, and a breadcrumb of the driver's GPS path.
- A driver assigned to a **weekly route owns it permanently** until unassigned. They open the app and see the route they're responsible for.
- Drivers attempting to start **outside the scheduled day-and-time window** are warned but not blocked.
- Admins see a **live truck dot moving on the map + ETA** for every in-progress route.

## 3. Non-goals (this iteration)

- Voice instructions (text-only HUD; voice can be added later via `flutter_tts`)
- Auto-rescheduling missed pickups onto the next week's run
- Multi-language UI / localization
- Per-stop ETA breakdown (only route-level ETA)
- Driver-to-driver chat
- Background GPS tracking when the app is backgrounded or killed
- Web admin's own turn-by-turn nav (admin uses dashboard, not field nav)
- Offline tile caching beyond `flutter_map`'s default in-memory tile cache (full offline regions deferred — would require `flutter_map_tile_caching` package, added later if needed)
- Mapbox / Google Maps / paid map SDKs (no billing card required for this iteration; uses OpenStreetMap raster tiles via `flutter_map`)

## 4. Architecture

```
ADMIN (web — Next.js / dashboard-shell.tsx)            DRIVER (mobile — Flutter)
  │                                                      │
  ├─ Create weekly route                                 ├─ Open app
  │  (start_hour, end_hour added to form)                │      ↓
  │                                                      ├─ assigned_templates_screen
  ├─ Driver Assignment panel                             │     (lists my templates with
  │   pick template + driver(s) → POST /assignments      │      on-time / early / late badge)
  │   (multiple drivers per template OK)                 │      ↓
  │                                                      ├─ template_preview_screen
  │      ┌── Live truck dot + ETA pill                   │     (flutter_map preview,
  │      │   on map (Realtime channel)                   │      stops + polyline overlay,
  │      ▼                                               │      "Start Route" button)
  ├─ MapOverview shows in-progress routes                │      ↓
  │  with moving truck markers                           ├─ /api/routes/templates/[id]/start
  │                                                      │     (gate: on_time | early | late)
  ├─ Today's Routes row click                            │      ↓ (if early/late → confirm modal)
  │     ↓                                                ├─ navigation_screen
  ├─ <RouteReportModal>                                  │     (flutter_map + auto-follow camera +
  │   summary + stops + breadcrumb playback              │      ORS-driven step-by-step HUD,
  │                                                      │      pickup confirm per stop)
  ├─ Waste Report Feed shows missed-pickup reports       │      ↓
  │  as orange dots                                      ├─ GPS pings every 20s →
                                                         │  /api/routes/[id]/telemetry
                                                         │      ↓
                                                         ├─ End Route → /api/routes/[id]/end
                                                         │     (auto-mark pending → missed,
                                                         │      auto-create reports)
                                                         └─ Pop back to assigned_templates_screen
```

**Component boundaries:**
- **Schema layer:** new tables + columns; FK cascades drive cleanup automatically.
- **API layer (Next.js route handlers):** thin REST endpoints; no business logic in the dashboard component.
- **Web UI layer:** dashboard-shell composes new panels and modal; existing realtime hooks reused.
- **Mobile UI layer:** screen-per-flow, each screen owns its data fetching and `flutter_map` controller lifecycle.
- **Routing-engine adapter:** `getORSRoadGeometry` (already exists) keeps producing polylines for the DB; a new `getORSStepInstructions` helper returns turn-by-turn step list. Mobile renders polyline + steps natively in the HUD.

## 5. Schema delta

```sql
-- 5.1) Time window on weekly templates
alter table public.route_templates
  add column if not exists start_hour smallint not null default 6
    check (start_hour between 0 and 23),
  add column if not exists end_hour smallint not null default 12
    check (end_hour between 1 and 24);
alter table public.route_templates
  drop constraint if exists route_templates_hours_check;
alter table public.route_templates
  add constraint route_templates_hours_check check (end_hour > start_hour);

-- 5.2) Permanent driver↔template assignment table
create table if not exists public.route_template_assignments (
  id uuid default gen_random_uuid() primary key,
  template_id uuid not null references public.route_templates(id) on delete cascade,
  driver_id uuid not null references auth.users(id) on delete cascade,
  assigned_by uuid references auth.users(id) on delete set null,
  assigned_at timestamptz not null default now(),
  unassigned_at timestamptz,
  is_active boolean not null default true
);
create unique index if not exists idx_rta_one_active_per_pair
  on public.route_template_assignments (template_id, driver_id) where is_active;
create index if not exists idx_rta_driver_active
  on public.route_template_assignments (driver_id, is_active);
create index if not exists idx_rta_template_active
  on public.route_template_assignments (template_id, is_active);

alter table public.route_template_assignments enable row level security;

-- RLS: drivers see their own assignments; admins see everything
create policy rta_select_own on public.route_template_assignments
  for select to authenticated
  using (
    driver_id = auth.uid()
    or public.is_current_user_admin()
  );
create policy rta_admin_write on public.route_template_assignments
  for all to authenticated
  using (public.is_current_user_admin())
  with check (public.is_current_user_admin());

-- 5.3) Live GPS pings for ETA + admin truck tracking
create table if not exists public.truck_pings (
  id uuid default gen_random_uuid() primary key,
  route_id uuid not null references public.routes(id) on delete cascade,
  truck_id uuid not null references public.trucks(id) on delete cascade,
  driver_id uuid references auth.users(id) on delete set null,
  lat double precision not null,
  lng double precision not null,
  speed_kmh numeric(5,2),
  heading numeric(5,2),
  recorded_at timestamptz not null default now()
);
create index if not exists idx_truck_pings_route_time
  on public.truck_pings (route_id, recorded_at desc);

alter table public.truck_pings enable row level security;

create policy truck_pings_insert_self on public.truck_pings
  for insert to authenticated
  with check (driver_id = auth.uid());
create policy truck_pings_select_admin on public.truck_pings
  for select to authenticated
  using (
    driver_id = auth.uid()
    or public.is_current_user_admin()
  );

-- 5.4) Retention: nightly cleanup of pings older than 7 days
create or replace function public.cleanup_truck_pings()
returns void
language sql
security definer
set search_path = public
as $$
  delete from public.truck_pings
  where recorded_at < now() - interval '7 days';
$$;

-- (Schedule via pg_cron in a separate migration if available, otherwise a daily cleanup
-- can run from a Vercel cron job hitting an /api/admin/cleanup-pings endpoint.)

-- 5.5) Reports: ensure 'missed_pickup' is a valid type
-- (Depends on existing schema. If reports.type uses an enum or check constraint,
-- add 'missed_pickup' if not present. No-op if already valid.)
```

## 6. API surface

All endpoints under `src/app/api/`. Authorization via existing `isRouteOpsAuthorized` (admin endpoints) or Supabase JWT (driver endpoints).

| Endpoint | Method | Auth | Purpose |
|----------|--------|------|---------|
| `/routes/templates/[id]/assignments` | `GET` | Admin | List drivers assigned to template (active only) |
| `/routes/templates/[id]/assignments` | `POST` | Admin | Body `{driverId}`. Creates new assignment row. Idempotent (ignore if already active). |
| `/routes/templates/[id]/assignments/[assignmentId]` | `DELETE` | Admin | Sets `is_active=false`, `unassigned_at=now()`. |
| `/routes/templates/[id]/start` | `POST` | Driver (must own active assignment) | Body `{force?: boolean}`. Returns `{gate, routeId, stops, polyline, steps, message}`. Materializes today's run via existing `getORSRoadGeometry` (idempotent) + extracts ORS step instructions via new `getORSStepInstructions` helper + creates per-day `route_assignments` row. If `gate ∈ {early, late}` and `!force`, returns `412 Precondition Failed` with the gate value; client retries with `force=true` after user confirms. |
| `/routes/[id]/directions` | `GET` | Driver (must own route assignment) | Returns `{steps: Array<{instruction, distance_m, duration_s, lat, lng, type}>, polyline}`. Lightweight refresh endpoint if mobile loses the steps cache. |
| `/routes/[id]/telemetry` | `POST` | Driver (must own route assignment) | Body `{lat, lng, speed_kmh?, heading?}`. Inserts ping + broadcasts on Supabase Realtime channel `route:<id>:telemetry`. |
| `/routes/[id]/end` | `POST` | Driver (must own route assignment) | Marks all `pending` `route_progress` rows → `missed`. Inserts `reports` (one per missed stop, type=`missed_pickup`, priority=`high`, lat/lng from stop). Sets `routes.status` → `completed` if all stops succeeded, else `completed_with_issues`. |
| `/routes/[id]/report` | `GET` | Admin | Returns `{route, driver, truck, stops[], progress[], assignments[], pings[]}` for the review modal. |

### Gate decision logic (server-side, in `start` endpoint)

```ts
function computeGate(template: { recurrence_day: string; start_hour: number; end_hour: number }, now: Date): "on_time" | "early" | "late" {
  const dayMap = { sunday: 0, monday: 1, tuesday: 2, wednesday: 3, thursday: 4, friday: 5, saturday: 6 };
  const scheduledDay = dayMap[template.recurrence_day];
  const today = now.getDay();
  const hour = now.getHours();

  if (today < scheduledDay) return "early";
  if (today > scheduledDay) return "late";
  // today === scheduledDay
  if (hour < template.start_hour) return "early";
  if (hour >= template.end_hour) return "late";
  return "on_time";
}
```

## 7. Frontend changes — web admin

### 7.1 Route Planner form (`dashboard-shell.tsx`)
Add two number inputs after the recurrence-day selector: **Start hour (0–23)** and **End hour (1–24)**, defaults 6 and 12. Form submit body includes `startHour`, `endHour`. Existing `/api/routes/templates` POST handler extended to accept these.

### 7.2 Driver Assignment panel (`dashboard-shell.tsx`)
Rewires from per-day route assignment to per-template assignment.
- Replace "Select route" dropdown with "Select weekly route" populated from `routeTemplates`.
- Replace "Select driver" + "Assign Manual / Auto" with multi-select driver picker + "Assign" button → `POST /assignments`.
- Add list of current active assignments per template with un-assign (×) button → `DELETE /assignments/[assignmentId]`.
- Help text: *"Assigned drivers see this weekly route in their app. Multiple drivers can share one route."*

### 7.3 Today's Routes row → Review modal
- Make each row in "Today's Routes" panel clickable (cursor-pointer + hover state).
- On click, fetch `/api/routes/[id]/report` → open `<RouteReportModal>`.
- `<RouteReportModal>` (new file `src/components/dashboard/route-report-modal.tsx`):
  - Reuses `<DangerConfirmModal>`'s portal + dimming + sticky-footer layout.
  - **Header:** route name, date, driver display name (masked email), truck code.
  - **Summary stats row:** `X completed / Y missed / Z total`, distance km, duration min, started/ended timestamps.
  - **Stop list:** ordered table (#, Label, Status pill, Time confirmed, Lat/Lng).
  - **Breadcrumb playback:** small Leaflet map showing polyline + scrubber bar over `truck_pings` recorded between start and end. Drag scrubber → marker moves to that ping's location.
  - **Missed pickups callout:** if any, link with count and "View in Waste Report Feed" anchor.
  - **Close** button.

### 7.4 Live truck markers + ETA on main map
- Subscribe to `route:<routeId>:telemetry` Supabase Realtime channels for every in-progress route on dashboard mount.
- Render pulsing blue dot with heading arrow at the latest ping per route.
- Compute ETA client-side: `remainingStops × 8 min` (server-side ETA can be added later; this matches the simple version's quality without the live-GPS-distance calc).
- ETA pill near the truck dot: `ETA 14 min`.
- Update map legend with "Live truck" entry.

## 8. Frontend changes — mobile (Flutter)

**Stack: existing `flutter_map` (no SDK swap, no card required) + ORS step instructions in a custom HUD.**

### 8.1 New deps in `client_app/pubspec.yaml`

```yaml
dependencies:
  flutter_map: ^7.0.2          # already present
  latlong2: ^0.9.1             # already present
  geolocator: ^11.1.0          # likely already present
  connectivity_plus: ^6.0.5    # NEW — buffered telemetry on reconnect
```

No tokens, no native build changes, no Mapbox.

### 8.2 New helper — `client_app/lib/services/api_client.dart` (extend)
Add methods:
- `getMyAssignedTemplates()` — Supabase query joining `route_template_assignments` and `route_templates`.
- `startTemplate(templateId, {bool force = false})` — POST `/api/routes/templates/[id]/start`.
- `getRouteDirections(routeId)` — GET `/api/routes/[id]/directions`. Returns `{steps, polyline}`.
- `postTelemetry(routeId, {lat, lng, speedKmh, heading})` — POST `/api/routes/[id]/telemetry`.
- `endRoute(routeId)` — POST `/api/routes/[id]/end`.

### 8.3 Screens

#### `assigned_templates_screen.dart` (new — replaces today's first-load behavior in `driver_shell.dart`)
- Loads `route_template_assignments where driver_id = me, is_active=true` joined with `route_templates`.
- Renders a list. Each row:
  - Template name
  - Recurrence day + time window: "Thu 06:00–12:00"
  - Status badge from local clock vs. template:
    - On-time (today is recurrence_day, hour ∈ [start, end)) — green chip
    - Early (today before recurrence_day, OR same day before start_hour) — amber chip
    - Late (today after recurrence_day, OR same day at/after end_hour) — red chip
  - Tap → `template_preview_screen`.

#### `template_preview_screen.dart` (new)
- `flutter_map` with stops as numbered `Marker`s + polyline preview overlay.
- Bottom sheet shows stop list (#, Label).
- "Start Route" button (full-width, bottom) → calls `apiClient.startTemplate(templateId, force: false)`.
  - 200 with `gate=on_time` → push `navigation_screen`.
  - 412 with `gate=early` → show `AlertDialog`: *"You are starting your route early. Proceed to Start Route?"* On confirm, re-call with `force=true`.
  - 412 with `gate=late` → show `AlertDialog`: *"You're late on starting your route. Proceed to Start Route?"* On confirm, re-call with `force=true`.

#### `navigation_screen.dart` (new)
- `flutter_map` covers full screen with:
  - Polyline overlay (route geometry from ORS)
  - Stop markers (numbered, colored by status: pending=blue, confirmed=green, missed=red)
  - Driver location marker (animated dot, rotated by `heading`)
  - Camera auto-follow with `MapController.move` on each GPS update
- **Top HUD card** — large, glanceable while driving:
  - Big arrow icon for next maneuver type (turn-left, turn-right, continue, arrive, depart) — uses Lucide-style SVG, sized 48px.
  - **Primary line**: `In 200 m, turn left onto Aramis Street` (current step instruction, distance auto-updating from Haversine of current GPS to step waypoint).
  - **Secondary line**: next stop label + total ETA (`Stop 2 of 4 • ETA 18 min`).
- **Bottom HUD bar**:
  - "Confirm pickup" button — enabled when within 50m of current stop. Calls existing `/api/routes/[id]/progress`.
  - "End Route" button (red, secondary) — confirm dialog → `POST /api/routes/[id]/end` → toast → `Navigator.popUntil(assigned_templates_screen)`.
- **Step advance logic**:
  - On each GPS tick, compute Haversine distance from current position to the next step waypoint.
  - When distance < 25m, advance to step `i+1`.
  - Recompute ETA: `sum of remaining step durations × (1 + 0.1 if traffic-degraded)`.
- **Off-route detection**:
  - If driver deviates >75m from polyline for >15s, call `getRouteDirections(routeId)` to refresh steps from current GPS, OR show "Off-route" banner without auto-recalc (simpler v1).
  - **v1 decision: show banner only**, no auto-recalc. Recalc is a follow-up.

#### GPS telemetry service (new — `client_app/lib/services/telemetry_service.dart`)
- `Geolocator.getPositionStream(LocationSettings(accuracy: high, distanceFilter: 15))`.
- Throttles to 1 ping per 20 seconds (regardless of `distanceFilter` events).
- Each position → POST `/api/routes/[id]/telemetry` with `{lat, lng, speed_kmh: position.speed * 3.6, heading: position.heading}`.
- On HTTP error or offline: enqueue in-memory (cap 500 entries), retry on reconnect via `connectivity_plus` listener.
- Lifecycle: started by `navigation_screen.initState`, stopped on `dispose`.
- Also publishes a `ValueNotifier<Position>` for the navigation screen to subscribe to (avoids duplicate `getPositionStream` listeners).

### 8.4 Driver auth gate
Existing `auth_gate.dart` continues to gate access; after login, if user role is `driver`, open `assigned_templates_screen` instead of the current `home_shell`.

## 9. Data flow

### 9.1 Driver starts a Thursday route on a Tuesday
1. Driver opens app, taps Thursday template.
2. `template_preview_screen` shows map + Start.
3. Driver taps Start.
4. App POSTs `/start` with no `force` flag.
5. Server computes gate: today=Tue, scheduled=Thu → returns `412 {gate: 'early'}`.
6. App shows confirm dialog: "You are starting your route early. Proceed?"
7. On confirm, app POSTs `/start` with `force=true`.
8. Server materializes today's `routes` row (idempotent on `template_id, route_date`), creates `route_assignment` linking driver, calls ORS `/v2/directions/driving-car/json` for step instructions, returns `{routeId, stops, polyline, steps}`.
9. App pushes `navigation_screen`, renders polyline + first step in HUD card, starts auto-follow camera.
10. Telemetry service starts. Pings POST every 20s.
11. Admin dashboard's Realtime subscription picks up pings → live truck dot moves.

### 9.2 Driver ends route with 1 missed pickup
1. Driver finished 3 of 4 stops, taps End Route.
2. Confirm dialog: "End route now? Unconfirmed pickups will be marked missed."
3. App POSTs `/end`.
4. Server scans `route_progress` for that route, finds 1 row with status=`pending`.
5. Server updates that row to `missed`, inserts `reports` row (type=`missed_pickup`, priority=`high`, lat/lng from stop, title="Missed pickup: <stop label>").
6. Server sets `routes.status` = `completed_with_issues`.
7. App receives 200, pops to assigned templates list.
8. Admin's Today's Routes row updates via existing realtime; orange dot appears in Waste Report Feed.

### 9.3 Admin reviews completed route
1. Admin clicks the row in Today's Routes.
2. Fetch `/api/routes/[id]/report` → returns full bundle.
3. `<RouteReportModal>` opens, shows summary + 4 stops (3 ✓, 1 ✗ Missed) + breadcrumb scrubber over the GPS pings.
4. Admin scrubs to 09:42 — sees the truck was on Aramis Street at that moment.

## 10. Error handling

| Scenario | Behavior |
|----------|----------|
| ORS step instructions empty / API fails | Server falls back to OSRM. If OSRM also fails, returns straight-line polyline + a single synthetic step `"Drive to stop X"`. App shows banner "Turn-by-turn unavailable; navigate by map." |
| `/start` template-deleted-mid-flight | Server returns 404; app toasts + pops to assigned templates list (which auto-refreshes). |
| Network drop during navigation | `flutter_map` uses in-memory tile cache (already-loaded tiles render); polyline + steps are already in app memory. Telemetry buffers up to 500 pings; flushes on `connectivity_plus` reconnect. New tiles outside cache will appear blank until reconnect — driver still sees route geometry. |
| Driver goes off-route | "Off-route" banner shown when GPS deviates >75m from polyline for >15s. v1 shows banner only; manual recalc by re-fetching `/directions`. |
| `/end` with zero confirmed stops | Server still marks all missed and creates reports. Driver app shows pre-end warning: *"No pickups confirmed. End route anyway? All will be marked missed."* |
| Telemetry POST 5xx | Silent retry with exponential backoff (1s, 2s, 4s, 8s, 16s), max 5 attempts; then drop ping silently. |
| Realtime channel disconnect on admin | Reconnect logic + "Live tracking paused" indicator on the truck dot. Auto-resumes when channel reconnects. |
| Admin re-assigns same driver to same template | `idx_rta_one_active_per_pair` makes second insert a 23505 unique violation; API catches and returns 200 with `alreadyActive: true`. |
| Driver tries to start a template they aren't assigned to | Server returns 403; app shows "You aren't assigned to this route." |

## 11. Testing strategy

### Unit (Vitest, server-side)
- `computeGate` function: 9 cases covering on/early/late with day and hour combinations.
- `materializeTodayRoute` idempotency: calling twice on the same template+date returns same `routeId`.
- `endRoute` missed-detection: route with 4 stops, 2 confirmed → 2 reports inserted, status=`completed_with_issues`.

### Integration (Vitest + supabase-js test client)
- Full `/start` flow with force=false then force=true.
- Telemetry insert + Realtime broadcast roundtrip.
- Report endpoint payload shape matches `<RouteReportModal>` props.

### Manual (real device)
- Android device: open app → tap template → Start → polyline appears + first HUD step shown → walk around → confirm stops → End → check admin dashboard for missed reports.
- Off-route test: walk perpendicular to polyline >75m → "Off-route" banner appears within 15s.
- Step advance test: walk past a turn waypoint → HUD updates to next instruction within 1 GPS tick.
- Offline test: enable airplane mode mid-route → polyline + HUD steps continue (already in memory); pings buffer; disable airplane mode → pings flush.
- Admin breadcrumb playback works on a real route from real GPS data.

### Performance budget
- Mobile cold start to assigned templates list: <2s on Android low-end (Snapdragon 4xx class).
- Telemetry POST latency: <500ms p95.
- Admin dashboard with 5 in-progress routes simultaneously: <50ms frame budget for ping marker updates (use `requestAnimationFrame` debounce).
- HUD step recompute (Haversine + step advance check) on each GPS tick: <2ms per tick.

## 12. Rollout

1. **Migration:** apply schema delta in Supabase SQL editor (idempotent, safe).
2. **Backend deploy:** Next.js with new endpoints. Existing dashboard keeps working with old assignments until UI refresh.
3. **Web UI deploy:** new Driver Assignment panel + Review modal. Admins can start using template-level assignments immediately.
4. **Mobile beta build:** distributed to 1–2 LGU pilot drivers via APK / TestFlight.
5. **Production mobile build:** after 1 week of pilot feedback.

## 13. Open risks

- ORS free tier: 2,000 requests/day. With ~50 routes/day per LGU + occasional `/directions` recalc, well under limit. If ORS hits 429, OSRM public server is the fallback (rate-limited but unbounded). Beyond pilot scale, self-host OSRM.
- OSM raster tiles via `flutter_map` rely on tile.openstreetmap.org. Their usage policy requires an identifying User-Agent header. Mitigation: set `userAgentPackageName: 'ph.trashmap.driver'` in `TileLayer`. For higher volume, switch to a CDN like CartoCDN or self-hosted tile server.
- Telemetry write volume: 1 driver × 20s pings × 8h shift = ~1,440 rows/day. 100 drivers × 30 days = 4.3M rows/month. Retention policy (7 days) keeps active table under ~1M rows. Index on `(route_id, recorded_at desc)` keeps queries fast.
- Day-of-week comparison uses server time. Drivers in same TZ as server (Asia/Manila): no problem. If LGU adopts in another TZ later, add `route_templates.timezone` column.
- Custom turn-by-turn HUD vs. Mapbox-quality nav: less polished (no native road-shield rendering, no smooth tilted 3D camera). Acceptable for 1-LGU pilot; revisit if drivers complain. Upgrade path: swap `flutter_map` for `maplibre_gl` (still card-free) without changing the HUD logic.

## 14. Out-of-band dependencies

- **Supabase Realtime** — already enabled; reused for telemetry channel.
- **ORS API key** — already configured (`ORS_API_KEY` in `.env.local`); used for both road geometry and step instructions.
- **OSM tile server** — public `tile.openstreetmap.org`; no key required; respect their usage policy with `userAgentPackageName`.
