"use client";

import "leaflet/dist/leaflet.css";
import { LatLngBounds } from "leaflet";
import { useEffect, useState } from "react";
import { Circle, CircleMarker, MapContainer, Popup, TileLayer } from "react-leaflet";
import { useMap, useMapEvents } from "react-leaflet";
import type { DashboardPin } from "@/components/layout/dashboard-mock-data";

type Props = {
  pins: DashboardPin[];
};

const colorByType: Record<DashboardPin["type"], string> = {
  dumpsite: "#f59e0b",
  missed_pickup: "#3b82f6",
  hotspot: "#ef4444",
};

function FitToPins({ pins }: { pins: DashboardPin[] }) {
  const map = useMap();

  useEffect(() => {
    if (pins.length === 0) return;
    if (pins.length === 1) {
      map.setView([pins[0].lat, pins[0].lng], 16);
      return;
    }

    const bounds = new LatLngBounds(pins.map((pin) => [pin.lat, pin.lng] as [number, number]));
    map.fitBounds(bounds.pad(0.2));
  }, [map, pins]);

  return null;
}

function EnsurePanes() {
  const map = useMap();

  useEffect(() => {
    if (!map.getPane("hotspot-area")) {
      const pane = map.createPane("hotspot-area");
      pane.style.zIndex = "460";
    }
    if (!map.getPane("report-pins")) {
      const pane = map.createPane("report-pins");
      pane.style.zIndex = "500";
    }
    if (!map.getPane("hotspot-top")) {
      const pane = map.createPane("hotspot-top");
      pane.style.zIndex = "650";
    }
  }, [map]);

  return null;
}

function ZoomAwareLayers({ hotspotPins, reportPins }: { hotspotPins: DashboardPin[]; reportPins: DashboardPin[] }) {
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

export function LGUMap({ pins }: Props) {
  const hotspotPins = pins.filter((pin) => pin.type === "hotspot");
  const reportPins = pins.filter((pin) => pin.type !== "hotspot");

  return (
    <MapContainer
      center={[14.676, 121.0437]}
      zoom={14}
      scrollWheelZoom={false}
      className="h-full w-full rounded-xl"
    >
      <TileLayer
        attribution='&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> contributors'
        url="https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png"
      />
      <EnsurePanes />
      <FitToPins pins={pins} />
      <ZoomAwareLayers hotspotPins={hotspotPins} reportPins={reportPins} />
    </MapContainer>
  );
}
