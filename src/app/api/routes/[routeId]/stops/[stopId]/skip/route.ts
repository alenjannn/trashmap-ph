import { NextResponse } from "next/server";
import { appendRouteAudit, getRouteOrThrow, getServiceSupabase, isRouteOpsAuthorized, upsertRouteProgress } from "@/lib/route-ops";

type SkipBody = {
  actorUserId?: string;
  reason?: string;
};

export async function POST(request: Request, context: { params: Promise<{ routeId: string; stopId: string }> }) {
  if (!isRouteOpsAuthorized(request)) {
    return NextResponse.json({ ok: false, message: "Unauthorized route ops request." }, { status: 401 });
  }

  try {
    const { routeId, stopId } = await context.params;
    const body = (await request.json()) as SkipBody;
    const supabase = getServiceSupabase();
    const route = await getRouteOrThrow(supabase, routeId);

    const { data: stopRow, error: stopReadError } = await supabase
      .from("route_stops")
      .select("id, status")
      .eq("id", stopId)
      .eq("route_id", route.id)
      .maybeSingle();
    if (stopReadError) {
      return NextResponse.json({ ok: false, message: `Failed to load stop: ${stopReadError.message}` }, { status: 500 });
    }
    if (!stopRow) {
      return NextResponse.json({ ok: false, message: "Route stop not found." }, { status: 404 });
    }

    if (stopRow.status !== "skipped") {
      const { error: stopUpdateError } = await supabase.from("route_stops").update({ status: "skipped" }).eq("id", stopId);
      if (stopUpdateError) {
        return NextResponse.json({ ok: false, message: `Failed to skip stop: ${stopUpdateError.message}` }, { status: 500 });
      }

      await upsertRouteProgress(supabase, {
        routeId: route.id,
        stopId,
        status: "skipped",
        driverId: body.actorUserId ?? null,
        notes: body.reason ?? "Skipped by driver",
      });
    }

    await appendRouteAudit(supabase, {
      routeId: route.id,
      stopId,
      zoneId: route.zone_id,
      eventType: "exception",
      actorUserId: body.actorUserId ?? null,
      actorRole: "driver",
      areaLabel: "stop_skipped",
      metadata: { reason: body.reason ?? "Skipped by driver" },
    });

    return NextResponse.json({ ok: true, routeId: route.id, stopId, message: "Stop skipped." });
  } catch (error) {
    const message = error instanceof Error ? error.message : "Failed to skip stop.";
    return NextResponse.json({ ok: false, message }, { status: 500 });
  }
}
