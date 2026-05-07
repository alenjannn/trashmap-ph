import { NextResponse } from "next/server";
import {
  appendRouteAudit,
  appendRouteNotification,
  getBearerUserId,
  getProfileRole,
  getRouteOrThrow,
  getServiceSupabase,
  isRouteOpsAuthorized,
  upsertRouteProgress,
} from "@/lib/route-ops";
import { buildMissedPickupReports, computeRouteEndStatus } from "@/lib/route-end";

type EndBody = {
  actorUserId?: string;
};

export async function POST(request: Request, context: { params: Promise<{ routeId: string }> }) {
  const opsAuthorized = isRouteOpsAuthorized(request);

  try {
    const { routeId } = await context.params;
    const body = (await request.json().catch(() => ({}))) as EndBody;
    const supabase = getServiceSupabase();

    let driverUserId: string | null = null;
    if (!opsAuthorized) {
      const uid = await getBearerUserId(request);
      if (!uid) {
        return NextResponse.json({ ok: false, message: "Unauthorized." }, { status: 401 });
      }
      const role = await getProfileRole(supabase, uid);
      if (role !== "driver") {
        return NextResponse.json({ ok: false, message: "Driver session or route ops token required." }, { status: 403 });
      }
      const { data: assignment, error: raError } = await supabase
        .from("route_assignments")
        .select("id")
        .eq("route_id", routeId)
        .eq("driver_id", uid)
        .eq("is_active", true)
        .maybeSingle();
      if (raError) {
        return NextResponse.json({ ok: false, message: raError.message }, { status: 500 });
      }
      if (!assignment) {
        return NextResponse.json({ ok: false, message: "No active assignment for this route." }, { status: 403 });
      }
      driverUserId = uid;
    }

    const route = await getRouteOrThrow(supabase, routeId);
    if (route.status === "completed" || route.status === "completed_with_issues") {
      return NextResponse.json({ ok: true, routeId: route.id, routeStatus: route.status, message: "Route already ended." });
    }
    if (route.status === "cancelled") {
      return NextResponse.json({ ok: false, message: "Cannot end cancelled route." }, { status: 400 });
    }

    if (!opsAuthorized && route.status !== "in_progress") {
      return NextResponse.json({ ok: false, message: "Route must be in progress to end as driver." }, { status: 400 });
    }

    const { data: toMiss, error: missReadError } = await supabase
      .from("route_stops")
      .select("id, label, lat, lng")
      .eq("route_id", route.id)
      .in("status", ["pending", "arrived"]);
    if (missReadError) {
      return NextResponse.json({ ok: false, message: `Failed to load unresolved stops: ${missReadError.message}` }, { status: 500 });
    }

    const missedStops = (toMiss ?? []).map((s) => ({
      id: s.id as string,
      label: (s.label as string) ?? "Stop",
      lat: Number(s.lat),
      lng: Number(s.lng),
    }));
    const missedCount = missedStops.length;

    if (missedCount > 0) {
      const ids = missedStops.map((s) => s.id as string);
      const { error: stopUpError } = await supabase.from("route_stops").update({ status: "missed" }).in("id", ids);
      if (stopUpError) {
        return NextResponse.json({ ok: false, message: `Failed to mark stops missed: ${stopUpError.message}` }, { status: 500 });
      }

      const progressDriverId = driverUserId ?? body.actorUserId ?? null;
      const reportReporterId = driverUserId ?? body.actorUserId ?? null;

      for (const stop of missedStops) {
        await upsertRouteProgress(supabase, {
          routeId: route.id,
          stopId: stop.id,
          status: "missed",
          driverId: progressDriverId,
          notes: "Marked missed when route ended.",
        });
      }
      const missedReports = buildMissedPickupReports({
        zoneId: route.zone_id,
        reporterId: reportReporterId,
        stops: missedStops,
      });
      if (missedReports.length > 0) {
        const { error: reportError } = await supabase.from("reports").insert(missedReports);
        if (reportError) {
          // Non-fatal: log and continue. Route completion must not be blocked by analytics writes.
          console.error(`[end] missed-pickup report insert failed (route ${routeId}): ${reportError.message}`);
        }
      }
    }

    const nextRouteStatus = computeRouteEndStatus(missedCount);
    const hasIssues = nextRouteStatus === "completed_with_issues";
    const { error: routeError } = await supabase.from("routes").update({ status: nextRouteStatus }).eq("id", route.id);
    if (routeError) {
      return NextResponse.json({ ok: false, message: `Failed to end route: ${routeError.message}` }, { status: 500 });
    }

    const { error: truckError } = await supabase.from("trucks").update({ status: "idle" }).eq("id", route.truck_id);
    if (truckError) {
      return NextResponse.json({ ok: false, message: `Failed to update truck status: ${truckError.message}` }, { status: 500 });
    }

    const { error: deactError } = await supabase
      .from("route_assignments")
      .update({ is_active: false })
      .eq("route_id", route.id)
      .eq("is_active", true);
    if (deactError) {
      return NextResponse.json({ ok: false, message: `Failed to deactivate route assignments: ${deactError.message}` }, { status: 500 });
    }

    const actorForAudit = body.actorUserId ?? driverUserId ?? null;
    await appendRouteAudit(supabase, {
      routeId: route.id,
      zoneId: route.zone_id,
      eventType: "route_completed",
      actorUserId: actorForAudit,
      actorRole: opsAuthorized ? "system" : "driver",
      areaLabel: "route_end",
      metadata: { missedStops: missedCount, routeStatus: nextRouteStatus, viaOps: opsAuthorized },
    });

    await appendRouteNotification(supabase, {
      routeId: route.id,
      zoneId: route.zone_id,
      eventType: "route_completed",
      targetScope: "both",
      title: "Collection Completed",
      body: hasIssues ? "Collection in your area ended with missed stops." : "Collection in your area is now completed.",
      metadata: { missedStops: missedCount, routeStatus: nextRouteStatus },
      ignoreDuplicate: true,
    });

    return NextResponse.json({
      ok: true,
      routeId: route.id,
      routeStatus: nextRouteStatus,
      missedStops: missedCount,
      unresolvedStops: missedCount,
      message: "Route ended.",
    });
  } catch (error) {
    const message = error instanceof Error ? error.message : "Failed to end route.";
    return NextResponse.json({ ok: false, message }, { status: 500 });
  }
}
