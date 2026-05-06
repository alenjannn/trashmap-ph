import { NextResponse } from "next/server";
import { getServiceSupabase, isRouteOpsAuthorized } from "@/lib/route-ops";
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

export async function POST(request: Request, context: { params: Promise<{ id: string }> }) {
  if (!isRouteOpsAuthorized(request)) {
    return NextResponse.json({ ok: false, message: "Unauthorized route ops request." }, { status: 401 });
  }

  try {
    const { id: templateId } = await context.params;
    const supabase = getServiceSupabase();

    // Load template
    const { data: template, error: tplError } = await supabase
      .from("route_templates")
      .select("id, name, zone_id, recurrence_day, is_active")
      .eq("id", templateId)
      .single();
    if (tplError || !template) {
      return NextResponse.json({ ok: false, message: "Route template not found." }, { status: 404 });
    }

    // Load template stops with collection point coords
    const { data: stops, error: stopsError } = await supabase
      .from("route_template_stops")
      .select("stop_order, collection_point_id, collection_points(label, lat, lng)")
      .eq("template_id", templateId)
      .order("stop_order", { ascending: true });
    if (stopsError || !stops || stops.length === 0) {
      return NextResponse.json({ ok: false, message: "No stops in template." }, { status: 400 });
    }

    const typedStops = stops as unknown as TemplateStopRow[];
    const validStops = typedStops.filter((s) => s.collection_points !== null);
    if (validStops.length === 0) {
      return NextResponse.json({ ok: false, message: "All stops lack collection point data." }, { status: 400 });
    }

    // Pick today's date
    const routeDate = new Date().toISOString().slice(0, 10);

    // Idempotency: check for existing materialized route for this template+date
    const { data: existingRoute } = await supabase
      .from("routes")
      .select("id")
      .eq("zone_id", template.zone_id as string)
      .eq("route_date", routeDate)
      .eq("source", "manual")
      .limit(1)
      .maybeSingle();
    if (existingRoute?.id) {
      return NextResponse.json({
        ok: true,
        routeId: existingRoute.id,
        message: "Route already materialized for today.",
        alreadyExisted: true,
      });
    }

    // Pick an idle truck
    const { data: trucks } = await supabase
      .from("trucks")
      .select("id, status")
      .order("created_at", { ascending: true })
      .limit(10);
    const truckPool = (trucks ?? []) as TruckRow[];
    const idleTruck = truckPool.find((t) => t.status === "idle") ?? truckPool[0];
    if (!idleTruck) {
      return NextResponse.json({ ok: false, message: "No trucks available." }, { status: 400 });
    }

    // Get road geometry via ORS
    const orsKey = process.env.ORS_API_KEY ?? "";
    const stopCoords = validStops.map((s) => ({
      lat: s.collection_points!.lat,
      lng: s.collection_points!.lng,
      label: s.collection_points!.label,
    }));

    const geometry = await getORSRoadGeometry(orsKey, stopCoords);

    // Insert routes row
    const { data: newRoute, error: routeInsertError } = await supabase
      .from("routes")
      .insert({
        route_date: routeDate,
        truck_id: idleTruck.id,
        zone_id: template.zone_id,
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
      return NextResponse.json({ ok: false, message: `Failed to create route: ${routeInsertError?.message}` }, { status: 500 });
    }

    const routeId = newRoute.id as string;

    // Insert route_stops rows
    const stopsPayload = validStops.map((s) => ({
      route_id: routeId,
      stop_order: s.stop_order,
      label: s.collection_points!.label,
      lat: s.collection_points!.lat,
      lng: s.collection_points!.lng,
      stop_type: "pickup",
      status: "pending",
    }));
    const { error: stopsInsertError } = await supabase.from("route_stops").insert(stopsPayload);
    if (stopsInsertError) {
      return NextResponse.json({ ok: false, message: `Failed to create stops: ${stopsInsertError.message}` }, { status: 500 });
    }

    return NextResponse.json({
      ok: true,
      routeId,
      stopCount: stopsPayload.length,
      geometryMode: geometry.mode,
      message: `Route materialized (${geometry.mode} geometry, ${stopsPayload.length} stops).`,
    });
  } catch (error) {
    const message = error instanceof Error ? error.message : "Failed to materialize route.";
    return NextResponse.json({ ok: false, message }, { status: 500 });
  }
}
