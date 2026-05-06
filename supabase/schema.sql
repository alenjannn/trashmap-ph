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
  name text not null,
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

-- App-wide LGU toggles and thresholds
create table if not exists app_config (
  key text primary key,
  value_json jsonb not null,
  updated_at timestamptz not null default now()
);

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
begin
  insert into public.app_user_profiles (user_id, role, is_authority_confirmed)
  values (new.id, 'citizen', false)
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