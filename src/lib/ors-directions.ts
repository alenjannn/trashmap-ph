/**
 * Road-following geometry helpers.
 *
 * Strategy: ORS (with key) → OSRM public demo (no key) → straight-line fallback.
 * Returns polyline in the app's `lat,lng;lat,lng;...` storage format.
 *
 * Why two providers:
 *   - ORS gives best quality but rejects short legs (< ~40m), needs an API key,
 *     and the free tier has tight per-minute / per-day quotas.
 *   - OSRM public demo (`router.project-osrm.org`) is keyless and very tolerant
 *     of short urban routes, but is "best effort" and not suitable for production.
 *
 * Both providers are HTTP-only; we never need a Leaflet plugin to draw the line —
 * the returned polyline is rendered by `<Polyline>` in the dashboard map.
 */

type ORSCoord = [number, number]; // [lng, lat]

type ORSDirectionsResponse = {
  routes?: Array<{
    geometry?: { coordinates?: ORSCoord[] };
    summary?: { distance?: number; duration?: number };
  }>;
  error?: { code?: number; message?: string } | string;
};

type OSRMStepResponse = {
  distance?: number;
  duration?: number;
  maneuver?: {
    type?: string;
    instruction?: string;
    location?: [number, number];
  };
  geometry?: { coordinates?: ORSCoord[] };
};

type OSRMResponse = {
  code?: string;
  message?: string;
  routes?: Array<{
    geometry?: { coordinates?: ORSCoord[]; type?: string } | string;
    distance?: number; // meters
    duration?: number; // seconds
    legs?: Array<{
      steps?: OSRMStepResponse[];
      distance?: number;
      duration?: number;
    }>;
  }>;
};

type GeometryProvider = "ors" | "osrm" | "mock";

type GeometryResult = {
  polyline: string;
  distanceKm: number;
  durationMin: number;
  mode: GeometryProvider;
  /** Last error from the highest-priority provider that failed (for surfacing to UI). */
  reason?: string;
};

function straightLinePolyline(stops: Array<{ lat: number; lng: number }>): string {
  return stops.map((s) => `${s.lat.toFixed(6)},${s.lng.toFixed(6)}`).join(";");
}

function haversineMeters(a: { lat: number; lng: number }, b: { lat: number; lng: number }): number {
  const R = 6371000; // earth radius in meters
  const toRad = (deg: number) => (deg * Math.PI) / 180;
  const dLat = toRad(b.lat - a.lat);
  const dLng = toRad(b.lng - a.lng);
  const lat1 = toRad(a.lat);
  const lat2 = toRad(b.lat);
  const h = Math.sin(dLat / 2) ** 2 + Math.cos(lat1) * Math.cos(lat2) * Math.sin(dLng / 2) ** 2;
  return 2 * R * Math.asin(Math.sqrt(h));
}

/**
 * Drop consecutive stops that sit within `minMeters` of the previously kept stop.
 * ORS rejects/returns empty geometry when consecutive coords are <~10 m apart;
 * OSRM tolerates it but produces zero-length legs. Dedup once at the boundary.
 */
function dedupCloseStops<T extends { lat: number; lng: number }>(stops: T[], minMeters: number): T[] {
  if (stops.length <= 1) return stops;
  const kept: T[] = [stops[0]];
  for (let i = 1; i < stops.length; i++) {
    const prev = kept[kept.length - 1];
    if (haversineMeters(prev, stops[i]) >= minMeters) {
      kept.push(stops[i]);
    }
  }
  return kept;
}

function estimateDistance(stops: Array<{ lat: number; lng: number }>): number {
  if (stops.length < 2) return 0.5;
  let dist = 0;
  for (let i = 1; i < stops.length; i++) {
    dist += haversineMeters(stops[i - 1], stops[i]) / 1000;
  }
  return Number(dist.toFixed(2));
}

