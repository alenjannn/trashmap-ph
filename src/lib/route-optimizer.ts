import { createClient } from "@supabase/supabase-js";
import { getORSRoadGeometry } from "@/lib/ors-directions";

type TruckSeed = {
  truck_code: string;
  plate_number: string;
  driver_name: string;
  capacity_kg: number;
  status: "idle" | "en_route" | "collecting" | "maintenance" | "offline";
};

type TruckRow = {
  id: string;
  truck_code: string;
};

type TemplateStopRow = {
  stop_order: number;
  collection_points: {
    id: string;
    label: string;
    lat: number;
    lng: number;
  } | null;
};

type TemplateRow = {
  id: string;
  name: string;
  zone_id: string;
  is_active: boolean;
  route_template_stops: TemplateStopRow[];
};

type InsertedRouteRow = {
  id: string;
  truck_id: string;
  estimated_distance_km: number | null;
  estimated_duration_minutes: number | null;
  estimated_fuel_liters: number | null;
  polyline: string | null;
};

type OptimizationMode = "mock" | "ors" | "osrm";

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
  message?: string;
};

const TRUCKS: TruckSeed[] = [
  { truck_code: "TRK-01", plate_number: "NAA-1001", driver_name: "Driver One", capacity_kg: 2500, status: "idle" },
  { truck_code: "TRK-02", plate_number: "NAA-1002", driver_name: "Driver Two", capacity_kg: 2800, status: "idle" },
  { truck_code: "TRK-03", plate_number: "NAA-1003", driver_name: "Driver Three", capacity_kg: 3000, status: "idle" },
];

function isoDateToday(): string {
  return new Date().toISOString().slice(0, 10);
}

function straightLinePolyline(stops: Array<{ lat: number; lng: number }>): string {
  return stops.map((s) => `${s.lat.toFixed(6)},${s.lng.toFixed(6)}`).join(";");
}

