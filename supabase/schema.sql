-- Day 1 foundation schema for TrashMap PH
-- Safe for repeated execution during local setup.

create extension if not exists pgcrypto;
create extension if not exists postgis;

-- Collection zones for route optimization and schedule publishing
create table if not exists zones (
  id uuid default gen_random_uuid() primary key,
  name text not null unique,
  lat double precision not null,
  lng double precision not null,
  created_at timestamptz not null default now()
);

-- Citizen reports (dumpsite + missed pickup)
create table if not exists reports (
  id uuid default gen_random_uuid() primary key,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  reporter_id uuid references auth.users(id),
  lat double precision not null,
  lng double precision not null,
  location geography(point, 4326) generated always as (
    st_setsrid(st_makepoint(lng, lat), 4326)::geography
  ) stored,
  report_type text not null default 'dumpsite'
    check (report_type in ('dumpsite', 'missed_pickup')),
  waste_type text not null default 'unknown'
    check (waste_type in ('biodegradable', 'recyclable', 'special_hazardous', 'mixed', 'unknown')),
  photo_url text,
  description text,
  status text not null default 'pending'
    check (status in ('pending', 'acknowledged', 'dispatched', 'resolved', 'rejected')),
  zone_id uuid references zones(id),
  updated_by uuid references auth.users(id)
);

create index if not exists idx_reports_location on reports using gist (location);
create index if not exists idx_reports_status_created_at on reports (status, created_at desc);

-- Clustered, high-priority waste concentration areas
create table if not exists hotspots (
  id uuid default gen_random_uuid() primary key,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  zone_id uuid references zones(id),
  center_lat double precision not null,
  center_lng double precision not null,
  center_location geography(point, 4326) generated always as (
    st_setsrid(st_makepoint(center_lng, center_lat), 4326)::geography
  ) stored,
  radius_meters integer not null default 50 check (radius_meters > 0),
  unique_reporters_count integer not null default 0 check (unique_reporters_count >= 0),
  status text not null default 'active' check (status in ('active', 'cleared')),
  severity text not null default 'medium' check (severity in ('low', 'medium', 'high', 'critical'))
);

create index if not exists idx_hotspots_center_location on hotspots using gist (center_location);

create or replace function public.refresh_hotspots_from_reports()
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  -- Rebuild active hotspots from recent unresolved reports using tight 1-10m pin neighborhoods.
  -- Radius auto-scales by cluster spread, clamped to 10m..200m.
  delete from public.hotspots where status = 'active';

  insert into public.hotspots (
    center_lat,
    center_lng,
    radius_meters,
    unique_reporters_count,
    status,
    severity,
    created_at,
    updated_at
  )
  with clustered as (
    select
      r.id,
      r.lat,
      r.lng,
      r.reporter_id,
      st_transform(r.location::geometry, 3857) as location_m,
      st_clusterdbscan(
        st_transform(r.location::geometry, 3857),
        eps := 25,
        minpoints := 10
      ) over () as cluster_id
    from public.reports r
    where r.created_at >= now() - interval '7 days'
      and r.status in ('pending', 'acknowledged', 'dispatched')
  ),
  grouped as (
    select
      cluster_id,
      st_centroid(st_collect(location_m)) as centroid_m,
      avg(lat) as center_lat,
      avg(lng) as center_lng,
      count(*) as report_count,
      count(distinct reporter_id) as unique_reporters_count
    from clustered
    where cluster_id is not null
    group by cluster_id
    having count(*) >= 10
  ),
  spread as (
    select
      g.cluster_id,
      g.center_lat,
      g.center_lng,
      g.report_count,
      g.unique_reporters_count,
      max(st_distance(c.location_m, g.centroid_m)) as max_pin_distance_m
    from grouped g
    join clustered c on c.cluster_id = g.cluster_id
    group by
      g.cluster_id,
      g.center_lat,
      g.center_lng,
      g.report_count,
      g.unique_reporters_count
  )
  select
    s.center_lat,
    s.center_lng,
    least(200, greatest(10, ceil(s.max_pin_distance_m + 10)))::integer as radius_meters,
    s.unique_reporters_count,
    'active' as status,
    case
      when s.report_count >= 20 then 'critical'
      when s.report_count >= 14 then 'high'
      when s.report_count >= 10 then 'medium'
      else 'low'
    end as severity,
    now() as created_at,
    now() as updated_at
  from spread s;
end;
$$;

drop trigger if exists trg_refresh_hotspots_on_reports on public.reports;
create or replace function public.refresh_hotspots_on_reports_trigger()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  perform public.refresh_hotspots_from_reports();
  return null;
