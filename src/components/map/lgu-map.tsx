"use client";

import "leaflet/dist/leaflet.css";
import L, { LatLngBounds } from "leaflet";
import { Fragment, useCallback, useEffect, useRef, useState } from "react";
import { Circle, CircleMarker, MapContainer, Marker, Polyline, Popup, Tooltip, TileLayer } from "react-leaflet";
import { useMap, useMapEvents } from "react-leaflet";
import type { DashboardPin, DashboardRoutePath } from "@/components/layout/dashboard-mock-data";

export type LiveTruckMarker = {
  routeId: string;
  lat: number;
  lng: number;
  heading: number | null;
  color: string;
  label: string;
  remainingStops: number;
};

type Props = {
  pins: DashboardPin[];
  routes: DashboardRoutePath[];
  liveTrucks?: LiveTruckMarker[];
  planningMode?: boolean;
  addingCollectionPoint?: boolean;
  draftStopIds?: string[];
  draftRoutePoints?: [number, number][];
  onCollectionPointClick?: (pin: DashboardPin) => void;
  onMapClick?: (lat: number, lng: number) => void;
};

const colorByType: Record<DashboardPin["type"], string> = {
  reported_garbage_point: "#f97316",
  missed_pickup: "#3b82f6",
  hotspot: "#ef4444",
  collection_point: "#14b8a6", // teal — distinct from route blue
  risk_zone: "#fbbf24",
};

function FitToPins({ pins, routes }: { pins: DashboardPin[]; routes: DashboardRoutePath[] }) {
  const map = useMap();
  const didFitRef = useRef(false);

  useEffect(() => {
    // Only fit once per mount; subsequent pin/route updates must not yank the user's view
    // around (and avoid racing Leaflet's zoom transition → `_leaflet_pos` undefined crash).
    if (didFitRef.current) return;

    const routePoints = routes.flatMap((route) => route.points);
    const allPoints = [...pins.map((pin) => [pin.lat, pin.lng] as [number, number]), ...routePoints];
    if (allPoints.length === 0) return;

    didFitRef.current = true;

    // Defer one frame so any in-flight zoom transition can settle before we mutate the view.
    const rafId = requestAnimationFrame(() => {
      try {
        if (allPoints.length === 1) {
          map.setView(allPoints[0], 16, { animate: false });
          return;
        }
        const bounds = new LatLngBounds(allPoints);
        map.fitBounds(bounds.pad(0.2), { animate: false });
      } catch {
        // Leaflet can throw mid-transition if the map element was just unmounted; ignore.
        didFitRef.current = false;
      }
    });

    return () => cancelAnimationFrame(rafId);
  }, [map, pins, routes]);

  return null;
}

const PANE_DEFS: ReadonlyArray<readonly [string, number]> = [
  ["hotspot-area", 460],
  ["risk-zone-area", 440],
  ["route-lines", 430],
  ["live-trucks", 455],
  ["report-pins", 500],
  ["hotspot-top", 650],
];

function liveTruckArrowIcon(heading: number | null, color: string) {
  const rot = heading != null && Number.isFinite(heading) ? heading : 0;
  return L.divIcon({
    className: "live-truck-arrow-icon",
    html: `<div style="transform:rotate(${rot}deg);color:${color};font-size:16px;line-height:1;text-shadow:0 0 2px #fff;">▲</div>`,
    iconSize: [20, 20],
    iconAnchor: [10, 10],
  });
}

function LiveTruckMarkers({ liveTrucks }: { liveTrucks: LiveTruckMarker[] }) {
  const [zoom, setZoom] = useState(14);
  useMapEvents({
    zoomend(e) {
      setZoom(e.target.getZoom());
    },
  });
  const ringR = Math.max(8, Math.min(18, Math.round(26 - zoom)));

  return (
    <>
      {liveTrucks.map((t) => (
        <Fragment key={t.routeId}>
          <CircleMarker
            center={[t.lat, t.lng]}
            radius={ringR}
            pane="live-trucks"
            pathOptions={{
              color: t.color,
              fillColor: t.color,
              fillOpacity: 0.28,
              weight: 2,
            }}
          />
          <Marker position={[t.lat, t.lng]} icon={liveTruckArrowIcon(t.heading, t.color)} pane="live-trucks">
            <Tooltip direction="top" offset={[0, -12]} opacity={0.95}>
              <span className="text-xs font-semibold">{t.label}</span>
              <br />
              <span className="text-[11px] text-zinc-700">
                ~{Math.max(0, t.remainingStops) * 8} min ETA · {t.remainingStops} stop
                {t.remainingStops === 1 ? "" : "s"} left
              </span>
            </Tooltip>
          </Marker>
        </Fragment>
      ))}
    </>
  );
}