function coordsToStoragePolyline(coords: ORSCoord[]): string {
  return coords.map(([lng, lat]) => `${lat.toFixed(6)},${lng.toFixed(6)}`).join(";");
}

async function tryORS(
  orsKey: string,
  stops: Array<{ lat: number; lng: number }>,
): Promise<{ ok: true; polyline: string; distanceKm: number; durationMin: number } | { ok: false; reason: string }> {
  if (!orsKey) return { ok: false, reason: "ORS_API_KEY not set" };
  if (stops.length < 2) return { ok: false, reason: "fewer than 2 stops after dedup" };

  const coordinates: ORSCoord[] = stops.map((s) => [s.lng, s.lat]);
  // `-1` per coordinate = unlimited snap-to-nearest-road radius. Prevents the
  // "empty geometry" 200-OK reply when stops sit slightly off the road network.
  const radiuses = coordinates.map(() => -1);

  try {
    const response = await fetch("https://api.openrouteservice.org/v2/directions/driving-car/geojson", {
      method: "POST",
      headers: {
        Authorization: orsKey,
        "Content-Type": "application/json",
        Accept: "application/json, application/geo+json",
      },
      body: JSON.stringify({ coordinates, instructions: false, radiuses, continue_straight: false }),
    });

    if (!response.ok) {
      let detail = `HTTP ${response.status}`;
      try {
        const errBody = (await response.json()) as ORSDirectionsResponse;
        const msg = typeof errBody.error === "string" ? errBody.error : errBody.error?.message;
        if (msg) detail = `${detail} — ${msg}`;
      } catch {
        // ignore parse failure, keep the HTTP code
      }
      return { ok: false, reason: `ORS ${detail}` };
    }

    const payload = (await response.json()) as ORSDirectionsResponse;
    const route = payload.routes?.[0];
    const coords = route?.geometry?.coordinates ?? [];
    if (coords.length < 2) return { ok: false, reason: "ORS returned empty geometry" };

    const distM = route?.summary?.distance ?? 0;
    const durS = route?.summary?.duration ?? 0;
    const distanceKm = distM > 0 ? Number((distM / 1000).toFixed(2)) : estimateDistance(stops);
    const durationMin = durS > 0 ? Math.max(5, Math.round(durS / 60)) : Math.max(15, stops.length * 8);

    return {
      ok: true,
      polyline: coordsToStoragePolyline(coords),
      distanceKm,
      durationMin,
    };
  } catch (error) {
    const message = error instanceof Error ? error.message : "network error";
    return { ok: false, reason: `ORS request failed: ${message}` };
  }
}

async function tryOSRM(
  stops: Array<{ lat: number; lng: number }>,
): Promise<{ ok: true; polyline: string; distanceKm: number; durationMin: number } | { ok: false; reason: string }> {
  if (stops.length < 2) return { ok: false, reason: "fewer than 2 stops" };

  // OSRM expects lng,lat pairs separated by `;`.
  const coordPath = stops.map((s) => `${s.lng.toFixed(6)},${s.lat.toFixed(6)}`).join(";");
  const url = `https://router.project-osrm.org/route/v1/driving/${coordPath}?overview=full&geometries=geojson`;

  try {
    const response = await fetch(url, {
      headers: { Accept: "application/json" },
    });

    if (!response.ok) {
      return { ok: false, reason: `OSRM HTTP ${response.status}` };
    }

    const payload = (await response.json()) as OSRMResponse;
    if (payload.code && payload.code !== "Ok") {
      return { ok: false, reason: `OSRM ${payload.code}: ${payload.message ?? "unknown"}` };
    }

    const route = payload.routes?.[0];
    const geometry = route?.geometry;
    if (!geometry || typeof geometry === "string") {
      return { ok: false, reason: "OSRM returned non-GeoJSON geometry" };
    }

    const coords = geometry.coordinates ?? [];
    if (coords.length < 2) return { ok: false, reason: "OSRM returned empty geometry" };

    const distM = route?.distance ?? 0;
    const durS = route?.duration ?? 0;
    const distanceKm = distM > 0 ? Number((distM / 1000).toFixed(2)) : estimateDistance(stops);
    const durationMin = durS > 0 ? Math.max(5, Math.round(durS / 60)) : Math.max(15, stops.length * 8);

    return {
      ok: true,
      polyline: coordsToStoragePolyline(coords),
      distanceKm,
      durationMin,
    };
  } catch (error) {
    const message = error instanceof Error ? error.message : "network error";
    return { ok: false, reason: `OSRM request failed: ${message}` };
  }
}

