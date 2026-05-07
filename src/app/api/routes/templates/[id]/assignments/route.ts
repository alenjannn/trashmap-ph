import { NextResponse } from "next/server";
import { getServiceSupabase, isRouteOpsAuthorized } from "@/lib/route-ops";

type PostBody = {
  driverId?: string;
};

export async function GET(request: Request, context: { params: Promise<{ id: string }> }) {
  if (!isRouteOpsAuthorized(request)) {
    return NextResponse.json({ ok: false, message: "Unauthorized route ops request." }, { status: 401 });
  }

  try {
    const { id: templateId } = await context.params;
    const supabase = getServiceSupabase();

    const { data: template, error: tplError } = await supabase
      .from("weekly_routes")
      .select("id")
      .eq("id", templateId)
      .maybeSingle();
    if (tplError || !template) {
      return NextResponse.json({ ok: false, message: "Route template not found." }, { status: 404 });
    }

    const { data: rows, error } = await supabase
      .from("route_template_assignments")
      .select("id, driver_id, assigned_at")
      .eq("template_id", templateId)
      .eq("is_active", true)
      .order("assigned_at", { ascending: true });
    if (error) {
      return NextResponse.json({ ok: false, message: error.message }, { status: 500 });
    }

    const driverIds = [...new Set((rows ?? []).map((r) => r.driver_id as string))];
    let profileMap = new Map<string, string | null>();
    if (driverIds.length > 0) {
      const { data: profiles } = await supabase
        .from("app_user_profiles")
        .select("user_id, display_name")
        .in("user_id", driverIds);
      profileMap = new Map((profiles ?? []).map((p) => [p.user_id as string, (p.display_name as string) ?? null]));
    }

    const assignments = (rows ?? []).map((r) => ({
      id: r.id as string,
      driverId: r.driver_id as string,
      displayName: profileMap.get(r.driver_id as string) ?? null,
      assignedAt: r.assigned_at as string,
    }));

    return NextResponse.json({ ok: true, assignments });
  } catch (e) {
    const message = e instanceof Error ? e.message : "Failed to list assignments.";
    return NextResponse.json({ ok: false, message }, { status: 500 });
  }
}

export async function POST(request: Request, context: { params: Promise<{ id: string }> }) {
  if (!isRouteOpsAuthorized(request)) {
    return NextResponse.json({ ok: false, message: "Unauthorized route ops request." }, { status: 401 });
  }

  try {
    const { id: templateId } = await context.params;
    const body = (await request.json()) as PostBody;
    const driverId = typeof body.driverId === "string" ? body.driverId.trim() : "";
    if (!driverId) {
      return NextResponse.json({ ok: false, message: "driverId required." }, { status: 400 });
    }

    const supabase = getServiceSupabase();

    const { data: template, error: tplError } = await supabase
      .from("weekly_routes")
      .select("id")
      .eq("id", templateId)
      .maybeSingle();
    if (tplError || !template) {
      return NextResponse.json({ ok: false, message: "Route template not found." }, { status: 404 });
    }

    const { data: existing } = await supabase
      .from("route_template_assignments")
      .select("id")
      .eq("template_id", templateId)
      .eq("driver_id", driverId)
      .eq("is_active", true)
      .maybeSingle();

    if (existing?.id) {
      return NextResponse.json({
        ok: true,
        alreadyActive: true,
        assignmentId: existing.id as string,
        message: "Driver already assigned to this weekly route.",
      });
    }

    const { data: inserted, error: insertError } = await supabase
      .from("route_template_assignments")
      .insert({
        template_id: templateId,
        driver_id: driverId,
        is_active: true,
      })
      .select("id")
      .single();

    if (insertError) {
      return NextResponse.json({ ok: false, message: insertError.message }, { status: 500 });
    }

    return NextResponse.json({
      ok: true,
      alreadyActive: false,
      assignmentId: inserted?.id as string,
      message: "Driver assigned to weekly route.",
    });
  } catch (e) {
    const message = e instanceof Error ? e.message : "Failed to assign driver.";
    return NextResponse.json({ ok: false, message }, { status: 500 });
  }
}
