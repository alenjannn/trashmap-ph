import { NextResponse } from "next/server";
import { getServiceSupabase, isRouteOpsAuthorized } from "@/lib/route-ops";

export async function GET(request: Request, context: { params: Promise<{ routeId: string }> }) {
  if (!isRouteOpsAuthorized(request)) {
    return NextResponse.json({ ok: false, message: "Unauthorized route ops request." }, { status: 401 });
  }

  try {
    const { routeId } = await context.params;
    const supabase = getServiceSupabase();

    const { data: route, error: routeError } = await supabase
      .from("routes")
      .select(
        "id, created_at, route_date, truck_id, zone_id, status, source, estimated_distance_km, estimated_duration_minutes, estimated_fuel_liters, polyline, template_id",
      )
      .eq("id", routeId)
      .maybeSingle();
    if (routeError) {
      return NextResponse.json({ ok: false, message: routeError.message }, { status: 500 });
    }
    if (!route) {
      return NextResponse.json({ ok: false, message: "Route not found." }, { status: 404 });
    }

    const [
      truckRes,
      stopsRes,
      progressRes,
      assignmentsRes,
      pingsRes,
    ] = await Promise.all([
      supabase.from("trucks").select("*").eq("id", route.truck_id as string).maybeSingle(),
      supabase.from("route_stops").select("*").eq("route_id", routeId).order("stop_order", { ascending: true }),
      supabase.from("route_progress").select("*").eq("route_id", routeId).order("created_at", { ascending: true }),
      supabase.from("route_assignments").select("*").eq("route_id", routeId).order("assigned_at", { ascending: false }),
      supabase.from("truck_pings").select("*").eq("route_id", routeId).order("recorded_at", { ascending: false }).limit(500),
    ]);

    if (stopsRes.error) {
      return NextResponse.json({ ok: false, message: stopsRes.error.message }, { status: 500 });
    }
    if (progressRes.error) {
      return NextResponse.json({ ok: false, message: progressRes.error.message }, { status: 500 });
    }
    if (assignmentsRes.error) {
      return NextResponse.json({ ok: false, message: assignmentsRes.error.message }, { status: 500 });
    }
    if (pingsRes.error) {
      return NextResponse.json({ ok: false, message: pingsRes.error.message }, { status: 500 });
    }

    const activeAssignment = (assignmentsRes.data ?? []).find((a) => a.is_active === true);
    const driverId = (activeAssignment?.driver_id ?? (assignmentsRes.data?.[0] as { driver_id?: string } | undefined)?.driver_id) as
      | string
      | undefined;

    let driverProfile: Record<string, unknown> | null = null;
    if (driverId) {
      const { data: prof } = await supabase.from("app_user_profiles").select("*").eq("user_id", driverId).maybeSingle();
      driverProfile = prof as Record<string, unknown> | null;
    }

    return NextResponse.json({
      ok: true,
      route,
      truck: truckRes.data ?? null,
      driverProfile,
      stops: stopsRes.data ?? [],
      progress: progressRes.data ?? [],
      assignments: assignmentsRes.data ?? [],
      pings: pingsRes.data ?? [],
    });
  } catch (error) {
    const message = error instanceof Error ? error.message : "Failed to load route report.";
    return NextResponse.json({ ok: false, message }, { status: 500 });
  }
}
