import { NextResponse } from "next/server";
import { runRouteOptimization } from "@/lib/route-optimizer";

function isAuthorized(request: Request): boolean {
  const cronSecret = process.env.OPTIMIZER_CRON_SECRET;
  if (!cronSecret) return false;
  const authHeader = request.headers.get("authorization") ?? "";
  return authHeader === `Bearer ${cronSecret}`;
}

export async function POST(request: Request) {
  if (!isAuthorized(request)) {
    return NextResponse.json(
      {
        ok: false,
        message: "Unauthorized scheduled optimizer call.",
      },
      { status: 401 },
    );
  }

  try {
    const result = await runRouteOptimization();
    return NextResponse.json({
      triggeredBy: "schedule",
      ...result,
    });
  } catch (error) {
    const message = error instanceof Error ? error.message : "Scheduled optimization failed.";
    return NextResponse.json({ ok: false, message }, { status: 500 });
  }
}