function EnsurePanes({ onReady }: { onReady: () => void }) {
  const map = useMap();

  useEffect(() => {
    for (const [name, zIndex] of PANE_DEFS) {
      if (!map.getPane(name)) {
        const pane = map.createPane(name);
        pane.style.zIndex = String(zIndex);
        pane.style.pointerEvents = "auto";
      }
    }
    onReady();
  }, [map, onReady]);

  return null;
}

function MapClickHandler({ onMapClick }: { onMapClick?: (lat: number, lng: number) => void }) {
  useMapEvents({
    click(e) {
      if (onMapClick) {
        onMapClick(e.latlng.lat, e.latlng.lng);
      }
    },
  });
  return null;
}

function ZoomAwareLayers({
  hotspotPins,
  reportPins,
  collectionPoints,
  riskZonePins,
  planningMode,
  draftStopIds,
  draftRoutePoints,
  onCollectionPointClick,
}: {
  hotspotPins: DashboardPin[];
  reportPins: DashboardPin[];
  collectionPoints: DashboardPin[];
  riskZonePins: DashboardPin[];
  planningMode?: boolean;
  draftStopIds?: string[];
  draftRoutePoints?: [number, number][];
  onCollectionPointClick?: (pin: DashboardPin) => void;
}) {
  const [zoom, setZoom] = useState(14);
  useMapEvents({
    zoomend(event) {
      setZoom(event.target.getZoom());
    },
  });

  const reportRadius = Math.max(7, Math.min(18, Math.round(24 - zoom)));
  const hotspotTopRadius = Math.max(10, Math.min(26, reportRadius + 6));

  return (
    <>
      {hotspotPins.map((pin) => (
        <Circle
          key={pin.id}
          center={[pin.lat, pin.lng]}
          radius={pin.radiusMeters ?? 100}
          pane="hotspot-area"
          pathOptions={{
            color: colorByType.hotspot,
            fillColor: colorByType.hotspot,
            fillOpacity: 0.2,
            weight: 2,
          }}
        >
          <Popup>
            <div className="space-y-1">
              <p className="text-sm font-semibold uppercase tracking-wide">{pin.type.replace("_", " ")}</p>
              <p className="text-sm">{pin.label}</p>
              <p className="text-xs text-zinc-500">Radius: {pin.radiusMeters ?? 100}m</p>
            </div>
          </Popup>
        </Circle>
      ))}

      {riskZonePins.map((pin) => (
        <Circle
          key={pin.id}
          center={[pin.lat, pin.lng]}
          radius={pin.radiusMeters ?? 100}
          pane="risk-zone-area"
          pathOptions={{
            color: colorByType.risk_zone,
            fillColor: colorByType.risk_zone,
            fillOpacity: 0.18,
            weight: 2,
          }}
        >
          <Popup>
            <div className="space-y-1">
              <p className="text-sm font-semibold uppercase tracking-wide">Risk Zone</p>
              <p className="text-sm">{pin.label}</p>
            </div>
          </Popup>
        </Circle>
      ))}

      {reportPins.map((pin) => (
        <CircleMarker
          key={pin.id}
          center={[pin.lat, pin.lng]}
          radius={reportRadius}
          pane="report-pins"
          pathOptions={{
            color: colorByType[pin.type],
            fillColor: colorByType[pin.type],
            fillOpacity: 0.75,
            weight: 2,
          }}
        >
          <Popup>
            <div className="space-y-1">
              <p className="text-sm font-semibold uppercase tracking-wide">{pin.type.replace("_", " ")}</p>
              <p className="text-sm">{pin.label}</p>
              {pin.wasteType ? (
                <p className="text-xs text-zinc-500">Waste: {pin.wasteType.replaceAll("_", " ")}</p>
              ) : null}
            </div>
          </Popup>
        </CircleMarker>
      ))}

      {collectionPoints.map((pin) => {
        const rawId = pin.id.replace("collection-point-", "");
        const orderIndex = draftStopIds ? draftStopIds.indexOf(rawId) : -1;
        const isSelected = orderIndex >= 0;
        const baseRadius = Math.max(7, reportRadius - 1);
        const circleRadius = planningMode ? (isSelected ? baseRadius + 4 : baseRadius + 2) : baseRadius;
        const fillColor = isSelected ? "#f59e0b" : colorByType.collection_point;
        const borderColor = isSelected ? "#d97706" : colorByType.collection_point;
        const fillOpacity = isSelected ? 1 : planningMode ? 0.6 : 0.8;

        return (
          <CircleMarker
            key={pin.id}
            center={[pin.lat, pin.lng]}
            radius={circleRadius}
            pane="report-pins"
            pathOptions={{
              color: borderColor,
              fillColor,
              fillOpacity,
              weight: isSelected ? 3 : 2,
            }}
            eventHandlers={
              planningMode && onCollectionPointClick
                ? {
                    click: () => {
                      onCollectionPointClick(pin);
                    },
                  }
                : {}
            }
          >
            {planningMode && isSelected ? (
              <Tooltip permanent direction="top" offset={[0, -circleRadius - 2]}>
                <span style={{ fontWeight: 700, fontSize: 11 }}>#{orderIndex + 1}</span>
              </Tooltip>
            ) : (
              <Popup>
                <div className="space-y-1">
                  <p className="text-sm font-semibold uppercase tracking-wide">Collection Point</p>
                  <p className="text-sm">{pin.label}</p>
                  {planningMode ? (
                    <p className="text-xs text-teal-600">Click to add to route</p>
                  ) : null}
                </div>
              </Popup>
            )}
          </CircleMarker>
        );
      })}

      {planningMode && draftRoutePoints && draftRoutePoints.length >= 2 ? (
        <Polyline
          positions={draftRoutePoints}
          pane="route-lines"
          pathOptions={{ color: "#f59e0b", weight: 3, opacity: 0.9, dashArray: "6 4" }}
        />
      ) : null}

      {hotspotPins.map((pin) => (
        <CircleMarker
          key={`${pin.id}-top`}
          center={[pin.lat, pin.lng]}
          radius={hotspotTopRadius}
          pane="hotspot-top"
          pathOptions={{
            color: colorByType.hotspot,
            fillColor: colorByType.hotspot,
            fillOpacity: 0.3,
            weight: 2,
          }}
        />
      ))}
    </>
  );
}