end;
$$;

create trigger trg_refresh_hotspots_on_reports
  after insert or update or delete on public.reports
  for each statement
  execute procedure public.refresh_hotspots_on_reports_trigger();

-- Initial build for existing reports.
select public.refresh_hotspots_from_reports();

-- Collection fleet registry
create table if not exists trucks (
  id uuid default gen_random_uuid() primary key,
  created_at timestamptz not null default now(),
  truck_code text not null unique,
  plate_number text unique,
  driver_name text,
  capacity_kg numeric(10, 2) check (capacity_kg >= 0),
  status text not null default 'idle'
    check (status in ('idle', 'en_route', 'collecting', 'maintenance', 'offline'))
);

-- Daily generated or manually adjusted truck routes
create table if not exists routes (
  id uuid default gen_random_uuid() primary key,
  created_at timestamptz not null default now(),
  route_date date not null,
  truck_id uuid not null references trucks(id) on delete cascade,
  zone_id uuid references zones(id),
  status text not null default 'draft'
    check (status in ('draft', 'published', 'in_progress', 'completed', 'cancelled')),
  source text not null default 'manual'
    check (source in ('manual', 'ai_optimized')),
  estimated_distance_km numeric(10, 2) check (estimated_distance_km >= 0),
  estimated_duration_minutes integer check (estimated_duration_minutes >= 0),
  estimated_fuel_liters numeric(10, 2) check (estimated_fuel_liters >= 0),
  polyline text
);

create index if not exists idx_routes_date_status on routes (route_date, status);

-- Ordered route stops for each generated route
create table if not exists route_stops (
  id uuid default gen_random_uuid() primary key,
  created_at timestamptz not null default now(),
  route_id uuid not null references routes(id) on delete cascade,
  stop_order integer not null check (stop_order > 0),
  label text not null,
  lat double precision not null,
  lng double precision not null,
  location geography(point, 4326) generated always as (
    st_setsrid(st_makepoint(lng, lat), 4326)::geography
  ) stored,
  stop_type text not null default 'pickup'
    check (stop_type in ('pickup', 'transfer', 'disposal', 'other')),
  eta timestamptz,
  status text not null default 'pending'
    check (status in ('pending', 'arrived', 'completed', 'skipped'))
);

create unique index if not exists idx_route_stops_unique_order on route_stops (route_id, stop_order);
create index if not exists idx_route_stops_route on route_stops (route_id);
create index if not exists idx_route_stops_location on route_stops using gist (location);

-- Driver and fleet progress events per stop
create table if not exists route_progress (
  id uuid default gen_random_uuid() primary key,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  route_id uuid not null references routes(id) on delete cascade,
  stop_id uuid references route_stops(id) on delete set null,
  truck_id uuid not null references trucks(id) on delete cascade,
  driver_id uuid references auth.users(id),
  status text not null default 'pending'
    check (status in ('pending', 'arrived', 'completed', 'skipped')),
  confirmed_at timestamptz,
  notes text
);

create index if not exists idx_route_progress_route on route_progress (route_id, created_at desc);
create index if not exists idx_route_progress_truck on route_progress (truck_id, created_at desc);
create index if not exists idx_route_progress_driver on route_progress (driver_id, created_at desc);

-- Extend route lifecycle for "ended with unresolved stops" flow.
alter table public.routes drop constraint if exists routes_status_check;
alter table public.routes
  add constraint routes_status_check
  check (status in ('draft', 'published', 'scheduled', 'in_progress', 'completed', 'completed_with_issues', 'cancelled'));

-- Weekly recurring admin route template (hybrid picked/reordered stops).
create table if not exists route_templates (
  id uuid default gen_random_uuid() primary key,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  name text not null,
  zone_id uuid not null references zones(id) on delete cascade,
  recurrence_day text not null
    check (recurrence_day in ('monday', 'tuesday', 'wednesday', 'thursday', 'friday', 'saturday', 'sunday')),
  is_active boolean not null default true,
  created_by uuid references auth.users(id) on delete set null
);

create unique index if not exists idx_route_templates_name_zone_unique
  on route_templates (zone_id, name);
create index if not exists idx_route_templates_zone_day_active
  on route_templates (zone_id, recurrence_day, is_active);

-- Ordered stop list under route template.
create table if not exists route_template_stops (
  id uuid default gen_random_uuid() primary key,
  created_at timestamptz not null default now(),
  template_id uuid not null references route_templates(id) on delete cascade,
  collection_point_id uuid not null references collection_points(id) on delete cascade,
  stop_order integer not null check (stop_order > 0),
  unique (template_id, stop_order),
  unique (template_id, collection_point_id)
);

