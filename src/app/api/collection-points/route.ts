import { NextResponse } from "next/server";
import { getServiceSupabase, isRouteOpsAuthorized } from "@/lib/route-ops";
import { snapToNearestRoad } from "@/lib/ors-directions";

type CreateCPBody = {
  label: string;
  lat: number;
  lng: number;
  zoneId?: string | null;
};

export async function POST(request: Request) {
  if (!isRouteOpsAuthorized(request)) {
    return NextResponse.json({ ok: false, message: "Unauthorized route ops request." }, { status: 401 });
  }

  try {
    const body = (await request.json()) as Partial<CreateCPBody>;

    if (!body.label?.trim()) {
      return NextResponse.json({ ok: false, message: "label is required." }, { status: 400 });
    }
    if (typeof body.lat !== "number" || typeof body.lng !== "number") {
      return NextResponse.json({ ok: false, message: "lat and lng are required numbers." }, { status: 400 });
    }

    const orsKey = process.env.ORS_API_KEY ?? "";

    // Snap to nearest drivable road
    const snapped = await snapToNearestRoad(orsKey, body.lat, body.lng);

    const supabase = getServiceSupabase();

    // Resolve zone: use provided, or fall back to first zone
    let zoneId: string | null = body.zoneId ?? null;
    if (!zoneId) {
      const { data: firstZone } = await supabase
        .from("zones")
        .select("id")
        .order("created_at", { ascending: true })
        .limit(1)
        .maybeSingle();
      zoneId = (firstZone?.id as string | null) ?? null;
    }

    const { data: inserted, error: insertError } = await supabase
      .from("collection_points")
      .insert({
        label: body.label.trim(),
        lat: snapped.lat,
        lng: snapped.lng,
        zone_id: zoneId,
        is_active: true,
      })
      .select("id, label, lat, lng")
      .single();

    if (insertError) {
      if (insertError.code === "23505") {
        return NextResponse.json({ ok: false, message: `A collection point named "${body.label.trim()}" already exists.` }, { status: 409 });
      }
      return NextResponse.json({ ok: false, message: `Failed to insert collection point: ${insertError.message}` }, { status: 500 });
    }

    return NextResponse.json({
      ok: true,
      collectionPoint: inserted,
      snapped: snapped.snapped,
      message: snapped.snapped
        ? `Collection point added at snapped road coordinate.`
        : `Collection point added (ORS snap unavailable, used original coordinates).`,
    });
  } catch (error) {
    const message = error instanceof Error ? error.message : "Failed to create collection point.";
    return NextResponse.json({ ok: false, message }, { status: 500 });
  }
}
