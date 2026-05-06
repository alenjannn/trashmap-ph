import { NextResponse } from "next/server";
import { runRouteOptimization } from "@/lib/route-optimizer";

export async function POST() {
  try {
    const result = await runRouteOptimization();
    return NextResponse.json(result);
  } catch (error) {
    const message = error instanceof Error ? error.message : "Route optimization failed.";
    return NextResponse.json({ ok: false, message }, { status: 500 });
  }
}
