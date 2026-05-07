import { createClient, type SupabaseClient } from "@supabase/supabase-js";

export type ActorRole = "admin" | "driver" | "system";
export type AssignMode = "manual" | "auto";

type RouteRow = {
  id: string;
  zone_id: string | null;
  status: string;
  route_date: string;
  truck_id: string;
};

export function isRouteOpsAuthorized(request: Request): boolean {
  const token = (
    process.env.ROUTE_OPS_SECRET ??
    process.env.OPTIMIZER_CRON_SECRET ??
    process.env.DEMO_SEED_SECRET ??
    ""
  ).trim();
  if (!token) return false;
  const authHeader = (request.headers.get("authorization") ?? "").trim();
  const match = /^Bearer\s+(\S+)/i.exec(authHeader);
  const provided = (match?.[1] ?? "").trim();
  return provided.length > 0 && provided === token;
}

/** Resolve Supabase auth user id from `Authorization: Bearer <jwt>`. */
export async function getBearerUserId(request: Request): Promise<string | null> {
  const authHeader = (request.headers.get("authorization") ?? "").trim();
  const match = /^Bearer\s+(\S+)/i.exec(authHeader);
  if (!match?.[1]) return null;
  const jwt = match[1];
  const supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL;
  const anonKey = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;
  if (!supabaseUrl || !anonKey) return null;
  const client = createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: `Bearer ${jwt}` } },
  });
  const { data, error } = await client.auth.getUser();
  if (error || !data.user) return null;
  return data.user.id;
}

export async function getProfileRole(supabase: SupabaseClient, userId: string): Promise<string | null> {
  const { data, error } = await supabase.from("app_user_profiles").select("role").eq("user_id", userId).maybeSingle();
  if (error || !data) return null;
  return data.role as string;
}

export function getServiceSupabase(): SupabaseClient {
  const supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL;
  const serviceRoleKey = process.env.SUPABASE_SERVICE_ROLE_KEY;
  if (!supabaseUrl || !serviceRoleKey) {
    throw new Error("Missing NEXT_PUBLIC_SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY.");
  }
  return createClient(supabaseUrl, serviceRoleKey);
}

/**
 * Resolves zone_id for a new route template: explicit id → collection points → any zone row → create default.
 */
export async function resolveTemplateZoneId(
  supabase: SupabaseClient,
  opts: { explicitZoneId?: string | null; collectionPointIds: string[] },
): Promise<string> {
  const cpIds = opts.collectionPointIds.filter(Boolean);
  const cpZoneIds: string[] = [];
  if (cpIds.length > 0) {
    const { data: cps } = await supabase.from("collection_points").select("zone_id").in("id", cpIds);
    const set = new Set<string>();
    for (const row of cps ?? []) {
      const z = row.zone_id as string | null;
      if (z) set.add(z);
    }
    cpZoneIds.push(...set);
  }

  const explicit = opts.explicitZoneId?.trim();
  if (explicit) {
    const { data } = await supabase.from("zones").select("id").eq("id", explicit).maybeSingle();
    if (data?.id) return data.id as string;
  }

  if (cpZoneIds.length === 1) return cpZoneIds[0];
  if (cpZoneIds.length > 1) {
    throw new Error(
      "Selected stops span multiple zones. Pick one zone in the dropdown, or use stops that share the same zone.",
    );
  }

  const { data: first } = await supabase
    .from("zones")
    .select("id")
    .order("created_at", { ascending: true })
    .limit(1)
    .maybeSingle();
  if (first?.id) return first.id as string;

  const { data: inserted, error } = await supabase
    .from("zones")
    .insert({ name: "Default service area", lat: 14.676, lng: 121.0437 })
    .select("id")
    .single();
  if (!error && inserted?.id) return inserted.id as string;

  const { data: byName } = await supabase.from("zones").select("id").eq("name", "Default service area").maybeSingle();
  if (byName?.id) return byName.id as string;

  throw new Error(
    error?.message ?? "No zones in database. Run schema seed or allow server to create default zone.",
  );
}

