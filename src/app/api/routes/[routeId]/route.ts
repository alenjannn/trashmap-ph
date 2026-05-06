import { NextResponse } from "next/server";
import { getServiceSupabase, isRouteOpsAuthorized } from "@/lib/route-ops";

export async function DELETE(request: Request, context: { params: Promise<{ routeId: string }> }) {
  if (!isRouteOpsAuthorized(request)) {
    return NextResponse.json({ ok: false, message: "Unauthorized route ops request." }, { status: 401 });
  }

  try {
    const { routeId } = await context.params;
    const supabase = getServiceSupabase();
    const { error } = await supabase.from("routes").delete().eq("id", routeId);
    if (error) {
      return NextResponse.json({ ok: false, message: error.message }, { status: 500 });
    }
    return NextResponse.json({ ok: true, message: "Route deleted." });
  } catch (error) {
    const message = error instanceof Error ? error.message : "Failed to delete route.";
    return NextResponse.json({ ok: false, message }, { status: 500 });
  }
}