create index if not exists idx_route_template_stops_template
  on route_template_stops (template_id, stop_order);

-- Driver assignment history and assignment mode trace.
create table if not exists route_assignments (
  id uuid default gen_random_uuid() primary key,
  created_at timestamptz not null default now(),
  route_id uuid not null references routes(id) on delete cascade,
  driver_id uuid not null references auth.users(id) on delete cascade,
  assigned_by uuid references auth.users(id) on delete set null,
  assigned_at timestamptz not null default now(),
  mode text not null default 'manual' check (mode in ('manual', 'auto')),
  is_active boolean not null default true
);

create index if not exists idx_route_assignments_route_active
  on route_assignments (route_id, is_active, assigned_at desc);
create index if not exists idx_route_assignments_driver_assigned_at
  on route_assignments (driver_id, assigned_at desc);
create unique index if not exists idx_route_assignments_one_active_per_route
  on route_assignments (route_id)
  where is_active = true;
create unique index if not exists idx_route_assignments_one_active_per_driver
  on route_assignments (driver_id)
  where is_active = true;

-- Immutable timeline for route lifecycle/audit.
create table if not exists route_audit_logs (
  id uuid default gen_random_uuid() primary key,
  created_at timestamptz not null default now(),
  route_id uuid not null references routes(id) on delete cascade,
  stop_id uuid references route_stops(id) on delete set null,
  event_type text not null check (event_type in ('route_started', 'truck_arriving', 'stop_completed', 'route_completed', 'exception')),
  actor_user_id uuid references auth.users(id) on delete set null,
  actor_role text not null check (actor_role in ('admin', 'driver', 'system')),
  zone_id uuid references zones(id) on delete set null,
  area_label text,
  event_time timestamptz not null default now(),
  metadata_json jsonb not null default '{}'::jsonb
);

create index if not exists idx_route_audit_logs_route_time
  on route_audit_logs (route_id, event_time desc);
create index if not exists idx_route_audit_logs_zone_time
  on route_audit_logs (zone_id, event_time desc);

-- Citizen zone subscriptions for route-targeted notifications.
create table if not exists citizen_zone_subscriptions (
  id uuid default gen_random_uuid() primary key,
  created_at timestamptz not null default now(),
  user_id uuid not null references auth.users(id) on delete cascade,
  zone_id uuid not null references zones(id) on delete cascade,
  is_active boolean not null default true,
  unique (user_id, zone_id)
);

create index if not exists idx_citizen_zone_subscriptions_zone_active
  on citizen_zone_subscriptions (zone_id, is_active);
create index if not exists idx_citizen_zone_subscriptions_user_active
  on citizen_zone_subscriptions (user_id, is_active);

-- Notification delivery trace for admin/citizen alerts.
create table if not exists route_notifications_log (
  id uuid default gen_random_uuid() primary key,
  created_at timestamptz not null default now(),
  route_id uuid not null references routes(id) on delete cascade,
  zone_id uuid references zones(id) on delete set null,
  event_type text not null check (event_type in ('route_started', 'truck_arriving', 'route_completed', 'exception')),
  target_scope text not null check (target_scope in ('admin', 'citizen_zone', 'both')),
  title text not null,
  body text not null,
  metadata_json jsonb not null default '{}'::jsonb
);

create index if not exists idx_route_notifications_log_route_time
  on route_notifications_log (route_id, created_at desc);
create index if not exists idx_route_notifications_log_zone_time
  on route_notifications_log (zone_id, created_at desc);
create unique index if not exists idx_route_notifications_unique_core_events
  on route_notifications_log (route_id, event_type, target_scope)
  where event_type in ('route_started', 'truck_arriving', 'route_completed') and target_scope = 'both';

-- Convenience view for today's assigned route with ordered stops and latest progress.
create or replace view public.v_driver_route_stops_today as
select
  r.id as route_id,
  r.route_date,
  r.truck_id,
  t.truck_code,
  r.status as route_status,
  r.polyline,
  rs.id as stop_id,
  rs.stop_order,
  rs.label as stop_label,
  rs.lat,
  rs.lng,
  rs.stop_type,
  rs.eta,
  coalesce(rp_latest.status, rs.status) as stop_status,
  rp_latest.confirmed_at
