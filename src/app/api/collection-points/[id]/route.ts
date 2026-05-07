import { NextResponse } from "next/server";
import { getServiceSupabase, isRouteOpsAuthorized } from "@/lib/route-ops";

const COORD_EPSILON = 1e-5; // ~1.1m at the equator; safely tighter than CP movement.

export async function DELETE(request: Request, context: { params: Promise<{ id: string }> }) {
  if (!isRouteOpsAuthorized(request)) {
    return NextResponse.json({ ok: false, message: "Unauthorized route ops request." }, { status: 401 });
  }

  try {
    const { id } = await context.params;
    const supabase = getServiceSupabase();

    // 1) Fetch CP coords first so we can clean up routes that materialized from it.
    const { data: cp, error: cpFetchError } = await supabase
      .from("collection_points")
      .select("id, lat, lng, label")
      .eq("id", id)
      .maybeSingle();
    if (cpFetchError) {
      return NextResponse.json({ ok: false, message: cpFetchError.message }, { status: 500 });
    }
    if (!cp) {
      return NextResponse.json(
        { ok: false, message: "Collection point not found (wrong id or already deleted)." },
        { status: 404 },
      );
    }

    // 2) Find every route_stops row whose lat/lng matches this CP (within epsilon).
    //    Coords were copied from CP at materialize/optimize time, so they are still equal.
    const latLow = cp.lat - COORD_EPSILON;
    const latHigh = cp.lat + COORD_EPSILON;
    const lngLow = cp.lng - COORD_EPSILON;
    const lngHigh = cp.lng + COORD_EPSILON;

    const { data: matchingStops, error: stopsLookupError } = await supabase
      .from("route_stops")
      .select("route_id")
      .gte("lat", latLow)
      .lte("lat", latHigh)
      .gte("lng", lngLow)
      .lte("lng", lngHigh);
    if (stopsLookupError) {
      return NextResponse.json({ ok: false, message: stopsLookupError.message }, { status: 500 });
    }

    const affectedRouteIds = Array.from(new Set((matchingStops ?? []).map((row) => row.route_id as string)));
    let purgedRoutes = 0;
    if (affectedRouteIds.length > 0) {
      const { data: deletedRoutes, error: routeDeleteError } = await supabase
        .from("routes")
        .delete()
        .in("id", affectedRouteIds)
        .select("id");
      if (routeDeleteError) {
        return NextResponse.json(
          { ok: false, message: `Failed clearing affected routes: ${routeDeleteError.message}` },
          { status: 500 },
        );
      }
      purgedRoutes = deletedRoutes?.length ?? 0;
    }

    // 3) Delete the CP itself. route_template_stops cascade via FK.
    const { data: deleted, error: cpDeleteError } = await supabase
      .from("collection_points")
      .delete()
      .eq("id", id)
      .select("id");
    if (cpDeleteError) {
      return NextResponse.json({ ok: false, message: cpDeleteError.message }, { status: 500 });
    }
    if (!deleted?.length) {
      return NextResponse.json(
        { ok: false, message: "Collection point not found (wrong id or already deleted)." },
        { status: 404 },
      );
    }

    return NextResponse.json({
      ok: true,
      message:
        purgedRoutes > 0
          ? `Collection point deleted. Purged ${purgedRoutes} affected route${purgedRoutes === 1 ? "" : "s"} from the map.`
          : "Collection point deleted.",
      purgedRoutes,
    });
  } catch (error) {
    const message = error instanceof Error ? error.message : "Failed to delete collection point.";
    return NextResponse.json({ ok: false, message }, { status: 500 });
  }
}
