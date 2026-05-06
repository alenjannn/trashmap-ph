import { NextResponse } from "next/server";
import { appendRouteAudit, appendRouteNotification, getRouteOrThrow, getServiceSupabase, isRouteOpsAuthorized } from "@/lib/route-ops";

type ArrivingBody = {
  actorUserId?: string;
  etaMinutes?: number;
};

export async function POST(request: Request, context: { params: Promise<{ routeId: string }> }) {
  if (!isRouteOpsAuthorized(request)) {
    return NextResponse.json({ ok: false, message: "Unauthorized route ops request." }, { status: 401 });
  }

  try {
    const { routeId } = await context.params;
    const body = (await request.json()) as ArrivingBody;
    const etaMinutes = body.etaMinutes ?? 5;

    if (etaMinutes > 5) {
      return NextResponse.json({ ok: true, routeId, skipped: true, message: "ETA is above arriving threshold." });
    }

    const supabase = getServiceSupabase();
    const route = await getRouteOrThrow(supabase, routeId);

    const { count, error: existingError } = await supabase
      .from("route_notifications_log")
      .select("id", { head: true, count: "exact" })
      .eq("route_id", route.id)
      .eq("event_type", "truck_arriving");
    if (existingError) {
      return NextResponse.json(
        { ok: false, message: `Failed to check arriving notification debounce: ${existingError.message}` },
        { status: 500 },
      );
    }
    if ((count ?? 0) > 0) {
      return NextResponse.json({ ok: true, routeId: route.id, skipped: true, message: "Arriving notification already sent." });
    }

    await appendRouteAudit(supabase, {
      routeId: route.id,
      zoneId: route.zone_id,
      eventType: "truck_arriving",
      actorUserId: body.actorUserId ?? null,
      actorRole: "system",
      areaLabel: "truck_arriving",
      metadata: { etaMinutes },
    });

    await appendRouteNotification(supabase, {
      routeId: route.id,
      zoneId: route.zone_id,
      eventType: "truck_arriving",
      targetScope: "both",
      title: "Truck Arriving",
      body: "Truck is arriving in your area soon.",
      metadata: { etaMinutes },
      ignoreDuplicate: true,
    });

    return NextResponse.json({ ok: true, routeId: route.id, message: "Arriving notification logged." });
  } catch (error) {
    const message = error instanceof Error ? error.message : "Failed to log arriving notification.";
    return NextResponse.json({ ok: false, message }, { status: 500 });
  }
}