from routes r
join trucks t on t.id = r.truck_id
join route_stops rs on rs.route_id = r.id
left join lateral (
  select rp.status, rp.confirmed_at
  from route_progress rp
  where rp.route_id = r.id
    and (rp.stop_id = rs.id or rp.stop_id is null)
  order by rp.created_at desc
  limit 1
) rp_latest on true
where r.route_date = current_date;

-- Published collection schedules visible to residents
create table if not exists schedules (
  id uuid default gen_random_uuid() primary key,
  created_at timestamptz not null default now(),
  published_at timestamptz default now(),
  zone_id uuid not null references zones(id) on delete cascade,
  collection_day text not null
    check (collection_day in ('monday', 'tuesday', 'wednesday', 'thursday', 'friday', 'saturday', 'sunday')),
  time_window_start time not null,
  time_window_end time not null,
  is_active boolean not null default true,
  check (time_window_end > time_window_start)
);

-- Local recycler and junk shop directory
create table if not exists recyclers (
  id uuid default gen_random_uuid() primary key,
  created_at timestamptz not null default now(),
  name text not null unique,
  lat double precision not null,
  lng double precision not null,
  location geography(point, 4326) generated always as (
    st_setsrid(st_makepoint(lng, lat), 4326)::geography
  ) stored,
  address text,
  contact_number text,
  accepted_materials text[] not null default '{}',
  operating_hours text,
  approval_status text not null default 'approved'
    check (approval_status in ('pending', 'approved', 'rejected'))
);

create index if not exists idx_recyclers_location on recyclers using gist (location);

-- Admin-defined permanent garbage collection points used by route optimizer.
create table if not exists collection_points (
  id uuid default gen_random_uuid() primary key,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  label text not null,
  lat double precision not null,
  lng double precision not null,
  location geography(point, 4326) generated always as (
    st_setsrid(st_makepoint(lng, lat), 4326)::geography
  ) stored,
  zone_id uuid references zones(id) on delete set null,
  is_active boolean not null default true,
  added_by uuid references auth.users(id) on delete set null
);

create unique index if not exists idx_collection_points_label_unique on collection_points (label);
create index if not exists idx_collection_points_location on collection_points using gist (location);

-- Predicted risk zones for overflow awareness.
create table if not exists risk_zones (
  id uuid default gen_random_uuid() primary key,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  zone_id uuid references zones(id) on delete set null,
  name text not null,
  center_lat double precision not null,
  center_lng double precision not null,
  center_location geography(point, 4326) generated always as (
    st_setsrid(st_makepoint(center_lng, center_lat), 4326)::geography
  ) stored,
  score numeric(4, 3) not null check (score >= 0 and score <= 1),
  level text not null check (level in ('low', 'medium', 'high', 'critical')),
  unique (name)
);

create index if not exists idx_risk_zones_center_location on risk_zones using gist (center_location);
create index if not exists idx_risk_zones_level_score on risk_zones (level, score desc);

-- Citizen/driver points + badges for gamification views.
create table if not exists gamification_points (
  user_id uuid primary key references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  points integer not null default 0 check (points >= 0),
  badges jsonb not null default '[]'::jsonb,
  barangay text default 'Unassigned'
);

create index if not exists idx_gamification_points_points_desc on gamification_points (points desc);

-- Before/after verification uploads for completed cleanups.
create table if not exists report_verifications (
  id uuid default gen_random_uuid() primary key,
  created_at timestamptz not null default now(),
  report_id uuid not null references reports(id) on delete cascade,
  before_photo_url text not null,
  after_photo_url text not null,
  verified_by uuid references auth.users(id) on delete set null,
  verified_at timestamptz not null default now(),
  notes text
);

create index if not exists idx_report_verifications_report on report_verifications (report_id);

-- App-wide LGU toggles and thresholds
create table if not exists app_config (
  key text primary key,
  value_json jsonb not null,
  updated_at timestamptz not null default now()
);

insert into app_config (key, value_json)
values
  ('notification_message', '{"title":"Collection Notice","body":""}'::jsonb)
on conflict (key) do update
set value_json = excluded.value_json,
    updated_at = now();

insert into collection_points (label, lat, lng, is_active)
values
  ('Brentwood Gate North', 14.690320, 121.106230, true),
  ('Brentwood Inner Loop A', 14.689910, 121.106870, true),
  ('Brentwood Inner Loop B', 14.689520, 121.107480, true),
  ('Brentwood East Row', 14.689050, 121.107930, true),
  ('Brentwood Mid Court', 14.688760, 121.107190, true),
  ('Brentwood South Pocket', 14.688340, 121.106820, true),
  ('Brentwood Lower West', 14.688050, 121.106080, true),
  ('Brentwood Exit South', 14.687720, 121.105590, true)
