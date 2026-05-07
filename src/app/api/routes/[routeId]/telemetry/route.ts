import { NextResponse } from "next/server";
import { getBearerUserId, getProfileRole, getRouteOrThrow, getServiceSupabase } from "@/lib/route-ops";

type TelemetryBody = {
  lat?: number;
  lng?: number;
  speed_kmh?: number | null;
  heading?: number | null;
};

export async function POST(request: Request, context: { params: Promise<{ routeId: string }> }) {
  const userId = await getBearerUserId(request);
  if (!userId) {
    return NextResponse.json({ ok: false, message: "Unauthorized." }, { status: 401 });
  }

  try {
    const supabase = getServiceSupabase();
    const role = await getProfileRole(supabase, userId);
    if (role !== "driver") {
      return NextResponse.json({ ok: false, message: "Driver session required." }, { status: 403 });
    }

    const { routeId } = await context.params;
    const body = (await request.json().catch(() => ({}))) as TelemetryBody;
    const lat = Number(body.lat);
    const lng = Number(body.lng);
    if (!Number.isFinite(lat) || !Number.isFinite(lng)) {
      return NextResponse.json({ ok: false, message: "Valid lat and lng required." }, { status: 400 });
    }

    const { data: assignment, error: raError } = await supabase
      .from("route_assignments")
      .select("id")
      .eq("route_id", routeId)
      .eq("driver_id", userId)
      .eq("is_active", true)
      .maybeSingle();
    if (raError) {
      return NextResponse.json({ ok: false, message: raError.message }, { status: 500 });
    }
    if (!assignment) {
      return NextResponse.json({ ok: false, message: "No active assignment for this route." }, { status: 403 });
    }

    const route = await getRouteOrThrow(supabase, routeId);
    if (route.status !== "in_progress") {
      return NextResponse.json({ ok: false, message: "Route not in progress; telemetry rejected." }, { status: 400 });
    }

    const speed =
      body.speed_kmh != null && Number.isFinite(Number(body.speed_kmh)) ? Number(body.speed_kmh) : null;
    const heading =
      body.heading != null && Number.isFinite(Number(body.heading)) ? Number(body.heading) : null;

    const { data: ping, error: insError } = await supabase
      .from("truck_pings")
      .insert({
        route_id: routeId,
        truck_id: route.truck_id,
        driver_id: userId,
        lat,
        lng,
        speed_kmh: speed,
        heading,
      })
      .select("id, recorded_at")
      .single();

    if (insError) {
      return NextResponse.json({ ok: false, message: insError.message }, { status: 500 });
    }

    return NextResponse.json({
      ok: true,
      pingId: ping.id as string,
      recordedAt: ping.recorded_at as string,
    });
  } catch (error) {
    const message = error instanceof Error ? error.message : "Telemetry failed.";
    return NextResponse.json({ ok: false, message }, { status: 500 });
  }
}