export function LGUMap({
  pins,
  routes,
  liveTrucks = [],
  planningMode,
  addingCollectionPoint,
  draftStopIds,
  draftRoutePoints,
  onCollectionPointClick,
  onMapClick,
}: Props) {
  const hotspotPins = pins.filter((pin) => pin.type === "hotspot");
  const reportPins = pins.filter(
    (pin) => pin.type === "reported_garbage_point" || pin.type === "missed_pickup",
  );
  const collectionPoints = pins.filter((pin) => pin.type === "collection_point");
  const riskZonePins = pins.filter((pin) => pin.type === "risk_zone");

  // Gate child layers on pane creation. Children that declare `pane="..."` MUST not render
  // before EnsurePanes has run; otherwise Leaflet drops them on the wrong pane and zoom
  // transitions later crash with "Cannot read properties of undefined (reading '_leaflet_pos')".
  const [panesReady, setPanesReady] = useState(false);
  const handlePanesReady = useCallback(() => setPanesReady(true), []);

  return (
    <MapContainer
      center={[14.676, 121.0437]}
      zoom={14}
      scrollWheelZoom={true}
      wheelDebounceTime={40}
      wheelPxPerZoomLevel={80}
      className={`h-full w-full rounded-xl${planningMode || addingCollectionPoint ? " cursor-crosshair" : ""}`}
    >
      <TileLayer
        attribution='&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> contributors'
        url="https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png"
      />
      <EnsurePanes onReady={handlePanesReady} />
      {panesReady ? (
        <>
          <FitToPins pins={pins} routes={routes} />
          {(planningMode || addingCollectionPoint) && onMapClick ? (
            <MapClickHandler onMapClick={onMapClick} />
          ) : null}
          {!planningMode
            ? routes.map((route) => (
                <Polyline
                  key={route.id}
                  positions={route.points}
                  pane="route-lines"
                  pathOptions={{
                    color: route.color,
                    weight: 4,
                    opacity: 0.85,
                  }}
                >
                  <Popup>
                    <div className="space-y-1">
                      <p className="text-sm font-semibold uppercase tracking-wide">Optimized Route</p>
                      <p className="text-sm">{route.truckLabel}</p>
                    </div>
                  </Popup>
                </Polyline>
              ))
            : null}
          {!planningMode && liveTrucks.length > 0 ? <LiveTruckMarkers liveTrucks={liveTrucks} /> : null}
          <ZoomAwareLayers
            hotspotPins={hotspotPins}
            reportPins={reportPins}
            collectionPoints={collectionPoints}
            riskZonePins={riskZonePins}
            planningMode={planningMode}
            draftStopIds={draftStopIds}
            draftRoutePoints={draftRoutePoints}
            onCollectionPointClick={onCollectionPointClick}
          />
        </>
      ) : null}
    </MapContainer>
  );
}
