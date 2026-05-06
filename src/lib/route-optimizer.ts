import { createClient } from "@supabase/supabase-js";
import { getORSRoadGeometry } from "@/lib/ors-directions";

type TruckSeed = {
  truck_code: string;
  plate_number: string;
  driver_name: string;
  capacity_kg: number;
  status: "idle" | "en_route" | "collecting" | "maintenance" | "offline";
};

type StopSeed = {
  label: string;
  lat: number;
  lng: number;
  stopType: "pickup" | "transfer" | "disposal" | "other";
  weight: number;
};

type TruckRow = {
  id: string;
  truck_code: string;
};

type CollectionPointRow = {
  label: string;
  lat: number;
  lng: number;
};

type HotspotRow = {
  center_lat: number;
  center_lng: number;
  severity: "low" | "medium" | "high" | "critical";
};

type InsertedRouteRow = {
  id: string;
  truck_id: string;
  estimated_distance_km: number | null;
  estimated_duration_minutes: number | null;
  estimated_fuel_liters: number | null;
  polyline: string | null;
};

type OptimizationMode = "mock" | "ors";

type RunOptions = {
  forceMode?: OptimizationMode;
};

type OptimizeResult = {
  ok: boolean;
  mode: OptimizationMode;
  routeDate: string;
  summary: {
    truckCount: number;
    routeCount: number;
    stopCount: number;
  };
  routes: InsertedRouteRow[];
  warning?: string;
};

const DEFAULT_STOPS: StopSeed[] = [
  { label: "Brentwood Gate North", lat: 14.69032, lng: 121.10623, stopType: "pickup", weight: 3 },
  { label: "Brentwood Inner Loop A", lat: 14.68991, lng: 121.10687, stopType: "pickup", weight: 2 },
  { label: "Brentwood Inner Loop B", lat: 14.68952, lng: 121.10748, stopType: "pickup", weight: 2 },
  { label: "Brentwood East Row", lat: 14.68905, lng: 121.10793, stopType: "pickup", weight: 2 },
  { label: "Brentwood Mid Court", lat: 14.68876, lng: 121.10719, stopType: "pickup", weight: 2 },
  { label: "Brentwood South Pocket", lat: 14.68834, lng: 121.10682, stopType: "pickup", weight: 2 },
  { label: "Brentwood Lower West", lat: 14.68805, lng: 121.10608, stopType: "pickup", weight: 2 },
  { label: "Brentwood Exit South", lat: 14.68772, lng: 121.10559, stopType: "pickup", weight: 1 },
];

const TRUCKS: TruckSeed[] = [
  {
    truck_code: "TRK-01",
    plate_number: "NAA-1001",
    driver_name: "Driver One",
    capacity_kg: 2500,
    status: "idle",
  },
  {
    truck_code: "TRK-02",
    plate_number: "NAA-1002",
    driver_name: "Driver Two",
    capacity_kg: 2800,
    status: "idle",
  },
  {
    truck_code: "TRK-03",
    plate_number: "NAA-1003",
    driver_name: "Driver Three",
    capacity_kg: 3000,
    status: "idle",
  },
];

function isoDateToday(): string {
  return new Date().toISOString().slice(0, 10);
}

function makePolyline(stops: StopSeed[]): string {
  return stops.map((stop) => `${stop.lat.toFixed(6)},${stop.lng.toFixed(6)}`).join(";");
}

function estimateDistanceKm(stops: StopSeed[]): number {
  const weight = stops.reduce((total, stop) => total + stop.weight, 0);
  return Number((stops.length * 1.35 + weight * 0.55).toFixed(2));
}

function splitStopsIntoBuckets(stops: StopSeed[], bucketCount: number): StopSeed[][] {
  const buckets: StopSeed[][] = Array.from({ length: bucketCount }, () => []);
  stops.forEach((stop, index) => {
    buckets[index % bucketCount].push(stop);
  });
  return buckets;
}

function getSupabaseServerClient() {
  const supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL;
  const serviceRoleKey = process.env.SUPABASE_SERVICE_ROLE_KEY;
  if (!supabaseUrl || !serviceRoleKey) {
    throw new Error(
      "Route optimizer requires NEXT_PUBLIC_SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY in server environment.",
    );
  }
  return createClient(supabaseUrl, serviceRoleKey);
}

function pickTruckCount(stopCount: number, maxTrucks: number): number {
  if (stopCount <= 10) return Math.min(1, maxTrucks);
  if (stopCount <= 22) return Math.min(2, maxTrucks);
  return Math.min(3, maxTrucks);
}

