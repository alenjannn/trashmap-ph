import { NextResponse } from "next/server";
import { appendRouteAudit, appendRouteNotification, getRouteOrThrow, getServiceSupabase, isRouteOpsAuthorized } from "@/lib/route-ops";

type EndBody = {
  actorUserId?: string;
};

export async function POST(request: Request, context: { params: Promise<{ routeId: string }> }) {
  if (!isRouteOpsAuthorized(request)) {
    return NextResponse.json({ ok: false, message: "Unauthorized route ops request." }, { status: 401 });
  }

  try {
    const { routeId } = await context.params;
    const body = (await request.json()) as EndBody;
    const supabase = getServiceSupabase();
    const route = await getRouteOrThrow(supabase, routeId);
    if (route.status === "completed" || route.status === "completed_with_issues") {
      return NextResponse.json({ ok: true, routeId: route.id, routeStatus: route.status, message: "Route already ended." });
    }
    if (route.status === "cancelled") {
      return NextResponse.json({ ok: false, message: "Cannot end cancelled route." }, { status: 400 });
    }

    const { count: unresolvedCount, error: unresolvedError } = await supabase
      .from("route_stops")
      .select("id", { count: "exact", head: true })
      .eq("route_id", route.id)
      .in("status", ["pending", "arrived"]);
    if (unresolvedError) {
      return NextResponse.json({ ok: false, message: `Failed to check unresolved stops: ${unresolvedError.message}` }, { status: 500 });
    }

    const hasIssues = (unresolvedCount ?? 0) > 0;
    const nextRouteStatus = hasIssues ? "completed_with_issues" : "completed";
    const { error: routeError } = await supabase.from("routes").update({ status: nextRouteStatus }).eq("id", route.id);
    if (routeError) {
      return NextResponse.json({ ok: false, message: `Failed to end route: ${routeError.message}` }, { status: 500 });
    }

    const { error: truckError } = await supabase.from("trucks").update({ status: "idle" }).eq("id", route.truck_id);
    if (truckError) {
      return NextResponse.json({ ok: false, message: `Failed to update truck status: ${truckError.message}` }, { status: 500 });
    }

    await appendRouteAudit(supabase, {
      routeId: route.id,
      zoneId: route.zone_id,
      eventType: "route_completed",
      actorUserId: body.actorUserId ?? null,
      actorRole: "driver",
      areaLabel: "route_end",
      metadata: { unresolvedStops: unresolvedCount ?? 0, routeStatus: nextRouteStatus },
    });

    await appendRouteNotification(supabase, {
      routeId: route.id,
      zoneId: route.zone_id,
      eventType: "route_completed",
      targetScope: "both",
      title: "Collection Completed",
      body: hasIssues
        ? "Collection in your area ended with unresolved stops."
        : "Collection in your area is now completed.",
      metadata: { unresolvedStops: unresolvedCount ?? 0, routeStatus: nextRouteStatus },
      ignoreDuplicate: true,
    });

    return NextResponse.json({
      ok: true,
      routeId: route.id,
      routeStatus: nextRouteStatus,
      unresolvedStops: unresolvedCount ?? 0,
      message: "Route ended.",
    });
  } catch (error) {
    const message = error instanceof Error ? error.message : "Failed to end route.";
    return NextResponse.json({ ok: false, message }, { status: 500 });
  }
}
