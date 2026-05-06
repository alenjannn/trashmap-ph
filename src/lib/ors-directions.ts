/**
 * ORS (OpenRouteService) geometry helper.
 * Fetches actual road-following coordinates from the ORS Directions API.
 * Returns polyline in the app's `lat,lng;lat,lng;...` format.
 * Falls back to straight-line format if ORS is unavailable.
 */

type ORSCoord = [number, number]; // [lng, lat]

type ORSDirectionsResponse = {
  routes?: Array<{
    geometry?: {
      coordinates?: ORSCoord[];
    };
    summary?: { distance?: number; duration?: number };
  }>;
};

type GeometryResult = {
  polyline: string; // "lat,lng;lat,lng;..." stored format
  distanceKm: number;
  durationMin: number;
  mode: "ors" | "mock";
};

function straightLinePolyline(stops: Array<{ lat: number; lng: number }>): string {
  return stops.map((s) => `${s.lat.toFixed(6)},${s.lng.toFixed(6)}`).join(";");
}

function estimateDistance(stops: Array<{ lat: number; lng: number }>): number {
  if (stops.length < 2) return 0.5;
  let dist = 0;
  for (let i = 1; i < stops.length; i++) {
    const prev = stops[i - 1];
    const curr = stops[i];
    const dLat = (curr.lat - prev.lat) * 111;
    const dLng = (curr.lng - prev.lng) * 111 * Math.cos((prev.lat * Math.PI) / 180);
    dist += Math.sqrt(dLat * dLat + dLng * dLng);
  }
  return Number(dist.toFixed(2));
}

export async function getORSRoadGeometry(
  orsKey: string,
  stops: Array<{ lat: number; lng: number; label?: string }>,
): Promise<GeometryResult> {
  const fallbackDist = estimateDistance(stops);
  const fallbackDuration = Math.max(15, stops.length * 10);

  if (!orsKey || stops.length < 2) {
    return {
      polyline: straightLinePolyline(stops),
      distanceKm: fallbackDist,
      durationMin: fallbackDuration,
      mode: "mock",
    };
  }

  const coordinates: ORSCoord[] = stops.map((s) => [s.lng, s.lat]);

  try {
    const response = await fetch("https://api.openrouteservice.org/v2/directions/driving-car/geojson", {
      method: "POST",
      headers: {
        Authorization: orsKey,
        "Content-Type": "application/json",
        Accept: "application/json, application/geo+json",
      },
      body: JSON.stringify({ coordinates, instructions: false }),
    });

    if (!response.ok) {
      throw new Error(`ORS returned ${response.status}`);
    }

    const payload = (await response.json()) as ORSDirectionsResponse;
    const route = payload.routes?.[0];
    const coords = route?.geometry?.coordinates ?? [];

    if (coords.length < 2) {
      throw new Error("ORS returned empty geometry");
    }

    // ORS returns [lng, lat]; convert to "lat,lng;..." storage format.
    const polyline = coords.map(([lng, lat]) => `${lat.toFixed(6)},${lng.toFixed(6)}`).join(";");

    const distM = route?.summary?.distance ?? 0;
    const durS = route?.summary?.duration ?? 0;
    const distanceKm = distM > 0 ? Number((distM / 1000).toFixed(2)) : fallbackDist;
    const durationMin = durS > 0 ? Math.max(5, Math.round(durS / 60)) : fallbackDuration;

    return { polyline, distanceKm, durationMin, mode: "ors" };
  } catch {
    return {
      polyline: straightLinePolyline(stops),
      distanceKm: fallbackDist,
      durationMin: fallbackDuration,
      mode: "mock",
    };
  }
}

/**
 * Snap a single lat/lng to the nearest drivable road using ORS nearest endpoint.
 * Returns snapped coordinates or the original if snap fails.
 */
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