on conflict (label) do update
set lat = excluded.lat,
    lng = excluded.lng,
    is_active = excluded.is_active,
    updated_at = now();

insert into risk_zones (name, center_lat, center_lng, score, level)
values
  ('Brentwood North Cluster', 14.690020, 121.106720, 0.420, 'medium'),
  ('Brentwood East Cluster', 14.689260, 121.107840, 0.610, 'high'),
  ('Brentwood Core Cluster', 14.688860, 121.107180, 0.780, 'high'),
  ('Brentwood South Cluster', 14.688020, 121.105980, 0.330, 'low')
on conflict do nothing;

-- Seed the primary demo zone so schedules seed has a valid zone_id to cross join against.
insert into zones (name, lat, lng)
values ('Brentwood Parkhomes', 14.6891, 121.1068)
on conflict (name) do nothing;

-- Link Brentwood collection points to their zone (idempotent).
update collection_points
set zone_id = (select id from zones where name = 'Brentwood Parkhomes' limit 1)
where label like 'Brentwood%' and zone_id is null;

insert into schedules (zone_id, collection_day, time_window_start, time_window_end, is_active)
select
  z.id,
  d.collection_day,
  d.time_window_start,
  d.time_window_end,
  true
from (
  values
    ('monday', '06:00'::time, '09:00'::time),
    ('tuesday', '06:00'::time, '09:00'::time),
    ('wednesday', '06:00'::time, '09:00'::time),
    ('thursday', '06:00'::time, '09:00'::time),
    ('friday', '06:00'::time, '09:00'::time),
    ('saturday', '07:00'::time, '10:00'::time),
    ('sunday', '07:00'::time, '10:00'::time)
) as d(collection_day, time_window_start, time_window_end)
cross join lateral (
  select id from zones order by created_at asc limit 1
) z
where not exists (
  select 1
  from schedules s
  where s.zone_id = z.id
    and s.collection_day = d.collection_day
);

insert into recyclers (name, lat, lng, address, contact_number, accepted_materials, operating_hours, approval_status)
values
  ('Antipolo Eco Recyclers', 14.587120, 121.176400, 'Sumulong Highway, Antipolo', '0917-100-1001', '{"plastic","paper","metal"}', 'Mon-Sat 8:00-17:00', 'approved'),
  ('Brentwood Materials Hub', 14.688560, 121.105910, 'Brentwood Service Road', '0917-100-1002', '{"plastic","glass","metal"}', 'Mon-Sat 7:30-17:30', 'approved'),
  ('Mambugan Junk Exchange', 14.690840, 121.108440, 'Mambugan Main Road', '0917-100-1003', '{"metal","electronics","cardboard"}', 'Mon-Sun 8:00-18:00', 'approved'),
  ('Upper Antipolo Green Point', 14.691420, 121.104860, 'Near Sumulong Junction', '0917-100-1004', '{"plastic","paper","tetra_pack"}', 'Mon-Fri 9:00-18:00', 'approved'),
  ('Cogeo Reuse Center', 14.687110, 121.108920, 'Cogeo Connector Road', '0917-100-1005', '{"glass","plastic","metal"}', 'Mon-Sat 8:00-17:00', 'approved'),
  ('Ynares Recycle Dropoff', 14.686720, 121.106200, 'Ynares Avenue', '0917-100-1006', '{"paper","plastic","metal","textiles"}', 'Mon-Sat 8:00-16:30', 'approved'),
  ('Masinag Circular Economy Hub', 14.688980, 121.104740, 'Masinag Service Area', '0917-100-1007', '{"metal","electronics","appliances"}', 'Tue-Sun 9:00-18:00', 'approved'),
  ('Valley Recyclables Depot', 14.689700, 121.107660, 'Valley Street Extension', '0917-100-1008', '{"paper","plastic","glass"}', 'Mon-Sat 8:00-17:00', 'approved')
on conflict do nothing;

-- Auth foundation for Day 2 role-gated access
create table if not exists app_user_profiles (
  user_id uuid primary key references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  display_name text,
  role text not null default 'citizen' check (role in ('admin', 'citizen', 'driver')),
  is_authority_confirmed boolean not null default false,
  driver_verification_status text not null default 'not_submitted'
    check (driver_verification_status in ('not_submitted', 'pending', 'approved', 'rejected'))
);

create index if not exists idx_app_user_profiles_role on app_user_profiles (role);