/** Min separation between consecutive stops sent to a routing engine. */
const MIN_STOP_SEPARATION_METERS = 12;

/**
 * Public entrypoint kept for backwards compatibility. Tries ORS, then OSRM, then mock.
 * `mode` indicates which provider actually produced the polyline.
 *
 * Stops are deduplicated in-place to drop consecutive points within
 * `MIN_STOP_SEPARATION_METERS` of the previous kept point. This single pre-pass
 * eliminates the most common "ORS returned empty geometry" cause without
 * losing any meaningful stop information.
 */
export async function getORSRoadGeometry(
  orsKey: string,
  stops: Array<{ lat: number; lng: number; label?: string }>,
): Promise<GeometryResult> {
  const cleanStops = dedupCloseStops(stops, MIN_STOP_SEPARATION_METERS);
  const fallbackDist = estimateDistance(cleanStops.length >= 2 ? cleanStops : stops);
  const fallbackDur = Math.max(15, (cleanStops.length || stops.length) * 8);

  // If dedup left us with <2 distinct stops, no provider can route. Bail to mock.
  if (cleanStops.length < 2) {
    return {
      polyline: straightLinePolyline(stops),
      distanceKm: fallbackDist,
      durationMin: fallbackDur,
      mode: "mock",
      reason: `Stops collapsed to ${cleanStops.length} distinct point(s) after ${MIN_STOP_SEPARATION_METERS} m dedup`,
    };
  }

  // 1) ORS first (best quality when key + quota are healthy).
  const orsAttempt = await tryORS(orsKey, cleanStops);
  if (orsAttempt.ok) {
    return {
      polyline: orsAttempt.polyline,
      distanceKm: orsAttempt.distanceKm,
      durationMin: orsAttempt.durationMin,
      mode: "ors",
    };
  }

  // 2) OSRM public demo (no key, no quota for testing).
  const osrmAttempt = await tryOSRM(cleanStops);
  if (osrmAttempt.ok) {
    return {
      polyline: osrmAttempt.polyline,
      distanceKm: osrmAttempt.distanceKm,
      durationMin: osrmAttempt.durationMin,
      mode: "osrm",
      reason: orsAttempt.reason,
    };
  }

  // 3) Both providers failed — keep the dashboard drawable.
  return {
    polyline: straightLinePolyline(cleanStops),
    distanceKm: fallbackDist,
    durationMin: fallbackDur,
    mode: "mock",
    reason: `ORS: ${orsAttempt.reason}; OSRM: ${osrmAttempt.reason}`,
  };
}

/**
 * Snap a single lat/lng to the nearest drivable road using ORS nearest endpoint.
 * Returns snapped coordinates or the original if snap fails.
 */
/** Turn-by-turn step for mobile HUD (ORS / OSRM / synthetic). */
export type TurnStep = {
  instruction: string;
  distance_m: number;
  duration_s: number;
  lat: number;
  lng: number;
  maneuver_type?: number;
};

export type TurnStepsResult = {
  steps: TurnStep[];
  mode: GeometryProvider;
  reason?: string;
};

type ORSJsonRoute = {
  geometry?: { coordinates?: ORSCoord[]; type?: string } | string;
  segments?: Array<{
    steps?: Array<{
      distance?: number;
      duration?: number;
      type?: number;
      instruction?: string;
      way_points?: [number, number];
    }>;
  }>;
};

