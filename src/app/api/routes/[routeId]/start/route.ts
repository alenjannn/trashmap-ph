import { NextResponse } from "next/server";
import { appendRouteAudit, appendRouteNotification, getRouteOrThrow, getServiceSupabase, isRouteOpsAuthorized } from "@/lib/route-ops";

type StartBody = {
  actorUserId?: string;
};

export async function POST(request: Request, context: { params: Promise<{ routeId: string }> }) {
  if (!isRouteOpsAuthorized(request)) {
    return NextResponse.json({ ok: false, message: "Unauthorized route ops request." }, { status: 401 });
  }

  try {
    const { routeId } = await context.params;
    const body = (await request.json()) as StartBody;
    const supabase = getServiceSupabase();
    const route = await getRouteOrThrow(supabase, routeId);

    if (route.status === "in_progress") {
      return NextResponse.json({ ok: true, routeId: route.id, message: "Route already started." });
    }
    if (route.status === "completed" || route.status === "completed_with_issues" || route.status === "cancelled") {
      return NextResponse.json({ ok: false, message: "Cannot start a closed route." }, { status: 400 });
    }

    const { error: routeError } = await supabase.from("routes").update({ status: "in_progress" }).eq("id", route.id);
    if (routeError) {
      return NextResponse.json({ ok: false, message: `Failed to start route: ${routeError.message}` }, { status: 500 });
    }

    const { error: truckError } = await supabase.from("trucks").update({ status: "en_route" }).eq("id", route.truck_id);
    if (truckError) {
      return NextResponse.json({ ok: false, message: `Failed to update truck status: ${truckError.message}` }, { status: 500 });
    }

    await appendRouteAudit(supabase, {
      routeId: route.id,
      zoneId: route.zone_id,
      eventType: "route_started",
      actorUserId: body.actorUserId ?? null,
      actorRole: "driver",
      areaLabel: "route_start",
      metadata: { routeDate: route.route_date },
    });

    await appendRouteNotification(supabase, {
      routeId: route.id,
      zoneId: route.zone_id,
      eventType: "route_started",
      targetScope: "both",
      title: "Collection Started",
      body: "Collection in your area has started.",
      metadata: { routeDate: route.route_date },
      ignoreDuplicate: true,
    });

    return NextResponse.json({ ok: true, routeId: route.id, message: "Route started." });
  } catch (error) {
    const message = error instanceof Error ? error.message : "Failed to start route.";
    return NextResponse.json({ ok: false, message }, { status: 500 });
  }
}
