# Day 2 Handoff Notes

## Priority Integration Path
1. Wire Flutter Report form submit -> Supabase `reports` insert.
2. Wire Next.js dashboard read -> live `reports` fetch.
3. Add Realtime subscription for `reports` on dashboard and mobile map.
4. Add missed-pickup differentiation and pin color mapping.

## Data Mapping (Mock -> Real)

### Web map pins (`dashboardPins`)
- `id` <- `reports.id`
- `lat` <- `reports.lat`
- `lng` <- `reports.lng`
- `type` <- `reports.report_type` mapped:
  - `dumpsite` -> `dumpsite`
  - `missed_pickup` -> `missed_pickup`
- hotspot layer later from `hotspots` table

### Incident feed (`incidentFeed`)
- `title` <- derived from `report_type` and `status`
- `locationLabel` <- reverse geocode or zone label (temporary: zone name)
- `createdAgo` <- relative from `reports.created_at`
- `severity` <- based on status/cluster count (temporary heuristic)

### Fleet panel (`fleetTrucks`)
- source table: `trucks`
- route progress source: `routes`

## Required Env Keys
- `NEXT_PUBLIC_SUPABASE_URL`
- `NEXT_PUBLIC_SUPABASE_ANON_KEY`
- `ORS_API_KEY`

## Day 2 Safety Checks
- keep static fallback visible when Supabase unavailable
- keep map loading state to avoid blank screens
- keep submit button disabled during in-flight request

## Expected Demo for Day 2 End
- submit report in Flutter
- report appears in LGU dashboard without refresh
- pin style reflects report type