function estimateDistanceKm(stops: Array<{ lat: number; lng: number }>): number {
  if (stops.length < 2) return 0.5;
  let dist = 0;
  for (let i = 1; i < stops.length; i++) {
    const a = stops[i - 1];
    const b = stops[i];
    const dLat = (b.lat - a.lat) * 111;
    const dLng = (b.lng - a.lng) * 111 * Math.cos((a.lat * Math.PI) / 180);
    dist += Math.sqrt(dLat * dLat + dLng * dLng);
  }
  return Number(dist.toFixed(2));
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

export async function runRouteOptimization(options?: RunOptions): Promise<OptimizeResult> {
  const supabase = getSupabaseServerClient();
  const routeDate = isoDateToday();
  const orsKey = process.env.ORS_API_KEY ?? "";
  const preferORS = options?.forceMode ? options.forceMode === "ors" : Boolean(orsKey);

  // Ensure trucks exist (idempotent seed) and pick from existing pool.
  const { data: truckRows, error: truckUpsertError } = await supabase
    .from("trucks")
    .upsert(TRUCKS, { onConflict: "truck_code" })
    .select("id, truck_code");
  if (truckUpsertError || !truckRows || truckRows.length === 0) {
    throw new Error(`Unable to prepare truck seed data. ${truckUpsertError?.message ?? ""}`.trim());
  }
  const typedTrucks = truckRows as TruckRow[];

  // Load active weekly route templates with their ordered stops + CP coords.
  const { data: templateRows, error: templatesError } = await supabase
    .from("route_templates")
    .select(
      "id, name, zone_id, is_active, route_template_stops(stop_order, collection_points(id, label, lat, lng))",
    )
    .eq("is_active", true)
    .order("created_at", { ascending: true });
  if (templatesError) {
    throw new Error(`Unable to load route templates. ${templatesError.message}`);
  }

  const templates = (templateRows ?? []) as unknown as TemplateRow[];

  // Filter to templates that actually have ≥2 valid stops.
  const usableTemplates = templates
    .map((t) => ({
      ...t,
      stops: (t.route_template_stops ?? [])
        .filter((s) => s.collection_points !== null)
        .sort((a, b) => a.stop_order - b.stop_order)
        .map((s) => ({
          label: s.collection_points!.label,
          lat: s.collection_points!.lat,
          lng: s.collection_points!.lng,
          stopType: "pickup" as const,
        })),
    }))
    .filter((t) => t.stops.length >= 2);

  if (usableTemplates.length === 0) {
    return {
      ok: false,
      mode: preferORS ? "ors" : "mock",
      routeDate,
      summary: { truckCount: 0, routeCount: 0, stopCount: 0 },
      routes: [],
      message: "No weekly routes defined. Create a weekly route in Route Planner before optimizing.",
    };
  }

  // Clear today's previously-optimized routes (cascades route_stops + route_progress).
  const { data: existingRoutes, error: existingRoutesError } = await supabase
    .from("routes")
    .select("id")
    .eq("route_date", routeDate)
    .eq("source", "ai_optimized");
  if (existingRoutesError) {
    throw new Error(`Unable to check existing optimized routes. ${existingRoutesError.message}`);
  }
  if (existingRoutes && existingRoutes.length > 0) {
    const ids = existingRoutes.map((r) => r.id);
    const { error: cleanupError } = await supabase.from("routes").delete().in("id", ids);
    if (cleanupError) {
      throw new Error(`Unable to clear previous optimized routes. ${cleanupError.message}`);
    }
  }

  // Track per-template geometry mode + reasons; pick worst-quality as overall.
  const modeRanks: Record<OptimizationMode, number> = { ors: 2, osrm: 1, mock: 0 };
  const templateGeometryModes: OptimizationMode[] = [];
  let firstFallbackReason: string | null = null;

  // One route per template, road-geometry-routed (ORS → OSRM → mock), round-robin trucks.
  const routeInsertPayload = await Promise.all(
    usableTemplates.map(async (template, idx) => {
      const truck = typedTrucks[idx % typedTrucks.length];
      const stops = template.stops;
      const fallbackDist = estimateDistanceKm(stops);
      const fallbackDur = Math.max(15, stops.length * 8);

      let polylineStr = straightLinePolyline(stops);
      let distanceKm = fallbackDist;
      let durationMin = fallbackDur;

      const geometry = await getORSRoadGeometry(orsKey, stops);
      polylineStr = geometry.polyline;
      distanceKm = geometry.distanceKm;
      durationMin = geometry.durationMin;

      templateGeometryModes.push(geometry.mode);
      if (!firstFallbackReason && geometry.reason && geometry.mode !== "ors") {
        firstFallbackReason = geometry.reason;
      }

      return {
        templateRef: template,
        truckId: truck.id,
        payload: {
          route_date: routeDate,
          truck_id: truck.id,
          zone_id: template.zone_id,
          template_id: template.id,
          status: "published" as const,
          source: "ai_optimized" as const,
          estimated_distance_km: distanceKm,
          estimated_duration_minutes: durationMin,
          estimated_fuel_liters: Number((distanceKm / 3.8).toFixed(2)),
          polyline: polylineStr,
        },
      };
    }),
  );

  const { data: insertedRoutes, error: routeInsertError } = await supabase
    .from("routes")
    .insert(routeInsertPayload.map((r) => r.payload))
    .select("id, truck_id, estimated_distance_km, estimated_duration_minutes, estimated_fuel_liters, polyline");
  if (routeInsertError || !insertedRoutes) {
    throw new Error(`Unable to persist optimized routes. ${routeInsertError?.message ?? ""}`.trim());
  }

  const stopRows = insertedRoutes.flatMap((routeRow, index) => {
    const stops = routeInsertPayload[index].templateRef.stops;
    return stops.map((stop, stopIndex) => ({
      route_id: routeRow.id,
      stop_order: stopIndex + 1,
      label: stop.label,
      lat: stop.lat,
      lng: stop.lng,
      stop_type: stop.stopType,
      status: "pending" as const,
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
    const routeToTruck = new Map(insertedRoutes.map((r) => [r.id, r.truck_id]));
    const progressRows = insertedStopRows.map((stop) => ({
      route_id: stop.route_id,
      stop_id: stop.id,
      truck_id: routeToTruck.get(stop.route_id),
      status: "pending" as const,
    }));
    const { error: progressInsertError } = await supabase.from("route_progress").insert(progressRows);
    if (progressInsertError) {
      throw new Error(`Unable to initialize route progress rows. ${progressInsertError.message}`);
    }
  }

  const finalMode: OptimizationMode =
    templateGeometryModes.length === 0
      ? "mock"
      : templateGeometryModes.reduce(
          (worst, m) => (modeRanks[m] < modeRanks[worst] ? m : worst),
          templateGeometryModes[0] as OptimizationMode,
        );
  const modeLabel = finalMode === "ors" ? "ORS road" : finalMode === "osrm" ? "OSRM road" : "straight-line";
  let finalWarning: string | undefined;
  if (finalMode === "mock") {
    finalWarning = `Road routing unavailable${firstFallbackReason ? ` (${firstFallbackReason})` : ""}; drew straight-line polylines.`;
  } else if (finalMode === "osrm") {
    finalWarning = `ORS unavailable${firstFallbackReason ? ` (${firstFallbackReason})` : ""}; used OSRM public road geometry.`;
  }

  return {
    ok: true,
    mode: finalMode,
    routeDate,
    summary: {
      truckCount: insertedRoutes.length,
      routeCount: insertedRoutes.length,
      stopCount: insertedStopRows.length,
    },
    routes: insertedRoutes as InsertedRouteRow[],
    warning: finalWarning,
    message: `Optimized ${insertedRoutes.length} weekly route(s) into today's run (${modeLabel} geometry).`,
  };
}