-- RLS: each user can read and update only their own profile row.
alter table public.app_user_profiles enable row level security;

drop policy if exists "profiles_select_own" on public.app_user_profiles;
create policy "profiles_select_own"
  on public.app_user_profiles
  for select
  to authenticated
  using (auth.uid() = user_id);

-- Allow any authenticated user to list driver profiles (for admin assignment dropdown).
drop policy if exists "profiles_select_drivers" on public.app_user_profiles;
create policy "profiles_select_drivers"
  on public.app_user_profiles
  for select
  to authenticated
  using (role = 'driver');

drop policy if exists "profiles_update_own" on public.app_user_profiles;
create policy "profiles_update_own"
  on public.app_user_profiles
  for update
  to authenticated
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

drop policy if exists "profiles_insert_own" on public.app_user_profiles;
create policy "profiles_insert_own"
  on public.app_user_profiles
  for insert
  to authenticated
  with check (auth.uid() = user_id);

-- Demo-only admin credential seed for hackathon local testing
-- Replace/remove before production.
create table if not exists admin_access_secrets (
  id uuid default gen_random_uuid() primary key,
  username text not null unique,
  password_plain text not null,
  is_active boolean not null default true,
  created_at timestamptz not null default now()
);

insert into admin_access_secrets (username, password_plain, is_active)
values ('admin123', 'admin123', true)
on conflict (username) do update
set password_plain = excluded.password_plain,
    is_active = excluded.is_active;

create or replace function public.handle_new_auth_user_profile()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  requested_role text;
begin
  requested_role := lower(coalesce(new.raw_user_meta_data ->> 'requested_role', 'citizen'));
  if requested_role not in ('admin', 'citizen', 'driver') then
    requested_role := 'citizen';
  end if;

  insert into public.app_user_profiles (user_id, role, is_authority_confirmed)
  values (new.id, requested_role, false)
  on conflict (user_id) do nothing;

  return new;
end;
$$;

do $$
begin
  if not exists (
    select 1
    from pg_trigger
    where tgname = 'on_auth_user_created_profile'
  ) then
    create trigger on_auth_user_created_profile
      after insert on auth.users
      for each row execute procedure public.handle_new_auth_user_profile();
  end if;
end $$;

create or replace function public.award_points_on_route_progress_completed()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.status = 'completed'
     and (old.status is distinct from new.status)
     and new.driver_id is not null then
    insert into public.gamification_points (user_id, points, badges)
    values (new.driver_id, 5, '[]'::jsonb)
    on conflict (user_id) do update
    set points = gamification_points.points + 5,
        updated_at = now();
  end if;

  return new;
end;
$$;

drop trigger if exists trg_award_points_on_route_progress_completed on public.route_progress;
create trigger trg_award_points_on_route_progress_completed
  after update on public.route_progress
  for each row
  execute procedure public.award_points_on_route_progress_completed();

create or replace function public.award_points_on_report_verification()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  reporter uuid;
begin
  select reporter_id into reporter
  from public.reports
  where id = new.report_id;

  if reporter is not null then
    insert into public.gamification_points (user_id, points, badges)
    values (reporter, 20, '[]'::jsonb)
    on conflict (user_id) do update
    set points = gamification_points.points + 20,
        updated_at = now();
  end if;

  return new;
end;
$$;

drop trigger if exists trg_award_points_on_report_verification on public.report_verifications;
create trigger trg_award_points_on_report_verification
  after insert on public.report_verifications
  for each row
  execute procedure public.award_points_on_report_verification();

-- Enable Supabase Realtime for tables used by Day 2 live demo flow
do $$
begin
  alter publication supabase_realtime add table reports;
exception when duplicate_object then
  null;
end $$;

do $$
begin
  alter publication supabase_realtime add table hotspots;
exception when duplicate_object then
  null;
end $$;

-- Demo RLS for hotspot visibility in dashboard.
alter table public.hotspots enable row level security;
drop policy if exists "hotspots_select_anon_demo" on public.hotspots;
create policy "hotspots_select_anon_demo"
on public.hotspots
for select
to anon, authenticated
using (true);

alter table public.collection_points enable row level security;
drop policy if exists "collection_points_select_public" on public.collection_points;
create policy "collection_points_select_public"
on public.collection_points
for select
to anon, authenticated
using (is_active = true);

drop policy if exists "collection_points_insert_auth" on public.collection_points;
create policy "collection_points_insert_auth"
on public.collection_points
for insert
to authenticated
with check (true);

drop policy if exists "collection_points_update_auth" on public.collection_points;
create policy "collection_points_update_auth"
on public.collection_points
for update
to authenticated
using (true)
with check (true);

