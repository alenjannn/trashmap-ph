-- Waste reports submitted by citizens
create table reports (
  id uuid default gen_random_uuid() primary key,
  created_at timestamptz default now(),
  lat double precision not null,
  lng double precision not null,
  photo_url text,
  description text,
  waste_type text,
  status text default 'pending' check (status in ('pending', 'dispatched', 'resolved')),
  updated_at timestamptz default now(),
  updated_by uuid references auth.users(id)
);

-- Collection zones for route optimization
create table zones (
  id uuid default gen_random_uuid() primary key,
  name text not null,
  lat double precision not null,
  lng double precision not null
);

-- Published collection schedules visible to residents
create table schedules (
  id uuid default gen_random_uuid() primary key,
  zone_id uuid references zones(id),
  collection_day text,
  time_window_start text,
  time_window_end text,
  published_at timestamptz default now()
);

-- Enable realtime on the reports table
alter publication supabase_realtime add table reports;