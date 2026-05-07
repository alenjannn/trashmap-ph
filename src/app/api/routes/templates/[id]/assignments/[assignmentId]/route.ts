import { NextResponse } from "next/server";
import { getServiceSupabase, isRouteOpsAuthorized } from "@/lib/route-ops";

export async function DELETE(request: Request, context: { params: Promise<{ id: string; assignmentId: string }> }) {
  if (!isRouteOpsAuthorized(request)) {
    return NextResponse.json({ ok: false, message: "Unauthorized route ops request." }, { status: 401 });
  }

  try {
    const { id: templateId, assignmentId } = await context.params;
    const supabase = getServiceSupabase();

    const { data: row, error: readError } = await supabase
      .from("weekly_route_assignments")
      .select("id, weekly_route_id, is_active")
      .eq("id", assignmentId)
      .maybeSingle();
    if (readError || !row) {
      return NextResponse.json({ ok: false, message: "Assignment not found." }, { status: 404 });
    }
    if ((row.weekly_route_id as string) !== templateId) {
      return NextResponse.json({ ok: false, message: "Assignment does not belong to this template." }, { status: 400 });
    }

    const { error: updateError } = await supabase
      .from("weekly_route_assignments")
      .update({ is_active: false, unassigned_at: new Date().toISOString() })
      .eq("id", assignmentId)
      .eq("is_active", true);

    if (updateError) {
      return NextResponse.json({ ok: false, message: updateError.message }, { status: 500 });
    }

    return NextResponse.json({ ok: true, message: "Assignment removed." });
  } catch (e) {
    const message = e instanceof Error ? e.message : "Failed to remove assignment.";
    return NextResponse.json({ ok: false, message }, { status: 500 });
  }
}