alter table public.risk_zones enable row level security;
drop policy if exists "risk_zones_select_public" on public.risk_zones;
create policy "risk_zones_select_public"
on public.risk_zones
for select
to anon, authenticated
using (true);

alter table public.app_config enable row level security;
drop policy if exists "app_config_select_public" on public.app_config;
create policy "app_config_select_public"
on public.app_config
for select
to anon, authenticated
using (true);

alter table public.gamification_points enable row level security;
-- Allow all authenticated users to read all rows for leaderboard aggregation.
drop policy if exists "gamification_points_select_own" on public.gamification_points;
drop policy if exists "gamification_points_select_auth" on public.gamification_points;
create policy "gamification_points_select_auth"
on public.gamification_points
for select
to authenticated
using (true);

drop policy if exists "gamification_points_insert_own" on public.gamification_points;
create policy "gamification_points_insert_own"
on public.gamification_points
for insert
to authenticated
with check (auth.uid() = user_id);

drop policy if exists "gamification_points_update_own" on public.gamification_points;
create policy "gamification_points_update_own"
on public.gamification_points
for update
to authenticated
using (auth.uid() = user_id)
with check (auth.uid() = user_id);

alter table public.report_verifications enable row level security;
drop policy if exists "report_verifications_select_auth" on public.report_verifications;
create policy "report_verifications_select_auth"
on public.report_verifications
for select
to authenticated
using (true);

drop policy if exists "report_verifications_insert_auth" on public.report_verifications;
create policy "report_verifications_insert_auth"
on public.report_verifications
for insert
to authenticated
with check (true);

alter table public.route_templates enable row level security;
drop policy if exists "route_templates_select_auth" on public.route_templates;
create policy "route_templates_select_auth"
on public.route_templates
for select
to authenticated
using (true);

drop policy if exists "route_templates_write_admin" on public.route_templates;
create policy "route_templates_write_admin"
on public.route_templates
for all
to authenticated
using (
  exists (
    select 1 from public.app_user_profiles p
    where p.user_id = auth.uid() and p.role = 'admin'
  )
)
with check (
  exists (
    select 1 from public.app_user_profiles p
    where p.user_id = auth.uid() and p.role = 'admin'
  )
);

alter table public.route_template_stops enable row level security;
drop policy if exists "route_template_stops_select_auth" on public.route_template_stops;
create policy "route_template_stops_select_auth"
on public.route_template_stops
for select
to authenticated
using (true);

drop policy if exists "route_template_stops_write_admin" on public.route_template_stops;
create policy "route_template_stops_write_admin"
on public.route_template_stops
for all
to authenticated
using (
  exists (
    select 1 from public.app_user_profiles p
    where p.user_id = auth.uid() and p.role = 'admin'
  )
)
with check (
  exists (
    select 1 from public.app_user_profiles p
    where p.user_id = auth.uid() and p.role = 'admin'
  )
);

alter table public.route_assignments enable row level security;
drop policy if exists "route_assignments_select_admin_or_own_driver" on public.route_assignments;
create policy "route_assignments_select_admin_or_own_driver"
on public.route_assignments
for select
to authenticated
using (
  driver_id = auth.uid()
  or exists (
    select 1 from public.app_user_profiles p
    where p.user_id = auth.uid() and p.role = 'admin'
  )
);

drop policy if exists "route_assignments_write_admin" on public.route_assignments;
create policy "route_assignments_write_admin"
on public.route_assignments
for all
to authenticated
using (
  exists (
    select 1 from public.app_user_profiles p
    where p.user_id = auth.uid() and p.role = 'admin'
  )
)
with check (
  exists (
    select 1 from public.app_user_profiles p
    where p.user_id = auth.uid() and p.role = 'admin'
  )
);

alter table public.route_audit_logs enable row level security;
drop policy if exists "route_audit_logs_select_zone_or_admin_or_own_driver" on public.route_audit_logs;
create policy "route_audit_logs_select_zone_or_admin_or_own_driver"
on public.route_audit_logs
for select
to authenticated
using (
  exists (
    select 1 from public.app_user_profiles p
    where p.user_id = auth.uid() and p.role = 'admin'
  )
  or exists (
    select 1
    from public.route_assignments ra
    where ra.route_id = route_audit_logs.route_id
      and ra.driver_id = auth.uid()
      and ra.is_active = true
  )
  or exists (
    select 1
    from public.citizen_zone_subscriptions czs
    where czs.user_id = auth.uid()
      and czs.zone_id = route_audit_logs.zone_id
      and czs.is_active = true
  )
);

