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

do $$
begin
  alter publication supabase_realtime add table routes;
exception when duplicate_object then
  null;
end $$;