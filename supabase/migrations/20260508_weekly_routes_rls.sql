-- =============================================================================
-- MIGRATION: RLS policies for weekly_routes, weekly_route_assignments,
--            weekly_route_stops
-- =============================================================================
-- These tables were created directly in the live DB and may lack RLS policies.
-- Applying proper policies ensures:
--   - Drivers can SELECT their own weekly_route_assignments rows
--   - Authenticated users can SELECT weekly_routes and weekly_route_stops
--   - Service role (Next.js API) always bypasses RLS
-- =============================================================================

-- weekly_routes: any authenticated/anon user can read active templates
alter table public.weekly_routes enable row level security;

drop policy if exists "weekly_routes_select_public" on public.weekly_routes;
create policy "weekly_routes_select_public"
  on public.weekly_routes
  for select
  to anon, authenticated
  using (true);

drop policy if exists "weekly_routes_write_admin" on public.weekly_routes;
create policy "weekly_routes_write_admin"
  on public.weekly_routes
  for all
  to authenticated
  using (public.is_current_user_admin())
  with check (public.is_current_user_admin());

-- weekly_route_assignments: driver can read own rows; admin can read all
alter table public.weekly_route_assignments enable row level security;

drop policy if exists "wra_select_own_or_admin" on public.weekly_route_assignments;
create policy "wra_select_own_or_admin"
  on public.weekly_route_assignments
  for select
  to authenticated
  using (
    driver_id = auth.uid()
    or public.is_current_user_admin()
  );

drop policy if exists "wra_write_admin" on public.weekly_route_assignments;
create policy "wra_write_admin"
  on public.weekly_route_assignments
  for all
  to authenticated
  using (public.is_current_user_admin())
  with check (public.is_current_user_admin());

-- weekly_route_stops: any authenticated/anon user can read stops
alter table public.weekly_route_stops enable row level security;

drop policy if exists "wrs_select_public" on public.weekly_route_stops;
create policy "wrs_select_public"
  on public.weekly_route_stops
  for select
  to anon, authenticated
  using (true);

drop policy if exists "wrs_write_admin" on public.weekly_route_stops;
create policy "wrs_write_admin"
  on public.weekly_route_stops
  for all
  to authenticated
  using (public.is_current_user_admin())
  with check (public.is_current_user_admin());

-- Realtime: add tables to publication so mobile app can subscribe
do $$ begin
  alter publication supabase_realtime add table public.weekly_routes;
exception when duplicate_object then null;
end $$;

do $$ begin
  alter publication supabase_realtime add table public.weekly_route_assignments;
exception when duplicate_object then null;
end $$;

do $$ begin
  alter publication supabase_realtime add table public.weekly_route_stops;
exception when duplicate_object then null;
end $$;
