import { NextResponse } from "next/server";
import { getServiceSupabase, isRouteOpsAuthorized, resolveTemplateZoneId } from "@/lib/route-ops";

type TemplateStopInput = {
  collectionPointId: string;
  stopOrder: number;
};

type CreateTemplateBody = {
  name: string;
  zoneId?: string | null;
  recurrenceDay: "monday" | "tuesday" | "wednesday" | "thursday" | "friday" | "saturday" | "sunday";
  createdBy?: string;
  /** 0–23, default 6 */
  startHour?: number;
  /** 1–24 exclusive end of window, default 12 */
  endHour?: number;
  stops: TemplateStopInput[];
};

export async function POST(request: Request) {
  if (!isRouteOpsAuthorized(request)) {
    return NextResponse.json({ ok: false, message: "Unauthorized route ops request." }, { status: 401 });
  }

  try {
    const body = (await request.json()) as Partial<CreateTemplateBody>;
    if (!body.name || !body.recurrenceDay) {
      return NextResponse.json({ ok: false, message: "name and recurrenceDay are required." }, { status: 400 });
    }

    const stops = (body.stops ?? []).filter((stop) => stop.collectionPointId && stop.stopOrder > 0);
    if (stops.length === 0) {
      return NextResponse.json({ ok: false, message: "At least one stop is required." }, { status: 400 });
    }

    const supabase = getServiceSupabase();
    let resolvedZoneId: string;
    try {
      resolvedZoneId = await resolveTemplateZoneId(supabase, {
        explicitZoneId: body.zoneId,
        collectionPointIds: stops.map((s) => s.collectionPointId),
      });
    } catch (e) {
      const msg = e instanceof Error ? e.message : "Could not resolve zone.";
      return NextResponse.json({ ok: false, message: msg }, { status: 400 });
    }

    const startHour = Number(body.startHour ?? 6);
    const endHour = Number(body.endHour ?? 12);
    if (!Number.isFinite(startHour) || startHour < 0 || startHour > 23) {
      return NextResponse.json({ ok: false, message: "startHour must be 0–23." }, { status: 400 });
    }
    if (!Number.isFinite(endHour) || endHour < 1 || endHour > 24) {
      return NextResponse.json({ ok: false, message: "endHour must be 1–24." }, { status: 400 });
    }
    if (endHour <= startHour) {
      return NextResponse.json({ ok: false, message: "endHour must be greater than startHour." }, { status: 400 });
    }

    const { data: template, error: templateError } = await supabase
      .from("route_templates")
      .insert({
        name: body.name,
        zone_id: resolvedZoneId,
        recurrence_day: body.recurrenceDay,
        created_by: body.createdBy ?? null,
        start_hour: startHour,
        end_hour: endHour,
      })
      .select("id, zone_id")
      .single();
    if (templateError) {
      return NextResponse.json({ ok: false, message: `Failed to create route template: ${templateError.message}` }, { status: 500 });
    }

    const { error: stopError } = await supabase.from("route_template_stops").insert(
      stops.map((stop) => ({
        template_id: template.id as string,
        collection_point_id: stop.collectionPointId,
        stop_order: stop.stopOrder,
      })),
    );
    if (stopError) {
      return NextResponse.json({ ok: false, message: `Failed to create template stops: ${stopError.message}` }, { status: 500 });
    }

    return NextResponse.json({
      ok: true,
      templateId: template.id,
      stopCount: stops.length,
      message: "Route template created.",
    });
  } catch (error) {
    const message = error instanceof Error ? error.message : "Failed to create route template.";
    return NextResponse.json({ ok: false, message }, { status: 500 });
  }
}