type ORSJsonResponse = {
  routes?: ORSJsonRoute[];
  error?: { code?: number; message?: string } | string;
};

function syntheticStepsFromStops(stops: Array<{ lat: number; lng: number; label?: string }>): TurnStep[] {
  return stops.map((s, i) => ({
    instruction:
      i === 0
        ? `Head to ${s.label?.trim() ? s.label : `stop ${i + 1}`}`
        : `Continue to ${s.label?.trim() ? s.label : `stop ${i + 1}`}`,
    distance_m: 0,
    duration_s: 0,
    lat: s.lat,
    lng: s.lng,
  }));
}

async function tryORSSteps(
  orsKey: string,
  stops: Array<{ lat: number; lng: number }>,
): Promise<{ ok: true; steps: TurnStep[] } | { ok: false; reason: string }> {
  if (!orsKey) return { ok: false, reason: "ORS_API_KEY not set" };
  if (stops.length < 2) return { ok: false, reason: "fewer than 2 stops after dedup" };

  const coordinates: ORSCoord[] = stops.map((s) => [s.lng, s.lat]);
  const radiuses = coordinates.map(() => -1);

  try {
    const response = await fetch("https://api.openrouteservice.org/v2/directions/driving-car/json", {
      method: "POST",
      headers: {
        Authorization: orsKey,
        "Content-Type": "application/json",
        Accept: "application/json",
      },
      body: JSON.stringify({
        coordinates,
        instructions: true,
        radiuses,
        continue_straight: false,
        units: "m",
      }),
    });

    if (!response.ok) {
      let detail = `HTTP ${response.status}`;
      try {
        const errBody = (await response.json()) as ORSJsonResponse;
        const msg = typeof errBody.error === "string" ? errBody.error : errBody.error?.message;
        if (msg) detail = `${detail} — ${msg}`;
      } catch {
        // ignore
      }
      return { ok: false, reason: `ORS ${detail}` };
    }

    const payload = (await response.json()) as ORSJsonResponse;
    const route = payload.routes?.[0];
    if (!route) return { ok: false, reason: "ORS returned no routes" };

    let coords: ORSCoord[] = [];
    const geom = route.geometry;
    if (geom && typeof geom === "object" && Array.isArray(geom.coordinates)) {
      coords = geom.coordinates;
    }
    if (coords.length < 2) {
      return { ok: false, reason: "ORS returned no geometry coordinates for steps" };
    }

    const out: TurnStep[] = [];
    for (const seg of route.segments ?? []) {
      for (const step of seg.steps ?? []) {
        const wp = step.way_points;
        const idx = wp != null ? (wp[1] ?? wp[0] ?? 0) : 0;
        const c = coords[idx] ?? coords[coords.length - 1];
        if (!c) continue;
        out.push({
          instruction: (step.instruction ?? "Continue").trim() || "Continue",
          distance_m: Number(step.distance ?? 0),
          duration_s: Number(step.duration ?? 0),
          lat: c[1],
          lng: c[0],
          maneuver_type: step.type,
        });
      }
    }

    if (out.length === 0) return { ok: false, reason: "ORS returned no steps" };
    return { ok: true, steps: out };
  } catch (error) {
    const message = error instanceof Error ? error.message : "network error";
    return { ok: false, reason: `ORS request failed: ${message}` };
  }
}

