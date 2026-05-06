import { NextResponse } from "next/server";
import { createClient } from "@supabase/supabase-js";
import { runRouteOptimization } from "@/lib/route-optimizer";

function isAuthorized(request: Request): boolean {
  const secret = process.env.DEMO_SEED_SECRET;
  if (!secret) return false;
  const authHeader = request.headers.get("authorization") ?? "";
  return authHeader === `Bearer ${secret}`;
}

export async function POST(request: Request) {
  if (!isAuthorized(request)) {
    return NextResponse.json({ ok: false, message: "Unauthorized demo seed request." }, { status: 401 });
  }

  const supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL;
  const serviceRoleKey = process.env.SUPABASE_SERVICE_ROLE_KEY;
  if (!supabaseUrl || !serviceRoleKey) {
    return NextResponse.json(
      { ok: false, message: "Missing Supabase server environment configuration." },
      { status: 500 },
    );
  }

  const supabase = createClient(supabaseUrl, serviceRoleKey);

  try {
    const optimizeResult = await runRouteOptimization();

    const routeIds = optimizeResult.routes.map((route) => route.id);
    if (routeIds.length > 0) {
      const { data: routeStops, error: stopsError } = await supabase
        .from("route_stops")
        .select("id, route_id")
        .in("route_id", routeIds)
        .order("stop_order", { ascending: true });

      if (stopsError) {
        return NextResponse.json(
          { ok: false, message: `Failed to load route stops for day4 seed: ${stopsError.message}` },
          { status: 500 },
        );
      }

      const firstStopByRoute = new Map<string, string>();
      for (const row of routeStops ?? []) {
        const routeId = row.route_id as string;
        if (!firstStopByRoute.has(routeId)) {
          firstStopByRoute.set(routeId, row.id as string);
        }
      }

      const nowIso = new Date().toISOString();
      for (const [routeId, stopId] of firstStopByRoute.entries()) {
        const { error: stopStatusError } = await supabase
          .from("route_stops")
          .update({ status: "completed" })
          .eq("id", stopId);
        if (stopStatusError) {
          return NextResponse.json(
            { ok: false, message: `Failed to mark day4 demo stop completed: ${stopStatusError.message}` },
            { status: 500 },
          );
        }

        const { error: progressStatusError } = await supabase
          .from("route_progress")
          .update({ status: "completed", confirmed_at: nowIso, updated_at: nowIso })
          .eq("route_id", routeId)
          .eq("stop_id", stopId);
        if (progressStatusError) {
          return NextResponse.json(
            { ok: false, message: `Failed to mark day4 demo progress completed: ${progressStatusError.message}` },
            { status: 500 },
          );
        }
      }
    }

    const { data: profileRows } = await supabase
      .from("app_user_profiles")
      .select("user_id")
      .in("role", ["citizen", "driver"])
      .limit(50);

    if ((profileRows ?? []).length > 0) {
      const pointsSeed = (profileRows ?? []).map((row, index) => ({
        user_id: row.user_id as string,
        points: 30 + index * 5,
        barangay: index % 2 === 0 ? "Brentwood" : "Mambugan",
        badges: ["early_reporter"],
      }));

      const { error: pointsError } = await supabase
        .from("gamification_points")
        .upsert(pointsSeed, { onConflict: "user_id" });
      if (pointsError) {
        return NextResponse.json(
          { ok: false, message: `Failed to seed gamification points: ${pointsError.message}` },
          { status: 500 },
        );
      }
    }

    return NextResponse.json({
      ok: true,
      message: "Day 4 demo dataset prepared.",
      optimize: optimizeResult,
      note: "Routes, stops, progress, and points leaderboard seed refreshed.",
    });
  } catch (error) {
    const message = error instanceof Error ? error.message : "Day 4 demo seed failed.";
    return NextResponse.json({ ok: false, message }, { status: 500 });
  }
}
