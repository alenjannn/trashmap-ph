import { NextResponse } from "next/server";
import { runRouteOptimization } from "@/lib/route-optimizer";

function isAuthorized(request: Request): boolean {
  const authHeader = request.headers.get("authorization") ?? "";
  // Accept either the project's own secret or Vercel's standard CRON_SECRET
  // (Vercel auto-injects this on cron-triggered invocations when the env var is set).
  const candidates = [process.env.OPTIMIZER_CRON_SECRET, process.env.CRON_SECRET].filter(
    (s): s is string => Boolean(s),
  );
  if (candidates.length === 0) return false;
  return candidates.some((secret) => authHeader === `Bearer ${secret}`);
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
