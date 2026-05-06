import { NextResponse } from "next/server";
import { getServiceSupabase, isRouteOpsAuthorized } from "@/lib/route-ops";

export async function DELETE(request: Request, context: { params: Promise<{ id: string }> }) {
  if (!isRouteOpsAuthorized(request)) {
    return NextResponse.json({ ok: false, message: "Unauthorized route ops request." }, { status: 401 });
  }

  try {
    const { id } = await context.params;
    const supabase = getServiceSupabase();
    const { error } = await supabase.from("collection_points").delete().eq("id", id);
    if (error) {
      return NextResponse.json({ ok: false, message: error.message }, { status: 500 });
    }
    return NextResponse.json({ ok: true, message: "Collection point deleted." });
  } catch (error) {
    const message = error instanceof Error ? error.message : "Failed to delete collection point.";
    return NextResponse.json({ ok: false, message }, { status: 500 });
  }
}