export async function runRouteOptimization(options?: RunOptions): Promise<OptimizeResult> {
  const supabase = getSupabaseServerClient();
  const routeDate = isoDateToday();
  const orsKey = process.env.ORS_API_KEY;
  const preferORS = options?.forceMode ? options.forceMode === "ors" : Boolean(orsKey);

  const { data: truckRows, error: truckUpsertError } = await supabase
    .from("trucks")
    .upsert(TRUCKS, { onConflict: "truck_code" })
    .select("id, truck_code");
  if (truckUpsertError || !truckRows || truckRows.length === 0) {
    throw new Error(`Unable to prepare truck seed data. ${truckUpsertError?.message ?? ""}`.trim());
  }

  const typedTrucks = truckRows as TruckRow[];
  const { data: collectionPointRows } = await supabase
    .from("collection_points")
    .select("label, lat, lng")
    .eq("is_active", true)
    .order("created_at", { ascending: true })
    .limit(60);

  const collectionPointStops: StopSeed[] =
    (collectionPointRows as CollectionPointRow[] | null)?.map((row) => ({
      label: row.label,
      lat: row.lat,
      lng: row.lng,
      stopType: "pickup" as const,
      weight: 3,
    })) ?? [];

  const { data: hotspotRows } = await supabase
    .from("hotspots")
    .select("center_lat, center_lng, severity")
    .eq("status", "active")
    .order("updated_at", { ascending: false })
    .limit(12);

  const hotspotStops: StopSeed[] =
    (hotspotRows as HotspotRow[] | null)?.map((row, index) => ({
      label: `Hotspot ${index + 1}`,
      lat: row.center_lat,
      lng: row.center_lng,
      stopType: "pickup" as const,
      weight: row.severity === "critical" ? 4 : row.severity === "high" ? 3 : 2,
    })) ?? [];

  const stopPool =
    collectionPointStops.length > 0
      ? [...collectionPointStops, ...hotspotStops.slice(0, Math.max(0, 24 - collectionPointStops.length))]
      : hotspotStops.length > 0
        ? hotspotStops
        : DEFAULT_STOPS;

  const activeTruckCount = pickTruckCount(stopPool.length, typedTrucks.length);
  const activeTrucks = typedTrucks.slice(0, activeTruckCount);
  const stopBuckets = splitStopsIntoBuckets(stopPool, activeTrucks.length);

  const { data: existingRoutes, error: existingRoutesError } = await supabase
    .from("routes")
    .select("id")
    .eq("route_date", routeDate)
    .eq("source", "ai_optimized");
  if (existingRoutesError) {
    throw new Error(`Unable to check existing optimized routes. ${existingRoutesError.message}`);
  }

  if (existingRoutes && existingRoutes.length > 0) {
    const existingIds = existingRoutes.map((route) => route.id);
    const { error: cleanupError } = await supabase.from("routes").delete().in("id", existingIds);
    if (cleanupError) {
      throw new Error(`Unable to clear previous optimized routes. ${cleanupError.message}`);
    }
  }

  let mode: OptimizationMode = preferORS ? "ors" : "mock";
  let warning: string | undefined;

  const routeInsertPayload = await Promise.all(
    activeTrucks.map(async (truck, index) => {
      const assignedStops = stopBuckets[index] ?? [];
      const fallbackDistance = estimateDistanceKm(assignedStops);
      const fallbackDuration = Math.max(25, assignedStops.length * 18);

      let polylineStr = makePolyline(assignedStops);
      let estimatedDistanceKm = fallbackDistance;
      let estimatedDurationMinutes = fallbackDuration;

      if (preferORS && orsKey && assignedStops.length >= 2) {
        const geometry = await getORSRoadGeometry(orsKey, assignedStops);
        if (geometry.mode === "ors") {
          polylineStr = geometry.polyline;
          estimatedDistanceKm = geometry.distanceKm;
          estimatedDurationMinutes = geometry.durationMin;
        } else {
          mode = "mock";
          warning = "ORS unavailable, switched to mock fallback.";
        }
      }

      const estimatedFuelLiters = Number((estimatedDistanceKm / 3.8).toFixed(2));
      return {
        route_date: routeDate,
        truck_id: truck.id,
        status: "published",
        source: "ai_optimized",
        estimated_distance_km: estimatedDistanceKm,
        estimated_duration_minutes: estimatedDurationMinutes,
        estimated_fuel_liters: estimatedFuelLiters,
        polyline: polylineStr,
      };
    }),
  );

  const { data: insertedRoutes, error: routeInsertError } = await supabase
    .from("routes")
    .insert(routeInsertPayload)
    .select("id, truck_id, estimated_distance_km, estimated_duration_minutes, estimated_fuel_liters, polyline");
  if (routeInsertError || !insertedRoutes) {
    throw new Error(`Unable to persist optimized routes. ${routeInsertError?.message ?? ""}`.trim());
  }

  const stopRows = insertedRoutes.flatMap((routeRow, index) => {
    const assignedStops = stopBuckets[index] ?? [];
    return assignedStops.map((stop, stopIndex) => ({
      route_id: routeRow.id,
      stop_order: stopIndex + 1,
      label: stop.label,
      lat: stop.lat,
      lng: stop.lng,
      stop_type: stop.stopType,
      status: "pending",
    }));
  });

  let insertedStopRows: Array<{ id: string; route_id: string }> = [];
  if (stopRows.length > 0) {
    const { data, error: stopInsertError } = await supabase
      .from("route_stops")
      .insert(stopRows)
      .select("id, route_id");
    if (stopInsertError || !data) {
      throw new Error(`Unable to persist route stops. ${stopInsertError?.message ?? ""}`.trim());
    }
    insertedStopRows = data;
  }

  if (insertedStopRows.length > 0) {
    const routeToTruck = new Map(insertedRoutes.map((route) => [route.id, route.truck_id]));
    const progressRows = insertedStopRows.map((stop) => ({
      route_id: stop.route_id,
      stop_id: stop.id,
      truck_id: routeToTruck.get(stop.route_id),
      status: "pending",
    }));
    const { error: progressInsertError } = await supabase.from("route_progress").insert(progressRows);
    if (progressInsertError) {
      throw new Error(`Unable to initialize route progress rows. ${progressInsertError.message}`);
    }
  }

  return {
    ok: true,
    mode,
    routeDate,
    summary: {
      truckCount: insertedRoutes.length,
      routeCount: insertedRoutes.length,
      stopCount: insertedStopRows.length,
    },
    routes: insertedRoutes as InsertedRouteRow[],
    warning,
  };
}
