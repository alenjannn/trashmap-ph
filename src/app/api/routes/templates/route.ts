import { NextResponse } from "next/server";
import { getServiceSupabase, isRouteOpsAuthorized } from "@/lib/route-ops";

type TemplateStopInput = {
  collectionPointId: string;
  stopOrder: number;
};

type CreateTemplateBody = {
  name: string;
  zoneId: string;
  recurrenceDay: "monday" | "tuesday" | "wednesday" | "thursday" | "friday" | "saturday" | "sunday";
  createdBy?: string;
  stops: TemplateStopInput[];
};

export async function POST(request: Request) {
  if (!isRouteOpsAuthorized(request)) {
    return NextResponse.json({ ok: false, message: "Unauthorized route ops request." }, { status: 401 });
  }

  try {
    const body = (await request.json()) as Partial<CreateTemplateBody>;
    if (!body.name || !body.zoneId || !body.recurrenceDay) {
      return NextResponse.json({ ok: false, message: "name, zoneId, recurrenceDay are required." }, { status: 400 });
    }

    const stops = (body.stops ?? []).filter((stop) => stop.collectionPointId && stop.stopOrder > 0);
    if (stops.length === 0) {
      return NextResponse.json({ ok: false, message: "At least one stop is required." }, { status: 400 });
    }

    const supabase = getServiceSupabase();
    const { data: template, error: templateError } = await supabase
      .from("route_templates")
      .insert({
        name: body.name,
        zone_id: body.zoneId,
        recurrence_day: body.recurrenceDay,
        created_by: body.createdBy ?? null,
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
