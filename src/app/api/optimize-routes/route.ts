import { NextResponse } from "next/server";
import { runRouteOptimization } from "@/lib/route-optimizer";

export async function POST() {
  try {
    const result = await runRouteOptimization();
    // ok:false (no templates) is a valid 200 response with explanation, not a 500.
    return NextResponse.json(result, { status: result.ok ? 200 : 200 });
  } catch (error) {
    const message = error instanceof Error ? error.message : "Route optimization failed.";
    return NextResponse.json({ ok: false, message }, { status: 500 });
  }
}