async function tryOSRMSteps(
  stops: Array<{ lat: number; lng: number }>,
): Promise<{ ok: true; steps: TurnStep[] } | { ok: false; reason: string }> {
  if (stops.length < 2) return { ok: false, reason: "fewer than 2 stops" };

  const coordPath = stops.map((s) => `${s.lng.toFixed(6)},${s.lat.toFixed(6)}`).join(";");
  const url = `https://router.project-osrm.org/route/v1/driving/${coordPath}?overview=full&geometries=geojson&steps=true`;

  try {
    const response = await fetch(url, { headers: { Accept: "application/json" } });
    if (!response.ok) return { ok: false, reason: `OSRM HTTP ${response.status}` };

    const payload = (await response.json()) as OSRMResponse;
    if (payload.code && payload.code !== "Ok") {
      return { ok: false, reason: `OSRM ${payload.code}: ${payload.message ?? "unknown"}` };
    }

    const leg = payload.routes?.[0]?.legs?.[0];
    const osrmSteps = leg?.steps as OSRMStepResponse[] | undefined;
    if (!osrmSteps?.length) return { ok: false, reason: "OSRM returned no steps" };

    const out: TurnStep[] = [];
    for (const step of osrmSteps) {
      const loc = step.maneuver?.location;
      const fromGeom = step.geometry?.coordinates?.[step.geometry.coordinates.length - 1];
      const lngLat: ORSCoord | undefined = loc ?? fromGeom;
      if (!lngLat) continue;
      const instruction =
        step.maneuver?.instruction?.trim() ||
        (step.maneuver?.type ? `${step.maneuver.type}` : "Continue");
      out.push({
        instruction: instruction || "Continue",
        distance_m: Number(step.distance ?? 0),
        duration_s: Number(step.duration ?? 0),
        lat: lngLat[1],
        lng: lngLat[0],
      });
    }

    if (out.length === 0) return { ok: false, reason: "OSRM steps empty after parse" };
    return { ok: true, steps: out };
  } catch (error) {
    const message = error instanceof Error ? error.message : "network error";
    return { ok: false, reason: `OSRM request failed: ${message}` };
  }
}

/**
 * Ordered turn-by-turn steps for mobile HUD. ORS → OSRM → synthetic (per stop).
 */
export async function getORSStepInstructions(
  orsKey: string,
  stops: Array<{ lat: number; lng: number; label?: string }>,
): Promise<TurnStepsResult> {
  const cleanStops = dedupCloseStops(stops, MIN_STOP_SEPARATION_METERS);
  if (cleanStops.length < 2) {
    return {
      steps: syntheticStepsFromStops(stops.length >= 1 ? stops : cleanStops),
      mode: "mock",
      reason: `Stops collapsed to ${cleanStops.length} distinct point(s)`,
    };
  }

  const orsAttempt = await tryORSSteps(orsKey, cleanStops);
  if (orsAttempt.ok) {
    return { steps: orsAttempt.steps, mode: "ors" };
  }

  const osrmAttempt = await tryOSRMSteps(cleanStops);
  if (osrmAttempt.ok) {
    return { steps: osrmAttempt.steps, mode: "osrm", reason: orsAttempt.reason };
  }

  return {
    steps: syntheticStepsFromStops(cleanStops),
    mode: "mock",
    reason: `ORS: ${orsAttempt.reason}; OSRM: ${osrmAttempt.reason}`,
  };
}

export async function snapToNearestRoad(
  orsKey: string,
  lat: number,
  lng: number,
): Promise<{ lat: number; lng: number; snapped: boolean }> {
  if (!orsKey) return { lat, lng, snapped: false };

  try {
    const response = await fetch(
      `https://api.openrouteservice.org/v2/snap/driving-car?point=${lng},${lat}&radius=500`,
      {
        headers: {
          Authorization: orsKey,
          Accept: "application/json",
        },
      },
    );

    if (!response.ok) throw new Error(`ORS snap ${response.status}`);

    const payload = (await response.json()) as {
      locations?: Array<{ location?: [number, number] }>;
    };
    const loc = payload.locations?.[0]?.location;
    if (!loc) throw new Error("No snap location");

    return { lat: loc[1], lng: loc[0], snapped: true };
  } catch {
    return { lat, lng, snapped: false };
  }
}
