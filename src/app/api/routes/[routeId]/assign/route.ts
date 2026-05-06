import { NextResponse } from "next/server";
import { getRouteOrThrow, getServiceSupabase, isRouteOpsAuthorized, pickAutoDriverId, type AssignMode } from "@/lib/route-ops";

type AssignBody = {
  driverId?: string;
  assignedBy?: string;
  mode?: AssignMode;
};

export async function POST(request: Request, context: { params: Promise<{ routeId: string }> }) {
  if (!isRouteOpsAuthorized(request)) {
    return NextResponse.json({ ok: false, message: "Unauthorized route ops request." }, { status: 401 });
  }

  try {
    const { routeId } = await context.params;
    const body = (await request.json()) as AssignBody;
    const mode: AssignMode = body.mode === "auto" ? "auto" : "manual";
    const supabase = getServiceSupabase();

    const route = await getRouteOrThrow(supabase, routeId);
    if (route.status === "completed" || route.status === "completed_with_issues" || route.status === "cancelled") {
      return NextResponse.json({ ok: false, message: "Cannot assign driver to closed route." }, { status: 400 });
    }

    const selectedDriverId = mode === "auto" ? await pickAutoDriverId(supabase) : (body.driverId ?? null);
    if (mode === "manual" && !body.driverId) {
      return NextResponse.json({ ok: false, message: "driverId required for manual assignment." }, { status: 400 });
    }
    if (!selectedDriverId) {
      return NextResponse.json({ ok: false, message: "No driver available to assign." }, { status: 400 });
    }

    const { error: deactivateError } = await supabase
      .from("route_assignments")
      .update({ is_active: false })
      .eq("route_id", route.id)
      .eq("is_active", true);
    if (deactivateError) {
      return NextResponse.json({ ok: false, message: `Failed to update previous assignment: ${deactivateError.message}` }, { status: 500 });
    }

    const { error: assignmentError } = await supabase.from("route_assignments").insert({
      route_id: route.id,
      driver_id: selectedDriverId,
      assigned_by: body.assignedBy ?? null,
      mode,
      is_active: true,
    });
    if (assignmentError) {
      return NextResponse.json({ ok: false, message: `Failed to assign driver: ${assignmentError.message}` }, { status: 500 });
    }

    if (route.status === "draft" || route.status === "published") {
      const { error: routeStatusError } = await supabase.from("routes").update({ status: "scheduled" }).eq("id", route.id);
      if (routeStatusError) {
        return NextResponse.json({ ok: false, message: `Failed to update route status: ${routeStatusError.message}` }, { status: 500 });
      }
    }

    return NextResponse.json({
      ok: true,
      routeId: route.id,
      driverId: selectedDriverId,
      mode,
      message: "Driver assigned.",
    });
  } catch (error) {
    const message = error instanceof Error ? error.message : "Failed to assign driver.";
    return NextResponse.json({ ok: false, message }, { status: 500 });
  }
}