drop policy if exists "route_audit_logs_insert_admin_driver" on public.route_audit_logs;
create policy "route_audit_logs_insert_admin_driver"
on public.route_audit_logs
for insert
to authenticated
with check (
  exists (
    select 1 from public.app_user_profiles p
    where p.user_id = auth.uid() and p.role in ('admin', 'driver')
  )
);

alter table public.citizen_zone_subscriptions enable row level security;
drop policy if exists "citizen_zone_subscriptions_select_own_or_admin" on public.citizen_zone_subscriptions;
create policy "citizen_zone_subscriptions_select_own_or_admin"
on public.citizen_zone_subscriptions
for select
to authenticated
using (
  user_id = auth.uid()
  or exists (
    select 1 from public.app_user_profiles p
    where p.user_id = auth.uid() and p.role = 'admin'
  )
);

drop policy if exists "citizen_zone_subscriptions_insert_own_or_admin" on public.citizen_zone_subscriptions;
create policy "citizen_zone_subscriptions_insert_own_or_admin"
on public.citizen_zone_subscriptions
for insert
to authenticated
with check (
  user_id = auth.uid()
  or exists (
    select 1 from public.app_user_profiles p
    where p.user_id = auth.uid() and p.role = 'admin'
  )
);

drop policy if exists "citizen_zone_subscriptions_update_own_or_admin" on public.citizen_zone_subscriptions;
create policy "citizen_zone_subscriptions_update_own_or_admin"
on public.citizen_zone_subscriptions
for update
to authenticated
using (
  user_id = auth.uid()
  or exists (
    select 1 from public.app_user_profiles p
    where p.user_id = auth.uid() and p.role = 'admin'
  )
)
with check (
  user_id = auth.uid()
  or exists (
    select 1 from public.app_user_profiles p
    where p.user_id = auth.uid() and p.role = 'admin'
  )
);

alter table public.route_notifications_log enable row level security;
drop policy if exists "route_notifications_log_select_scope" on public.route_notifications_log;
create policy "route_notifications_log_select_scope"
on public.route_notifications_log
for select
to authenticated
using (
  exists (
    select 1 from public.app_user_profiles p
    where p.user_id = auth.uid() and p.role = 'admin'
  )
  or (
    target_scope in ('citizen_zone', 'both')
    and exists (
      select 1
      from public.citizen_zone_subscriptions czs
      where czs.user_id = auth.uid()
        and czs.zone_id = route_notifications_log.zone_id
        and czs.is_active = true
    )
  )
);

drop policy if exists "route_notifications_log_insert_admin_driver" on public.route_notifications_log;
create policy "route_notifications_log_insert_admin_driver"
on public.route_notifications_log
for insert
to authenticated
with check (
  exists (
    select 1 from public.app_user_profiles p
    where p.user_id = auth.uid() and p.role in ('admin', 'driver')
  )
);

do $$
begin
  alter publication supabase_realtime add table routes;
exception when duplicate_object then
  null;
end $$;

do $$
begin
  alter publication supabase_realtime add table route_stops;
exception when duplicate_object then
  null;
end $$;

do $$
begin
  alter publication supabase_realtime add table route_progress;
exception when duplicate_object then
  null;
end $$;

do $$
begin
  alter publication supabase_realtime add table collection_points;
exception when duplicate_object then
  null;
end $$;

do $$
begin
  alter publication supabase_realtime add table risk_zones;
exception when duplicate_object then
  null;
end $$;

do $$
begin
  alter publication supabase_realtime add table gamification_points;
exception when duplicate_object then
  null;
end $$;

do $$
begin
  alter publication supabase_realtime add table app_config;
exception when duplicate_object then
  null;
end $$;

do $$
begin
  alter publication supabase_realtime add table route_templates;
exception when duplicate_object then
  null;
end $$;

do $$
begin
  alter publication supabase_realtime add table route_template_stops;
exception when duplicate_object then
  null;
end $$;

do $$
begin
  alter publication supabase_realtime add table route_assignments;
exception when duplicate_object then
  null;
end $$;

do $$
begin
  alter publication supabase_realtime add table route_audit_logs;
exception when duplicate_object then
  null;
end $$;

do $$
begin
  alter publication supabase_realtime add table citizen_zone_subscriptions;
exception when duplicate_object then
  null;
end $$;

do $$
begin
  alter publication supabase_realtime add table route_notifications_log;
exception when duplicate_object then
  null;
end $$;