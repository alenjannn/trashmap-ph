import type { SupabaseClient } from "@supabase/supabase-js";
import { getORSRoadGeometry } from "@/lib/ors-directions";

type TemplateStopRow = {
  stop_order: number;
  collection_point_id: string;
  collection_points: {
    label: string;
    lat: number;
    lng: number;
  } | null;
};

type TruckRow = {
  id: string;
  status: string;
};

export type MaterializeResult =
  | {
      ok: true;
      routeId: string;
      alreadyExisted: boolean;
      polyline: string;
      distanceKm: number;
      durationMin: number;
      geometryMode: "ors" | "osrm" | "mock";
      geometryWarning: string | null;
      stopCoords: Array<{ lat: number; lng: number; label: string; stop_order: number; collection_point_id: string }>;
    }
  | { ok: false; status: number; message: string };

/**
 * Idempotent materialization: one route row per (template_id, route_date).
 * Shared by POST /api/routes/templates/[id]/materialize (ops) and driver template /start.
 */
export async function materializeTemplateForDate(
  supabase: SupabaseClient,
  templateId: string,
  routeDate: string,
  orsKey: string,
): Promise<MaterializeResult> {
  const { data: template, error: tplError } = await supabase
    .from("weekly_routes")
    .select("id, name, zone_id, recurrence_day, is_active")
    .eq("id", templateId)
    .single();
  if (tplError || !template) {
    return { ok: false, status: 404, message: "Route template not found." };
  }

  const { data: stops, error: stopsError } = await supabase
    .from("weekly_route_stops")
    .select("stop_order, collection_point_id, collection_points(label, lat, lng)")
    .eq("weekly_route_id", templateId)
    .order("stop_order", { ascending: true });
  if (stopsError || !stops || stops.length === 0) {
    return { ok: false, status: 400, message: "No stops in template." };
  }

  const typedStops = stops as unknown as TemplateStopRow[];
  const validStops = typedStops.filter((s) => s.collection_points !== null);
  if (validStops.length === 0) {
    return { ok: false, status: 400, message: "All stops lack collection point data." };
  }

  const { data: existingRoute } = await supabase
    .from("routes")
    .select("id, polyline, estimated_distance_km, estimated_duration_minutes, source")
    .eq("template_id", templateId)
    .eq("route_date", routeDate)
    .limit(1)
    .maybeSingle();

  if (existingRoute?.id) {
    const existingId = existingRoute.id as string;
    const { data: existingStops } = await supabase
      .from("route_stops")
      .select("stop_order, label, lat, lng")
      .eq("route_id", existingId)
      .order("stop_order", { ascending: true });

    const rows = (existingStops ?? []) as Array<{
      stop_order: number;
      label: string;
      lat: number;
      lng: number;
    }>;

    const stopCoords = rows.map((r) => ({
      lat: r.lat,
      lng: r.lng,
      label: r.label,
      stop_order: r.stop_order,
      collection_point_id: "",
    }));

    return {
      ok: true,
      routeId: existingId,
      alreadyExisted: true,
      polyline: (existingRoute.polyline as string) ?? "",
      distanceKm: Number(existingRoute.estimated_distance_km ?? 0),
      durationMin: Number(existingRoute.estimated_duration_minutes ?? 0),
      geometryMode: "ors",
      geometryWarning: null,
      stopCoords,
    };
  }

  const { data: trucks } = await supabase
    .from("trucks")
    .select("id, status")
    .order("created_at", { ascending: true })
    .limit(10);
  const truckPool = (trucks ?? []) as TruckRow[];
  const idleTruck = truckPool.find((t) => t.status === "idle") ?? truckPool[0];
  if (!idleTruck) {
    return { ok: false, status: 400, message: "No trucks available." };
  }

  const stopCoordsForRouting = validStops.map((s) => ({
    lat: s.collection_points!.lat,
    lng: s.collection_points!.lng,
    label: s.collection_points!.label,
  }));

  const geometry = await getORSRoadGeometry(orsKey, stopCoordsForRouting);
  let geometryWarning: string | null = null;
  if (geometry.mode === "mock") {
    geometryWarning = `Both routing providers failed${geometry.reason ? ` (${geometry.reason})` : ""} — drew straight-line fallback.`;
  } else if (geometry.mode === "osrm") {
    geometryWarning = orsKey
      ? `ORS unavailable${geometry.reason ? ` (${geometry.reason})` : ""}; used OSRM public road geometry.`
      : "ORS_API_KEY missing — used OSRM public road geometry.";
  }

  const { data: newRoute, error: routeInsertError } = await supabase
    .from("routes")
    .insert({
      route_date: routeDate,
      truck_id: idleTruck.id,
      zone_id: template.zone_id,
      template_id: templateId,
      status: "published",
      source: "manual",
      estimated_distance_km: geometry.distanceKm,
      estimated_duration_minutes: geometry.durationMin,
      estimated_fuel_liters: Number((geometry.distanceKm / 3.8).toFixed(2)),
      polyline: geometry.polyline,
    })
    .select("id")
    .single();
  if (routeInsertError || !newRoute) {
    return {
      ok: false,
      status: 500,
      message: `Failed to create route: ${routeInsertError?.message ?? "unknown"}`,
    };
  }

  const routeId = newRoute.id as string;

  const stopsPayload = validStops.map((s) => ({
    route_id: routeId,
    stop_order: s.stop_order,
    label: s.collection_points!.label,
    lat: s.collection_points!.lat,
    lng: s.collection_points!.lng,
    stop_type: "pickup" as const,
    status: "pending" as const,
  }));
  const { error: stopsInsertError } = await supabase.from("route_stops").insert(stopsPayload);
  if (stopsInsertError) {
    return { ok: false, status: 500, message: `Failed to create stops: ${stopsInsertError.message}` };
  }

  const stopCoords = validStops.map((s) => ({
    lat: s.collection_points!.lat,
    lng: s.collection_points!.lng,
    label: s.collection_points!.label,
    stop_order: s.stop_order,
    collection_point_id: s.collection_point_id,
  }));

  return {
    ok: true,
    routeId,
    alreadyExisted: false,
    polyline: geometry.polyline,
    distanceKm: geometry.distanceKm,
    durationMin: geometry.durationMin,
    geometryMode: geometry.mode,
    geometryWarning,
    stopCoords,
  };
}
