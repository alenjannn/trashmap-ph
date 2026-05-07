"use client";

import "leaflet/dist/leaflet.css";
import L from "leaflet";
import { useEffect, useMemo, useState } from "react";
import { CircleMarker, MapContainer, Marker, Polyline, TileLayer, Tooltip, useMapEvents } from "react-leaflet";

function parsePolyline(polyline: string | null): [number, number][] {
  if (!polyline) return [];
  return polyline
    .split(";")
    .map((segment) => segment.trim())
    .filter(Boolean)
    .map((segment) => {
      const [latRaw, lngRaw] = segment.split(",");
      const lat = Number(latRaw);
      const lng = Number(lngRaw);
      if (Number.isNaN(lat) || Number.isNaN(lng)) return null;
      return [lat, lng] as [number, number];
    })
    .filter((point): point is [number, number] => point !== null);
}

function playbackIcon(color: string) {
  return L.divIcon({
    className: "route-report-playback-marker",
    html: `<div style="width:14px;height:14px;border-radius:9999px;background:${color};border:2px solid #fff;box-shadow:0 1px 4px rgba(0,0,0,0.35);"></div>`,
    iconSize: [14, 14],
    iconAnchor: [7, 7],
  });
}

function PlaybackLayers({
  points,
  scrubLatLng,
  color,
}: {
  points: [number, number][];
  scrubLatLng: [number, number] | null;
  color: string;
}) {
  const [zoom, setZoom] = useState(14);
  useMapEvents({
    zoomend(e) {
      setZoom(e.target.getZoom());
    },
  });
  const r = Math.max(5, Math.min(14, Math.round(20 - zoom)));

  return (
    <>
      {points.length >= 2 ? (
        <Polyline positions={points} pathOptions={{ color, weight: 4, opacity: 0.85 }} />
      ) : null}
      {scrubLatLng ? (
        <>
          <CircleMarker
            center={scrubLatLng}
            radius={r + 4}
            pathOptions={{ color, fillColor: color, fillOpacity: 0.2, weight: 2 }}
          />
          <Marker position={scrubLatLng} icon={playbackIcon(color)}>
            <Tooltip direction="top" offset={[0, -8]} opacity={1}>
              Playback position
            </Tooltip>
          </Marker>
        </>
      ) : null}
    </>
  );
}

export type RouteReportModalProps = {
  routeId: string | null;
  opsToken: string;
  onClose: () => void;
};

