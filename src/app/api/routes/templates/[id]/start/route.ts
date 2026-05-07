import { NextResponse } from "next/server";
import {
  appendRouteAudit,
  appendRouteNotification,
  getBearerUserId,
  getProfileRole,
  getRouteOrThrow,
  getServiceSupabase,
} from "@/lib/route-ops";
import { computeGate, routeDateInManila } from "@/lib/route-gate";
import { materializeTemplateForDate } from "@/lib/template-materialize";
import { getORSStepInstructions } from "@/lib/ors-directions";

type StartBody = {
  force?: boolean;
};

export async function POST(request: Request, context: { params: Promise<{ id: string }> }) {
  const userId = await getBearerUserId(request);
  if (!userId) {
    return NextResponse.json({ ok: false, message: "Unauthorized." }, { status: 401 });
  }

  try {
    const supabase = getServiceSupabase();
    const role = await getProfileRole(supabase, userId);
    if (role !== "driver") {
      return NextResponse.json({ ok: false, message: "Driver session required." }, { status: 403 });
    }

    const { id: templateId } = await context.params;
    const body = (await request.json().catch(() => ({}))) as StartBody;
    const force = body.force === true;

    const { data: tplAssignment, error: taError } = await supabase
      .from("weekly_route_assignments")
      .select("id")
      .eq("weekly_route_id", templateId)
      .eq("driver_id", userId)
      .eq("is_active", true)
      .maybeSingle();
    if (taError) {
      return NextResponse.json({ ok: false, message: taError.message }, { status: 500 });
    }
    if (!tplAssignment) {
      return NextResponse.json({ ok: false, message: "You aren't assigned to this weekly route." }, { status: 403 });
    }

    const { data: template, error: tplError } = await supabase
      .from("weekly_routes")
      .select("id, name, recurrence_day, start_hour, end_hour")
      .eq("id", templateId)
      .single();
    if (tplError || !template) {
      return NextResponse.json({ ok: false, message: "Route template not found." }, { status: 404 });
    }

    const startHour = Number(template.start_hour ?? 6);
    const endHour = Number(template.end_hour ?? 12);
    const gate = computeGate(
      {
        recurrence_day: template.recurrence_day as string,
        start_hour: Number.isFinite(startHour) ? startHour : 6,
        end_hour: Number.isFinite(endHour) ? endHour : 12,
      },
      new Date(),
    );

    if ((gate === "early" || gate === "late") && !force) {
      return NextResponse.json(
        {
          ok: false,
          gate,
          message: `Route start is ${gate}. Retry with { "force": true } after driver confirms.`,
        },
        { status: 412 },
      );
    }

    const routeDate = routeDateInManila();
    const orsKey = process.env.ORS_API_KEY ?? "";
    const mat = await materializeTemplateForDate(supabase, templateId, routeDate, orsKey);
    if (!mat.ok) {
      return NextResponse.json({ ok: false, message: mat.message }, { status: mat.status });
    }

    const stopCoordsForSteps = mat.stopCoords.map((s) => ({ lat: s.lat, lng: s.lng, label: s.label }));
    const stepsPack = await getORSStepInstructions(orsKey, stopCoordsForSteps);

    const { error: deactDriver } = await supabase
      .from("route_assignments")
      .update({ is_active: false })
      .eq("driver_id", userId)
      .eq("is_active", true);
    if (deactDriver) {
      return NextResponse.json({ ok: false, message: deactDriver.message }, { status: 500 });
    }

    const { error: deactRoute } = await supabase
      .from("route_assignments")
      .update({ is_active: false })
      .eq("route_id", mat.routeId)
      .eq("is_active", true);
    if (deactRoute) {
      return NextResponse.json({ ok: false, message: deactRoute.message }, { status: 500 });
    }

    const { error: insRa } = await supabase.from("route_assignments").insert({
      route_id: mat.routeId,
      driver_id: userId,
      assigned_by: null,
      mode: "manual",
      is_active: true,
    });
    if (insRa) {
      return NextResponse.json({ ok: false, message: insRa.message }, { status: 500 });
    }

    const routeRow = await getRouteOrThrow(supabase, mat.routeId);
    const closed = routeRow.status === "completed" || routeRow.status === "completed_with_issues" || routeRow.status === "cancelled";
    if (closed) {
      return NextResponse.json({ ok: false, message: "Cannot start a closed route." }, { status: 400 });
    }

    if (routeRow.status !== "in_progress") {
      const { error: routeError } = await supabase.from("routes").update({ status: "in_progress" }).eq("id", mat.routeId);
      if (routeError) {
        return NextResponse.json({ ok: false, message: routeError.message }, { status: 500 });
      }
      const { error: truckError } = await supabase.from("trucks").update({ status: "en_route" }).eq("id", routeRow.truck_id);
      if (truckError) {
        return NextResponse.json({ ok: false, message: truckError.message }, { status: 500 });
      }

      await appendRouteAudit(supabase, {
        routeId: mat.routeId,
        zoneId: routeRow.zone_id,
        eventType: "route_started",
        actorUserId: userId,
        actorRole: "driver",
        areaLabel: "driver_start_template",
        metadata: { routeDate, templateId, gate },
      });

      await appendRouteNotification(supabase, {
        routeId: mat.routeId,
        zoneId: routeRow.zone_id,
        eventType: "route_started",
        targetScope: "both",
        title: "Collection Started",
        body: "Collection in your area has started.",
        metadata: { routeDate, templateId },
        ignoreDuplicate: true,
      });
    }

    const { data: routeStops } = await supabase
      .from("route_stops")
      .select("id, stop_order, label, lat, lng, status")
      .eq("route_id", mat.routeId)
      .order("stop_order", { ascending: true });

    let stepsWarning: string | null = null;
    if (stepsPack.mode === "mock" && stepsPack.reason) {
      stepsWarning = stepsPack.reason;
    }

    return NextResponse.json({
      ok: true,
      gate,
      routeId: mat.routeId,
      polyline: mat.polyline,
      steps: stepsPack.steps,
      stepsMode: stepsPack.mode,
      stepsWarning,
      geometryWarning: mat.geometryWarning,
      geometryMode: mat.geometryMode,
      stops: routeStops ?? [],
      alreadyMaterialized: mat.alreadyExisted,
      message: gate === "on_time" ? "Route ready." : `Started (${gate}).`,
    });
  } catch (error) {
    const message = error instanceof Error ? error.message : "Failed to start route.";
    return NextResponse.json({ ok: false, message }, { status: 500 });
  }
}
