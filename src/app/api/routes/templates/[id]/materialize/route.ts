import { NextResponse } from "next/server";
import { getServiceSupabase, isRouteOpsAuthorized } from "@/lib/route-ops";
import { routeDateInManila } from "@/lib/route-gate";
import { materializeTemplateForDate } from "@/lib/template-materialize";

export async function POST(request: Request, context: { params: Promise<{ id: string }> }) {
  if (!isRouteOpsAuthorized(request)) {
    return NextResponse.json({ ok: false, message: "Unauthorized route ops request." }, { status: 401 });
  }

  try {
    const { id: templateId } = await context.params;
    const supabase = getServiceSupabase();
    const routeDate = routeDateInManila();
    const orsKey = process.env.ORS_API_KEY ?? "";

    const result = await materializeTemplateForDate(supabase, templateId, routeDate, orsKey);
    if (!result.ok) {
      return NextResponse.json({ ok: false, message: result.message }, { status: result.status });
    }

    const modeLabel =
      result.geometryMode === "ors" ? "ORS road" : result.geometryMode === "osrm" ? "OSRM road" : "straight-line";

    return NextResponse.json({
      ok: true,
      routeId: result.routeId,
      stopCount: result.stopCoords.length,
      geometryMode: result.geometryMode,
      warning: result.geometryWarning,
      alreadyExisted: result.alreadyExisted,
      message: result.geometryWarning
        ? `Route materialized (${modeLabel}, ${result.stopCoords.length} stops). ${result.geometryWarning}`
        : `Route materialized (${modeLabel} geometry, ${result.stopCoords.length} stops).`,
    });
  } catch (error) {
    const message = error instanceof Error ? error.message : "Failed to materialize route.";
    return NextResponse.json({ ok: false, message }, { status: 500 });
  }
}