export function RouteReportModal({ routeId, opsToken, onClose }: RouteReportModalProps) {
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [payload, setPayload] = useState<Record<string, unknown> | null>(null);
  const [scrubIndex, setScrubIndex] = useState(0);

  useEffect(() => {
    if (!routeId || !opsToken.trim()) {
      return;
    }
    let cancelled = false;
    void (async () => {
      setLoading(true);
      setError(null);
      try {
        const res = await fetch(`/api/routes/${routeId}/report`, {
          headers: { Authorization: `Bearer ${opsToken.trim()}` },
        });
        const data = (await res.json()) as { ok?: boolean; message?: string; [k: string]: unknown };
        if (cancelled) return;
        if (!res.ok || !data.ok) {
          setError(typeof data.message === "string" ? data.message : "Failed to load report.");
          setPayload(null);
          return;
        }
        setPayload(data);
        setScrubIndex(0);
      } catch {
        if (!cancelled) setError("Network error loading report.");
      } finally {
        if (!cancelled) setLoading(false);
      }
    })();
    return () => {
      cancelled = true;
    };
  }, [routeId, opsToken]);

  const pingsAsc = useMemo(() => {
    const pings = (payload?.pings as Array<Record<string, unknown>> | undefined) ?? [];
    return [...pings].sort(
      (a, b) =>
        new Date(String(a.recorded_at ?? 0)).getTime() - new Date(String(b.recorded_at ?? 0)).getTime(),
    );
  }, [payload]);

  const route = payload?.route as Record<string, unknown> | undefined;
  const stops = (payload?.stops as Array<Record<string, unknown>> | undefined) ?? [];
  const driverProfile = payload?.driverProfile as Record<string, unknown> | null | undefined;
  const truck = payload?.truck as Record<string, unknown> | null | undefined;

  const polyline = route ? parsePolyline((route.polyline as string | null) ?? null) : [];
  const missedStops = stops.filter((s) => s.status === "missed");

  const safeScrub = Math.min(scrubIndex, Math.max(0, pingsAsc.length - 1));
  const activePing = pingsAsc.length > 0 ? pingsAsc[safeScrub] : null;
  const scrubLatLng: [number, number] | null =
    activePing && typeof activePing.lat === "number" && typeof activePing.lng === "number"
      ? [activePing.lat as number, activePing.lng as number]
      : null;

  const mapCenter: [number, number] =
    scrubLatLng ??
    (polyline.length > 0 ? polyline[Math.floor(polyline.length / 2)] : [14.676, 121.0437]);

  if (!routeId) return null;

  return (
    <div
      className="fixed inset-0 z-[10001] flex items-center justify-center bg-black/40 backdrop-blur-sm"
      role="presentation"
      onClick={onClose}
    >
      <div
        role="dialog"
        aria-modal="true"
        aria-labelledby="route-report-title"
        className="mx-4 flex max-h-[90vh] w-full max-w-2xl flex-col overflow-hidden rounded-2xl border border-zinc-200 bg-white shadow-2xl"
        onClick={(e) => e.stopPropagation()}
      >
        <div className="flex shrink-0 items-start justify-between border-b border-zinc-100 px-5 py-4">
          <div>
            <h2 id="route-report-title" className="text-base font-bold text-zinc-900">
              Route report
            </h2>
            <p className="mt-0.5 text-xs font-semibold text-zinc-800">
              {route ? `${String(route.route_date ?? "")} · ${String(route.status ?? "")}` : "…"}
            </p>
          </div>
          <button
            type="button"
            onClick={onClose}
            className="cursor-pointer rounded-lg px-2 py-1 text-sm font-semibold text-zinc-700 hover:bg-zinc-100 hover:text-zinc-900"
          >
            Close
          </button>
        </div>

        <div className="min-h-0 flex-1 overflow-y-auto px-5 py-4">
          {loading ? <p className="text-sm text-zinc-600">Loading…</p> : null}
          {error ? <p className="text-sm text-red-700">{error}</p> : null}

          {!loading && !error && payload ? (
            <div className="space-y-4">
              <div className="rounded-lg border border-zinc-100 bg-zinc-50 px-3 py-2 text-xs text-zinc-800">
                <p>
                  <span className="font-semibold text-zinc-600">Truck: </span>
                  {truck
                    ? `${String(truck.truck_code ?? truck.id ?? "—")}${truck.driver_name != null ? ` · ${String(truck.driver_name)}` : ""}`
                    : "—"}
                </p>
                <p className="mt-1">
                  <span className="font-semibold text-zinc-600">Driver: </span>
                  {driverProfile
                    ? String(driverProfile.display_name ?? driverProfile.user_id ?? "—")
                    : "—"}
                </p>
                {route?.weekly_route_id ? (
                  <p className="mt-1">
                    <span className="font-semibold text-zinc-600">Template: </span>
                    {String(route.weekly_route_id).slice(0, 8)}…
                  </p>
                ) : null}
              </div>

              {missedStops.length > 0 ? (
                <div className="rounded-lg border border-amber-200 bg-amber-50 px-3 py-2 text-xs text-amber-950">
                  <p className="font-semibold">Missed pickups ({missedStops.length})</p>
                  <ul className="mt-1 list-inside list-disc">
                    {missedStops.map((s) => (
                      <li key={String(s.id)}>{String(s.label ?? s.id)}</li>
                    ))}
                  </ul>
                </div>
              ) : null}

              <div>
                <p className="mb-2 text-[10px] font-semibold uppercase tracking-wide text-zinc-500">Stops</p>
                <div className="max-h-48 overflow-auto rounded-lg border border-zinc-200">
                  <table className="w-full text-left text-xs">
                    <thead className="sticky top-0 bg-zinc-100 text-zinc-600">
                      <tr>
                        <th className="px-2 py-1.5">#</th>
                        <th className="px-2 py-1.5">Label</th>
                        <th className="px-2 py-1.5">Status</th>
                      </tr>
                    </thead>
                    <tbody>
                      {stops.map((s) => (
                        <tr key={String(s.id)} className="border-t border-zinc-100">
                          <td className="px-2 py-1.5">{String(s.stop_order ?? "")}</td>
                          <td className="px-2 py-1.5">{String(s.label ?? "")}</td>
                          <td className="px-2 py-1.5">
                            <span
                              className={
                                s.status === "missed"
                                  ? "font-semibold text-amber-800"
                                  : s.status === "completed"
                                    ? "text-emerald-700"
                                    : "text-zinc-700"
                              }
                            >
                              {String(s.status ?? "")}
                            </span>
                          </td>
                        </tr>
                      ))}
                    </tbody>
                  </table>
                </div>
              </div>

              {pingsAsc.length > 0 ? (
                <div>
                  <p className="mb-2 text-[10px] font-semibold uppercase tracking-wide text-zinc-500">
                    GPS playback ({pingsAsc.length} pings)
                  </p>
                  <div className="h-52 overflow-hidden rounded-lg border border-zinc-200">
                    <MapContainer
                      center={mapCenter}
                      zoom={15}
                      scrollWheelZoom={false}
                      className="h-full w-full"
                    >
                      <TileLayer
                        attribution='&copy; OpenStreetMap'
                        url="https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png"
                      />
                      <PlaybackLayers points={polyline} scrubLatLng={scrubLatLng} color="#2563eb" />
                    </MapContainer>
                  </div>
                  <label className="mt-2 flex items-center gap-2 text-xs text-zinc-700">
                    <span className="shrink-0">Scrub</span>
                    <input
                      type="range"
                      min={0}
                      max={Math.max(0, pingsAsc.length - 1)}
                      value={safeScrub}
                      onChange={(e) => setScrubIndex(Number(e.target.value))}
                      className="min-w-0 flex-1"
                    />
                    <span className="shrink-0 tabular-nums text-zinc-500">
                      {safeScrub + 1}/{pingsAsc.length}
                    </span>
                  </label>
                </div>
              ) : (
                <p className="text-xs text-zinc-500">No GPS pings recorded for this route.</p>
              )}
            </div>
          ) : null}
        </div>
      </div>
    </div>
  );
}
