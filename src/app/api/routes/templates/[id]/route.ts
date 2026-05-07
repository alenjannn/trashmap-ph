import { NextResponse } from "next/server";
import { getServiceSupabase, isRouteOpsAuthorized } from "@/lib/route-ops";

/**
 * ~1.1 m at the equator; tighter than any GPS jitter we'd expect.
 * Stop coords are copied verbatim from `collection_points` at materialize time,
 * so an exact-or-very-near match identifies routes that were derived from this template.
 */
const COORD_EPSILON = 1e-5;

type TemplateStopWithCoord = {
  collection_points: { lat: number; lng: number } | null;
};

export async function DELETE(request: Request, context: { params: Promise<{ id: string }> }) {
  if (!isRouteOpsAuthorized(request)) {
    return NextResponse.json({ ok: false, message: "Unauthorized route ops request." }, { status: 401 });
  }

  try {
    const { id } = await context.params;
    const supabase = getServiceSupabase();

    // 1) Direct path: routes already tagged with this template_id (post-schema data).
    //    The new FK has on-delete-cascade so simply deleting the template would also
    //    drop these — but we surface the count to the caller, and explicit delete is
    //    idempotent and safe regardless of whether the schema delta has been applied.
    const { data: directRoutes, error: directLookupError } = await supabase
      .from("routes")
      .select("id")
      .eq("weekly_route_id", id);
    if (directLookupError) {
      return NextResponse.json({ ok: false, message: directLookupError.message }, { status: 500 });
    }

    // 2) Legacy path: routes that pre-date `template_id` (column was NULL when they
    //    were inserted). Match by stop coordinates instead — same trick as the
    //    collection_points DELETE handler.
    const { data: tplStops, error: tplStopsError } = await supabase
      .from("weekly_route_stops")
      .select("collection_points(lat, lng)")
      .eq("weekly_route_id", id);
    if (tplStopsError) {
      return NextResponse.json({ ok: false, message: tplStopsError.message }, { status: 500 });
    }

    const stopCoords = ((tplStops ?? []) as unknown as TemplateStopWithCoord[])
      .map((s) => s.collection_points)
      .filter((c): c is { lat: number; lng: number } => c !== null);

    const orphanRouteIds = new Set<string>();
    for (const c of stopCoords) {
      const { data: matching, error: matchError } = await supabase
        .from("route_stops")
        .select("route_id")
        .gte("lat", c.lat - COORD_EPSILON)
        .lte("lat", c.lat + COORD_EPSILON)
        .gte("lng", c.lng - COORD_EPSILON)
        .lte("lng", c.lng + COORD_EPSILON);
      if (matchError) {
        return NextResponse.json({ ok: false, message: matchError.message }, { status: 500 });
      }
      for (const row of matching ?? []) {
        orphanRouteIds.add(row.route_id as string);
      }
    }

    const allRouteIds = new Set<string>([
      ...((directRoutes ?? []).map((r) => r.id as string)),
      ...orphanRouteIds,
    ]);

    let purgedRoutes = 0;
    if (allRouteIds.size > 0) {
      const { data: purged, error: purgeError } = await supabase
        .from("routes")
        .delete()
        .in("id", Array.from(allRouteIds))
        .select("id");
      if (purgeError) {
        return NextResponse.json(
          { ok: false, message: `Failed clearing dependent routes: ${purgeError.message}` },
          { status: 500 },
        );
      }
      purgedRoutes = purged?.length ?? 0;
    }

    // 3) Delete the template. route_template_stops cascade via existing FK.
    const { error: tplDeleteError } = await supabase
      .from("weekly_routes")
      .delete()
      .eq("id", id);
    if (tplDeleteError) {
      return NextResponse.json({ ok: false, message: tplDeleteError.message }, { status: 500 });
    }

    return NextResponse.json({
      ok: true,
      purgedRoutes,
      message:
        purgedRoutes > 0
          ? `Weekly route deleted. Purged ${purgedRoutes} dependent route${purgedRoutes === 1 ? "" : "s"} from the map.`
          : "Weekly route deleted.",
    });
  } catch (error) {
    const message = error instanceof Error ? error.message : "Failed to delete template.";
    return NextResponse.json({ ok: false, message }, { status: 500 });
  }
}