export async function getRouteOrThrow(supabase: SupabaseClient, routeId: string): Promise<RouteRow> {
  const { data, error } = await supabase
    .from("routes")
    .select("id, zone_id, status, route_date, truck_id")
    .eq("id", routeId)
    .maybeSingle();
  if (error) {
    throw new Error(`Failed to load route: ${error.message}`);
  }
  if (!data) {
    throw new Error("Route not found.");
  }
  return data as RouteRow;
}

export async function appendRouteAudit(
  supabase: SupabaseClient,
  payload: {
    routeId: string;
    stopId?: string | null;
    zoneId?: string | null;
    eventType: "route_started" | "truck_arriving" | "stop_completed" | "route_completed" | "exception";
    actorUserId?: string | null;
    actorRole: ActorRole;
    areaLabel?: string;
    metadata?: Record<string, unknown>;
  },
): Promise<void> {
  const { error } = await supabase.from("route_audit_logs").insert({
    route_id: payload.routeId,
    stop_id: payload.stopId ?? null,
    zone_id: payload.zoneId ?? null,
    event_type: payload.eventType,
    actor_user_id: payload.actorUserId ?? null,
    actor_role: payload.actorRole,
    area_label: payload.areaLabel ?? null,
    metadata_json: payload.metadata ?? {},
  });
  if (error) {
    throw new Error(`Failed to write route audit log: ${error.message}`);
  }
}

export async function appendRouteNotification(
  supabase: SupabaseClient,
  payload: {
    routeId: string;
    zoneId?: string | null;
    eventType: "route_started" | "truck_arriving" | "route_completed" | "exception";
    title: string;
    body: string;
    targetScope: "admin" | "citizen_zone" | "both";
    metadata?: Record<string, unknown>;
    ignoreDuplicate?: boolean;
  },
): Promise<void> {
  const { error } = await supabase.from("route_notifications_log").insert({
    route_id: payload.routeId,
    zone_id: payload.zoneId ?? null,
    event_type: payload.eventType,
    target_scope: payload.targetScope,
    title: payload.title,
    body: payload.body,
    metadata_json: payload.metadata ?? {},
  });
  if (error) {
    if (payload.ignoreDuplicate && error.code === "23505") {
      return;
    }
    throw new Error(`Failed to write route notification log: ${error.message}`);
  }
}

export async function pickAutoDriverId(supabase: SupabaseClient): Promise<string | null> {
  const { data, error } = await supabase
    .from("app_user_profiles")
    .select("user_id")
    .eq("role", "driver")
    .limit(1);
  if (error) {
    throw new Error(`Failed to select auto driver: ${error.message}`);
  }
  if (!data || data.length === 0) return null;
  return data[0].user_id as string;
}

export async function upsertRouteProgress(
  supabase: SupabaseClient,
  payload: {
    routeId: string;
    stopId: string;
    status: "completed" | "skipped" | "missed";
    driverId?: string | null;
    notes?: string | null;
  },
): Promise<void> {
  const nowIso = new Date().toISOString();
  const { data: existingRow, error: readError } = await supabase
    .from("route_progress")
    .select("id")
    .eq("route_id", payload.routeId)
    .eq("stop_id", payload.stopId)
    .limit(1)
    .maybeSingle();
  if (readError) {
    throw new Error(`Failed to read route progress row: ${readError.message}`);
  }

  if (existingRow?.id) {
    const { error: updateError } = await supabase
      .from("route_progress")
      .update({
        status: payload.status,
        confirmed_at: nowIso,
        notes: payload.notes ?? null,
        driver_id: payload.driverId ?? null,
        updated_at: nowIso,
      })
      .eq("id", existingRow.id as string);
    if (updateError) {
      throw new Error(`Failed to update route progress row: ${updateError.message}`);
    }
    return;
  }

  const { error: insertError } = await supabase.from("route_progress").insert({
    route_id: payload.routeId,
    stop_id: payload.stopId,
    truck_id: (await getRouteOrThrow(supabase, payload.routeId)).truck_id,
    status: payload.status,
    confirmed_at: nowIso,
    notes: payload.notes ?? null,
    driver_id: payload.driverId ?? null,
    updated_at: nowIso,
  });
  if (insertError) {
    throw new Error(`Failed to insert route progress row: ${insertError.message}`);
  }
}
